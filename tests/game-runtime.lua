-- Reproduce the failing runtime constant and CA's documented UTF8 string overrides.
local original={find=string.find,sub=string.sub,len=string.len}
local source=assert(io.open('.superpowers/library-probe-bundle.lua','rb'))
local bundle=source:read('*a');source:close()
local native_math={};for k,v in pairs(math)do if k~='huge'then native_math[k]=v end end
local function utf8_sub(value,first,last)
 local starts={};for index=1,#value do local b=value:byte(index);if b<128 or b>=192 then starts[#starts+1]=index end end
 local count=#starts
 first=first or 1;last=last or count
 if first<0 then first=count+first+1 end;if last<0 then last=count+last+1 end
 first=math.max(first,1);last=math.min(last,count)
 if first>last then return ''end
 return original.sub(value,starts[first],(starts[last+1]or(#value+1))-1)
end
string.find_lua,string.sub_lua,string.len_lua=original.find,original.sub,original.len
string.find=function(value,pattern,start,plain)assert(plain==nil,'native find accepts three arguments');return original.find(value,pattern,start,true)end
string.sub=utf8_sub
string.len=function(value)local _,count=value:gsub('[^\128-\191]','');return count end
local ok,failure=pcall(function()
 local chunk=assert(loadstring(bundle..'\nreturn wh3ep_model,wh3ep_json,wh3ep_storage_factory,wh3ep_registry_factory','@game-runtime-bundle'))
 setfenv(chunk,setmetatable({math=native_math},{__index=_G}))
 local model,json,create_storage,wrap_registry=chunk()
 local library=model.new()
 assert(model.validate(library),'new library must validate without math.huge')
 local snapshot={faction_key='cathay',class_key='lord',character_kind='lord',equipment={{slot_key='weapon',item_key='test_sword'}},followers={}}
 local updated,preset=model.add(library,snapshot,'  Тест Ёж  ','lord')
 assert(updated and preset.name=='Тест Ёж','UTF8 byte offsets must survive native sub override')
 local list=model.list(updated,'cathay','lord','matching','ёж')
 assert(list and #list==1,'Cyrillic casefold search must use Lua find')
 local values={}
 local storage=create_storage(model,json,wrap_registry({read=function(k)return values[k]end,write=function(k,v)assert(#v<512);values[k]=v end}))
 assert(storage.save(updated,0),'JSON encode must work without native math.huge')
 local loaded,status=storage.load()
 assert(status=='ok'and loaded.factions.cathay.presets[1].name=='Тест Ёж','JSON must retain bytes across native UTF8 functions')
 assert(not model.validate({schema_version=1,library_revision=1/0,next_id=1,factions={}}),'infinity must remain invalid')
 assert(not model.capture(snapshot,'bad\nname','lord','p2'),'control-character validation must retain Lua patterns')
end)
string.find,string.sub,string.len=original.find,original.sub,original.len
string.find_lua,string.sub_lua,string.len_lua=nil,nil,nil
assert(ok,failure)
print('PASS: bundled model/JSON/storage under missing math.huge and documented native UTF8 string overrides')