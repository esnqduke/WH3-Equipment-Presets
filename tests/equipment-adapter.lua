local factory=assert(loadfile('src/wh3ep_equipment.lua'))()
local items={{key='old',owner=1,slot='weapon',category='weapon',capacity=1},{key='sword',owner=0,slot='weapon',category='weapon',capacity=1},{key='follower',owner=0,slot='general',category='general',capacity=4}}
local calls,commands,turn,empty_valid={},0,true,false
local icon_failure=false
local metadata_failure=false
local name_failure=false
local effect_count=2
local rarity_override,effect_failure,effect_text=nil,false,nil
local function target_items()local t={};for _,x in ipairs(items)do if x.owner==1 then t[#t+1]=x end end;return t end
cm={is_factions_turn_by_key=function()return turn end,char_name_to_string=function()if name_failure then error('native name unavailable')end;return 'Donor'end,get_character_by_cqi=function()return{}end,callback=function(cb)cb()end}
ModLog=function()end
local function describe(cqi)if cqi==1 or cqi==2 then return{cqi=cqi,faction_key='f',class_key='a',character_kind=cqi==1 and 'lord'or 'hero'}end end
cco=function(_,cqi)return{Call=function(_,q)
 calls[#calls+1]=q
 if q=='FactionContext.AncillaryList.Size'then return #items end
 if q=='AncillaryList.Size'then return #target_items()end
 if q=='(target = this) => {target | target.CQI}'then return cqi end
 local i=q:match('FactionContext.AncillaryList.At%((%d+)%)')
 local item=i and items[tonumber(i)+1]
 if q:find('IsContextValid(target.AncillaryList',1,true)then return empty_valid end
 if q:find('IsContextValid(',1,true)then return item.owner~=0 end
 if q:find('CanCharacterEquip(target)',1,true)then return item.can~=false end
 if q:find('NumAllowedPerCharacterForFaction(target, target.FactionContext.FactionRecordContext)',1,true)then return item.capacity end
 if q:find('EquipToCharacter(target,',1,true)then commands=commands+1;return nil end
 if q:find('AncillaryRecordContext.Key != AncillaryRecordContext.Key',1,true)and q:find('.Size}',1,true)then return 0 end
 if q:find('.Filter(',1,true)and q:find('.Size}',1,true)then
  local n=0;for _,x in ipairs(target_items())do if q:find('== "general"',1,true)and x.category=='general'or not q:find('== "general"',1,true)and x.slot==item.slot then n=n+1 end end;return n
 end
 if not item then local ti=q:match('^AncillaryList.At%((%d+)%)');item=ti and target_items()[tonumber(ti)+1]end
 if q:find('CharacterEquippedToContext.CQI',1,true)then return item.owner end
 if q:find('CategoryContext.Key',1,true)then return item.slot end
 if q:find('CategoryContext.Category',1,true)then return item.category end
 if q:find('CategoryContext.IsHidden',1,true)then return false end
 if q:match('AncillaryRecordContext%.RarityState$')then if metadata_failure then error('metadata unavailable')end;return rarity_override or (item.category=='general'and 'common'or 'rare')end
 if q:match('AncillaryRecordContext%.EffectList%.Size$')then if metadata_failure then error('metadata unavailable')end;return effect_count end
 local effect=q:match('AncillaryRecordContext%.EffectList%.At%((%d+)%)%.LocalisedText$')
 if effect then if effect_failure and tonumber(effect)==1 then error('effect unavailable')end;return effect_text or (tonumber(effect)==0 and 'Armour: +5'or 'Leadership: +3 (Lord\226\128\153s army)')end
 if q:find('.IconPath}',1,true)then if icon_failure then error('icon unavailable')end;return 'ui/test/'..item.key..'.png'end
 if q:find('OnscreenName',1,true)then if name_failure then error('native name unavailable')end;return 'Localized item'end
 if q:match('%.Key$')then return item.key end
 error('Unexpected native query')
end}end
local engine=factory(describe)
assert(#calls==0,'construction must not touch native inventory')
local state=assert(engine.snapshot(1))
assert(#state.instances==3 and #state.equipped==1 and state.instances[3].capacity==4)
assert(state.names.sword=='Localized item'and state.counts.sword==1 and state.owners[1].old==1)
name_failure=true;items[2].owner=2
local unnamed=assert(engine.snapshot(1))
assert(not unnamed.names.sword and not unnamed.donors[2].name,'missing native names must be left for the localized UI fallback')
name_failure=false;items[2].owner=0
assert(state.icons.sword=='ui/test/sword.png' and state.icons.follower=='ui/test/follower.png','native ancillary icons must be captured for gear and followers')
assert(state.rarities and state.rarities.sword=='rare'and state.rarities.follower=='common','native rarity states must cover equipment and followers')
assert(state.tooltips and state.tooltips.sword=='Armour: +5\nLeadership: +3 (Lord\226\128\153s army)'and state.tooltips.follower==state.tooltips.sword,'effect tooltips must preserve native localized text and parameters')
local seen={};for _,q in ipairs(calls)do seen[q]=true end
assert(seen['FactionContext.AncillaryList.At(1).AncillaryRecordContext.RarityState']and seen['FactionContext.AncillaryList.At(2).AncillaryRecordContext.EffectList.At(1).LocalisedText'],'metadata must use confirmed ancillary record and effect fields')
metadata_failure=true;local sparse=assert(engine.snapshot(1));assert(not sparse.rarities.sword and not sparse.tooltips.sword and sparse.counts.sword==1,'optional metadata errors must preserve inventory snapshot');metadata_failure=false
effect_count=0;assert(not assert(engine.snapshot(1)).tooltips.sword,'no effects must leave tooltip absent')
effect_count=65;assert(not assert(engine.snapshot(1)).tooltips.sword,'oversized effects must leave tooltip absent');effect_count=2
effect_count='2';assert(not assert(engine.snapshot(1)).tooltips.sword,'non-numeric effect counts must leave tooltip absent');effect_count=2
effect_failure=true;assert(not assert(engine.snapshot(1)).tooltips.sword,'an unavailable later effect must not publish a misleading partial tooltip');effect_failure=false
effect_text='';assert(not assert(engine.snapshot(1)).tooltips.sword,'empty localized text must leave tooltip absent');effect_text=nil
effect_text=42;assert(not assert(engine.snapshot(1)).tooltips.sword,'malformed effect text must leave tooltip absent');effect_text=nil
rarity_override='unique';assert(not assert(engine.snapshot(1)).rarities.sword,'unconfirmed rarity state must remain absent')
rarity_override='crafted';assert(assert(engine.snapshot(1)).rarities.sword=='crafted','crafted is a confirmed stock rarity state');rarity_override=nil
icon_failure=true;local without_icons=assert(engine.snapshot(1));assert(not without_icons.icons.sword,'missing image must not block snapshot');icon_failure=false
local action={key='sword',category='equipment',candidate=state.instances[2],replacement=state.equipped[1]}
assert(engine.compatible(1,action.candidate));assert(engine.equip(1,action));assert(commands==1)
assert(calls[#calls]:find('target.AncillaryList.At(0)',1,true),'replacement must reference the verified current target slot')
items[2].owner=2
assert(not engine.equip(1,action)and commands==1,'changed source owner must not equip')
items[2].owner=0;items[2].can=false
assert(not engine.equip(1,action)and commands==1,'native compatibility false must prevent command')
items[2].can=true;items[1].key='changed'
assert(not engine.equip(1,action)and commands==1,'changed replacement must prevent command')
items[1].key='old'
state=assert(engine.snapshot(1))
assert(engine.equip(1,{key='follower',category='general',candidate=state.instances[3],empty_index=0}))
assert(commands==2 and not calls[#calls]:find('.PadRight(',1,true)and calls[#calls]:find('.FirstContext',1,true),'follower command must receive empty ancillary context, not UI padding')
items[#items+1]={key='keep',owner=1,slot='general',category='general',capacity=4}
state=assert(engine.snapshot(1))
assert(engine.equip(1,{key='follower',category='general',candidate=state.instances[3],empty_index=1}))
assert(commands==3 and calls[#calls]:find('AncillaryRecordContext.Key != AncillaryRecordContext.Key',1,true),'addition with existing follower must not select that occupied follower as replacement')
empty_valid=true
assert(not engine.equip(1,{key='follower',category='general',candidate=state.instances[3],empty_index=1})and commands==3,'unexpected nonempty replacement context must stop command')
empty_valid=false
turn=false;local before=#calls
assert(not engine.snapshot(1)and #calls==before,'wrong turn must reject before CCO reads')
assert(not engine.snapshot(99),'invalid target must not touch CCO')
print('PASS: native equipment boundary, capacities/names, source/target revalidation, no speculative unequip/grants, own-turn guard')
