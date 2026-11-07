-- Real adapter, native string capacity intentionally constrained at the boundary.
local wrap_registry=assert(loadfile('src/wh3ep_registry.lua'))()
local model=assert(loadfile('src/wh3ep_model.lua'))()
local json=assert(loadfile('vendor/dkjson/dkjson.lua'))()
local create_storage=assert(loadfile('src/wh3ep_storage.lua'))()
local raw,writes,reads,max_written,fail={},{},0,0,nil
local function reset()raw,writes,reads,max_written,fail={},{},0,0,nil end
local native={read=function(key)reads=reads+1;return raw[key]end,write=function(key,value)
 writes[#writes+1]={key=key,value=value};max_written=math.max(max_written,#value)
 if fail and fail(key,value)then return end
 -- A simulated native string limit, not a claimed engine contract.
 if #value>1023 then raw[key]='';return end
 raw[key]=value
end}
local registry=wrap_registry(native)
local primary='wh3ep_library_v1'
local function part_key(key)
 local bank=assert(raw[key]:match('^WH3EP_CHUNK1:(%d+):'))
 return key..'_chunks_v1_'..bank..'_1'
end
local payload=string.rep('Ёж"\\\n',250)..'\0tail'
registry.write(primary,payload)
assert(registry.read(primary)==payload,'large payload must round-trip despite native string-size refusal')
assert(max_written<512,'every native write must remain a short ASCII string')
assert(raw[primary]:match('^WH3EP_CHUNK1:'),'original key must publish a short manifest')
local head=raw[primary]
local count=#writes
assert(registry.read(primary)==payload and #writes==count,'reading must never migrate or rewrite')
local next_payload=payload..' next'
assert(registry.write(primary,next_payload))
assert(registry.read(primary)==next_payload and raw[primary]~=head)
local live_head=raw[primary]
fail=function(key)return key:find('_chunks_v1_',1,true)~=nil end
assert(not registry.write(primary,payload..' fail'))
assert(raw[primary]==live_head and registry.read(primary)==next_payload,'failed part must not replace previous manifest/data')
fail=function(key)return key==primary end
assert(not registry.write(primary,payload..' failed manifest'))
assert(raw[primary]==live_head and registry.read(primary)==next_payload,'failed manifest must leave prior data accessible')
fail=nil
local part=part_key(primary)
local saved_part=raw[part]
raw[part]=saved_part:gsub('^WH3EP_PART1:%d+:','WH3EP_PART1:999999:')
assert(registry.read(primary)==raw[primary],'wrong generation must return damaged envelope, never mixed data')
raw[part]=saved_part
raw[part]=saved_part:sub(1,-2)..(saved_part:sub(-1)=='0'and '1'or '0')
assert(registry.read(primary)==raw[primary],'checksum must reject changed data even at equal length')
raw[part]=nil
assert(registry.read(primary)==raw[primary],'missing part must be treated as damaged content')
raw[part]=saved_part
local existing=raw[primary]
raw[primary]='WH3EP_CHUNK1:0:1:999999999:1:1'
local before_reads=reads
assert(registry.read(primary)==raw[primary]and reads==before_reads+1,'invalid manifest must not drive unbounded reads')
raw[primary]=existing
local old_legacy='{"legacy":"Кириллица"}'
raw[primary]=old_legacy
count=#writes
assert(registry.read(primary)==old_legacy and #writes==count,'legacy strings must read unchanged without migration writes')
assert(registry.write(primary,payload)and registry.read(primary)==payload,'explicit write can migrate legacy data')
raw[primary]='WH3EP_CHUNK2:future'
local future,future_status=registry.read(primary)
assert(not future and future_status=='future_schema','future envelope must be read-only')
count=#writes
assert(not registry.write(primary,payload)and #writes==count,'future envelope must never be overwritten')

-- Existing model/storage transactions operate on logical JSON, including legacy data.
reset();registry=wrap_registry(native)
local snapshot={faction_key='cathay',class_key='lord',character_kind='lord',equipment={{slot_key='weapon',item_key='sword'}},followers={}}
local first=assert(model.add(model.new(),snapshot,'Старый пресет',''))
raw[primary]=json.encode(first)
local storage=create_storage(model,json,registry)
local loaded,status,meta=storage.load()
assert(status=='ok'and loaded.library_revision==1 and #writes==0)
local rich={faction_key='cathay',class_key='dragon',character_kind='lord',equipment={},followers={}}
for index=1,5 do rich.equipment[index]={slot_key='slot_'..index,item_key='wh3_item_'..string.rep('x',120)..index}end
local second=assert(model.add(loaded,rich,'Мяо тест','dragon'))
assert(storage.save(second,1,meta.token),'full storage transaction must fit through small native values')
local current,current_status,current_meta=storage.load()
assert(current_status=='ok'and current.library_revision==2 and #current.factions.cathay.presets==2)
assert(registry.read('wh3ep_library_backup_v1')==meta.token,'backup must retain exact previous logical JSON')
assert(max_written<512)
local third=assert(model.update(current,'cathay','p2',{favorite=true}))
local prior_primary,prior_backup=registry.read(primary),registry.read('wh3ep_library_backup_v1')
fail=function(key)return key:find('wh3ep_library_pending_v1_chunks_v1_',1,true)==1 end
assert(not storage.save(third,2,current_meta.token))
assert(registry.read(primary)==prior_primary and registry.read('wh3ep_library_backup_v1')==prior_backup,'staging failure preserves logical primary and backup')
local damaged_once=false
fail=function(key,value)
 if key==primary and not damaged_once then raw[key]=value:sub(1,9);damaged_once=true;return true end
end
local saved,code=storage.save(third,2,current_meta.token)
assert(not saved and code=='write_failed'and registry.read(primary)==prior_primary,'partial manifest write must roll back exact prior JSON')
fail=nil
local loaded_again,_,again_meta=storage.load()
local fourth=assert(model.update(loaded_again,'cathay','p2',{name='После исправления'}))
assert(storage.save(fourth,2,again_meta.token))
local damaged_manifest=raw[primary]
local damaged_part_key=part_key(primary)
local damaged_part_value=raw[damaged_part_key]..'DAMAGED_BYTES_MARKER'
raw[damaged_part_key]=damaged_part_value
local offered,offered_status,offered_meta=storage.load()
assert(offered and offered_status=='backup_available','corrupt block must offer an independently complete backup')
local damaged_head_before=raw[primary]
local writes_before_archive=#writes
local no_archive=create_storage(model,json,{read=registry.read,write=registry.write,archive=function()return nil,'archive_failed'end})
assert(not no_archive.restore_backup(offered_meta.token)and #writes==writes_before_archive and raw[primary]==damaged_head_before,'failed snapshot capture must not mutate damaged primary')
fail=function(key)return key:find('wh3ep_library_damaged_v1_chunks_v1_',1,true)==1 end
assert(not storage.restore_backup(offered_meta.token)and raw[primary]==damaged_head_before,'failed archive write must not proceed to restore')
fail=nil
assert(storage.restore_backup(offered_meta.token),'explicit backup restore must work through chunk adapter')
local archived=registry.read('wh3ep_library_damaged_v1')
assert(archived:find(damaged_part_value,1,true),'recovery must preserve raw damaged block bytes independently of reusable banks')
assert(archived:find(damaged_manifest,1,true),'recovery must preserve the original manifest as well')
local restored,_,restored_meta=storage.load()
local after_recovery=assert(model.update(restored,'cathay','p2',{name='После восстановления'}))
assert(storage.save(after_recovery,2,restored_meta.token))
assert(registry.read('wh3ep_library_damaged_v1')==archived,'subsequent bank reuse must not change the damaged archive')
assert(storage.load().library_revision==3)
raw[primary]='WH3EP_CHUNK2:future'
local denied,denied_status=storage.load()
count=#writes
assert(not denied and denied_status=='future_schema'and not storage.restore_backup(),'future envelope blocks load/save/restore')
assert(#writes==count)
print('PASS: short native blocks, UTF8/bytes, manifest integrity/generation/bounds, legacy compatibility, future protection, full transaction/backup/rollback/recovery')
-- Fail every individual native write of a real transaction, once at a time.
-- No single failed write may erase the previous committed library.
local legacy=json.encode(first)
local probe_raw,probe_count={},0
local probe=wrap_registry({read=function(k)return probe_raw[k]end,write=function(k,v)probe_raw[k]=v;probe_count=probe_count+1 end})
probe_raw[primary]=legacy
assert(create_storage(model,json,probe).save(second,1,legacy))
local transaction_writes=probe_count
for _,failure_mode in ipairs({'ignore','partial','exception','false'})do
 for failed_write=1,transaction_writes do
  local values={[primary]=legacy};local attempt=0
  local boundary=wrap_registry({read=function(k)return values[k]end,write=function(k,v)
   attempt=attempt+1
   if attempt==failed_write then
    if failure_mode=='partial'then values[k]=v:sub(1,7)
    elseif failure_mode=='exception'then error('simulated native failure',0)
    elseif failure_mode=='false'then return false end
    return
   end
   assert(#v<512);values[k]=v
  end})
  local transaction=create_storage(model,json,boundary)
  assert(not transaction.save(second,1,legacy),'injected failed write must not count as success')
  local old,old_status=transaction.load()
  assert(old_status=='ok'and old.library_revision==1,'every one-shot native write failure must preserve/recover old primary')
  assert(boundary.read(primary)==legacy,'old primary must be byte-identical after failed transaction')
 end
end
-- Read failures at each boundary are likewise one-shot and must not erase data.
local base_raw={[primary]=legacy};local baseline_reads=0
local base_boundary=wrap_registry({read=function(k)baseline_reads=baseline_reads+1;return base_raw[k]end,write=function(k,v)base_raw[k]=v end})
assert(create_storage(model,json,base_boundary).save(second,1,legacy))
for failed_read=1,baseline_reads do
 local values={[primary]=legacy};local attempt=0
 local boundary=wrap_registry({read=function(k)
  attempt=attempt+1;if attempt==failed_read then error('simulated read failure',0)end
  return values[k]
 end,write=function(k,v)values[k]=v end})
 local transaction=create_storage(model,json,boundary)
 local saved=transaction.save(second,1,legacy)
 -- A failure after the first verified commit may occur in a redundant final read;
 -- success is permitted only if the candidate is still fully readable.
 local final,final_status=transaction.load()
 assert(final_status=='ok'and final and (final.library_revision==1 or final.library_revision==2),'read failure must leave a complete old or new primary')
 if saved then assert(final.library_revision==2,'reported success requires complete new library')
 else assert(boundary.read(primary)==legacy,'failed transaction must roll back exact old primary')end
end
reset();registry=wrap_registry(native)
for index=1,20 do assert(registry.write(primary,payload..tostring(index)))end
local key_count=0;for _ in pairs(raw)do key_count=key_count+1 end
assert(key_count<=1+2*math.ceil((#payload+2)/192),'successful writes must reuse two banks, not accumulate generations')
count=#writes
assert(not registry.write(primary,string.rep('x',2*1024*1024+1))and #writes==count,'oversized input must be refused before native writes')
print('PASS: every native write/read failure boundary, exact old-primary preservation and bounded two-bank key reuse')