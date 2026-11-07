-- WH3 8.1 native boundary. No issuing/removing ancillaries; only EquipToCharacter.
local binding='(target = this) => {target | '
local function integer(n,min,max)return type(n)=='number'and n-n==0 and n%1==0 and n>=min and n<=max end
local function same_counts(a,b)
    for k,n in pairs(a)do if n~=(b[k]or 0)then return false end end
    for k,n in pairs(b)do if n~=(a[k]or 0)then return false end end
    return true
end
return function(describe)
    local E={}
    local function guarded(stage,callback)
        local ok,result,code=pcall(callback)
        if not ok then
            ModLog('[WH3EP] equipment_native_error='..stage)
            pcall(function()
                local line=type(result)=='string'and result:match(':(%d+):')or 'unknown'
                ModLog('[WH3EP] equipment_native_error_line='..(line or 'unknown'))
            end)
            return nil,'engine_error'
        end
        return result,code
    end
    local function target(cqi)
        local info,code=describe(cqi)
        if not info then return nil,code end
        if not cm:is_factions_turn_by_key(info.faction_key)then return nil,'wrong_turn'end
        local context=cco('CcoCampaignCharacter',cqi)
        if not context or tonumber(context:Call(binding..'target.CQI}'))~=cqi then return nil,'context_changed'end
        return context,info
    end
    local function owner(context,prefix)
        local valid=context:Call('IsContextValid('..prefix..'CharacterEquippedToContext)')
        if valid==false then return 0 end
        if valid~=true then error('invalid_owner',0)end
        local cqi=tonumber(context:Call(prefix..'CharacterEquippedToContext.CQI'))
        if not integer(cqi,1,2147483647)then error('invalid_owner',0)end
        return cqi
    end
    local function source(context,item)
        local n=context:Call('FactionContext.AncillaryList.Size')
        if not integer(n,0,2000)or not integer(item.index,0,n-1)then return nil,'inventory_changed'end
        local direct='FactionContext.AncillaryList.At('..item.index..').'
        if context:Call(direct..'AncillaryRecordContext.Key')~=item.key or owner(context,direct)~=item.owner then return nil,'inventory_changed'end
        if item.owner~=0 and not describe(item.owner)then return nil,'donor_unavailable'end
        return 'target.'..direct:sub(1,-2)
    end
    local function capacity(context,entry)
        local value=context:Call(binding..entry..'.AncillaryRecordContext.CategoryContext.NumAllowedPerCharacterForFaction(target, target.FactionContext.FactionRecordContext)}')
        return integer(value,0,100)and value or false
    end
    function E.snapshot(cqi)
        return guarded('snapshot',function()
            local context,info=target(cqi);if not context then return nil,info end
            local n=context:Call('FactionContext.AncillaryList.Size')
            if not integer(n,0,2000)then return nil,'inventory_too_large'end
            local state={target=info,instances={},equipped={},counts={},owners={},donors={},names={},icons={},rarities={},tooltips={}}
            local records,capacities={},{}
            local function metadata(direct,bound)
                local key=context:Call(direct..'Key')
                if type(key)~='string'then error('invalid_item',0)end
                if not records[key]then
                    local slot=context:Call(direct..'CategoryContext.Key')
                    local category=context:Call(direct..'CategoryContext.Category')
                    local hidden=context:Call(direct..'CategoryContext.IsHidden')
                    if type(slot)~='string'or type(category)~='string'or type(hidden)~='boolean'then error('invalid_category',0)end
                    if capacities[slot]==nil then capacities[slot]=capacity(context,bound)end
                    local named,name=pcall(function()return context:Call(direct..'OnscreenName')end)
                    state.names[key]=named and type(name)=='string'and name~=''and name or nil
                    local pictured,path=pcall(function()return context:Call(binding..bound..'.IconPath}')end)
                    if pictured and type(path)=='string'and path~=''then state.icons[key]=path end
                    -- Installed 8.1 ancillary tooltip: RarityState, EffectList, CcoEffect.LocalisedText.
                    local ranked,rarity=pcall(function()return context:Call(direct..'RarityState')end)
                    if ranked and (rarity=='common'or rarity=='uncommon'or rarity=='rare'or rarity=='legendary'or rarity=='crafted')then state.rarities[key]=rarity end
                    local described,text=pcall(function()
                        local count=context:Call(direct..'EffectList.Size')
                        -- Bound optional presentation work; this is not an engine inventory limit.
                        if not integer(count,1,64)then return nil end
                        local lines={}
                        for index=0,count-1 do
                            local line=context:Call(direct..'EffectList.At('..index..').LocalisedText')
                            if type(line)~='string'then return nil end
                            if line~=''then lines[#lines+1]=line end
                        end
                        return #lines>0 and table.concat(lines,'\n')or nil
                    end)
                    if described then state.tooltips[key]=text end
                    records[key]={key=key,slot_key=slot,category=category,hidden=hidden,capacity=capacities[slot]}
                end
                return records[key]
            end
            for index=0,n-1 do
                local direct='FactionContext.AncillaryList.At('..index..').'
                local meta=metadata(direct..'AncillaryRecordContext.','target.'..direct:sub(1,-2))
                local who=owner(context,direct)
                local item={index=index,key=meta.key,slot_key=meta.slot_key,category=meta.category,hidden=meta.hidden,capacity=meta.capacity,owner=who}
                state.instances[#state.instances+1]=item
                state.counts[item.key]=(state.counts[item.key]or 0)+1
                state.owners[who]=state.owners[who]or{};state.owners[who][item.key]=(state.owners[who][item.key]or 0)+1
                if who~=0 and who~=cqi and state.donors[who]==nil then
                    local donor=describe(who)
                    if donor then
                        local named,name=pcall(function()return cm:char_name_to_string(cm:get_character_by_cqi(who))end)
                        state.donors[who]={character_kind=donor.character_kind,name=named and type(name)=='string'and name~=''and name or nil}
                    end
                end
            end
            local count=context:Call('AncillaryList.Size')
            if not integer(count,0,100)then return nil,'invalid_target_inventory'end
            local target_counts,pool_counts={},{}
            for index=0,count-1 do
                local direct='AncillaryList.At('..index..').'
                local meta=metadata(direct..'AncillaryRecordContext.','target.'..direct:sub(1,-2))
                if not meta.hidden and meta.category~='mount'then
                    state.equipped[#state.equipped+1]={target_index=index,key=meta.key,slot_key=meta.slot_key,category=meta.category}
                    target_counts[meta.key]=(target_counts[meta.key]or 0)+1
                end
            end
            for _,item in ipairs(state.instances)do if item.owner==cqi and not item.hidden and item.category~='mount'then pool_counts[item.key]=(pool_counts[item.key]or 0)+1 end end
            if not same_counts(target_counts,pool_counts)then return nil,'inventory_changed'end
            return state
        end)
    end
    function E.compatible(cqi,item)
        return guarded('compatible',function()
            local context,code=target(cqi);if not context then return nil,code end
            local entry,why=source(context,item);if not entry then return nil,why end
            local value=context:Call(binding..entry..'.CanCharacterEquip(target)}')
            if type(value)~='boolean'then return nil,'engine_error'end
            return value
        end)
    end
    function E.equip(cqi,action)
        return guarded('equip',function()
            local context,code=target(cqi);if not context then return nil,code end
            local entry,why=source(context,action.candidate);if not entry then return nil,why end
            if context:Call(binding..entry..'.CanCharacterEquip(target)}')~=true then return nil,'incompatible'end
            local allowed=capacity(context,entry)
            local old
            if action.replacement then
                local item=action.replacement
                local count=context:Call('AncillaryList.Size')
                if not integer(count,0,100)or not integer(item.target_index,0,count-1)then return nil,'inventory_changed'end
                local direct='AncillaryList.At('..item.target_index..').AncillaryRecordContext.'
                if context:Call(direct..'Key')~=item.key or context:Call(direct..'CategoryContext.Key')~=item.slot_key then return nil,'inventory_changed'end
                old='target.AncillaryList.At('..item.target_index..')'
            end
            if action.category=='general'then
                local general='target.AncillaryList.Filter(AncillaryRecordContext.CategoryContext.Category == "general")'
                local occupied=context:Call(binding..general..'.Size}')
                if not integer(allowed,1,100)or not integer(occupied,0,allowed)then return nil,'no_slot'end
                if not old then
                    if occupied~=action.empty_index or occupied>=allowed then return nil,'inventory_changed'end
                    -- PadRight is UI list padding, not the ancillary argument passed by ContextSlot.
                    -- An empty ancillary list yields the same absent replacement form as empty gear slots.
                    local empty='target.AncillaryList.Filter(AncillaryRecordContext.Key != AncillaryRecordContext.Key)'
                    if context:Call(binding..empty..'.Size}')~=0 then return nil,'context_changed'end
                    old=empty..'.FirstContext'
                    local valid=context:Call(binding..'IsContextValid('..old..')}')
                    if valid~=false then return nil,'context_changed'end
                    ModLog('[WH3EP] apply_empty_follower_context_valid=false')
                end
            else
                if allowed~=1 then return nil,'unsupported'end
                local same_slot='target.AncillaryList.Filter(AncillaryRecordContext.CategoryContext.Key == '..entry..'.AncillaryRecordContext.CategoryContext.Key)'
                local occupied=context:Call(binding..same_slot..'.Size}')
                if occupied~=(old and 1 or 0)then return nil,'inventory_changed'end
                old=old or same_slot..'.FirstContext'
            end
            -- No yielding between final checks and the native operation.
            local result=context:Call(binding..entry..'.EquipToCharacter(target, '..old..')}')
            if result==false then return nil,'rejected'end
            ModLog('[WH3EP] apply_native_command_source='..(action.candidate.owner==0 and 'free'or 'donor'))
            return true
        end)
    end
    function E.schedule(callback,delay)cm:callback(callback,delay)end
    return E
end
