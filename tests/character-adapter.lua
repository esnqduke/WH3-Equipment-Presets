-- Exercise the shipped adapter; only engine boundaries are mocked.
local file=assert(io.open('.superpowers/library-probe-bundle.lua','rb'))
local source=file:read('*a');file:close()
local characters={}
local function character(cqi,kind,subtype,faction,garrison)
 local c={garrison=garrison==true}
 function c:is_null_interface()return false end
 function c:character_type(value)return kind==value end
 function c:faction()return{name=function()return faction or 'cathay'end}end
 function c:character_subtype_key()return subtype end
 characters[cqi]=c;return c
end
character(1,'general','dragon_lord')
character(2,'wizard','wh3_main_cth_alchemist')
character(3,'champion','other_hero')
character(4,'colonel','placeholder')
character(5,'minister','minister')
character(6,'wizard','foreign_hero','other_faction')
character(7,'general','wh3_main_cth_lord_caravan_master')
character(8,'general','fixture_garrison_general',nil,true)
character(9,'general','fixture_convoy_master')
local multiplayer,agent_checks,cco_calls=false,0,0
local local_faction='cathay'
local cm={is_multiplayer=function()return multiplayer end,get_character_by_cqi=function(_,cqi)return characters[cqi]end,
 get_local_faction_name=function()return local_faction end,
 char_is_garrison_commander=function(_,c)return c.garrison end,
 is_factions_turn_by_key=function()return true end,
 char_is_agent=function(_,c)
  agent_checks=agent_checks+1
  -- Contract from lib_campaign_manager.lua:5572.
  return not(c:character_type('general')or c:character_type('colonel')or c:character_type('minister'))
 end}
local records={{Key='test_sword',slot='weapon',category='weapon',hidden=false},
 {Key='test_follower',slot='general',category='general',hidden=false},
 {Key='test_mount',slot='mount',category='mount',hidden=true}}
