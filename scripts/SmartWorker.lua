-- SmartWorker.lua
-- Entry point and core controller for the SmartWorker mod

SmartWorker = {}
SmartWorker.MOD_NAME = g_currentModName
SmartWorker.VERSION = "1.0.0"

local modDirectory = g_currentModDirectory

function SmartWorker:init()
    print("[SmartWorker] v" .. self.VERSION .. " initializing...")
    FieldAnalyzer:init()
    WorkerScheduler:init()
    print("[SmartWorker] Ready.")
end

function SmartWorker:update(dt)
    WorkerScheduler:update(dt)
end

-- Hook into game load
local function onGameLoaded()
    SmartWorker:init()
end

local function onUpdate(dt)
    SmartWorker:update(dt)
end

addModEventListener({
    loadedMission = onGameLoaded,
    update = onUpdate
})
