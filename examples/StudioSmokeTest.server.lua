-- Put this Script next to the WaveManagerRoblox ModuleScript in ServerScriptService.
-- No assets or players required. Run on the server; Output should print PASS.
local WaveManager = require(script.Parent.WaveManagerRoblox)

local match = WaveManager.new({
    {count = 2, countdown = 1, duration = 10, intermission = 1},
    {count = 1, countdown = 0, duration = 10},
})
local a, b = Instance.new("Folder"), Instance.new("Folder")
local ok, err = pcall(function()
    assert(match:start())
    assert(match:step(1))
    local token = match:getState().token
    assert(match:registerEnemy(token, a))
    assert(match:registerEnemy(token, b))
    assert(not match:registerEnemy(token, a))
    assert(match:pause())
    assert(not match:step(100))
    assert(match:getState().timeLeft == 10)
    assert(match:enemyKilled(token, a))
    assert(not match:enemyKilled(token, a))
    assert(match:enemyEscaped(token, b, false))
    assert(match:getState().phase == "Intermission")
    assert(match:getState().paused)
    assert(match:resume())
    assert(match:step(1))
    local nextToken = match:getState().token
    assert(nextToken ~= token)
    assert(not match:registerEnemy(token, a))
    assert(match:registerEnemy(nextToken, a))
    assert(not match:enemyKilled(token, a))
    assert(match:enemyKilled(nextToken, a))
    assert(match:getState().phase == "Completed")
    assert(match:getState().completedWaves == 2)
end)
a:Destroy()
b:Destroy()
if not ok then
    error(err)
end
print("WaveManager Studio smoke test: PASS")
