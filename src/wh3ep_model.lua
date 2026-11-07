-- Byte-oriented parsing must use the original Lua operations exposed by the game.
local sub=string.sub_lua or string.sub
local byte_find=string.find_lua or string.find
local M = {}
local MAX_ID = 2147483647
local PRESET_ICONS={'general','attack','defense','scouting','magic','ranged','cavalry','command','support','supplies'}
local preset_icon_keys={}
for _,icon_key in ipairs(PRESET_ICONS) do preset_icon_keys[icon_key]=true end
function M.preset_icon_keys()
    local result={}
    for index,icon_key in ipairs(PRESET_ICONS) do result[index]=icon_key end
    return result
end
local function integer(value, minimum, maximum)
    return type(value)=='number' and value==value and value%1==0 and value>=minimum and value<=maximum
end
local function codepoint(text, offset)
    local first=text:byte(offset)
    if not first then return nil end
    if first<128 then return first,offset+1 end
    local length, value, minimum
    if first>=194 and first<=223 then length,value,minimum=2,first-192,128
    elseif first>=224 and first<=239 then length,value,minimum=3,first-224,2048
    elseif first>=240 and first<=244 then length,value,minimum=4,first-240,65536
    else return nil end
    for index=1,length-1 do
        local byte=text:byte(offset+index)
        if not byte or byte<128 or byte>191 then return nil end
        value=value*64+byte-128
    end
    if value<minimum or value>1114111 or (value>=55296 and value<=57343) then return nil end
    return value,offset+length
end
local function utf8length(text)
    local offset,count=1,0
    while offset<=#text do
        local value,next_offset=codepoint(text,offset)
        if not value then return nil end
        offset,count=next_offset,count+1
    end
    return count
end
local function whitespace(value)
    return value==32 or (value>=9 and value<=13) or value==133 or value==160 or value==5760
        or (value>=8192 and value<=8202) or value==8232 or value==8233 or value==8239 or value==8287 or value==12288
end
local function name(text)
    if type(text)~='string' or #text>1024 then return nil end
    local first,last,offset=nil,nil,1
    while offset<=#text do
        local value,next_offset=codepoint(text,offset)
        if not value then return nil end
        if not whitespace(value) then first=first or offset;last=next_offset-1 end
        offset=next_offset
    end
    if not first then return nil end
    text=sub(text,first,last)
    local length=utf8length(text)
    if not length or length>64 or byte_find(text,'[%z\1-\31\127]') then return nil end
    return text
