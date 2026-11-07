local helpers=assert(loadfile('tests/fixtures/equipment.lua'))()
local fixture,gear,follower,preset=helpers.fixture,helpers.gear,helpers.follower,helpers.preset
local goal=preset({{slot_key='weapon',item_key='sword'},{slot_key='armor',item_key='armor'}})
local app,w=fixture({gear('old',1),gear('sword',2),gear('sword',0),gear('armor',0,'armor')})
local plan=assert(app.preview(1,goal,true))
assert(plan.actions[1].candidate.owner==0,'free copy must win even when donor listed first')
assert(app.start(1,goal,true,plan,w.notify));w.drain()
assert(not app.busy()and w.commands==2 and w.reports[#w.reports].status=='complete')
assert(w.reports[#w.reports].completed==2)
local again=assert(app.preview(1,goal,true));assert(#again.actions==0 and again.summary.already==2,'repeat must be idempotent')
assert(app.start(1,goal,true,again,w.notify));assert(w.commands==2)
for _,owner in ipairs({2,3})do
 app,w=fixture({gear('old',1),gear('sword',owner)})
 local one=preset({{slot_key='weapon',item_key='sword'}})
 local no=assert(app.preview(1,one,false));assert(no.summary.occupied==1 and #no.actions==0)
 local yes=assert(app.preview(1,one,true));assert(yes.summary.donor==1)
 assert(app.start(1,one,true,yes,w.notify));assert(app.waiting()and w.commands==1 and #w.timers==0,'donor waits for explicit verification')
 assert(not app.start(1,one,true,yes,w.notify),'busy controller must not send a second command')
 w.confirm();assert(app.resume());assert(not app.busy()and w.commands==1 and w.reports[#w.reports].status=='complete')
end
app,w=fixture({gear('old',1),gear('bad',0,'weapon',false)})
local missing=preset({{slot_key='weapon',item_key='missing'},{slot_key='armor',item_key='bad'}})
plan=assert(app.preview(1,missing,false));assert(#plan.actions==0,'missing and incompatible must not unequip current')
app,w=fixture({gear('old',1),gear('bad',0,'weapon',false)})
plan=assert(app.preview(1,preset({{slot_key='weapon',item_key='bad'}}),false));assert(plan.summary.incompatible==1)
-- Preserve wanted followers regardless of their requested order; replace surplus only.
local followers=preset({}, {'new','keep','keep'})
app,w=fixture({follower('keep',1),follower('surplus',1),follower('keep',1),follower('new',0)})
plan=assert(app.preview(1,followers,false))
assert(plan.summary.already==2 and #plan.actions==1 and plan.actions[1].replacement.key=='surplus')
assert(app.start(1,followers,false,plan,w.notify));w.drain();assert(w.reports[#w.reports].status=='complete')
app,w=fixture({follower('a',0,2),follower('b',0,2),follower('c',0,2)})
plan=assert(app.preview(1,preset({}, {'a','b','c'}),false))
assert(#plan.actions==2 and plan.summary.no_slot==1,'follower capacity must come from snapshot')
app,w=fixture({follower('same',0,4)})
plan=assert(app.preview(1,preset({}, {'same','same'}),false))
assert(#plan.actions==1 and plan.summary.missing==1,'one copy cannot serve two desired positions')
-- Stale previews, selection/cancel and corruption must stop the queue.
app,w=fixture({gear('sword',0),gear('armor',0,'armor')})
plan=assert(app.preview(1,goal,false));w.items[1].owner=2
assert(not app.start(1,goal,false,plan,w.notify)and w.commands==0,'stale preview must not issue commands')
app,w=fixture({gear('sword',0),gear('armor',0,'armor')})
plan=assert(app.preview(1,goal,false));assert(app.start(1,goal,false,plan,w.notify));app.cancel();w.drain()
assert(w.commands==1 and not app.busy()and w.reports[#w.reports].status=='cancelled')
app,w=fixture({gear('sword',0),gear('armor',0,'armor')})
plan=assert(app.preview(1,goal,false));w.corrupt=true;assert(app.start(1,goal,false,plan,w.notify));w.drain()
assert(w.commands==1 and w.reports[#w.reports].status=='inventory_changed','lost/extra item must stop immediately')
app,w=fixture({gear('sword',2)})
local one=preset({{slot_key='weapon',item_key='sword'}})
plan=assert(app.preview(1,one,true));app.start(1,one,true,plan,w.notify)
assert(app.resume()and w.commands==1 and not app.busy()and w.reports[#w.reports].status=='not_applied','declined native popup must never resend command')
print('PASS: complete-set planning/execution, free priority, both donor types, follower multiplicity/capacity, idempotency, stale/cancel/conservation guards')
app,w=fixture({gear('sword',0)})
local single=preset({{slot_key='weapon',item_key='sword'}})
plan=assert(app.preview(1,single,false));w.items[1].compatible=false
assert(app.start(1,single,false,plan,w.notify)and w.commands==0)
assert(w.reports[#w.reports].summary.incompatible==1,'result must reflect compatibility changed after preview')
app,w=fixture({gear('sword',2),gear('armor',0,'armor')})
plan=assert(app.preview(1,goal,true));app.start(1,goal,true,plan,w.notify)
app.cancel();assert(app.busy()and app.waiting(),'cancel retains verification barrier for already-issued donor command')
w.confirm();assert(app.resume()and not app.busy())
assert(w.commands==1 and w.reports[#w.reports].status=='cancelled','verification after cancel must not advance remaining queue')
print('PASS: changed compatibility reflected in report; cancelled donor resumes verification only')
-- Missing/incompatible positions must preserve current gear even when another step succeeds.
for _,take in ipairs({false,true})do
 local mixed=preset({{slot_key='weapon',item_key='absent'},
  {slot_key='armor',item_key='blocked'}, {slot_key='talisman',item_key='new_talisman'}}, {'absent_follower','blocked_follower'})
 local blocked_follower=follower('blocked_follower',0);blocked_follower.compatible=false
 app,w=fixture({gear('old_weapon',1),gear('old_armor',1,'armor'),
  gear('blocked',0,'armor',false),gear('old_talisman',1,'talisman'),
  gear('new_talisman',0,'talisman'),follower('old_follower',1),blocked_follower})
 plan=assert(app.preview(1,mixed,take))
 assert(plan.summary.missing==2 and plan.summary.incompatible==2 and #plan.actions==1)
 assert(app.start(1,mixed,take,plan,w.notify));w.drain()
 local report=w.reports[#w.reports]
 assert(report.status=='complete' and report.completed==1 and w.commands==1)
 assert(report.summary.missing==2 and report.summary.incompatible==2)
 for _,item in ipairs(w.items)do
  if item.key=='old_weapon' or item.key=='old_armor' or item.key=='old_follower' then
   assert(item.owner==1,'unavailable replacement must leave existing item equipped')
  elseif item.key=='blocked' or item.key=='blocked_follower' or item.key=='old_talisman' then
   assert(item.owner==0,'blocked items stay in reserve; only replaced talisman returns there')
  elseif item.key=='new_talisman' then assert(item.owner==1)end
 end
 local repeat_plan=assert(app.preview(1,mixed,take))
 assert(#repeat_plan.actions==0)
 assert(app.start(1,mixed,take,repeat_plan,w.notify));w.drain()
 assert(w.commands==1 and w.reports[#w.reports].completed==0)
end
print('PASS: mixed missing/incompatible gear and followers preserve current items, both donor toggles, repeat sends no commands')
