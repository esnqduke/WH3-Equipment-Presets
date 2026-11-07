-- Plans and executes against fresh runtime snapshots; no campaign or library writes.
local function copy(value)
    if type(value)~='table'then return value end
    local out={};for key,item in pairs(value)do out[key]=copy(item)end;return out
end
local function counts_equal(a,b)
    for key,n in pairs(a or{})do if n~=(b and b[key]or 0)then return false end end
    for key,n in pairs(b or{})do if n~=(a and a[key]or 0)then return false end end
    return true
end
local function owners_equal(a,b)
    for owner,items in pairs(a or{})do if not counts_equal(items,b and b[owner])then return false end end
    for owner,items in pairs(b or{})do if not counts_equal(items,a and a[owner])then return false end end
    return true
end
local function same_state(a,b)
    return a and b and a.target.cqi==b.target.cqi and a.target.faction_key==b.target.faction_key
        and a.target.class_key==b.target.class_key and a.target.character_kind==b.target.character_kind
        and counts_equal(a.counts,b.counts)and owners_equal(a.owners,b.owners)
end
local function goal(preset)
    if type(preset)~='table'or type(preset.equipment)~='table'or type(preset.followers)~='table'
        or #preset.equipment>128 or #preset.followers>128 then return nil end
    local g={id=preset.id,equipment={},followers={}};local slots={}
    for i,item in ipairs(preset.equipment)do
        if type(item)~='table'or type(item.slot_key)~='string'or type(item.item_key)~='string'or slots[item.slot_key]then return nil end
        slots[item.slot_key]=true;g.equipment[i]={slot_key=item.slot_key,item_key=item.item_key}
    end
    for i,key in ipairs(preset.followers)do if type(key)~='string'then return nil end;g.followers[i]=key end
    return g
end
local function same_goal(a,b)
    if not a or not b or a.id~=b.id or #a.equipment~=#b.equipment or #a.followers~=#b.followers then return false end
    for i,v in ipairs(a.equipment)do local w=b.equipment[i];if v.slot_key~=w.slot_key or v.item_key~=w.item_key then return false end end
    for i,v in ipairs(a.followers)do if b.followers[i]~=v then return false end end
    return true
