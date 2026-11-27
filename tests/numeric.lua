-- Fractional-time differential test; integer microseconds are the reference clock.
-- Run: luau tests/numeric.lua (or lua5.4 tests/numeric.lua).
local W = require(_VERSION == "Lua 5.4" and "WaveManagerRoblox" or "../WaveManagerRoblox")
local seed = 1234567
local function rand(n)
    seed = (seed * 48271) % 2147483647
    return seed % n + 1
end
local function check(m, phase, micros)
    local s = m:getState()
    assert(s.phase == phase, s.phase .. " vs " .. phase)
    assert(math.abs(s.timeLeft - micros / 1000000) <= 2e-9, "timer disagreement")
    assert(s.timeLeft >= 0 and s.timeLeft < math.huge)
end
local partitions, pauses = 0, 0
for trial = 1, 1000 do
    local countdown = rand(2000000000)
    local duration = rand(2000000000) + 1000
    local m = W.new({{count=1,countdown=countdown/1e6,duration=duration/1e6}})
    assert(m:start())
    local total, elapsed = countdown+duration, 0
    local prior = m:getState()
    while elapsed < total do
        local chunk = math.min(total-elapsed, rand(math.max(1,math.floor(total/180))))
        if rand(9) == 1 then
            assert(m:pause()); assert(not m:step(chunk/1e6)); assert(m:resume())
            check(m, prior.phase, elapsed < countdown and countdown-elapsed or total-elapsed)
            pauses = pauses+1
        end
        assert(m:step(chunk/1e6)); elapsed=elapsed+chunk
        local now=m:getState()
        if elapsed == total then check(m,"Failed",0)
        elseif elapsed >= countdown then check(m,"Active",total-elapsed)
        else check(m,"Countdown",countdown-elapsed) end
        if prior.phase == now.phase then assert(now.timeLeft <= prior.timeLeft) end
        prior=now; partitions=partitions+1
    end
end
-- 24 hours of *simulated* 60 Hz frames. Never wait for real time.
local frames=86400*60
local long=W.new({{count=1,countdown=0,duration=86400}})
assert(long:start())
for i=1,frames-1 do assert(long:step(1/60)) end
local before=long:getState()
assert(before.phase=="Active" and math.abs(before.timeLeft-1/60)<2e-9)
assert(long:step(1/60)); assert(long:getState().reason=="timeout")
-- Small positive durations must not be consumed by start/step(0).
local tiny=W.new({{count=1,countdown=1e-12,duration=1}})
assert(tiny:start()); assert(tiny:step(0)); assert(tiny:getState().phase=="Countdown")
assert(tiny:step(1e-12)); assert(tiny:getState().phase=="Active")
-- Overshoot through intermission + countdown, then exact active deadline.
local over=W.new({{count=1,countdown=0,duration=2,intermission=.25},{count=1,countdown=.125,duration=.5}})
assert(over:start()); local tok=over:getState().token
assert(over:registerEnemy(tok,1)); assert(over:enemyKilled(tok,1))
assert(over:step(.5)); check(over,"Active",375000)
assert(over:step(.375)); check(over,"Failed",0)
print("NUMERIC PASS: "..partitions.." fractional steps; "..pauses.." pauses; "..frames.." simulated 60Hz frames")
