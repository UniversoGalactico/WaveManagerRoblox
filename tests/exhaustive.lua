-- Finite-state exploration of every two-wave plan in a small integer domain.
-- Run from the repository root: luau tests/exhaustive.lua
local W
if _VERSION == "Lua 5.4" then W = require("WaveManagerRoblox")
else W = require("../WaveManagerRoblox") end

local actions = {
    {"start"}, {"step",0}, {"step",1}, {"step",2}, {"step",4}, {"step",-1},
    {"pause"}, {"resume"}, {"cancel"}, {"fail"},
    {"register",1,false}, {"kill",1,false}, {"escape",1,false,true},
    {"register",false,true}, {"kill",false,true}, {"escape",false,true,true},
    {"escape",1,true,"invalid"},
}
for id = 1, 3 do
    actions[#actions+1] = {"register",id,true}
    actions[#actions+1] = {"kill",id,true}
    actions[#actions+1] = {"escape",id,true,false}
    actions[#actions+1] = {"escape",id,true,true}
end

local function newState()
    return {phase="Idle",paused=false,wave=0,time=0,completed=0,ids={0,0,0}}
end
local function clone(x)
    return {phase=x.phase,paused=x.paused,wave=x.wave,time=x.time,
        completed=x.completed,ids={x.ids[1],x.ids[2],x.ids[3]},reason=x.reason}
end
local function live(x)
    return x.phase == "Active" or x.phase == "Countdown" or x.phase == "Intermission"
end
local function counts(x)
    local r,k,e = 0,0,0
    for _,v in ipairs(x.ids) do
        if v ~= 0 then r = r+1 end
        if v == 2 then k = k+1 end
        if v == 3 then e = e+1 end
    end
    return r,k,e
end
local function finish(x, phase, reason)
    x.phase, x.reason, x.time, x.paused = phase,reason,0,false
end
local function begin(x, plan)
    x.wave = x.wave+1
    x.phase,x.time,x.ids = "Countdown",plan[x.wave].countdown,{0,0,0}
end
local function settle(x, plan)
    while live(x) and not x.paused and x.time == 0 do
        if x.phase == "Countdown" then
            x.phase,x.time = "Active",plan[x.wave].duration
        elseif x.phase == "Intermission" then
            begin(x, plan)
        else
            finish(x,"Failed","timeout")
        end
    end
end

-- Independent reference: time advances by one integer tick at a time,
-- and counters are derived from the finite vector of enemy identities.
local function transition(x, plan, a)
    local y = clone(x)
    local op,id,fresh,fatal = a[1],a[2],a[3],a[4]
    local function reject(reason) return x,false,reason end
    if op == "start" then
        if y.phase ~= "Idle" then return reject("already-started") end
        begin(y,plan); settle(y,plan)
    elseif op == "step" then
        if id < 0 then return reject("invalid-dt") end
        if not live(y) then return reject("inactive") end
        if y.paused then return reject("paused") end
        for _ = 1,id do
            if not live(y) then break end
            y.time = y.time-1
            settle(y,plan)
        end
    elseif op == "pause" then
        if not live(y) or y.paused then return reject("cannot-pause") end
        y.paused = true
    elseif op == "resume" then
        if not live(y) or not y.paused then return reject("not-paused") end
        y.paused = false; settle(y,plan)
    elseif op == "cancel" or op == "fail" then
        if not live(y) then return reject("inactive") end
        if op == "cancel" then finish(y,"Cancelled","cancelled")
        else finish(y,"Failed","external") end
    else
        if op == "escape" and type(fatal) ~= "boolean" then return reject("invalid-fatal") end
        if y.phase ~= "Active" then return reject("not-active") end
        if not fresh then return reject("stale-token") end
        if op == "register" and y.paused then return reject("paused") end
        if id == false then return reject("invalid-enemy-id") end
        if op == "register" then
            if y.ids[id] ~= 0 then return reject("duplicate-enemy") end
            local registered = counts(y)
            if registered == plan[y.wave].count then return reject("quota-full") end
            y.ids[id] = 1
        else
            if y.ids[id] ~= 1 then return reject("unknown-or-resolved-enemy") end
            y.ids[id] = op == "kill" and 2 or 3
            local _,k,e = counts(y)
            if fatal then
                finish(y,"Failed","fatal-escape")
            elseif k+e == plan[y.wave].count then
                y.completed = y.completed+1
                if y.wave == #plan then finish(y,"Completed","all-waves-cleared")
                else
                    y.phase,y.time = "Intermission",plan[y.wave].intermission
                    settle(y,plan)
                end
            end
        end
    end
    return y,true,nil
end

local stale = {}
local function command(m,a)
    local op,id,fresh,fatal = a[1],a[2],a[3],a[4]
    if op == "start" then return m:start()
    elseif op == "step" then return m:step(id)
    elseif op == "pause" then return m:pause()
    elseif op == "resume" then return m:resume()
    elseif op == "cancel" then return m:cancel()
    elseif op == "fail" then return m:fail() end
    local token = fresh and m:getState().token or stale
    if op == "register" then return m:registerEnemy(token,id)
    elseif op == "kill" then return m:enemyKilled(token,id)
    else return m:enemyEscaped(token,id,fatal) end
end

local function key(x)
    return table.concat({x.phase,tostring(x.paused),x.wave,x.time,x.completed,
        x.ids[1],x.ids[2],x.ids[3],x.reason or "-"},":")
end

local function verify(x,m,plan)
    local s = m:getState()
    local r,k,e = counts(x)
    local n = x.wave == 0 and 0 or plan[x.wave].count
    assert(s.phase==x.phase and s.paused==x.paused and s.wave==x.wave and s.timeLeft==x.time,
        "phase/timer mismatch: "..key(x).." / "..s.phase..":"..s.timeLeft)
    assert(s.waveCount==#plan and s.completedWaves==x.completed and s.reason==x.reason,"progress/reason mismatch")
    assert(s.totalEnemies==n and s.registeredEnemies==r and s.killedEnemies==k and s.escapedEnemies==e,"counter mismatch")
    assert(s.resolvedEnemies==k+e and s.remainingEnemies==n-k-e and s.unregisteredEnemies==n-r and s.aliveEnemies==r-k-e,"derived counter mismatch")
    assert((s.token~=nil)==(x.phase=="Active"),"token lifetime mismatch")
end

local function explore(plan)
    local initial = newState()
    local nodes = {{state=initial,path={}}}
    local visited = {[key(initial)]=true}
    local head,edges,accepted,rejected = 1,0,0,0
    local function replay(path)
        local m = W.new(plan)
        for _,index in ipairs(path) do assert(command(m,actions[index])) end
        return m
    end
    while head <= #nodes do
        local node = nodes[head]
        head = head+1
        local base = replay(node.path)
        verify(node.state,base,plan)
        for index,a in ipairs(actions) do
            local target,expected,reason = transition(node.state,plan,a)
            -- Rejections are checked consecutively against the same base instance;
            -- a rejected operation must not mutate that instance or its history.
            local m = expected and replay(node.path) or base
            local logBefore = not expected and #m:getHistory() or 0
            local actual,err = command(m,a)
            assert(actual==expected and err==reason,"return mismatch: "..a[1].." "..key(node.state).." expected "..tostring(reason).." got "..tostring(err))
            verify(target,m,plan)
            if not expected then
                assert(#m:getHistory()==logBefore,"rejection added a history event")
                rejected = rejected+1
            else
                accepted = accepted+1
                local k = key(target)
                if not visited[k] then
                    visited[k] = true
                    local path = {}
                    for i,v in ipairs(node.path) do path[i]=v end
                    path[#path+1]=index
                    nodes[#nodes+1]={state=target,path=path}
                end
            end
            edges = edges+1
        end
    end
    return #nodes,edges,accepted,rejected
end

local states,edges,accepted,rejected,plans = 0,0,0,0,0
for count1=1,2 do for countdown1=0,1 do for duration1=1,2 do for intermission1=0,1 do
    for count2=1,2 do for countdown2=0,1 do for duration2=1,2 do
        local p = {
            {count=count1,countdown=countdown1,duration=duration1,intermission=intermission1},
            {count=count2,countdown=countdown2,duration=duration2,intermission=0},
        }
        local s,e,a,r = explore(p)
        states,edges,accepted,rejected,plans=states+s,edges+e,accepted+a,rejected+r,plans+1
        if plans%16==0 then print("Explored "..plans.." plans, "..states.." states, "..edges.." commands") end
    end end end
end end end end
assert(plans==128 and edges==accepted+rejected)
print("EXHAUSTIVE PASS: "..plans.." plans; "..states.." abstract states; "..edges.." commands; "..accepted.." accepted; "..rejected.." rejected")
