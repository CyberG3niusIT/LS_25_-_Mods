-- FarmNotify.lua
-- Entry point for the FarmNotify mod

FarmNotify = {}
FarmNotify.MOD_NAME = g_currentModName
FarmNotify.VERSION = "1.0.0"
FarmNotify.modDirectory = g_currentModDirectory

function FarmNotify:init()
    print("[FarmNotify] v" .. self.VERSION .. " initializing...")
    NotificationManager:init()
    FieldMonitor:init()
    PhoneUI:init()
    print("[FarmNotify] Ready.")
end

function FarmNotify:update(dt)
    FieldMonitor:update(dt)
    PhoneUI:update(dt)
end

function FarmNotify:draw()
    PhoneUI:draw()
end

local function onGameLoaded()
    FarmNotify:init()
end

local function onUpdate(dt)
    FarmNotify:update(dt)
end

local function onDraw()
    FarmNotify:draw()
end

addModEventListener({
    loadedMission = onGameLoaded,
    update = onUpdate,
    draw = onDraw
})
