-- Assemble the diagnostic library probe from its source modules.
local modules = {
    { 'wh3ep_json', 'vendor/dkjson/dkjson.lua' },
    { 'wh3ep_model', 'src/wh3ep_model.lua' },
    { 'wh3ep_storage_factory', 'src/wh3ep_storage.lua' },
    { 'wh3ep_registry_factory', 'src/wh3ep_registry.lua' },
    { 'wh3ep_apply_factory', 'src/wh3ep_apply.lua' },
    { 'wh3ep_equipment_factory', 'src/wh3ep_equipment.lua' },
    { 'wh3ep_locale_ru', 'src/locales/ru.lua' },
    { 'wh3ep_locale_eng', 'src/locales/eng.lua' },
    { 'wh3ep_locale_cn', 'src/locales/cn.lua' },
    { 'wh3ep_locale_zh', 'src/locales/zh.lua' },
    { 'wh3ep_locale_sp', 'src/locales/sp.lua' },
    { 'wh3ep_locale_br', 'src/locales/br.lua' },
    { 'wh3ep_locale_ge', 'src/locales/ge.lua' },
    { 'wh3ep_locale_ja', 'src/locales/ja.lua' },
    { 'wh3ep_locale_fr', 'src/locales/fr.lua' },
    { 'wh3ep_locale_pl', 'src/locales/pl.lua' },
    { 'wh3ep_locale_kr', 'src/locales/kr.lua' },
    { 'wh3ep_localization_factory', 'src/wh3ep_localization.lua' },
    { 'wh3ep_library_ui_factory', 'src/wh3ep_library_ui.lua' },
}
local root = (arg and arg[1]) or '.'

local function project_path(path)
    return root .. '/' .. path
end

local function read(path)
    local file = assert(io.open(project_path(path), 'rb'))
    local value = file:read('*a')
    file:close()
    return value
end

local output = {}
for _, module in ipairs(modules) do
    output[#output + 1] = 'local ' .. module[1] .. ' = (function()\n'
    if module[1] == 'wh3ep_json' then
        output[#output + 1] = [[local string=setmetatable({find=string.find_lua or string.find,sub=string.sub_lua or string.sub,len=string.len_lua or string.len},{__index=string})
local math=setmetatable({huge=1/0},{__index=math})
]]
    end
    output[#output + 1] = read(module[2])
    output[#output + 1] = '\nend)()\n'
end
output[#output + 1] = read('spikes/wh3ep_library_probe.lua')

local target = assert(io.open(project_path('.superpowers/library-probe-bundle.lua'), 'wb'))
target:write(table.concat(output))
target:close()
print('PASS: assembled diagnostic library probe bundle from current sources')
