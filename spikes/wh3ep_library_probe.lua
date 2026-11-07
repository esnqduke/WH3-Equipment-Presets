-- Bundled after lexical model, JSON, storage and UI modules by build-library-probe.ps1.
local wh3ep_library_started=false
function wh3ep_probe()
    if wh3ep_library_started then return end
    wh3ep_library_started=true
    local native_registry={
        read=function(key)return core:svr_load_registry_string(key)end,
        write=function(key,value)
            -- lib_core forwards the native return without documenting its meaning.
            -- Keep failure policy unchanged; only observe the write/read boundary.
            local roles={wh3ep_library_v1='primary',wh3ep_library_backup_v1='backup',
                wh3ep_library_pending_v1='pending',wh3ep_library_damaged_v1='damaged'}
            local role=roles[key]
            if not role then
                local parent=key:match('^(.-)_chunks_v1_')
                role=parent and roles[parent]and (roles[parent]..'_chunk')or 'unknown'
            end
            local ok,result=pcall(function()return core:svr_save_registry_string(key,value)end)
            local read_ok,actual=pcall(function()return core:svr_load_registry_string(key)end)
            local observed=type(actual)=='string' and #actual or -1
            ModLog('[WH3EP] registry_write_role='..role
                ..' expected_bytes='..tostring(#value)..' write_ok='..tostring(ok)
                ..' returned_type='..type(result)..' returned_false='..tostring(result==false)
                ..' read_ok='..tostring(read_ok)..' observed_bytes='..tostring(observed)
                ..' equal='..tostring(read_ok and actual==value))
            if not ok then error('native_registry_write_failed',0)end
            return result
        end
    }
    local registry=wh3ep_registry_factory(native_registry)
    local storage=wh3ep_storage_factory(wh3ep_model,wh3ep_json,registry)
    local function describe(cqi)
        ModLog('[WH3EP] describe_stage=lookup')
        if cm:is_multiplayer()then return nil,'multiplayer'end
        local character=cm:get_character_by_cqi(cqi)
        if not character or character:is_null_interface()then return nil,'select_character'end
        local kind
        if character:character_type('general')then
            -- Stock 8.1 lib_campaign_manager: armed-citizenry commanders are garrisons.
            if cm:char_is_garrison_commander(character)then return nil,'select_character'end
            kind='lord'
        elseif cm:char_is_agent(character)then kind='hero'
        else return nil,'select_character'end
        local faction=character:faction():name()
        if faction~=cm:get_local_faction_name()then return nil,'select_character'end
        ModLog('[WH3EP] describe_stage=name')
        local named,name=pcall(function()return cm:char_name_to_string(character)end)
        ModLog('[WH3EP] describe_stage=ready')
        return {cqi=cqi,faction_key=faction,class_key=character:character_subtype_key(),character_kind=kind,name=named and type(name)=='string'and name or nil}
    end
    local function capture(cqi)
        local snapshot,code=describe(cqi)
        if not snapshot then return nil,code end
        ModLog('[WH3EP] library_capture_begin')
        ModLog('[WH3EP] library_capture_kind='..snapshot.character_kind)
        ModLog('[WH3EP] library_capture_caravan='..tostring(snapshot.class_key=='wh3_main_cth_lord_caravan_master'))
        local context=cco('CcoCampaignCharacter',cqi)
        if not context then return nil,'capture_failed'end
        local count=context:Call('AncillaryList.Size')
        if type(count)~='number'or count<0 or count>100 or count%1~=0 then return nil,'capture_failed'end
        snapshot.equipment,snapshot.followers={},{}
        local slots={}
        for index=0,count-1 do
            local entry='AncillaryList.At('..tostring(index)..').AncillaryRecordContext.'
            local item=context:Call(entry..'Key')
            local slot=context:Call(entry..'CategoryContext.Key')
            local category=context:Call(entry..'CategoryContext.Category')
            local hidden=context:Call(entry..'CategoryContext.IsHidden')
            if type(item)~='string'or type(slot)~='string'or type(category)~='string'or type(hidden)~='boolean'then return nil,'capture_failed'end
            if not hidden and category~='mount' then
                if category=='general'then snapshot.followers[#snapshot.followers+1]=item
                else
                    if slots[slot]then ModLog('[WH3EP] library_unsupported_multislot');return nil,'unsupported_category'end
                    slots[slot]=true
                    snapshot.equipment[#snapshot.equipment+1]={slot_key=slot,item_key=item}
                end
            end
        end
        ModLog('[WH3EP] library_capture_equipment='..tostring(#snapshot.equipment))
        ModLog('[WH3EP] library_capture_followers='..tostring(#snapshot.followers))
        return snapshot
    end
    local equipment=wh3ep_equipment_factory(describe)
    local apply=wh3ep_apply_factory(equipment)
    local ui=wh3ep_library_ui_factory(wh3ep_model,storage,{describe=describe,capture=capture,apply=apply,inspect=equipment.snapshot})
    ui.start()
    ModLog('[WH3EP] library_version=0.7.16')
    ModLog('[WH3EP] library_listeners_ready')
end