local env=setmetatable({cm=cm,core={},ModLog=function()end,cco=function(_,cqi)
 cco_calls=cco_calls+1
 return {Call=function(_,path)
  if path=='AncillaryList.Size'then return #records end
  local index,suffix=path:match('^AncillaryList.At%((%d+)%)%.AncillaryRecordContext%.(.+)$')
  local r=assert(records[tonumber(index)+1])
  if suffix=='Key'then return r.Key end
  if suffix=='CategoryContext.Key'then return r.slot end
  if suffix=='CategoryContext.Category'then return r.category end
  if suffix=='CategoryContext.IsHidden'then return r.hidden end
  error('Unexpected CCO query')
 end}
end},{__index=_G})
local chunk=assert(loadstring(source..[[
local captured
wh3ep_library_ui_factory=function(_,_,adapter)captured=adapter;return{start=function()end}end
wh3ep_probe()
return captured
]],'@character-adapter-bundle'))
setfenv(chunk,env)
local adapter=chunk()
assert(adapter.apply and type(adapter.apply.preview)=='function'and type(adapter.apply.start)=='function','real bundle must wire application controller')
assert(cco_calls==0,'startup must not read inventory')
assert(adapter.describe(1).character_kind=='lord')
local hero=adapter.describe(2)
assert(hero and hero.character_kind=='hero'and hero.class_key=='wh3_main_cth_alchemist','alchemist must be admitted by native agent predicate')
assert(adapter.describe(3).character_kind=='hero')
local caravan=adapter.describe(7)
assert(caravan and caravan.character_kind=='lord'and caravan.class_key=='wh3_main_cth_lord_caravan_master','caravan retains its distinct lord subtype')
for _,cqi in ipairs({4,5,6,8,99})do assert(not adapter.describe(cqi),'reject garrison/service/foreign/missing characters')end
local snapshot=assert(adapter.capture(2))
assert(#snapshot.equipment==1 and #snapshot.followers==1 and snapshot.character_kind=='hero','hero capture must retain equipment/followers but exclude hidden mount')
local caravan_snapshot=assert(adapter.capture(7))
assert(caravan_snapshot.class_key=='wh3_main_cth_lord_caravan_master'and #caravan_snapshot.equipment==1,'caravan capture uses ordinary character inventory')
multiplayer=true
assert(not adapter.describe(1)and not adapter.capture(2),'multiplayer remains unsupported')
assert(agent_checks>0,'hero classification must use native campaign manager predicate')
print('PASS: actual bundled adapter admits heroes/caravan lords, preserves subtypes, captures slots and rejects invalid targets')
multiplayer=false
-- Synthetic subtype labels prove that admission does not depend on a race/subtype allowlist.
local cases={
 {'empire','general','elector_lord','lord'}, {'empire','wizard','battle_wizard','hero'},
 {'dwarfs','general','runelord','lord'}, {'dwarfs','runesmith','runesmith','hero'},
 {'elves','general','prince','lord'}, {'elves','spy','assassin','hero'},
 {'skaven','general','grey_seer','lord'}, {'skaven','engineer','engineer','hero'},
 {'undead','general','vampire_lord','lord'}, {'undead','champion','wight','hero'},
 {'chaos','general','daemon_prince','lord'}, {'chaos','wizard','sorcerer','hero'},
 {'kislev','general','boyar','lord'}, {'kislev','dignitary','patriarch','hero'},
 {'cathay','general','caravan_master','lord'}, {'chaos_dwarfs','general','convoy_master','lord'},
 {'future_mod_faction','general','new_lord','lord'}, {'future_mod_faction','engineer','new_hero','hero'}
}
for i,case in ipairs(cases)do
 local cqi=20+i;local_faction=case[1]
 character(cqi,case[2],'fixture_'..case[3],case[1])
 local info=assert(adapter.describe(cqi))
 assert(info.character_kind==case[4]and info.class_key=='fixture_'..case[3]and info.faction_key==case[1],'generic type classification must preserve subtype/faction')
 local captured=assert(adapter.capture(cqi));assert(#captured.equipment==1 and #captured.followers==1,'each generic playable type must use the same capture contract')
 local_faction='foreign';assert(not adapter.describe(cqi),'every race must retain local-faction isolation')
end
local_faction='cathay'
assert(adapter.capture(9).character_kind=='lord','convoy-role fixture uses ordinary lord capture')
local ordinary_records=records;records={}
for i=1,7 do records[#records+1]={Key='gear_'..i,slot='slot_'..i,category='weapon',hidden=false}end
for i=1,8 do records[#records+1]={Key='follower_'..i,slot='general',category='general',hidden=false}end
local expanded=assert(adapter.capture(9))
assert(#expanded.equipment==7 and #expanded.followers==8,'capture must not truncate special-character inventories to six display cells')
records=ordinary_records
-- Schema and matching policy are generic too: shared crosses kinds, bound does not.
local model=assert(loadfile('src/wh3ep_model.lua'))()
assert(model.capture(expanded,'Expanded',expanded.class_key,'p1'),'schema must preserve expanded inventory captured from a special-role lord')
for _,kind in ipairs({'lord','hero'})do
 local info={faction_key='cathay',class_key='fixture_shared_text',character_kind=kind,equipment={},followers={}}
 local library=assert(model.add(model.new(),info,'Shared',''))
 library=assert(model.add(library,info,'Bound','fixture_shared_text'))
 local other_kind=kind=='lord'and 'hero'or 'lord'
 assert(#model.list(library,'cathay','fixture_shared_text','matching','',kind)==2)
 assert(#model.list(library,'cathay','fixture_shared_text','matching','',other_kind)==1,'bound class must not leak across kinds even with identical subtype text')
 assert(#model.list(library,'cathay','different_subtype','matching','',kind)==1,'bound class must not leak across subtypes')
 assert(#model.list(library,'other_faction','fixture_shared_text','all','',kind)==0,'shared must remain faction local')
end
-- Exercise the real native snapshot and real planner, with only CCO reads mocked.
local pool={}
env.cco=function(_,cqi)return{Call=function(_,q)
 if q=='(target = this) => {target | target.CQI}'then return cqi end
 if q=='FactionContext.AncillaryList.Size'then return #pool end
 if q=='AncillaryList.Size'then return 0 end
 local index=q:match('FactionContext.AncillaryList.At%((%d+)%)')
 local item=assert(index and pool[tonumber(index)+1],'unexpected native character fixture query')
 if q:find('IsContextValid(',1,true)then return item.owner~=0 end
 if q:find('CharacterEquippedToContext.CQI',1,true)then return item.owner end
 if q:find('NumAllowedPerCharacterForFaction(target, target.FactionContext.FactionRecordContext)',1,true)then return 1 end
 if q:find('CanCharacterEquip(target)',1,true)then return item.compatible~=false end
 if q:match('CategoryContext.Key$')or q:match('CategoryContext.Category$')then return 'weapon'end
 if q:match('CategoryContext.IsHidden$')then return false end
 if q:match('RarityState$')then return 'rare'end
 if q:match('EffectList.Size$')then return 0 end
 if q:match('OnscreenName$')then return 'Item'end
 if q:match('IconPath}$')then return 'ui/test/item.png'end
 if q:match('AncillaryRecordContext.Key$')then return item.key end
 error('unexpected native character fixture query')
end}end
for _,target in ipairs({1,2,7,9})do
 pool={}
 for _,owner in ipairs({1,2,3,4,5,6,7,8,9})do
  if owner~=target then pool[#pool+1]={owner=owner,key='item_'..owner}end
 end
 local runtime=assert(adapter.inspect(target))
 assert(not runtime.donors[4]and not runtime.donors[5]and not runtime.donors[6]and not runtime.donors[8],'service, foreign and garrison owners must never be offered as donors')
 for _,item in ipairs(pool)do
  local goal={equipment={{slot_key='weapon',item_key=item.key}},followers={}}
  local allowed=item.owner==1 or item.owner==2 or item.owner==3 or item.owner==7 or item.owner==9
  local plan=assert(adapter.apply.preview(target,goal,true))
  assert(#plan.actions==(allowed and 1 or 0),'only admitted faction-local owners can donate to every target kind')
  assert(#assert(adapter.apply.preview(target,goal,false)).actions==0,'donor opt-out applies to every target kind')
  if allowed then
   item.compatible=false
   assert(#assert(adapter.apply.preview(target,goal,true)).actions==0,'native CanCharacterEquip must govern every cross-kind transfer')
   item.compatible=nil
  end
 end
end
print('PASS: generic race/type fixtures, caravan/convoy roles, class/shared scopes, lord-hero donors, faction/service/garrison exclusions and native compatibility')
