local saved,issued,listeners,logs,timers={wh3ep_test_items_v1_test_cathay='complete'},{},{},'',{}
local multiplayer,human,subculture=false,true,'wh3_main_sc_cth_cathay'
local fail_at,reject_at
local faction={is_null_interface=function()return false end,is_human=function()return human end,subculture=function()return subculture end}
local panel={Priority=function()return 50 end}
local button={PropagatePriority=function()end,MoveTo=function()end,SetVisible=function()end}
local label={SetStateText=function(self,value)self.text=value end}
core={add_listener=function(_,name,event,condition,callback)listeners[event]={condition,callback}end,
 get_ui_root=function()return panel end,get_or_create_component=function(_,id,path,parent)assert(parent==panel);return button end}
find_uicomponent=function(parent,id)if id=='character_details_panel'then return panel end;return label end
ModLog=function(value)logs=logs..value..'\n'end
cm={is_multiplayer=function()return multiplayer end,get_local_faction_name=function()return 'test_cathay'end,
 get_faction=function(_,key)assert(key=='test_cathay');return faction end,
 get_saved_value=function(_,key)return saved[key]end,set_saved_value=function(_,key,value)saved[key]=value end,
 callback=function(_,callback,delay)assert(delay>=1);timers[#timers+1]=callback end,
 add_ancillary_to_faction=function(_,target,key,suppress)
  assert(target==faction and suppress==true)
  if fail_at and #issued+1==fail_at then error('PRIVATE_NATIVE_ERROR_MARKER',0)end
  if reject_at and #issued+1==reject_at then return false end
  issued[#issued+1]=key
 end}
local function load()
 listeners,timers={},{}
 assert(loadfile('spikes/wh3ep_test_items.lua'))();wh3ep_test_items();wh3ep_test_items()
end
local function event(name,id)
 local listener=assert(listeners[name]);local context={string=id}
 if listener[1]==true or listener[1](context)then listener[2](context)end
end
local function click()event('ComponentLClickUp','wh3ep_test_items_button')end
local function cooldown()local pending=timers;timers={};for _,callback in ipairs(pending)do callback()end end
load();assert(#issued==0,'startup must not grant')
event('PanelOpenedCampaign','character_details_panel')
multiplayer=true;click();assert(#issued==0)
multiplayer=false;human=false;click();assert(#issued==0)
human=true;subculture='other';click();assert(#issued==0)
subculture='wh3_main_sc_cth_cathay';click()
assert(#issued==64,'expanded batch needs 30 equipment and 34 followers, ignoring legacy one-shot marker')
local counts,followers={},{}
for _,key in ipairs(issued)do counts[key]=(counts[key]or 0)+1;if key:match('^wh3_main_anc_follower_cth_')then followers[key]=true end end
local distinct=0
for key in pairs(followers)do distinct=distinct+1;assert(counts[key]==2,'each follower needs two copies')end
assert(distinct==17,'need many distinct followers to fill slots without using the desired one')
local equipment=0
for key,n in pairs(counts)do if not followers[key]then assert(n==3,'equipment variants need three identical copies each');equipment=equipment+n end end
assert(equipment==30)
click();assert(#issued==64,'double click during cooldown must not grant twice')
cooldown();click();assert(#issued==128,'explicit next click after cooldown must grant another full batch')
assert(saved.wh3ep_test_items_v2_test_cathay=='complete:2')
load();assert(#issued==128,'reloading completed state must not automatically grant')
click();assert(#issued==192,'saved completed batch must not block another explicitly requested batch')
saved={};issued={};fail_at=2
load();click();assert(#issued==1,'partial exception must stop')
cooldown();click();assert(#issued==1,'ambiguous partial batch cannot be retried')
load();click();assert(#issued==1,'partial marker must survive session reload')
assert(saved.wh3ep_test_items_v2_test_cathay=='started:1')
assert(not logs:find('PRIVATE_NATIVE_ERROR_MARKER',1,true),'raw exceptions must not be logged')
fail_at=nil;saved={};issued={};reject_at=3
load();click();assert(#issued==2,'native false must stop')
cooldown();click();assert(#issued==2,'reported rejection keeps partial marker')
reject_at=nil;saved={wh3ep_test_items_v2_test_cathay='broken'};issued={}
load();click();assert(#issued==0,'invalid marker must not silently grant a new batch')
print('PASS: repeatable 64-item batches, 17 distinct followers, cooldown, legacy marker compatibility, explicit-only grants and persistent partial-failure guard')