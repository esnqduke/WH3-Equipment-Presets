-- Behavioral checks for the diagnostic pack. It must persist across sessions,
-- read a loadout, and never require any inventory mutation API.
local root = assert(arg[1], "test root required")
local source = "spikes/wh3ep_probe.lua"
local fixture = root .. "/The Creative Assembly/Warhammer3/"
local function read(name)
    local f = assert(io.open(fixture .. name, "rb"))
    local value = f:read("*a")
    f:close()
    return value
end
local function clear(name) os.remove(fixture .. name) end
for _, name in ipairs({"wh3ep_probe_state.txt", "wh3ep_probe.log", "wh3ep_probe_capture.txt"}) do clear(name) end
local actual_getenv = os.getenv
os.getenv = function(key) if key == "APPDATA" then return root end return actual_getenv(key) end
common = { game_version = function() return "8.1.0.0" end }
local leader = { command_queue_index = function() return 42 end, character_subtype_key = function() return "test_lord" end }
local faction = { name = function() return "test_faction" end, faction_leader = function() return leader end }
cm = { is_multiplayer = function() return false end, get_local_faction = function() return faction end }
ModLog = function() end
cco = function(kind, id)
    local values
    if kind == "CcoCampaignCharacter" and id == 42 then
        values = { ["AncillaryList.Size"] = 1,
            ["AncillaryList.At(0).AncillaryRecordContext.Key"] = "test_sword",
            ["AncillaryList.At(0).AncillaryRecordContext.CategoryContext.Key"] = "weapon",
            ["SelectedOrContainedCharacter.CQI"] = 42 }
    elseif kind == "CcoCampaignFaction" and id == "test_faction" then
        values = { ["AncillaryList.Size"] = 2 }
    else error("unexpected CCO target") end
    return { Call = function(self, expr) return values[expr] end }
end
local chunk = loadfile(source)
assert(chunk, "probe source not implemented")
chunk()
assert(type(wh3ep_probe) == "function", "native loader entry point missing")
wh3ep_probe()
assert(read("wh3ep_probe_state.txt"):match("^WH3EP1\n1\n"), "first run must persist counter 1")
local capture = read("wh3ep_probe_capture.txt")
assert(capture:find("faction=test_faction", 1, true), "capture must retain faction key")
assert(capture:find("class=test_lord", 1, true), "capture must retain class key")
assert(capture:find("test_sword|weapon", 1, true), "capture must retain item and slot category")
assert(read("wh3ep_probe.log"):find("character_equipped=1", 1, true), "loadout count must be recorded")
-- Reload the chunk like a fresh campaign Lua environment.
assert(loadfile(source))()
wh3ep_probe()
assert(read("wh3ep_probe_state.txt"):match("^WH3EP1\n2\n"), "a new session must retain the first run")
local f = assert(io.open(fixture .. "wh3ep_probe_state.txt", "wb"))
f:write("broken state"); f:close()
assert(loadfile(source))()
wh3ep_probe()
assert(read("wh3ep_probe_state.txt") == "broken state", "corrupt state must not be overwritten")
assert(read("wh3ep_probe.log"):find("state_invalid", 1, true), "corrupt state must produce a diagnostic")
-- Valid prefixes must not make truncated or modified files safe to overwrite.
for _, malformed in ipairs({"WH3EP1\n2\n", "WH3EP1\n2\ncorrupted\n", "WH3EP1\n2\nТестовый пресет\njunk", "WH3EP1\n2\nТестовый пресет\n" .. string.rep("x", 600)}) do
    local state = assert(io.open(fixture .. "wh3ep_probe_state.txt", "wb"))
    state:write(malformed); state:close()
    assert(loadfile(source))()
    wh3ep_probe()
    assert(read("wh3ep_probe_state.txt") == malformed, "a truncated state or valid prefix with extra bytes must remain untouched")
end
-- A failing capture stream must not produce a false success marker.
local good_state = assert(io.open(fixture .. "wh3ep_probe_state.txt", "wb"))
good_state:write("WH3EP1\n2\nТестовый пресет\n"); good_state:close()
local log_before = #read("wh3ep_probe.log")
local actual_open = io.open
io.open = function(path, mode)
    if path:find("wh3ep_probe_capture.txt", 1, true) and mode == "wb" then
        return { write = function() return nil, "disk full" end, close = function() return true end }
    end
    return actual_open(path, mode)
end
assert(loadfile(source))()
wh3ep_probe()
io.open = actual_open
local failure_log = read("wh3ep_probe.log"):sub(log_before + 1)
assert(failure_log:find("capture_write_failed", 1, true), "capture write failure must be logged")
assert(not failure_log:find("probe_complete", 1, true), "capture failure must not be reported as complete")
os.getenv = actual_getenv
print("PASS: persistent counter, faction/class/item capture, new session, corrupt-file preservation")