end
return function(engine)
    local A={};local active,last_report
    local function snapshot(cqi)
        local ok,state,code=pcall(engine.snapshot,cqi)
        if not ok then return nil,'engine_error'end
        return state,code
    end
    local function build(state,g,take)
        local plan={state=state,goal=copy(g),take=take,entries={},actions={},summary={}}
        local used={}
        local function choose(key,slot,category)
            local found,occupied,failed=false,false,false
            for _,free in ipairs({true,false})do
                for _,item in ipairs(state.instances)do
                    if item.key==key and not used[item.index]and item.owner~=state.target.cqi then
                        found=true
                        if item.owner~=0 then occupied=true end
                        if not item.hidden and item.category~='mount'and (not slot or item.slot_key==slot)
                            and (category=='general'and item.category=='general'or category~='general'and item.category~='general')
                            and ((free and item.owner==0)or(not free and item.owner~=0 and take and state.donors[item.owner]))then
                            local ok,can,code=pcall(engine.compatible,state.target.cqi,item)
                            if not ok or(can==nil and code)then error('compatibility_failed',0)end
                            if can==true then return item,item.owner==0 and 'free'or 'donor'end
                            failed=true
                        end
                    end
                end
            end
            return nil,failed and 'incompatible'or occupied and 'occupied'or found and 'incompatible'or 'missing'
        end
        local function add(entry,candidate,replacement,empty_index)
            plan.entries[#plan.entries+1]=entry
            if candidate then
                used[candidate.index]=true
                entry.candidate=candidate;entry.replacement=replacement;entry.empty_index=empty_index
                plan.actions[#plan.actions+1]=entry
            end
        end
        for _,wanted in ipairs(g.equipment)do
            local current={};local already=false
            for _,item in ipairs(state.equipped)do if item.slot_key==wanted.slot_key then current[#current+1]=item;if item.key==wanted.item_key then already=true end end end
            local entry={key=wanted.item_key,slot_key=wanted.slot_key,category='equipment'}
            if already then entry.status='already';add(entry)
            elseif #current>1 then entry.status='unsupported';add(entry)
            else
                local item,status=choose(wanted.item_key,wanted.slot_key,'equipment')
                if item and item.capacity~=1 then item,status=nil,'unsupported'end
                entry.status=status;add(entry,item,current[1])
            end
        end
        local all,kept,assigned={}, {}, {}
        for _,item in ipairs(state.equipped)do if item.category=='general'and not item.hidden then all[#all+1]=item end end
        for i,key in ipairs(g.followers)do
            for _,item in ipairs(all)do if item.key==key and not kept[item.target_index]then kept[item.target_index]=true;assigned[i]=item;break end end
        end
        local surplus={};for _,item in ipairs(all)do if not kept[item.target_index]then surplus[#surplus+1]=item end end
        local additions=0
        for i,key in ipairs(g.followers)do
            local entry={key=key,category='general'}
            if assigned[i]then entry.status='already';add(entry)
            else
                local item,status=choose(key,nil,'general');local replacement,empty_index
                if item then
                    local capacity=item.capacity
                    if type(capacity)~='number'or capacity%1~=0 or capacity<0 or capacity>100 then item,status=nil,'unsupported'
                    elseif capacity==0 or #all>capacity then item,status=nil,'no_slot'
                    elseif #all+additions<capacity then empty_index=#all+additions;additions=additions+1
                    elseif #surplus>0 then replacement=table.remove(surplus,1)
                    else item,status=nil,'no_slot'end
                end
                entry.status=status;add(entry,item,replacement,empty_index)
            end
        end
        for _,entry in ipairs(plan.entries)do plan.summary[entry.status]=(plan.summary[entry.status]or 0)+1 end
        return plan
    end
    local function safe_plan(state,g,take)
        local ok,plan=pcall(build,state,g,take)
        if not ok then return nil,'engine_error'end
        return plan
    end
    function A.preview(cqi,preset,take)
        if active then return nil,'busy'end
        local g=goal(preset);if not g then return nil,'invalid_preset'end
        local state,code=snapshot(cqi);if not state then return nil,code end
        return safe_plan(state,g,take==true)
    end
    local function emit(job,status,code)
        local report={status=status,code=code,completed=job.completed,summary=copy(job.final_summary or job.initial.summary)}
        last_report=report
        if job.notify then
            local ok=pcall(job.notify,copy(report))
            if not ok then job.cancelled=true end
        end
    end
    local function finish(job,status,code)
        if active~=job then return end
        active=nil;emit(job,status,code)
    end
    local step
    local function verify(job,pending)
        if active~=job or job.pending~=pending then return end
        local after,code=snapshot(job.cqi)
        if not after then finish(job,'error',code);return end
        if not counts_equal(pending.before.counts,after.counts)then finish(job,'inventory_changed');return end
        local expected=copy(pending.before.owners)
        local function delta(owner,key,n)
            expected[owner]=expected[owner]or{};expected[owner][key]=(expected[owner][key]or 0)+n
            if expected[owner][key]==0 then expected[owner][key]=nil end
        end
        local action=pending.action
        delta(action.candidate.owner,action.key,-1);delta(job.cqi,action.key,1)
        if action.replacement then delta(job.cqi,action.replacement.key,-1);delta(0,action.replacement.key,1)end
        if not owners_equal(expected,after.owners)then
            finish(job,owners_equal(pending.before.owners,after.owners)and (job.cancelled and 'cancelled'or 'not_applied')or 'inventory_changed');return
        end
        job.pending=nil;job.completed=job.completed+1;job.expected=after
        if job.cancelled then finish(job,'cancelled');return end
        emit(job,'running');step(job)
    end
    step=function(job)
        if active~=job then return end
        if job.cancelled then finish(job,'cancelled');return end
        local state,code=snapshot(job.cqi)
        if not state then finish(job,'error',code);return end
        if not same_state(job.expected,state)then finish(job,'inventory_changed');return end
        local plan,plan_code=safe_plan(state,job.goal,job.take)
        if not plan then finish(job,'error',plan_code);return end
        local action=plan.actions[1]
        if not action then
            job.final_summary=copy(plan.summary);job.final_summary.already=job.initial.summary.already or 0
            finish(job,'complete');return
        end
        if action.candidate.owner~=0 then
            local allowed=job.donors[action.candidate.owner]
            if not allowed or(allowed[action.key]or 0)<1 then finish(job,'inventory_changed');return end
            allowed[action.key]=allowed[action.key]-1
        end
        local ok,issued,error_code=pcall(engine.equip,job.cqi,action)
        if not ok or issued~=true then finish(job,'error',error_code or 'command_failed');return end
        local pending={before=state,action=action,manual=action.candidate.owner~=0};job.pending=pending
        if pending.manual then emit(job,'awaiting_confirmation')
        else
            emit(job,'running')
            local scheduled=pcall(engine.schedule,function()verify(job,pending)end,0.2)
            if not scheduled then finish(job,'error','schedule_failed')end
        end
    end
    function A.start(cqi,preset,take,approved,notify)
        if active then return nil,'busy'end
        local g=goal(preset)
        if not g or not approved or not same_goal(g,approved.goal)or approved.take~=(take==true)then return nil,'plan_changed'end
        local state,code=snapshot(cqi);if not state then return nil,code end
        if not same_state(approved.state,state)then return nil,'plan_changed'end
        local job={cqi=cqi,goal=g,take=take==true,expected=state,initial=approved,notify=notify,completed=0,donors={}}
        for _,action in ipairs(approved.actions)do if action.candidate.owner~=0 then
            local owner=action.candidate.owner;job.donors[owner]=job.donors[owner]or{}
            job.donors[owner][action.key]=(job.donors[owner][action.key]or 0)+1
        end end
        active=job;step(job);return true
    end
    function A.busy()return active~=nil end
    function A.waiting()return active and active.pending and active.pending.manual or false end
    function A.resume()
        if not A.waiting()then return nil,'busy'end
        local job=active;verify(job,job.pending);return true
    end
    function A.cancel()
        if not active then return false end
        active.cancelled=true
        if not active.pending then finish(active,'cancelled')
        elseif active.pending.manual then emit(active,'awaiting_confirmation','queue_cancelled_pending')end
        return true
    end
    function A.report()return last_report and copy(last_report)end
    return A
end