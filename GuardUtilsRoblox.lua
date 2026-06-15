-- GuardUtils.lua | ModuleScript (ServerScriptService.ServerModules)
-- Responsabilidad única: Funciones de validación, sanitización, rate limiting, mutex y watchdog.

local GuardUtils = {}
local Players = game:GetService("Players")

local CONFIG = table.freeze({
    MAX_STATEDATA_KEYS = 100,
    MAX_REQUESTS_PER_SECOND = 10,
    MAX_SAFE_INTEGER = 2 ^ 50,
    WATCHDOG_INTERVAL = 60,
    MAX_KEY_AGE_SECONDS = 120,
    DEFAULT_MUTEX_TIMEOUT = 30,
})

-- Estado interno
local rateLimitTimestamps = {}
local mutexTables = {}       -- [tableId] = { mutex = { [key] = timestamp }, timeout = number }

-- ================================================================
-- VALIDACIÓN DE TIPOS
-- ================================================================
function GuardUtils.isValidData(value, maxKeys)
    if value == nil then return false end
    local t = type(value)
    if t == "function" or t == "userdata" or t == "thread" then return false end
    if typeof(value) == "Instance" then return false end
    if t == "number" and value ~= value then return false end
    if t == "table" then
        local count = 0
        local limit = maxKeys or CONFIG.MAX_STATEDATA_KEYS
        for k, v in pairs(value) do
            count += 1
            if count > limit then return false end
            if not GuardUtils.isValidData(k, maxKeys) or not GuardUtils.isValidData(v, maxKeys) then return false end
        end
    end
    return true
end

function GuardUtils.jugadorValido(player)
    if not player or not player:IsA("Player") or not player.Parent then return false end
    return player:IsDescendantOf(Players)
end

function GuardUtils.datosCargados(player, isLoadedFunc)
    if type(isLoadedFunc) == "function" then return isLoadedFunc(player) end
    return false
end

-- ================================================================
-- SANITIZACIÓN
-- ================================================================
function GuardUtils.sanitizeString(value, maxLength)
    if type(value) ~= "string" then return nil end
    local cleaned = value:gsub("%z", "")
    local limit = maxLength or 1000
    if #cleaned > limit then return nil end
    cleaned = cleaned:match("^%s*(.-)%s*$")
    if cleaned == "" then return nil end
    return cleaned
end

function GuardUtils.sanitizeNumber(value, min, max)
    if type(value) ~= "number" then return nil end
    if value ~= value then return nil end
    if value == math.huge or value == -math.huge then return nil end
    local minVal = min or 0
    local maxVal = max or CONFIG.MAX_SAFE_INTEGER
    return math.clamp(math.floor(value), minVal, maxVal)
end

-- ================================================================
-- RATE LIMITING
-- ================================================================
function GuardUtils.isRateLimited(key, maxRequestsPerSecond)
    if type(key) ~= "string" then
        warn("[GuardUtils] isRateLimited recibió una clave no string (" .. typeof(key) .. "). Retornando false.")
        return false
    end
    if #key == 0 then
        warn("[GuardUtils] isRateLimited recibió una clave vacía. Retornando false.")
        return false
    end
    local now = os.clock()
    rateLimitTimestamps[key] = rateLimitTimestamps[key] or {}
    local ts = rateLimitTimestamps[key]
    local i = 1
    while ts[i] and (now - ts[i]) > 1.0 do table.remove(ts, i) end
    local limit = maxRequestsPerSecond or CONFIG.MAX_REQUESTS_PER_SECOND
    if #ts >= limit then return true end
    table.insert(ts, now)
    return false
end

function GuardUtils.cleanupRateLimit(key)
    if type(key) == "string" then rateLimitTimestamps[key] = nil end
end

-- Watchdog de rate limiting
task.spawn(function()
    while true do
        task.wait(CONFIG.WATCHDOG_INTERVAL)
        local now = os.clock()
        for key, timestamps in pairs(rateLimitTimestamps) do
            local i = 1
            while timestamps[i] and (now - timestamps[i]) > 1.0 do table.remove(timestamps, i) end
            if #timestamps == 0 then rateLimitTimestamps[key] = nil end
        end
    end
end)

-- ================================================================
-- MUTEX + WATCHDOG (NUEVO)
-- ================================================================

-- Registra una tabla de mutex para ser vigilada por el watchdog.
-- @param mutexTable La tabla que contendrá los mutex (ej: mutexJugador).
-- @param timeout Segundos antes de liberar un mutex colgado.
-- @return tableId Identificador para usar con acquireMutex y releaseMutex.
function GuardUtils.registerMutexTable(mutexTable, timeout)
    local tableId = tostring(mutexTable) .. "_" .. os.time()
    mutexTables[tableId] = {
        mutex = mutexTable,
        timeout = timeout or CONFIG.DEFAULT_MUTEX_TIMEOUT,
    }
    return tableId
end

-- Intenta adquirir un mutex para una clave. Retorna true si se adquirió, false si ya estaba tomado.
function GuardUtils.acquireMutex(mutexTable, key)
    if mutexTable[key] then return false end
    mutexTable[key] = os.time()
    return true
end

-- Libera un mutex para una clave.
function GuardUtils.releaseMutex(mutexTable, key)
    mutexTable[key] = nil
end

-- Watchdog centralizado para todas las tablas de mutex registradas.
task.spawn(function()
    while true do
        task.wait(CONFIG.WATCHDOG_INTERVAL)
        local ahora = os.time()
        for tableId, data in pairs(mutexTables) do
            local mutexTable = data.mutex
            local timeout = data.timeout
            for key, lockedAt in pairs(mutexTable) do
                if (ahora - lockedAt) > timeout then
                    warn("[GuardUtils] Watchdog liberando mutex para tabla " .. tableId .. ", clave: " .. tostring(key))
                    mutexTable[key] = nil
                end
            end
        end
    end
end)

-- ================================================================
-- UTILIDADES ADICIONALES
-- ================================================================
function GuardUtils.deepCopy(original)
    if type(original) ~= "table" then return original end
    local seen = {}
    local function _deepCopy(orig)
        if type(orig) ~= "table" then return orig end
        if seen[orig] then return { __cyclic = true } end
        seen[orig] = true
        local copy = {}
        for k, v in pairs(orig) do copy[_deepCopy(k)] = _deepCopy(v) end
        return copy
    end
    return _deepCopy(original)
end

function GuardUtils.isDataStoreSafe(value)
    if type(value) ~= "table" then return true end
    for k, v in pairs(value) do
        if type(v) == "table" and v.__cyclic then return false end
        if not GuardUtils.isDataStoreSafe(k) or not GuardUtils.isDataStoreSafe(v) then return false end
    end
    return true
end

local idCounter = 0
function GuardUtils.generarId(prefijo)
    idCounter = (idCounter % 100000) + 1
    return (prefijo or "id") .. "_" .. os.time() .. "_" .. idCounter
end

return GuardUtils
