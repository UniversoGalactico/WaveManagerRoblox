-- WaveManager.lua | ModuleScript (ServerScriptService.ServerModules)
-- Responsabilidad única: Controlar el flujo de oleadas de enemigos.
-- Depende solo de GuardUtils para validación, mutex y rate limiting.

local WaveManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuardUtils = require(script.Parent.GuardUtils)

local CONFIG = table.freeze({
    DEFAULT_WAVE_DURATION = 60,
    PRE_WAVE_PAUSE = 10,
    POST_WAVE_PAUSE = 15,
    ENEMIES_PER_WAVE_BASE = 5,
    ENEMIES_PER_WAVE_MULTIPLIER = 1.5,
    MAX_WAVES = 50,
    MUTEX_TIMEOUT = 30,
    MAX_LOG_SIZE = 200,
    MAX_WAVE_ENEMIES = 500,
    MAX_BOUNCE_ITERATIONS = 1000, -- seguridad anti-bucle infinito
})

local activeWaves = {}
local mutexJugador = {}
local transaccionesLog = {}

-- Registrar la tabla de mutex en GuardUtils para que el watchdog la limpie automáticamente
GuardUtils.registerMutexTable(mutexJugador, CONFIG.MUTEX_TIMEOUT)

local function agregarAlLog(entry)
    if type(entry) ~= "table" then return end
    local logEntry = {}
    for k, v in pairs(entry) do logEntry[k] = v end
    logEntry.timestamp = os.time()
    if #transaccionesLog >= CONFIG.MAX_LOG_SIZE then table.remove(transaccionesLog, 1) end
    table.insert(transaccionesLog, logEntry)
end

local function jugadorValido(player)
    return GuardUtils.jugadorValido(player)
end

Players.PlayerRemoving:Connect(function(player)
    local userId = player.UserId
    if activeWaves[userId] then
        activeWaves[userId].state = "cancelled"
        activeWaves[userId] = nil
    end
    GuardUtils.releaseMutex(mutexJugador, userId)
end)

function WaveManager.StartWave(player)
    if not jugadorValido(player) then return false end
    local userId = player.UserId

    if activeWaves[userId] then
        agregarAlLog({ level = "Info", message = "Oleada ya activa", userId = userId })
        return false
    end

    if not GuardUtils.acquireMutex(mutexJugador, userId) then
        agregarAlLog({ level = "Warning", message = "Mutex ocupado", userId = userId })
        return false
    end

    local waveCompleted = false
    local success, err = pcall(function()
        local currentWave = 1
        currentWave = GuardUtils.sanitizeNumber(currentWave, 1, CONFIG.MAX_WAVES) or 1

        if currentWave > CONFIG.MAX_WAVES then error("MAX_WAVES_REACHED") end

        local numEnemies = math.floor(CONFIG.ENEMIES_PER_WAVE_BASE * (CONFIG.ENEMIES_PER_WAVE_MULTIPLIER ^ (currentWave - 1)))
        numEnemies = math.clamp(numEnemies, 1, CONFIG.MAX_WAVE_ENEMIES)

        activeWaves[userId] = {
            currentWave = currentWave,
            enemiesRemaining = numEnemies,
            state = "pre_wave",
            player = player,
            startTime = 0,
        }

        agregarAlLog({ level = "Info", message = "Pre-wave iniciada", userId = userId, wave = currentWave })
        task.wait(CONFIG.PRE_WAVE_PAUSE)

        if not jugadorValido(player) then error("PLAYER_LEFT") end

        local waveData = activeWaves[userId]
        waveData.state = "active"
        waveData.startTime = os.clock()
        agregarAlLog({ level = "Info", message = "Oleada activa", userId = userId, wave = currentWave, enemies = numEnemies })

        local waveWon = false
        local iterations = 0
        while waveData.state == "active" do
            if not jugadorValido(player) then waveData.state = "cancelled"; error("PLAYER_LEFT") end
            local elapsed = os.clock() - waveData.startTime
            if elapsed >= CONFIG.DEFAULT_WAVE_DURATION then break end
            if waveData.enemiesRemaining <= 0 then waveWon = true; break end
            task.wait(0.5)
            iterations += 1
            if iterations > CONFIG.MAX_BOUNCE_ITERATIONS then error("LOOP_PROTECTION") end
        end

        if not jugadorValido(player) then error("PLAYER_LEFT") end

        waveData.state = "post_wave"
        if waveWon then
            agregarAlLog({ level = "Success", message = "Oleada completada", userId = userId, wave = currentWave })
        else
            agregarAlLog({ level = "Info", message = "Oleada fallida", userId = userId, wave = currentWave })
        end
        task.wait(CONFIG.POST_WAVE_PAUSE)
        waveCompleted = waveWon
    end)

    GuardUtils.releaseMutex(mutexJugador, userId)
    activeWaves[userId] = nil

    if not success then
        agregarAlLog({ level = "Error", message = "Error en oleada", userId = userId, error = tostring(err) })
        return false
    end
    return waveCompleted
end

function WaveManager.GetWaveState(player)
    if not jugadorValido(player) then return nil end
    local waveData = activeWaves[player.UserId]
    if not waveData then return nil end
    local success, stateInfo = pcall(function()
        return {
            currentWave = waveData.currentWave,
            state = waveData.state,
            enemiesRemaining = waveData.enemiesRemaining,
        }
    end)
    if not success then return {} end
    return stateInfo
end

function WaveManager.OnEnemyKilled(enemyModel, player)
    if not jugadorValido(player) then return end
    if not enemyModel or not enemyModel.Parent then return end
    local userId = player.UserId
    local waveData = activeWaves[userId]
    if not waveData or waveData.state ~= "active" then return end
    waveData.enemiesRemaining = math.max(0, waveData.enemiesRemaining - 1)
    agregarAlLog({ level = "Debug", message = "Enemigo eliminado", userId = userId, remaining = waveData.enemiesRemaining })
end

function WaveManager.PauseWave(player)
    if not jugadorValido(player) then return false end
    local waveData = activeWaves[player.UserId]
    if not waveData or waveData.state ~= "active" then return false end
    waveData.state = "paused"
    agregarAlLog({ level = "Info", message = "Oleada pausada", userId = player.UserId })
    return true
end

function WaveManager.ResumeWave(player)
    if not jugadorValido(player) then return false end
    local waveData = activeWaves[player.UserId]
    if not waveData or waveData.state ~= "paused" then return false end
    waveData.state = "active"
    agregarAlLog({ level = "Info", message = "Oleada reanudada", userId = player.UserId })
    return true
end

function WaveManager.GetLog()
    local copy = {}
    for i, entry in ipairs(transaccionesLog) do
        if type(entry) == "table" then
            local entryCopy = {}
            for k, v in pairs(entry) do entryCopy[k] = v end
            table.insert(copy, entryCopy)
        else
            table.insert(copy, entry)
        end
    end
    return copy
end

return WaveManager
