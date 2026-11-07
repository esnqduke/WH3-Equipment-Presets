local store, output, listeners = {}, "", {}
local selected, opened, queried = nil, false, 0
local prefix = "wh3ep_probe_persistence_v1"
local item_count = 1
ModLog=function(message) output=output..message.."\n" end
local ui_root = {}
local panel = {Priority=function() return 50 end}
local text={SetStateText=function() end}
local priority
local button={SetStateText=function() end,SetVisible=function() end,MoveTo=function() end,PropagatePriority=function(self,value) priority=value end}
core={
    svr_load_registry_string=function(self,key) return store[key] end,
    svr_save_registry_string=function(self,key,value) store[key]=value end,
    add_listener=function(self,name,event,condition,callback,persistent) listeners[event]={condition=condition,callback=callback} end,
    get_ui_root=function() return ui_root end,
    get_or_create_component=function(self,id,path,parent) assert(parent==panel,"button must belong to the character panel, not the background root");opened=true;return button end
}
find_uicomponent=function(parent,id) if parent==ui_root and id=="character_details_panel" then return panel end; return text end
cm={
    get_local_faction_name=function() return "test_faction" end,
    get_character_by_cqi=function(self,id) assert(id==42);return selected end,
    is_multiplayer=function() return false end
}
cco=function(kind,id)
    queried=queried+1
    assert(selected,"CCO must not be queried during campaign startup")
    local map
    if kind=="CcoCampaignCharacter" then
        assert(id==42)
        map={['AncillaryList.Size']=item_count,['AncillaryList.At(0).AncillaryRecordContext.Key']='test_sword',['AncillaryList.At(0).AncillaryRecordContext.CategoryContext.Key']='weapon'}
        map['FactionContext.AncillaryList.Size']=4
        for index=0,3 do
            local entry='FactionContext.AncillaryList.At('..index..').'
            map[entry..'AncillaryRecordContext.Key']=index==3 and 'test_axe' or 'test_sword'
            map[entry..'AncillaryRecordContext.CategoryContext.Key']='weapon'
            map['IsContextValid('..entry..'CharacterEquippedToContext)']=index>=2
            if index>=2 then map[entry..'CharacterEquippedToContext.CQI']=index==2 and 42 or 43 end
        end
    else
        assert(kind=="CcoCampaignFaction" and id=="test_faction")
        map={['AncillaryList.Size']=2}
    end
    return {Call=function(self,expression) return map[expression] end}
end
local function event(name,context)
    local listener=assert(listeners[name],"missing event listener")
    if listener.condition==true or listener.condition(context) then listener.callback(context) end
end
assert(loadfile("spikes/wh3ep_probe_capture.lua"))()
wh3ep_probe()
assert(queried==0,"startup must not read character or inventory")
assert(store[prefix]=="WH3EP1\n1\nТестовый пресет\n","persistent engine storage must still work")
event('PanelOpenedCampaign',{string='character_details_panel'})
assert(opened,"opening character details must expose the test button")
assert(priority and priority>panel:Priority(),"button must render above the fullscreen panel")
event('ComponentLClickUp',{string='wh3ep_probe_capture_button'})
assert(queried==0,"clicking without a selected character must not read a stale target")
selected={
    command_queue_index=function() return 42 end,
    is_null_interface=function() return false end,
    character_subtype_key=function() return "test_lord" end,
    faction=function() return {name=function()return "test_faction"end} end
}
event('CharacterSelected',{character=function() return selected end})
event('ComponentLClickUp',{string='wh3ep_probe_capture_button'})
local snapshot=assert(store.wh3ep_probe_snapshot_v1,"click must persist an equipment snapshot")
assert(snapshot:find('faction=test_faction',1,true),"snapshot faction missing")
assert(snapshot:find('class=test_lord',1,true),"snapshot class missing")
assert(snapshot:find('test_sword|weapon',1,true),"snapshot item or category missing")
assert(output:find('capture_complete',1,true),"completed snapshot must be reported")
print('PASS: no startup inventory access, explicit selection required, button snapshot contains faction/class/items')
event('ComponentLClickUp',{string='wh3ep_probe_inventory_button'})
local inventory=assert(store.wh3ep_probe_inventory_v1,'inventory click must store faction instances')
assert(inventory:find('0|test_sword|weapon|0',1,true),'first free identical instance missing')
assert(inventory:find('1|test_sword|weapon|0',1,true),'second free identical instance missing')
assert(inventory:find('2|test_sword|weapon|42',1,true),'target equipped instance missing')
assert(inventory:find('3|test_axe|weapon|43',1,true),'other owner instance missing')
assert(output:find('inventory_free=2',1,true) and output:find('inventory_equipped=2',1,true),'ownership counts missing')
print('PASS: distinct faction list positions, identical free instances, target and donor ownership')
local saved, calls = snapshot, queried
selected.faction=function() return {name=function() return "foreign_faction" end} end
event('ComponentLClickUp',{string='wh3ep_probe_capture_button'})
assert(queried==calls and store.wh3ep_probe_snapshot_v1==saved, 'foreign target must not be read or saved')
selected.faction=function() return {name=function() return "test_faction" end} end
item_count=101
event('ComponentLClickUp',{string='wh3ep_probe_capture_button'})
assert(store.wh3ep_probe_snapshot_v1==saved, 'invalid inventory must preserve previous snapshot')
selected.is_null_interface=function() return true end
calls=queried
event('ComponentLClickUp',{string='wh3ep_probe_capture_button'})
assert(queried==calls, 'stale selection must not reach native CCO')
event('PanelClosedCampaign',{string='character_details_panel'})
print('PASS: foreign/stale characters rejected; invalid inventory preserves snapshot')