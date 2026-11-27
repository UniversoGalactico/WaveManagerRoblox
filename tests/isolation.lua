-- Interleave many independent matches; share enemy IDs but never wave tokens.
local W = require(_VERSION == "Lua 5.4" and "WaveManagerRoblox" or "../WaveManagerRoblox")
local count, waves = 256, 20
local plan={}
for w=1,waves do plan[w]={count=3,countdown=0,duration=4,intermission=0} end
local matches, tokens, seen={}, {}, {}
for i=1,count do
    matches[i]=W.new(plan); assert(matches[i]:start())
    tokens[i]=matches[i]:getState().token
    assert(not seen[tokens[i]]); seen[tokens[i]]=true
end
local shared=setmetatable({}, {__eq=function() error("unexpected equality callback") end})
local operations=0
local function expect(ok, wanted) operations=operations+1; assert(ok==wanted) end
for w=1,waves do
    -- Register identical enemy identities across every match; a token from a
    -- neighboring match must never authorize a write even when IDs collide.
    for i,m in ipairs(matches) do
        local foreign=tokens[i%count+1]
        expect(m:registerEnemy(foreign,shared),false)
        expect(m:registerEnemy(tokens[i],shared),true)
        expect(m:registerEnemy(tokens[i],"B"),true)
        expect(m:registerEnemy(tokens[i],"C"),true)
        expect(m:step(i%3),true)
        if i%2==0 then expect(m:pause(),true) end
    end
    for i=count,1,-1 do
        local m=matches[i]; local t=tokens[i]
        expect(m:enemyKilled(tokens[i%count+1],shared),false)
        expect(m:enemyKilled(t,shared),true)
        expect(m:enemyEscaped(t,shared,true),false)
        local s=m:getState()
        assert(s.wave==w and s.killedEnemies==1 and s.registeredEnemies==3 and s.paused==(i%2==0))
        assert(s.timeLeft==4-i%3)
    end
    for i,m in ipairs(matches) do
        local t=tokens[i]
        if i%2==0 then expect(m:resume(),true) end
        expect(m:enemyEscaped(t,"B"),true)
        expect(m:enemyKilled(t,"C"),true)
        local s=m:getState()
        assert(s.completedWaves==w)
        if w<waves then
            assert(s.phase=="Active" and s.wave==w+1 and s.registeredEnemies==0)
            assert(not seen[s.token]); seen[s.token]=true
            expect(m:registerEnemy(t,shared),false)
            tokens[i]=s.token
        else assert(s.phase=="Completed" and not s.token) end
    end
end
print("ISOLATION PASS: "..count.." interleaved matches, "..count*waves.." waves, "..operations.." commands")