end
local function fold(text)
    local result,offset={},1
    while offset<=#text do
        local value,next_offset=codepoint(text,offset)
        if not value then return nil end
        local original=value
        if value>=65 and value<=90 then value=value+32
        elseif value>=1040 and value<=1071 then value=value+32
        elseif value==1025 then value=1105 end
        if original==value then result[#result+1]=sub(text,offset,next_offset-1)
        elseif value<128 then result[#result+1]=string.char(value)
        else result[#result+1]=string.char(192+math.floor(value/64),128+value%64) end
        offset=next_offset
    end
    return table.concat(result)
end
local function key(value, empty)
    return type(value)=='string' and (empty or #value>0) and #value<=512 and not byte_find(value,'[%z\1-\31\127]') and utf8length(value)~=nil
end
local function array_length(value, limit)
    if type(value)~='table' then return nil end
    local count,maximum=0,0
    for index in pairs(value) do
        if not integer(index,1,limit) then return nil end
        count=count+1;maximum=math.max(maximum,index)
    end
    if count~=maximum then return nil end
    return count
end
local function tree(value, depth, seen)
    local kind=type(value)
    if kind=='string' then return utf8length(value)~=nil end
    if kind=='number' then return value-value==0 end
    if kind=='boolean' or kind=='nil' then return true end
    if kind~='table' or depth>16 or seen[value] then return false end
    seen[value]=true
    for index,item in pairs(value) do
        if (type(index)~='string' and not integer(index,1,MAX_ID)) or not tree(item,depth+1,seen) then seen[value]=nil;return false end
        if type(index)=='string' and not utf8length(index) then seen[value]=nil;return false end
    end
    seen[value]=nil
    return true
end
local function copy(value)
    if type(value)~='table' then return value end
    local result={}
    for index,item in pairs(value) do result[index]=copy(item) end
    return result
end
local function only_fields(value,allowed)
    for field in pairs(value) do if not allowed[field] then return false end end
    return true
end
local function valid_preset(preset)
    if type(preset)~='table' or type(preset.id)~='string' or not preset.id:match('^p[1-9]%d*$')
        or not integer(tonumber(sub(preset.id,2)),1,MAX_ID) then return false end
    if type(preset.name)~='string' or name(preset.name)~=preset.name or not key(preset.class_key,true) or type(preset.favorite)~='boolean'
        or (preset.character_kind~='lord' and preset.character_kind~='hero') then return false end
    if (preset.icon_key~=nil and not preset_icon_keys[preset.icon_key]) then return false end
    if not only_fields(preset,{id=true,name=true,class_key=true,character_kind=true,favorite=true,icon_key=true,equipment=true,followers=true}) then return false end
    local equipment=array_length(preset.equipment,128)
    local followers=array_length(preset.followers,128)
    if not equipment or not followers then return false end
    local slots={}
    for _,item in ipairs(preset.equipment) do
        if type(item)~='table' or not key(item.slot_key) or not key(item.item_key) or slots[item.slot_key] then return false end
        if not only_fields(item,{slot_key=true,item_key=true}) then return false end
        slots[item.slot_key]=true
    end
    for _,item in ipairs(preset.followers) do if not key(item) then return false end end
    return true
end
function M.new()
    return {schema_version=1,library_revision=0,next_id=1,factions={}}
end
function M.validate(library)
    if type(library)~='table' then return nil,'invalid_structure' end
    local schema=library.schema_version
    if type(schema)=='number' and schema>1 and schema-schema==0 and schema%1==0 then return nil,'future_schema' end
    if not tree(library,1,{}) then return nil,'invalid_structure' end
    if library.schema_version~=1 then return nil,'invalid_schema' end
    if not integer(library.library_revision,0,MAX_ID) or not integer(library.next_id,1,MAX_ID) or type(library.factions)~='table' then return nil,'invalid_header' end
    if not only_fields(library,{schema_version=true,library_revision=true,next_id=true,factions=true}) then return nil,'invalid_header' end
    local ids,maximum={},0
    for faction,entry in pairs(library.factions) do
        if not key(faction) or type(entry)~='table' or not array_length(entry.presets,500) then return nil,'invalid_faction' end
        if not only_fields(entry,{presets=true}) then return nil,'invalid_faction' end
        for _,preset in ipairs(entry.presets) do
            if not valid_preset(preset) or ids[preset.id] then return nil,'invalid_preset' end
            ids[preset.id]=true;maximum=math.max(maximum,tonumber(sub(preset.id,2)))
        end
    end
    if library.next_id<=maximum then return nil,'invalid_next_id' end
    return true
end
function M.capture(snapshot, text, class_key, id, icon_key)
    if type(snapshot)~='table' then return nil,'invalid_snapshot' end
    local normalized=name(text)
    if not normalized then return nil,'invalid_name' end
    if class_key==nil then class_key=snapshot.class_key or '' end
    if not array_length(snapshot.equipment,128) or not array_length(snapshot.followers,128) then return nil,'invalid_snapshot' end
    local preset={id=id,name=normalized,class_key=class_key,character_kind=snapshot.character_kind==nil and 'lord' or snapshot.character_kind,favorite=false,equipment={},followers={}}
    if icon_key~=nil then preset.icon_key=icon_key end
    for _,item in ipairs(snapshot.equipment) do
        if type(item)~='table' then return nil,'invalid_snapshot' end
        preset.equipment[#preset.equipment+1]={slot_key=item.slot_key,item_key=item.item_key}
    end
    for _,item in ipairs(snapshot.followers) do preset.followers[#preset.followers+1]=item end
    if not valid_preset(preset) then return nil,'invalid_preset' end
    return preset
end
function M.add(library,snapshot,text,class_key,icon_key)
    local ok,code=M.validate(library);if not ok then return nil,code end
    if type(snapshot)~='table' or not key(snapshot.faction_key) then return nil,'invalid_faction' end
    local faction=snapshot.faction_key
    if library.factions[faction] and #library.factions[faction].presets>=500 then return nil,'preset_limit' end
    if library.next_id>=MAX_ID or library.library_revision>=MAX_ID then return nil,'revision_limit' end
    if icon_key==nil then icon_key='general' end
    local preset,error_code=M.capture(snapshot,text,class_key,'p'..tostring(library.next_id),icon_key)
    if not preset then return nil,error_code end
    local result=copy(library)
    result.factions[faction]=result.factions[faction] or {presets={}}
    local presets=result.factions[faction].presets
    presets[#presets+1]=preset
    result.next_id=result.next_id+1;result.library_revision=result.library_revision+1
    return result,copy(preset)
end
local function find(library,faction,id)
    local entry=library.factions[faction]
    if entry then for index,preset in ipairs(entry.presets) do if preset.id==id then return index,preset end end end
end
function M.update(library,faction,id,patch)
    local ok,code=M.validate(library);if not ok then return nil,code end
    if type(patch)~='table' or not tree(patch,1,{}) then return nil,'invalid_patch' end
    local allowed={name=true,class_key=true,character_kind=true,favorite=true,icon_key=true,equipment=true,followers=true}
    for field in pairs(patch) do if not allowed[field] then return nil,'invalid_patch' end end
    local index,previous=find(library,faction,id)
    if not index then return nil,'not_found' end
    if library.library_revision>=MAX_ID then return nil,'revision_limit' end
    local changed=copy(previous)
    for field,value in pairs(patch) do changed[field]=copy(value) end
    local preset,error_code=M.capture(changed,changed.name,changed.class_key,id,changed.icon_key)
    if not preset then return nil,error_code end
    preset.favorite=changed.favorite
    if not valid_preset(preset) then return nil,'invalid_preset' end
    local result=copy(library)
    result.factions[faction].presets[index]=preset
    result.library_revision=result.library_revision+1
    return result,copy(preset)
end
function M.delete(library,faction,id)
    local ok,code=M.validate(library);if not ok then return nil,code end
    local index=find(library,faction,id)
    if not index then return nil,'not_found' end
    if library.library_revision>=MAX_ID then return nil,'revision_limit' end
    local result=copy(library)
    table.remove(result.factions[faction].presets,index)
    result.library_revision=result.library_revision+1
    return result
end
function M.list(library,faction,class_key,filter,query,kind)
    local ok,code=M.validate(library);if not ok then return nil,code end
    filter,query,kind=filter or 'matching',query or '',kind or 'lord'
    if filter~='matching' and filter~='general' and filter~='all' and filter~='favorites' then return nil,'invalid_filter' end
    if type(query)~='string' then return nil,'invalid_query' end
    query=fold(query);if not query then return nil,'invalid_query' end
    local result={}
    local entry=library.factions[faction]
    for _,preset in ipairs(entry and entry.presets or {}) do
        local matches_class=preset.class_key=='' or preset.class_key==class_key
        local matches_filter=filter=='all' or (filter=='general' and preset.class_key=='')
            or (filter=='matching' and matches_class) or (filter=='favorites' and matches_class and preset.favorite)
        if (preset.class_key=='' or preset.character_kind==kind) and matches_filter and byte_find(fold(preset.name),query,1,true) then result[#result+1]=copy(preset) end
    end
    table.sort(result,function(left,right)
        if left.favorite~=right.favorite then return left.favorite end
        local a,b=fold(left.name),fold(right.name)
        if a~=b then return a<b end
        return tonumber(sub(left.id,2))<tonumber(sub(right.id,2))
    end)
    return result
end
return M
