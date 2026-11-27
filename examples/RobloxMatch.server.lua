-- Demonstration server Script. Place beside WaveManagerRoblox ModuleScript.
-- Requires ServerStorage.EnemyTemplate (Model with living Humanoid),
-- and Workspace.EnemySpawn (BasePart). The template supplies its own NPC AI.
-- The module does not own NPCs or Roblox connections; this integration does.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local WaveManager = require(script.Parent.WaveManagerRoblox)
local template = ServerStorage:WaitForChild("EnemyTemplate")
local spawnPoint = workspace:WaitForChild("EnemySpawn")
assert(template:IsA("Model") and spawnPoint:IsA("BasePart"))

local match = WaveManager.new({
    {count = 3, countdown = 3, duration = 30, intermission = 3},
    {count = 5, countdown = 3, duration = 45},
})
local folder = Instance.new("Folder")
folder.Name = "WaveDemoEnemies"
folder.Parent = workspace
local tracked = {}
local heartbeat
local stopped = false
local last = os.clock()
local lastToken
local nextSpawn = 0
local SPAWN_INTERVAL = 0.35

-- Synchronize the same elapsed-time source before timers and death callbacks.
-- Do not also use Heartbeat's dt or paused time would be double-counted.
local function sync()
    local now = os.clock()
    match:step(math.max(0, now - last))
    last = now
    return now
end

local function cleanup(model)
    local connection = tracked[model]
    if connection then
        tracked[model] = nil
        connection:Disconnect()
    end
    model:Destroy()
end

local function stop()
    if stopped then return end
    stopped = true
    if heartbeat then heartbeat:Disconnect() end
    for model in pairs(tracked) do
        cleanup(model)
    end
    folder:Destroy()
    local state = match:getState()
    print("Wave match ended:", state.phase, state.reason, state.completedWaves)
end

local function spawnOne(token)
    local model
    local success, err = pcall(function()
        model = template:Clone()
        assert(model, "EnemyTemplate could not be cloned")
        local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
        assert(humanoid and humanoid.Health > 0, "Expected a living Humanoid")
        model:PivotTo(spawnPoint.CFrame)
        local registered, reason = match:registerEnemy(token, model)
        assert(registered, reason)
        -- Subscribe before making the NPC active in Workspace.
        tracked[model] = humanoid.Died:Connect(function()
            if stopped or not tracked[model] then return end
            sync()
            match:enemyKilled(token, model)
            cleanup(model)
        end)
        model.Parent = folder
    end)
    if not success then
        if model then cleanup(model) end
        match:fail()
        warn("Wave spawn failed:", err)
        return false
    end
    return true
end

assert(match:start())
last = os.clock()
heartbeat = RunService.Heartbeat:Connect(function()
    local now = sync()
    local state = match:getState()
    if state.phase == "Completed" or state.phase == "Failed" or state.phase == "Cancelled" then
        stop()
        return
    end
    if state.phase ~= "Active" or state.paused then return end
    if state.token ~= lastToken then
        lastToken = state.token
        nextSpawn = now
    end
    -- One NPC per interval; no unbounded catch-up burst after a lag spike.
    if state.unregisteredEnemies > 0 and now >= nextSpawn then
        nextSpawn = now + SPAWN_INTERVAL
        spawnOne(state.token)
    end
end)

-- In a real game, the match owner must cancel + stop on match teardown.
-- For example, when the last player leaves or the arena is removed.
script.Destroying:Connect(function()
    match:cancel()
    stop()
end)
