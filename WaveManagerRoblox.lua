-- WaveManager v2.0.0-rc.1 | Server-side, dependency-free.
-- One instance per match (solo or co-op). Drive time with :step(dt).
local WaveManager = { VERSION = "2.0.0-rc.1" }
local Methods = {}
local Private = setmetatable({}, { __mode = "k" })
local Meta = { __index = Methods, __metatable = "WaveManager" }
local MAX_WAVES, MAX_ENEMIES, LOG_SIZE = 1000, 10000, 64

local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function numberField(n, min, max, integer, name)
    assert(finite(n) and n >= min and n <= max and (not integer or n % 1 == 0),
        "Invalid " .. name)
    return n
end

local function duration(n, default, min, name)
    if n == nil then n = default end
    return numberField(n, min, 86400, false, name)
end

local function copyPlan(plan)
    assert(type(plan) == "table" and getmetatable(plan) == nil, "Expected a plain wave array")
    local length = 0
    for k in pairs(plan) do
        numberField(k, 1, MAX_WAVES, true, "wave index")
        length = length + 1
    end
    assert(length > 0, "Expected at least one wave")
    local result = {}
    for i = 1, length do
        local w = plan[i]
        assert(type(w) == "table" and getmetatable(w) == nil, "Invalid or missing wave " .. i)
        result[i] = {
            count = numberField(w.count, 1, MAX_ENEMIES, true, "enemy count"),
            duration = duration(w.duration, 60, 0.001, "duration"),
            countdown = duration(w.countdown, 10, 0, "countdown"),
            intermission = duration(w.intermission, 15, 0, "intermission"),
        }
    end
    return result
end

local function get(self)
    local s = Private[self]
    assert(s, "Use a WaveManager instance with ':'")
    return s
end

local function live(s)
    return s.phase == "Countdown" or s.phase == "Active" or s.phase == "Intermission"
end

local function record(s, event)
    s.sequence = s.sequence + 1
    local index = (s.sequence - 1) % LOG_SIZE + 1
    s.log[index] = {
        sequence = s.sequence, event = event, wave = s.wave,
        phase = s.phase, paused = s.paused, reason = s.reason,
    }
end

local function enter(s, phase, remaining)
    s.phase, s.timeLeft = phase, remaining
    record(s, phase)
end

local function clearEnemies(s)
    s.token = nil
    s.enemies = {}
end

local function terminal(s, phase, reason)
    clearEnemies(s)
    s.reason, s.paused = reason, false
    enter(s, phase, 0)
end

local function beginWave(s)
    s.wave = s.wave + 1
    local w = s.plan[s.wave]
    s.total, s.registered, s.killed = w.count, 0, 0
    s.enemies, s.token = {}, nil
    enter(s, "Countdown", w.countdown)
end

-- No yielding or external callbacks in any transition.
-- A step can cross an intermission, a countdown, and at most one active deadline.
local function advance(s, dt)
    while live(s) and not s.paused do
        if dt < s.timeLeft then
            s.timeLeft = s.timeLeft - dt
            return
        end
        dt = dt - s.timeLeft
        if s.phase == "Countdown" then
            s.token = {} -- unique identity, even across controllers
            enter(s, "Active", s.plan[s.wave].duration)
        elseif s.phase == "Intermission" then
            beginWave(s)
        else
            terminal(s, "Failed", "timeout")
        end
    end
end

local function finishWave(s)
    s.completedWaves = s.completedWaves + 1
    clearEnemies(s)
    if s.wave == #s.plan then
        terminal(s, "Completed", "all-waves-cleared")
    else
        enter(s, "Intermission", s.plan[s.wave].intermission)
        advance(s, 0)
    end
end

function WaveManager.new(plan)
    local self = setmetatable({}, Meta)
    Private[self] = {
        plan = copyPlan(plan), phase = "Idle", paused = false, wave = 0,
        total = 0, registered = 0, killed = 0, completedWaves = 0,
        timeLeft = 0, enemies = {}, log = {}, sequence = 0,
    }
    return self
end

function Methods:start()
    local s = get(self)
    if s.phase ~= "Idle" then return false, "already-started" end
    beginWave(s)
    advance(s, 0)
    return true
end

function Methods:step(dt)
    local s = get(self)
    if not finite(dt) or dt < 0 then return false, "invalid-dt" end
    if not live(s) then return false, "inactive" end
    if s.paused then return false, "paused" end
    advance(s, dt)
    return true
end

function Methods:pause()
    local s = get(self)
    if not live(s) or s.paused then return false, "cannot-pause" end
    s.paused = true
    record(s, "Paused")
    return true
end

function Methods:resume()
    local s = get(self)
    if not live(s) or not s.paused then return false, "not-paused" end
    s.paused = false
    record(s, "Resumed")
    advance(s, 0)
    return true
end

local function validId(id)
    local t = type(id)
    return (t == "string" and #id > 0 and #id <= 128)
        or (t == "number" and finite(id) and id % 1 == 0 and math.abs(id) <= 9007199254740991)
        or t == "table" or t == "userdata"
end

function Methods:registerEnemy(token, id)
    local s = get(self)
    if s.phase ~= "Active" then return false, "not-active" end
    if not rawequal(token, s.token) then return false, "stale-token" end
    if s.paused then return false, "paused" end
    if not validId(id) then return false, "invalid-enemy-id" end
    if s.enemies[id] ~= nil then return false, "duplicate-enemy" end
    if s.registered >= s.total then return false, "quota-full" end
    s.enemies[id] = true
    s.registered = s.registered + 1
    return true
end

function Methods:enemyKilled(token, id)
    local s = get(self)
    if s.phase ~= "Active" then return false, "not-active" end
    if not rawequal(token, s.token) then return false, "stale-token" end
    if not validId(id) then return false, "invalid-enemy-id" end
    if s.enemies[id] ~= true then return false, "unknown-or-resolved-enemy" end
    s.enemies[id] = false
    s.killed = s.killed + 1
    if s.killed == s.total then finishWave(s) end
    return true
end

function Methods:cancel()
    local s = get(self)
    if not live(s) then return false, "inactive" end
    terminal(s, "Cancelled", "cancelled")
    return true
end

function Methods:fail()
    local s = get(self)
    if not live(s) then return false, "inactive" end
    terminal(s, "Failed", "external")
    return true
end

function Methods:getState()
    local s = get(self)
    return {
        phase = s.phase, paused = s.paused, wave = s.wave,
        waveCount = #s.plan, completedWaves = s.completedWaves,
        timeLeft = s.timeLeft, totalEnemies = s.total,
        registeredEnemies = s.registered, killedEnemies = s.killed,
        remainingEnemies = s.total - s.killed,
        unregisteredEnemies = s.total - s.registered,
        aliveEnemies = s.registered - s.killed,
        token = s.token, reason = s.reason,
    }
end

function Methods:getHistory()
    local s = get(self)
    local result = {}
    for i = math.max(1, s.sequence - LOG_SIZE + 1), s.sequence do
        local event = s.log[(i - 1) % LOG_SIZE + 1]
        result[#result + 1] = {
            sequence = event.sequence, event = event.event, wave = event.wave,
            phase = event.phase, paused = event.paused, reason = event.reason,
        }
    end
    return result
end

return WaveManager
