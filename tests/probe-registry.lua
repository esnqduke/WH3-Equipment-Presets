-- Exercise the probe protocol at the native engine-storage boundary.
local stored, output = nil, ""
local key = "wh3ep_probe_persistence_v1"
local io_original, os_original, cm_original, cco_original = io, os, cm, cco
local forbidden = setmetatable({}, {__index=function() error("registry probe used an excluded API") end})
local drop_writes = false
core = {
    svr_load_registry_string=function(self, name) assert(name==key, "unexpected registry namespace"); return stored end,
    svr_save_registry_string=function(self, name, value)
        assert(name==key, "unexpected registry namespace")
        if drop_writes then return false end
        stored=value
        return true
    end
}
ModLog=function(message) output=output..message.."\n" end
local function run()
    assert(loadfile("spikes/wh3ep_probe_registry.lua"))()
    io,os,cm=forbidden,forbidden,forbidden
    cco=function() error("registry probe queried CCO") end
    wh3ep_probe()
    wh3ep_probe()
    io,os,cm,cco=io_original,os_original,cm_original,cco_original
end
run()
assert(stored=="WH3EP1\n1\nТестовый пресет\n", "first session must save exact Unicode payload in own registry key")
assert(output:find("registry_complete",1,true), "successful roundtrip must be reported")
output="";run()
assert(stored=="WH3EP1\n2\nТестовый пресет\n", "new Lua session must increment existing engine state")
stored="WH3EP1\n2\n";output="";run()
assert(stored=="WH3EP1\n2\n", "malformed engine state must be preserved")
assert(output:find("registry_state_invalid",1,true), "invalid state must be reported")
stored="WH3EP1\n2\nТестовый пресет\n";drop_writes=true;output="";run()
assert(stored=="WH3EP1\n2\nТестовый пресет\n", "rejected writes must leave stored data unchanged")
assert(output:find("registry_roundtrip_failed",1,true), "failed write must be detected through readback")
assert(not output:find("registry_complete",1,true), "failed write must not produce success marker")
print("PASS: native-storage protocol, Unicode payload, session reuse, malformed-state preservation, failed-write detection")