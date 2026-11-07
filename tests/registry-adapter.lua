-- Diagnose the actual engine adapter without logging any stored text or raw errors.
local f=assert(io.open('.superpowers/library-probe-bundle.lua','rb'))
local source=f:read('*a');f:close()
local mode,stored,logs='ok',nil,{}
local core={svr_save_registry_string=function(_,key,value)
 if mode=='write_error'then error('PRIVATE_ERROR_MARKER',0)end
 if mode=='false'then return false end
 stored=mode=='truncated'and value:sub(1,3)or value
end,svr_load_registry_string=function()
 if mode=='read_error'then error('PRIVATE_ERROR_MARKER',0)end
 return stored
end}
local env=setmetatable({core=core,ModLog=function(value)logs[#logs+1]=value end},{__index=_G})
local chunk=assert(loadstring(source..[[
local captured
wh3ep_registry_factory=function(native)return native end
wh3ep_storage_factory=function(_,_,registry)captured=registry;return{}end
wh3ep_library_ui_factory=function()return{start=function()end}end
wh3ep_probe()
return captured
]],'@registry-adapter-bundle'))
setfenv(chunk,env)
local registry=chunk()
local payload='PRIVATE_PRESET_VALUE'
local key='wh3ep_library_pending_v1'
local function run(which)
 mode,stored,logs=which,nil,{}
 local ok,result=pcall(registry.write,key,payload)
 local output=table.concat(logs,'\n')
 assert(not output:find('PRIVATE_',1,true),'diagnostics must not contain payloads or exception text')
 return ok,result,output
end
local ok,result,output=run('ok')
assert(ok and result==nil and stored==payload)
assert(output:find('registry_write_role=pending',1,true),'must identify own storage role')
assert(output:find('expected_bytes=20',1,true)and output:find('observed_bytes=20',1,true)and output:find('equal=true',1,true),'must identify exact readback')
ok,result,output=run('false')
assert(ok and result==false and output:find('returned_false=true',1,true),'must distinguish native false result')
ok,result,output=run('truncated')
assert(ok and output:find('observed_bytes=3',1,true)and output:find('equal=false',1,true),'must distinguish truncated readback')
ok,result,output=run('write_error')
assert(not ok and output:find('write_ok=false',1,true),'write exception must remain a failure with safe diagnostics')
ok,result,output=run('read_error')
assert(ok and output:find('read_ok=false',1,true),'read exception must be diagnosed without masking successful native write result')
print('PASS: actual registry adapter reports safe byte counts/results/readback without payload or raw-error disclosure')