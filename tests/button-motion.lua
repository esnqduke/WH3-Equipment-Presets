local function read(path)
    local file = assert(io.open(path, 'rb'))
    local value = file:read('*a')
    file:close()
    return value
end

local function attr(text, name)
    return text:match(name .. '="([^"]+)"')
end

local function state_body(component, name)
    return component:match('<' .. name .. '%s+([^>]*)>(.-)</' .. name .. '>')
end

local names = {'wh3ep_primary','wh3ep_secondary','wh3ep_compact_primary','wh3ep_compact_secondary','wh3ep_apply','wh3ep_help'}
local state_names = {'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off'}
local transitions = {
    {'active','0','hover',140},
    {'hover','1','active',140},{'hover','2','down',50},
    {'down','1','down_off',90},{'down','3','hover',90},
    {'down_off','0','down',50},{'down_off','8','active',90},
    {'selected','0','selected_hover',140},
    {'selected_hover','1','selected',140},{'selected_hover','2','selected_down',50},
    {'selected_down','1','selected_down_off',90},{'selected_down','3','selected_hover',90},
    {'selected_down_off','0','selected_down',50},{'selected_down_off','8','selected',90}
}

for _, name in ipairs(names) do
    local xml = read('src/ui/' .. name .. '.twui.xml')
    local component = assert(xml:match('<' .. name .. '%s.-</' .. name .. '>'), name .. ' component exists')
    local state_guids = {}
    for _, state_name in ipairs(state_names) do
        local state_attrs, body = state_body(component, state_name)
        assert(state_attrs and body, name .. ' must define ' .. state_name)
        state_guids[state_name] = attr(state_attrs, 'uniqueguid')
        local layer_count = 0
        for _ in body:gmatch('<image%s') do layer_count = layer_count + 1 end
        assert(layer_count == 4, name .. '/' .. state_name .. ' needs base, hover, down and inactive layers')
    end
    for _, transition in ipairs(transitions) do
        local from, event, to, milliseconds = unpack(transition)
        local _, body = state_body(component, from)
        local found = false
        for attrs in body:gmatch('<transition%s+([^>]+)/>') do
            if attr(attrs, 'index') == event then
                found = true
                local target = attr(attrs, 'transition_m_target_state')
                assert(target == state_guids[to], name .. ' ' .. from .. ' transition target ' .. event)
                assert(attr(attrs, 'transition_m_transition_time') == tostring(milliseconds), name .. ' ' .. from .. ' transition duration ' .. event)
                assert(attr(attrs, 'transition_m_interpolation_property_mask') == '64', name .. ' ' .. from .. ' must interpolate image opacity')
            end
        end
        assert(found, name .. ' missing ' .. from .. ' transition ' .. event)
    end
end

local static_layers = {
    wh3ep_entry = 5, wh3ep_star = 9, wh3ep_checkbox = 9, wh3ep_radio = 9,
    wh3ep_preset_icon_option = 9, wh3ep_row = 7, wh3ep_filter = 4
}
for name, expected_count in pairs(static_layers) do
    local xml = read('src/ui/' .. name .. '.twui.xml')
    local component = assert(xml:match('<' .. name .. '%s.-</' .. name .. '>'))
    for _, state_name in ipairs(state_names) do
        local _, body = state_body(component, state_name)
        local count = 0
        for _ in body:gmatch('<image%s') do count = count + 1 end
        assert(count == expected_count, name .. '/' .. state_name .. ' overlay layer count')
    end
    for _, transition in ipairs(transitions) do
        local from, event, to, milliseconds = unpack(transition)
        local _, body = state_body(component, from)
        local found = false
        for attrs in body:gmatch('<transition%s+([^>]+)/>') do
            if attr(attrs, 'index') == event then
                found = true
                assert(attr(attrs, 'transition_m_transition_time') == tostring(milliseconds), name .. ' ' .. from .. ' transition duration ' .. event)
                assert(attr(attrs, 'transition_m_interpolation_property_mask') == '64', name .. ' ' .. from .. ' must interpolate image opacity')
            end
        end
        assert(found, name .. ' missing ' .. from .. ' transition ' .. event)
    end
end

for _, name in ipairs({'wh3ep_toggle_label','wh3ep_radio_text'}) do
    local xml = read('src/ui/' .. name .. '.twui.xml')
    local component = assert(xml:match('<' .. name .. '%s.-</' .. name .. '>'))
    for _, transition in ipairs(transitions) do
        local from, event, to, milliseconds = unpack(transition)
        local _, body = state_body(component, from)
        for attrs in body:gmatch('<transition%s+([^>]+)/>') do
            if attr(attrs, 'index') == event then
                assert(attr(attrs, 'transition_m_transition_time') == tostring(milliseconds), name .. ' ' .. from .. ' text transition duration ' .. event)
                assert(attr(attrs, 'transition_m_interpolation_property_mask') == '8', name .. ' text-color interpolation mask')
            end
        end
    end
end

local picker = read('src/ui/wh3ep_preset_icon_option.twui.xml')
local picker_component = assert(picker:match('<wh3ep_preset_icon_option%s.-</wh3ep_preset_icon_option>'))
for _, state_name in ipairs(state_names) do
    local _, body = state_body(picker_component, state_name)
    local text = assert(body:match('<component_text%s+([^>]+)/>'), 'picker caption exists in ' .. state_name)
    local left, right = attr(text, 'textxoffset'):match('([^,]+),([^,]+)')
    local _, bottom = attr(text, 'textyoffset'):match('([^,]+),([^,]+)')
    assert(tonumber(left) >= 4 and tonumber(right) >= 4, 'picker caption keeps 5% horizontal margins in ' .. state_name)
    assert((attr(text, 'text') or '') == '', 'picker has no visible caption in ' .. state_name)
end

local centered = {
    'wh3ep_apply','wh3ep_compact_primary','wh3ep_compact_secondary','wh3ep_counter','wh3ep_entry','wh3ep_filter',
    'wh3ep_heading','wh3ep_help','wh3ep_primary','wh3ep_preset_icon_option','wh3ep_preview_heading','wh3ep_preview_ribbon',
    'wh3ep_preview_subtitle','wh3ep_secondary','wh3ep_status','wh3ep_subtitle','wh3ep_summary_text'
}
for _, name in ipairs(centered) do
    local xml = read('src/ui/' .. name .. '.twui.xml')
    local component = assert(xml:match('<' .. name .. '%s.-</' .. name .. '>'))
    for _, state_name in ipairs(state_names) do
        local attrs, body = state_body(component, state_name)
        if attrs and body then
            local width = tonumber(attr(attrs, 'width'))
            for text_attrs in body:gmatch('<component_text%s+([^>]+)/>') do
                if attr(text_attrs, 'texthalign') == 'Center' then
                    local x = attr(text_attrs, 'textxoffset')
                    local left, right = x:match('([^,]+),([^,]+)')
                    left, right = tonumber(left), tonumber(right)
                    if name == 'wh3ep_entry' then
                        assert(left >= 52 and right >= 8, 'entry text safe zone preserves icon reservation')
                    else
                        local minimum = width * 0.05
                        assert(left >= minimum and right >= minimum, name .. '/' .. state_name .. ' centered text must keep 5% side margins')
                        assert(math.abs(left - right) <= 1, name .. '/' .. state_name .. ' centered text offsets must be symmetric')
                    end
                end
            end
        end
    end
end

print('PASS: WH3 button opacity transitions, image layers and centered text safe zones')
