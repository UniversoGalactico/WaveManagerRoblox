-- Run from repo root: lua5.4 tests/run.lua OR luau tests/run.lua
local W
if _VERSION == "Lua 5.4" then
    W = require("WaveManagerRoblox")
else
    W = require("../WaveManagerRoblox")
end
local checks = 0
local function eq(a, b, label)
    checks = checks + 1
    assert(a == b, (label or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end
local function ok(value) eq(value, true) end
local function no(value, reason, expected)
    eq(value, false)
    if expected then eq(reason, expected) end
end
local function rejected(plan)
    eq(pcall(W.new, plan), false, "invalid plan")
end
local function wave(count, countdown, duration, intermission)
    return {count = count, countdown = countdown, duration = duration, intermission = intermission}
end

-- Deterministic lifecycle and mutation isolation.
local plan = {wave(2, 2, 5, 1), wave(1, 0, 3, 0)}
local m = W.new(plan)
plan[1].count = 99
plan[2].duration = 99
eq(m:getState().phase, "Idle")
no(m:pause())
no(m:cancel())
ok(m:start())
no(m:start())
eq(m:getState().totalEnemies, 2)
ok(m:step(1))
ok(m:pause())
no(m:step(100))
eq(m:getState().timeLeft, 1)
ok(m:resume())
ok(m:step(1))
local a = m:getState()
eq(a.phase, "Active")
eq(a.timeLeft, 5)
a.wave = 77
eq(m:getState().wave, 1)
local t = a.token
no(m:enemyKilled(t, "unregistered"))
no(m:registerEnemy({}, "e1"))
ok(m:registerEnemy(t, "e1"))
no(m:registerEnemy(t, "e1"))
ok(m:enemyKilled(t, "e1"))
no(m:enemyKilled(t, "e1"))
no(m:registerEnemy(t, "e1"))
eq(m:getState().remainingEnemies, 1)
ok(m:registerEnemy(t, "e2"))
no(m:registerEnemy(t, "overflow"))
ok(m:step(2))
ok(m:pause())
no(m:registerEnemy(t, "paused"))
no(m:step(90))
eq(m:getState().timeLeft, 3)
ok(m:enemyKilled(t, "e2"))
eq(m:getState().phase, "Intermission")
eq(m:getState().paused, true)
no(m:step(100))
ok(m:resume())
ok(m:step(1))
local b = m:getState()
eq(b.phase, "Active")
eq(b.wave, 2)
eq(b.timeLeft, 3)
eq(b.completedWaves, 1)
assert(not rawequal(b.token, t))
no(m:registerEnemy(t, "e1"))
ok(m:registerEnemy(b.token, "e1"))
no(m:enemyKilled(t, "e1"))
ok(m:enemyKilled(b.token, "e1"))
eq(m:getState().phase, "Completed")
eq(m:getState().completedWaves, 2)
eq(m:getState().token, nil)
no(m:start())
no(m:cancel())
no(m:fail())
no(m:step(100))
local hist = m:getHistory()
hist[1].event = "bad"
eq(m:getHistory()[1].event, "Countdown")

-- Instance methods are bound to their owner, and public field writes cannot
-- shadow a method or masquerade as internal state.
local ownerA = W.new({wave(1,0,1,0)})
local ownerB = W.new({wave(1,0,1,0)})
eq(pcall(function() ownerA.step = function() end end),false)
eq(pcall(function() ownerA.phase = "Completed" end),false)
eq(pcall(ownerA.start,ownerB),false)
eq(pcall(ownerA.start),false)
eq(ownerA:getState().phase,"Idle"); eq(ownerB:getState().phase,"Idle")
if _VERSION == "Lua 5.4" then
    -- Even a registered ID that contains its owner must not root a dead match.
    local weak = setmetatable({}, {__mode="v"})
    do
        local abandoned = W.new({wave(1,0,1,0)})
        assert(abandoned:start())
        local identity = {owner=abandoned}
        assert(abandoned:registerEnemy(abandoned:getState().token,identity))
        weak[1],weak[2] = abandoned,identity
    end
    collectgarbage("collect"); collectgarbage("collect")
    eq(weak[1],nil); eq(weak[2],nil)
end

-- Deadline, huge delta, failure/cancel, and zero-duration phase behavior.
for _, dt in ipairs({0, -1, math.huge, -math.huge, 0/0, "1", false}) do
    local c = W.new({wave(1, 0, 1, 0)})
    ok(c:start())
    if dt == 0 then ok(c:step(dt)) else no(c:step(dt)) end
    eq(c:getState().timeLeft, 1)
end
local c = W.new({wave(1, 2, 3, 0)})
ok(c:start())
ok(c:step(4))
eq(c:getState().phase, "Active")
eq(c:getState().timeLeft, 1)
ok(c:step(1))
eq(c:getState().phase, "Failed")
eq(c:getState().reason, "timeout")
local d = W.new({wave(1, 0, 1, 0), wave(1, 0, 1, 0)})
ok(d:start())
local dt = d:getState().token
ok(d:registerEnemy(dt, 1))
ok(d:pause())
ok(d:enemyKilled(dt, 1))
eq(d:getState().phase, "Intermission")
eq(d:getState().timeLeft, 0)
ok(d:resume())
eq(d:getState().wave, 2)
eq(d:getState().phase, "Active")
no(d:registerEnemy(dt, 1))
ok(d:cancel())
eq(d:getState().phase, "Cancelled")
local e = W.new({wave(1, 0, 1, 0)})
ok(e:start())
ok(e:pause())
ok(e:fail())
eq(e:getState().reason, "external")
eq(e:getState().paused, false)
local f = W.new({wave(1, 10, 1, 0)})
ok(f:start())
ok(f:step(1e100))
eq(f:getState().phase, "Failed")

-- Fractional frame partitions must not leave a one-frame countdown residue.
for _, parts in ipairs({3,6,7,10,12,30,60,100,120,1000,10000,100000}) do
    local fractional = W.new({wave(1,1,2,0)})
    ok(fractional:start())
    for _ = 1, parts do assert(fractional:step(1/parts)) end
    local state = fractional:getState()
    eq(state.phase,"Active")
    assert(math.abs(state.timeLeft-2) < 1e-8)
end
local tiny = W.new({wave(1,1e-12,1,0)})
ok(tiny:start()); eq(tiny:getState().phase,"Countdown")
ok(tiny:step(0)); eq(tiny:getState().phase,"Countdown")
ok(tiny:step(1e-12)); eq(tiny:getState().phase,"Active")
local precise = W.new({wave(1,3600,1,0)})
ok(precise:start())
for _ = 1, 216000 do assert(precise:step(1/60)) end
eq(precise:getState().phase,"Active")
assert(math.abs(precise:getState().timeLeft-1) < 1e-8)

-- Input validation including sparse arrays and locked metatables.
for _, p in ipairs({{}, {false}, {[2] = wave(1,0,1,0)}, {wave(1,0,1,0), extra = true},
    {wave(0,0,1,0)}, {wave(1.5,0,1,0)}, {wave(10001,0,1,0)},
    {wave(1,-1,1,0)}, {wave(1,0,0,0)}, {wave(1,0,math.huge,0)},
    {wave(1,0,1,0/0)}, {wave(1,0,1,86401)}, setmetatable({wave(1,0,1,0)}, {}),
    {setmetatable(wave(1,0,1,0), {})}, {[1001] = wave(1,0,1,0)},
    {{count=1, duraton=2}}}) do rejected(p) end
rejected(nil)
rejected(123)
local g = W.new({wave(2,0,1,0)})
local h = W.new({wave(2,0,1,0)})
ok(g:start()); ok(h:start())
local gt, ht = g:getState().token, h:getState().token
no(g:registerEnemy(ht, "e"))
no(g:registerEnemy(setmetatable({}, {__eq = function() error("must not invoke __eq") end}), "e"))
for _, id in ipairs({false, 0/0, math.huge, 1.1, "", string.rep("x",129), function() end}) do
    no(g:registerEnemy(gt, id)); no(g:enemyKilled(gt, id))
end
no(g:registerEnemy(gt, nil))
no(g:registerEnemy(gt, 9007199254740992))
no(g:registerEnemy(gt, -9007199254740992))
if math.mininteger then no(g:registerEnemy(gt, math.mininteger)) end
local id = {}
ok(g:registerEnemy(gt, id)); ok(h:registerEnemy(ht, id))
ok(g:enemyKilled(gt, id))
eq(h:getState().killedEnemies, 0)
for _ = 1, 100 do ok(h:pause()); ok(h:resume()) end
local log = h:getHistory()
eq(#log, 64)
for i = 2, #log do eq(log[i].sequence, log[i-1].sequence + 1) end

-- A lethal escape must beat a simultaneous wave clear, without accepting stale,
-- duplicate, foreign, unregistered, or malformed notifications.
local fatal = W.new({wave(2,0,10,0)})
ok(fatal:start())
local ft = fatal:getState().token
ok(fatal:registerEnemy(ft,"a")); ok(fatal:registerEnemy(ft,"b"))
no(fatal:enemyEscaped({},"a",true))
no(fatal:enemyEscaped(ft,"unknown",true))
no(fatal:enemyEscaped(ft,"a",1))
ok(fatal:enemyEscaped(ft,"a",false))
no(fatal:enemyEscaped(ft,"a",true))
eq(fatal:getState().phase,"Active")
ok(fatal:pause())
ok(fatal:enemyEscaped(ft,"b",true))
local fs = fatal:getState()
eq(fs.phase,"Failed"); eq(fs.reason,"fatal-escape"); eq(fs.completedWaves,0)
eq(fs.escapedEnemies,2); eq(fs.remainingEnemies,0); eq(fs.paused,false); eq(fs.token,nil)
no(fatal:enemyEscaped(ft,"b",true))
local early = W.new({wave(3,0,10,0),wave(1,0,1,0)})
ok(early:start())
local et = early:getState().token
ok(early:registerEnemy(et,"fatal")); ok(early:enemyEscaped(et,"fatal",true))
eq(early:getState().remainingEnemies,2); eq(early:getState().wave,1)
eq(early:getState().phase,"Failed")

-- Independent deadline-based reference model. Integer time deliberately avoids
-- floating point ambiguity. The implementation instead uses remaining durations.
local function model(plan2)
    return {plan = plan2, phase = "Idle", paused = false, wave = 0, completed = 0,
        now = 0, deadline = 0, registered = 0, killed = 0, escaped = 0, total = 0, ids = {}}
end
local function active(x)
    return x.phase == "Countdown" or x.phase == "Active" or x.phase == "Intermission"
end
local function begin(x, at)
    x.wave = x.wave + 1
    x.phase, x.deadline = "Countdown", at + x.plan[x.wave].countdown
    x.total, x.registered, x.killed, x.escaped, x.ids = x.plan[x.wave].count, 0, 0, 0, {}
end
local function endModel(x, phase, reason)
    x.phase, x.reason, x.paused, x.deadline = phase, reason, false, x.now
end
local function normalize(x)
    while active(x) and not x.paused and x.now >= x.deadline do
        local at = x.deadline
        if x.phase == "Countdown" then
            x.phase, x.deadline = "Active", at + x.plan[x.wave].duration
        elseif x.phase == "Intermission" then begin(x, at)
        else endModel(x, "Failed", "timeout") end
    end
end
local function apply(x, op, arg, fresh)
    if op == 1 then
        if x.phase ~= "Idle" then return false end
        begin(x, x.now); normalize(x); return true
    elseif op == 2 then
        if not active(x) or x.paused then return false end
        x.now = x.now + arg; normalize(x); return true
    elseif op == 3 then
        if not active(x) or x.paused then return false end
        x.paused = true; return true
    elseif op == 4 then
        if not active(x) or not x.paused then return false end
        x.paused = false; normalize(x); return true
    elseif op == 5 then
        if x.phase ~= "Active" or not fresh or x.paused or x.ids[arg] ~= nil or x.registered >= x.total then return false end
        x.ids[arg] = "live"; x.registered = x.registered + 1; return true
    elseif op == 6 or op == 9 then
        if x.phase ~= "Active" or not fresh or x.ids[arg] ~= "live" then return false end
        x.ids[arg] = "resolved"
        if op == 6 then x.killed = x.killed + 1 else x.escaped = x.escaped + 1 end
        if x.killed + x.escaped == x.total then
            x.completed = x.completed + 1
            if x.wave == #x.plan then endModel(x, "Completed", "all-waves-cleared")
            else
                x.phase, x.deadline = "Intermission", x.now + x.plan[x.wave].intermission
                normalize(x)
            end
        end
        return true
    elseif op == 7 then
        if not active(x) then return false end
        endModel(x, "Cancelled", "cancelled"); return true
    else
        if not active(x) then return false end
        endModel(x, "Failed", "external"); return true
    end
end
local function verify(x, y)
    local s = y:getState()
    eq(s.phase, x.phase); eq(s.paused, x.paused); eq(s.wave, x.wave)
    eq(s.waveCount, #x.plan); eq(s.completedWaves, x.completed)
    eq(s.timeLeft, active(x) and x.deadline - x.now or 0)
    eq(s.totalEnemies, x.total); eq(s.registeredEnemies, x.registered); eq(s.killedEnemies, x.killed)
    eq(s.escapedEnemies, x.escaped); eq(s.resolvedEnemies, x.killed+x.escaped)
    eq(s.remainingEnemies, x.total-x.killed-x.escaped); eq(s.aliveEnemies, x.registered-x.killed-x.escaped)
    eq(s.unregisteredEnemies, x.total-x.registered); eq(s.reason, x.reason)
    eq(s.token ~= nil, x.phase == "Active")
    assert(s.resolvedEnemies <= s.registeredEnemies and s.registeredEnemies <= s.totalEnemies)
end
local seed = 239874
local function rand(n)
    seed = (seed * 48271) % 2147483647
    return seed % n + 1
end
local operations, completions, failures, cancellations = 0, 0, 0, 0
for trial = 1, 3000 do
    local p = {}
    for i = 1, rand(4) do p[i] = wave(rand(4), rand(3)-1, rand(12), rand(3)-1) end
    local x, y = model(p), W.new(p)
    local past = {}
    for turn = 1, 100 do
        local s = y:getState()
        local op, arg, fresh = rand(20), rand(6), rand(5) ~= 1
        if s.phase == "Idle" then op = 1
        elseif op <= 4 then op, arg = 2, rand(5)-1
        elseif op <= 6 then op = 3
        elseif op <= 8 then op = 4
        elseif op <= 13 then op = 5
        elseif op <= 16 then op = 6
        elseif op <= 18 then op = 9
        elseif op == 19 then op = 7
        else op = 8 end
        if s.token and past[#past] ~= s.token then past[#past+1] = s.token end
        local token = fresh and s.token or (past[#past-1] or {})
        -- Never accidentally use the current token in the stale branch.
        if not fresh and token == s.token then token = {} end
        local expected = apply(x, op, arg, fresh)
        local actual
        if op == 1 then actual = y:start()
        elseif op == 2 then actual = y:step(arg)
        elseif op == 3 then actual = y:pause()
        elseif op == 4 then actual = y:resume()
        elseif op == 5 then actual = y:registerEnemy(token, arg)
        elseif op == 6 then actual = y:enemyKilled(token, arg)
        elseif op == 9 then actual = y:enemyEscaped(token, arg)
        elseif op == 7 then actual = y:cancel()
        else actual = y:fail() end
        eq(actual, expected, "operation " .. op)
        verify(x, y)
        operations = operations + 1
        if x.phase == "Completed" or x.phase == "Failed" or x.phase == "Cancelled" then
            if x.phase == "Completed" then completions = completions + 1
            elseif x.phase == "Failed" then failures = failures + 1
            else cancellations = cancellations + 1 end
            break
        end
    end
end
assert(completions > 0 and failures > 0 and cancellations > 0)

-- A success-biased schedule reaches late waves and injects duplicate, stale and
-- cross-outcome notifications at every transition. No time advances while paused.
local wins = 0
for trial = 1, 500 do
    local p = {}
    for i = 1, rand(10) do p[i] = wave(rand(12), rand(3)-1, 20, rand(4)-1) end
    local x, y = model(p), W.new(p)
    local tokenBefore
    local function command(op, arg, fresh)
        local s = y:getState()
        local token = fresh and s.token or (tokenBefore or {})
        if not fresh and token == s.token then token = {} end
        local expected = apply(x, op, arg, fresh)
        local actual
        if op == 1 then actual = y:start()
        elseif op == 2 then actual = y:step(arg)
        elseif op == 3 then actual = y:pause()
        elseif op == 4 then actual = y:resume()
        elseif op == 5 then actual = y:registerEnemy(token, arg)
        elseif op == 6 then actual = y:enemyKilled(token, arg)
        else actual = y:enemyEscaped(token, arg) end
        eq(actual, expected); verify(x, y); operations = operations + 1
    end
    command(1, 0, true)
    for i = 1, #p do
        local s = y:getState()
        if s.phase == "Intermission" then command(2, s.timeLeft, true) end
        s = y:getState()
        if s.phase == "Countdown" then command(2, s.timeLeft, true) end
        s = y:getState(); eq(s.wave, i); eq(s.phase, "Active")
        command(5, 1, false)
        for j = 1, p[i].count do
            command(5, j, true); command(5, j, true)
            command(3, 0, true); command(2, 100, true)
            local outcome = rand(2) == 1 and 6 or 9
            command(outcome, j, true)
            command(outcome == 6 and 9 or 6, j, true)
            if y:getState().paused then command(4, 0, true) end
        end
        tokenBefore = s.token
    end
    eq(y:getState().phase, "Completed"); wins = wins + 1
end

-- Full capacity and progression stress, including reused IDs across waves.
local long = {}
for i = 1, 1000 do long[i] = wave(10,0,1,0) end
local z = W.new(long); ok(z:start())
for i = 1, #long do
    local s = z:getState(); eq(s.wave, i)
    for j = 1, 10 do ok(z:registerEnemy(s.token, j)); ok(z:enemyKilled(s.token,j)) end
end
eq(z:getState().phase, "Completed")
eq(z:getState().completedWaves, 1000)
local big = W.new({wave(10000,0,1,0)}); ok(big:start())
local bt = big:getState().token
for j = 1, 10000 do ok(big:registerEnemy(bt, j)) end
no(big:registerEnemy(bt, 10001))
for j = 1, 10000 do ok(big:enemyKilled(bt, j)) end
eq(big:getState().phase, "Completed")
print("PASS: " .. checks .. " assertions; " .. operations .. " randomized model operations; completed=" .. completions .. ", failed=" .. failures .. ", cancelled=" .. cancellations .. "; success-biased campaigns=" .. wins)
