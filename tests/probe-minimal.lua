-- The isolated loader probe must use only the stock logger, exactly once.
local output = ""
local original_io, original_os, original_cm, original_cco = io, os, cm, cco
local forbidden = setmetatable({}, {__index = function() error("minimal probe used an excluded API") end})
ModLog = function(message) output = output .. message .. "\n" end
assert(loadfile("spikes/wh3ep_probe_minimal.lua"))()
io, os, cm = forbidden, forbidden, forbidden
cco = function() error("minimal probe queried CCO") end
wh3ep_probe()
wh3ep_probe()
io, os, cm, cco = original_io, original_os, original_cm, original_cco
assert(output == "[WH3EP] minimal_version=0.1.1\n[WH3EP] minimal_complete\n", "minimal probe must log once without filesystem or campaign APIs")
print("PASS: minimal loader probe excludes filesystem, campaign, and CCO APIs")