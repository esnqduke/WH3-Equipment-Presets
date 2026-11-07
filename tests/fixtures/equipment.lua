local create=assert(loadfile('src/wh3ep_apply.lua'))()
local function fixture(items)
 local world={items=items,commands=0,timers={},reports={},valid=true,corrupt=false}
 local function copy(t)local r={};for k,v in pairs(t)do r[k]=v end;return r end
 local engine={}
 function engine.snapshot(cqi)
  if not world.valid or cqi~=1 then return nil,'wrong_turn'end
  local s={target={cqi=1,faction_key='f',class_key='a',character_kind='lord'},instances={},equipped={},counts={},owners={},names={},donors={[2]={name='Hero',character_kind='hero'},[3]={name='Lord',character_kind='lord'}}}
  for i,item in ipairs(world.items)do
   local x=copy(item);x.index=i-1;s.instances[i]=x;s.names[x.key]=x.key
   s.counts[x.key]=(s.counts[x.key]or 0)+1
   s.owners[x.owner]=s.owners[x.owner]or{};s.owners[x.owner][x.key]=(s.owners[x.owner][x.key]or 0)+1
   if x.owner==1 then x=copy(x);x.target_index=#s.equipped;s.equipped[#s.equipped+1]=x end
  end
  return s
 end
 function engine.compatible(_,item)return item.compatible~=false end
 function engine.equip(_,action)
  world.commands=world.commands+1
  local source=assert(world.items[action.candidate.index+1]);assert(source.key==action.key)
  local function perform()
   if action.replacement then
    local position=0
    for _,x in ipairs(world.items)do if x.owner==1 then
     if position==action.replacement.target_index then assert(x.key==action.replacement.key);x.owner=0;break end
     position=position+1
    end end
   end
   source.owner=1
   if world.corrupt then world.items[#world.items]=nil end
   -- Every successful mutation reorders inventory, so stale indices cannot be reused.
   local reversed={};for i=#world.items,1,-1 do reversed[#reversed+1]=world.items[i]end;world.items=reversed
  end
  if source.owner~=0 then world.confirm=perform else perform()end
  return true
 end
 function engine.schedule(cb)world.timers[#world.timers+1]=cb end
 local app=create(engine)
 function world.drain()while #world.timers>0 do local cb=table.remove(world.timers,1);cb()end end
 function world.notify(report)world.reports[#world.reports+1]=report end
 return app,world,engine
end
local function gear(key,owner,slot,compatible)return{key=key,owner=owner,slot_key=slot or 'weapon',category=slot or 'weapon',capacity=1,compatible=compatible}end
local function follower(key,owner,capacity)return{key=key,owner=owner,slot_key='general',category='general',capacity=capacity or 3}end
local function preset(equipment,followers)return{id='p1',equipment=equipment or{},followers=followers or{}}end

return{fixture=fixture,gear=gear,follower=follower,preset=preset}
