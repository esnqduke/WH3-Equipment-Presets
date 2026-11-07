local function scenario(options)
 options=options or {}
 local store,listeners,queue,logs={}, {}, {}, ''
 local mutations=0
 local pending_effect
 local label_destroyed=false
 local items={{key='wh_main_anc_weapon_sword_of_striking',category='weapon',owner=42},{key='wh_main_anc_weapon_sword_of_battle',category='weapon',owner=(options.no_free or options.fixed) and 43 or 0},{key='wh_main_anc_weapon_sword_of_striking',category='weapon',owner=0}}
 if options.already_equipped then items[1].key='wh_main_anc_weapon_sword_of_battle' end
 if options.free_copy then items[#items+1]={key='wh_main_anc_weapon_sword_of_battle',category='weapon',owner=0} end
 local donor={is_null_interface=function()return false end,faction=function()return{name=function()return options.foreign_donor and 'foreign_faction' or 'test_faction'end}end,character_type=function(self,kind)return options.donor_lord and kind=='general' or kind=='wizard'end}
 local label={value='',SetStateText=function(self,value)assert(not label_destroyed,'must not write to a closed panel');self.value=value end}
 local panel={Priority=function()return 50 end}
 local button={PropagatePriority=function()end,MoveTo=function()end,SetVisible=function()end}
 local character={is_null_interface=function()return false end,command_queue_index=function()return 42 end,character_subtype_key=function()return 'test_lord'end,faction=function()return{name=function()return options.foreign and 'foreign_faction' or 'test_faction'end}end,character_type=function(self,kind)return kind=='general' and not options.hero end}
 ModLog=function(value)logs=logs..value..'\n'end
 core={svr_load_registry_string=function(self,key)return store[key]end,svr_save_registry_string=function(self,key,value)store[key]=value end,add_listener=function(self,name,event,condition,callback)listeners[event]={condition,callback}end,get_ui_root=function()return panel end,get_or_create_component=function()return button end}
 find_uicomponent=function(parent,id)if id=='character_details_panel'then return panel end;return label end
 cm={is_factions_turn_by_key=function()return not options.wrong_turn end,is_multiplayer=function()return options.multiplayer or false end,get_character_by_cqi=function(self,id)if id==43 then if options.missing_donor then return nil end;return donor end;assert(id==42);return character end,get_local_faction_name=function()return 'test_faction'end,callback=function(self,callback)queue[#queue+1]=callback end}
 local function equipped()
  local result={}
  for _,item in ipairs(items)do if item.owner==42 then result[#result+1]=item end end
  return result
 end
 cco=function(kind,id)
  assert(kind=='CcoCampaignCharacter' and id==42)
  return {Call=function(self,expression)
   if expression:find('EquipToCharacter',1,true)then
    local expected='(target = this) => {target | target.FactionContext.AncillaryList.At('..tostring(options.free_copy and 3 or 1)..').EquipToCharacter(target, target.AncillaryList.Filter(AncillaryRecordContext.CategoryContext.Category == "weapon").FirstContext)}'
    assert(expression==expected,'wrong candidate, target binding or replacement expression')
    mutations=mutations+1
    assert(expression:find('CanCharacterEquip',1,true)==nil)
    local function apply_effect()
    if not options.no_effect then
     local chosen=items[options.free_copy and 4 or 2]
     items[1].owner=options.native_swap and chosen.owner or 0;chosen.owner=42
     if options.lose_item then table.remove(items,3)end
    end
    end
    if options.confirmation then pending_effect=apply_effect else apply_effect() end
    return nil
   end
   if expression:find('CanCharacterEquip(target)',1,true)then if options.inventory_changed then items[2].owner=43 end; return not options.incompatible end
   if expression:find('target.CQI',1,true)then return options.binding_mismatch and 999 or 42 end
   if expression=='FactionContext.AncillaryList.Size'then return #items end
   if expression=='AncillaryList.Size'then return #equipped()end
   local index=expression:match('FactionContext.AncillaryList.At%((%d+)%)')
   local item=index and items[tonumber(index)+1]
   if not item then index=expression:match('^AncillaryList.At%((%d+)%)');item=index and equipped()[tonumber(index)+1]end
   if item then
    if expression:find('IsContextValid',1,true)then return item.owner~=0 end
    if expression:find('CharacterEquippedToContext.CQI',1,true)then assert(item.owner~=0,'must not dereference invalid owner');return item.owner end
    if expression:find('CategoryContext.Key',1,true)or expression:find('CategoryContext.Category',1,true)then return item.category end
    if expression:find('AncillaryRecordContext.Key',1,true)then return item.key end
   end
   error('Unexpected query: '..expression)
  end}
 end
 assert(loadfile('spikes/wh3ep_probe_capture.lua'))()
 wh3ep_probe()
 local function event(name,context)
  local listener=assert(listeners[name]);if listener[1]==true or listener[1](context)then listener[2](context)end
 end
 event('CharacterSelected',{character=function()return character end})
 event('PanelOpenedCampaign',{string='character_details_panel'})
 local function click()event('ComponentLClickUp',{string=options.fixed and 'wh3ep_probe_transfer_button' or 'wh3ep_probe_equip_button'})end
 if options.allow_transfer then event('ComponentLClickUp',{string='wh3ep_probe_take_button'})end
 assert(mutations==0,'no startup mutations')
 click()
 if options.confirmation then
  assert(mutations==1 and items[2].owner==43,'dialog must precede effect')
  for _,callback in ipairs(queue)do callback()end
  queue={}
  assert(not logs:find('equip_verify_failed',1,true),'must not fail before dialog confirmation')
  assert(not logs:find('equip_complete',1,true),'must not succeed before dialog confirmation')
  if not options.confirmation_cancel then assert(pending_effect);pending_effect() end
  click()
 elseif not (options.fixed and (options.closed_panel or options.selection_changed)) then click() end
 if options.multiplayer or options.incompatible or options.no_free or options.binding_mismatch or options.inventory_changed or options.wrong_turn or options.hero or options.foreign or options.already_equipped or (options.fixed and not options.free_copy and (not options.allow_transfer or options.foreign_donor or options.missing_donor)) then
  assert(mutations==0,'ineligible operation must not mutate')
 else
  assert(mutations==1,'explicit click must perform one existing-instance operation; busy click ignored')
  if options.closed_panel then event('PanelClosedCampaign',{string='character_details_panel'});label_destroyed=true end
  if options.selection_changed then
   event('CharacterSelected',{character=function()return{is_null_interface=function()return false end,command_queue_index=function()return 43 end}end})
  end
  if options.fixed and (options.closed_panel or options.selection_changed) then click() end
  for _,callback in ipairs(queue)do callback()end
  if options.no_effect or options.lose_item or options.native_swap or options.confirmation_cancel then
   assert(not logs:find('equip_complete',1,true),'failed effect or inventory loss must not be reported successful')
   assert(logs:find('equip_verify_failed',1,true),'verification failure must be reported')
   if options.confirmation_cancel then assert(logs:find('equip_not_applied',1,true),'cancellation must be distinguished from donor damage') end
   if options.native_swap then assert(logs:find('transfer_donor_changed',1,true) and not logs:find('transfer_complete',1,true),'native donor swap must not count as a policy-compliant transfer') end
   if options.native_swap then
    assert(logs:find('equip_counts_preserved=true',1,true),'diagnostic must distinguish conservation from donor changes')
    assert(logs:find('equip_target_verified=true',1,true),'diagnostic must distinguish target success from donor changes')
    assert(logs:find('transfer_donor_unexpected=wh_main_anc_weapon_sword_of_striking',1,true),'diagnostic must identify unexpected donor item')
   end
  else
   assert(items[options.free_copy and 4 or 2].owner==42 and items[1].owner==0 and #items==(options.free_copy and 4 or 3),'swap must conserve old and free items')
   if options.free_copy then assert(items[2].owner==43,'free copy must take priority over donor') end
   if options.fixed and not options.free_copy then assert(logs:find('transfer_complete',1,true),'donor transfer must be verified') end
   assert(logs:find('equip_complete',1,true),'verified operation must be reported')
   if options.selection_changed then assert(not label.value:find('Оружие надето',1,true),'old target result must not be shown on a different character') end
   if not options.closed_panel and not options.selection_changed then assert(label.value:find('Оружие надето',1,true),'UI must show successful outcome') end
  end
 end
end
scenario()
scenario({incompatible=true})
scenario({multiplayer=true})
scenario({no_free=true})
scenario({no_effect=true})
scenario({lose_item=true})
scenario({binding_mismatch=true})
scenario({inventory_changed=true})
scenario({wrong_turn=true})
scenario({hero=true})
scenario({foreign=true})
scenario({closed_panel=true})
scenario({selection_changed=true})
scenario({fixed=true})
scenario({fixed=true,allow_transfer=true})
scenario({fixed=true,allow_transfer=true,donor_lord=true})
scenario({fixed=true,allow_transfer=true,free_copy=true})
scenario({fixed=true,free_copy=true})
scenario({fixed=true,allow_transfer=true,already_equipped=true})
scenario({fixed=true,allow_transfer=true,foreign_donor=true})
scenario({fixed=true,allow_transfer=true,missing_donor=true})
scenario({fixed=true,allow_transfer=true,native_swap=true})
scenario({fixed=true,allow_transfer=true,closed_panel=true})
scenario({fixed=true,allow_transfer=true,selection_changed=true})
scenario({fixed=true,allow_transfer=true,confirmation=true})
scenario({fixed=true,allow_transfer=true,confirmation=true,confirmation_cancel=true})
print('PASS: single free-instance equip, conserved replacement, busy click, compatibility/MP/availability guards, free-copy priority, hero/lord donors, donor-swap and inventory loss detection')
