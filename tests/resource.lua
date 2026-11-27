-- Portable Lua 5.4 GC test. Luau does not expose forced collection.
local W = require("WaveManagerRoblox")
assert(_VERSION == "Lua 5.4")
local function collect()
    collectgarbage("collect"); collectgarbage("collect")
end
local function new()
    local m = W.new({{count=2,countdown=0,duration=1,intermission=0},{count=1,countdown=0,duration=1}})
    assert(m:start()); return m
end
local cases = 0
for _,kind in ipairs({"cancel", "fail", "timeout", "fatal", "advance"}) do
    local m = new()
    local weak=setmetatable({}, {__mode="v"})
    local token=m:getState().token
    do
        local a,b={owner=m},{owner=m}
        weak[1],weak[2]=a,b
        assert(m:registerEnemy(token,a)); assert(m:registerEnemy(token,b))
        assert(m:enemyKilled(token,a))
    end
    collect(); assert(weak[1] and weak[2],"identity must remain available for duplicate rejection")
    assert(not m:registerEnemy(token,weak[1])); assert(not m:enemyKilled(token,weak[1]))
    if kind=="cancel" then assert(m:cancel())
    elseif kind=="fail" then assert(m:fail())
    elseif kind=="timeout" then assert(m:step(1))
    elseif kind=="fatal" then assert(m:enemyEscaped(token,weak[2],true))
    else assert(m:enemyKilled(token,weak[2])); assert(m:getState().wave==2) end
    collect(); assert(not weak[1] and not weak[2],"retained enemy identity: "..kind)
    cases=cases+1
end
-- Completed final wave: even an external snapshot/token must not root enemy IDs.
local m=W.new({{count=1,countdown=0,duration=1}})
assert(m:start()); local snapshot=m:getState()
local weak=setmetatable({}, {__mode="v"})
do
    local id={owner=m}; weak[1]=id
    assert(m:registerEnemy(snapshot.token,id)); assert(m:enemyKilled(snapshot.token,id))
end
collect(); assert(not weak[1] and m:getState().phase=="Completed"); cases=cases+1
-- Drop an active match with circular references; the module must not retain it.
local refs=setmetatable({}, {__mode="v"})
for i=1,1000 do
    local x=new(); local id={owner=x}; refs[i*2]=x; refs[i*2-1]=id
    assert(x:registerEnemy(x:getState().token,id))
end
collect(); assert(next(refs)==nil,"abandoned match cycle retained"); cases=cases+1
print("RESOURCE PASS: "..cases.." GC scenarios; 1000 abandoned cyclic matches collected")
