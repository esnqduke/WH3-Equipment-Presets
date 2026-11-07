local factory=assert(loadfile('src/wh3ep_storage.lua'))()
local model=assert(loadfile('src/wh3ep_model.lua'))()
local json=assert(loadfile('vendor/dkjson/dkjson.lua'))()
local keys={primary='wh3ep_library_v1',backup='wh3ep_library_backup_v1',pending='wh3ep_library_pending_v1',damaged='wh3ep_library_damaged_v1'}
local values,writes={},0
local fail_mode,fail_key,decode_calls=nil,nil,0
local registry={
 read=function(key)return values[key]end,
 write=function(key,value)
  writes=writes+1
  if fail_key==key then
   if fail_mode=='reject' then return false end
   if fail_mode=='partial_once' then values[key]=value:sub(1,5);fail_key=nil;return false end
   if fail_mode=='partial_always' then values[key]=value:sub(1,5);return false end
  end
  values[key]=value
 end
}
local wrapped={encode=json.encode,decode=function(...)decode_calls=decode_calls+1;return json.decode(...)end}
local storage=factory(model,wrapped,registry)
local function check(value,message)assert(value,message)end
local snapshot={faction_key='test_faction',class_key='test_lord',character_kind='lord',equipment={{slot_key='weapon',item_key='mod_unknown_sword'}},followers={'follower','follower'}}
local library,status,info=storage.load()
check(status=='new' and library.library_revision==0 and writes==0)
local first=assert(model.add(library,snapshot,'Кириллица Ёж','test_lord'))
local ok,code,stored=storage.save(first,0,info.token)
check(ok and code=='saved' and stored.token==values[keys.primary])
local loaded,loaded_status,loaded_info=storage.load()
check(loaded_status=='ok' and loaded.factions.test_faction.presets[1].name=='Кириллица Ёж')
check(loaded.factions.test_faction.presets[1].followers[2]=='follower')
local first_raw=values[keys.primary]
local second=assert(model.update(loaded,'test_faction','p1',{name='После сохранения'}))
check(storage.save(second,1,loaded_info.token))
check(values[keys.backup]==first_raw,'backup must retain previous complete valid version')
local current_raw=values[keys.primary]
check(not storage.save(first,0),'old revision must not overwrite newer library')
check(values[keys.primary]==current_raw)
local reloaded=storage.load();check(reloaded.library_revision==2,'new instance reads library, not campaign save')
local third=assert(model.update(reloaded,'test_faction','p1',{favorite=true}))
fail_key,fail_mode=keys.pending,'reject'
check(not storage.save(third,2,current_raw) and values[keys.primary]==current_raw and values[keys.backup]==first_raw,'staging failure must preserve current and backup')
fail_key,fail_mode=keys.backup,'reject'
check(not storage.save(third,2,current_raw) and values[keys.primary]==current_raw,'backup failure must not commit primary')
fail_key,fail_mode=keys.primary,'partial_once'
check(not storage.save(third,2,current_raw) and values[keys.primary]==current_raw,'partial primary write must restore exact previous raw value')
fail_key=nil
values[keys.primary]='{broken'
local count=writes
local recovered,recovery_status,recovery_info=storage.load()
check(recovered and recovery_status=='backup_available' and writes==count,'recovery must be offered without automatic writes')
check(not storage.save(third,recovered.library_revision,recovery_info.token),'damaged primary cannot be silently replaced during normal save')
check(values[keys.primary]=='{broken')
check(storage.restore_backup(recovery_info.token))
check(values[keys.damaged]=='{broken' and values[keys.primary]==current_raw,'explicit restore preserves damaged original and valid backup')
local future=json.decode(current_raw);future.schema_version=2
values[keys.primary]=json.encode(future)
local future_raw=values[keys.primary]
local missing,future_status=storage.load()
check(not missing and future_status=='future_schema')
check(not storage.save(third,2,future_raw) and not storage.restore_backup(future_raw),'future schema must remain read-only')
check(values[keys.primary]==future_raw)
values[keys.primary]=current_raw
local same_revision=json.decode(current_raw);same_revision.factions.test_faction.presets[1].name='External edit'
values[keys.primary]=json.encode(same_revision)
check(not storage.save(third,2,current_raw),'raw-token conflict must catch external edit with unchanged revision')
values[keys.primary]=current_raw
fail_key,fail_mode=keys.primary,'partial_always'
local failed,failed_code=storage.save(third,2,current_raw)
check(not failed and failed_code=='write_failed_backup_available','failed rollback must report backup availability')
fail_key=nil
local backup_library,backup_status=storage.load()
check(backup_library and backup_status=='backup_available','verified backup must survive an unsuccessful rollback')
values={};writes=0
local before_decode=decode_calls
values[keys.primary]=string.rep(' ',2*1024*1024+1)
local too_big,big_status=storage.load()
check(not too_big and big_status=='too_large' and decode_calls==before_decode,'size rejected before decoder')
values[keys.primary]=string.rep('[',17)..string.rep(']',17)
local deep,deep_status=storage.load()
check(not deep and deep_status=='too_deep' and decode_calls==before_decode,'depth rejected before decoder')
values[keys.primary]='return __wh3ep_executed = true'
_G.__wh3ep_executed=false
check(not storage.load() and _G.__wh3ep_executed==false,'stored text must never execute as Lua')
values[keys.primary]='{"schema_version":1,"library_revision":1,"next_id":2,"factions":{"lost_faction":null}}'
local null_library=storage.load()
check(not null_library,'null faction must not silently disappear and turn corrupted data into a valid library')
values[keys.primary]='{"schema_version":1,"library_revision":0,"next_id":1,"factions":null}'
check(not storage.load(),'null factions must not masquerade as an empty map')
values[keys.primary]='{"schema_version":2147483648,"factions":null}'
local large_future,large_future_status=storage.load()
check(not large_future and large_future_status=='future_schema','all future schema versions must be read-only even with unknown future shape')
values[keys.primary]='{"schema_version":1 "library_revision":0 "next_id":1 "factions":{}}'
check(not storage.load(),'missing commas must be rejected')
values[keys.primary]='{"schema_version":1,"library_revision":0,"next_id":1,"factions":[]}'
check(not storage.load(),'factions must be a JSON object')
values[keys.primary]='{"schema_version":1,"library_revision":0,"next_id":1,"factions":{"x":{"presets":[null]}}}'
check(not storage.load(),'trailing null array entries must not disappear')
values[keys.primary]=current_raw..' {}'
check(not storage.load(),'a valid JSON prefix with trailing data must be rejected')
values[keys.primary]='{"schema_version":1}'
check(not storage.load(),'malformed schema must not be treated as empty library')
values={}
local clean=storage.load()
local escaped=assert(model.add(clean,snapshot,'Кавычки " [] \\',''))
check(storage.save(escaped,0))
local escaped_loaded=storage.load()
check(escaped_loaded.factions.test_faction.presets[1].name=='Кавычки " [] \\','JSON escaping and depth scan must agree')
local empty=factory(model,json,{read=function()return nil end,write=function()return false end})
check(not empty.save(first,0),'reported write failure cannot count as successful')
print('PASS: native-registry JSON round-trip, Unicode, revision/raw conflicts, staged/backup writes, partial-write rollback, explicit recovery, future-schema protection, size/depth limits, non-execution')