-- FarmNotify.lua
-- Main entry point — wires all subsystems together

FarmNotify = {}
FarmNotify.MOD_NAME   = g_currentModName
FarmNotify.VERSION    = "1.0.0"
FarmNotify.modDir     = g_currentModDirectory

-- Subsystem references (set in :init)
FarmNotify.settings   = nil
FarmNotify.animator   = nil

FarmNotify.SAVE_KEY   = "FarmNotify"

-- ─── Lifecycle ─────────────────────────────────────────────────────────────

function FarmNotify:init()
    print(string.format("[FarmNotify] v%s starting — %s", self.VERSION, self.modDir))
    math.randomseed(getTime())

    -- Settings (phone model, volume, etc.)
    FarmNotifySettings:init()
    self.settings = FarmNotifySettings

    -- Core subsystems
    NotificationManager:init()
    EventDetector:init()
    SoundController:init(self.modDir, self.settings:get("volume"))
    MapNavigator:init()
    PhoneUI:init(self.modDir)

    -- Phone model (loads texture overlay)
    PhoneModel:init(self.modDir, self.settings:get("phoneModel"))

    -- Animator
    PhoneAnimator:init(self.settings:get("popupDuration"))
    self.animator = PhoneAnimator

    -- Wire animator callbacks
    self.animator.onSlideInComplete = function()
        -- Notification is now fully visible — play sound once
    end
    self.animator.onSlideOutComplete = function()
        -- Check if next notification is waiting
        FarmNotify:_tryShowNextNotification()
    end

    print("[FarmNotify] All systems initialized.")
end

function FarmNotify:update(dt)
    if g_currentMission == nil or not g_currentMission.missionDynamicInfo.isStarted then return end

    EventDetector:update(dt)
    MapNavigator:update(dt)
    PhoneAnimator:update(dt)

    -- Check for new notifications to show
    if self.animator.state == PhoneAnimator.STATE.HIDDEN then
        self:_tryShowNextNotification()
    end

    -- Input handling (keyboard)
    self:_handleInput()
end

function FarmNotify:draw()
    if g_currentMission == nil then return end
    if g_gui:getIsGuiVisible() and not PhoneAnimator:isInboxOpen() then return end
    PhoneUI:draw()
end

-- ─── Notification Display ──────────────────────────────────────────────────

function FarmNotify:_tryShowNextNotification()
    local notif = NotificationManager:peekNext()
    if notif == nil then return end

    NotificationManager:markDisplayed(notif.id)
    SoundController:play(notif.type)
    PhoneAnimator:showNotification(notif)
end

-- ─── Input ─────────────────────────────────────────────────────────────────

FarmNotify._nWasDown   = false
FarmNotify._mouseWasDown = false

function FarmNotify:_handleInput()
    -- [N] toggle inbox
    local nDown = Input.isKeyPressed(Input.KEY_n)
    if nDown and not self._nWasDown then
        self.animator:toggleInbox()
        if self.animator:isInboxOpen() then
            NotificationManager:markAllRead()
        end
    end
    self._nWasDown = nDown

    -- Escape closes inbox
    if self.animator:isInboxOpen() then
        if Input.isKeyPressed(Input.KEY_escape) then
            self.animator:closeInbox()
        end
    end

    -- Mouse scroll in inbox
    -- LS25: mouse wheel handled via InputAction
    local scrollUp   = Input.isKeyPressed(Input.KEY_pageUp)
    local scrollDown = Input.isKeyPressed(Input.KEY_pageDown)
    if scrollUp   then PhoneUI:handleScroll(-1) end
    if scrollDown then PhoneUI:handleScroll( 1) end

    -- Mouse click on phone
    if Input.isMouseButtonPressed(Input.MOUSE_BUTTON_LEFT) then
        if not self._mouseWasDown then
            local mx, my = getNormalizedScreenValues(g_inputBinding:getMousePosition())
            PhoneUI:handleClick(mx, my)
        end
        self._mouseWasDown = true
    else
        self._mouseWasDown = false
    end
end

-- ─── Save / Load ───────────────────────────────────────────────────────────

function FarmNotify:saveToXML(xmlFile, key)
    setXMLString(xmlFile, key .. "#version", self.VERSION)
    NotificationManager:saveToXML(xmlFile, key .. ".notifications")
end

function FarmNotify:loadFromXML(xmlFile, key)
    NotificationManager:loadFromXML(xmlFile, key .. ".notifications")
end

-- ─── Settings API (called from mod options UI) ────────────────────────────

function FarmNotify:setPhoneModel(modelId)
    PhoneModel:setModel(modelId)
    self.settings:set("phoneModel", modelId)
end

function FarmNotify:setVolume(vol)
    SoundController:setVolume(vol)
    self.settings:set("volume", vol)
end

-- ─── Cleanup ───────────────────────────────────────────────────────────────

function FarmNotify:delete()
    SoundController:delete()
    PhoneModel:delete()
    print("[FarmNotify] Shutdown complete.")
end

-- ─── Game Event Hooks ──────────────────────────────────────────────────────

local modEventListener = {}

function modEventListener:loadedMission(mission, wasSuccessful)
    if wasSuccessful then
        FarmNotify:init()
    end
end

function modEventListener:update(dt)
    FarmNotify:update(dt)
end

function modEventListener:draw()
    FarmNotify:draw()
end

function modEventListener:saveSavegame()
    if g_currentMission and g_currentMission.missionInfo then
        local saveDir = g_currentMission.missionInfo.savegameDirectory
        if saveDir then
            local xmlFile = createXMLFile("FarmNotifySave", saveDir .. "farmnotify.xml", "FarmNotify")
            if xmlFile ~= nil then
                FarmNotify:saveToXML(xmlFile, "FarmNotify")
                saveXMLFile(xmlFile)
                deleteXMLFile(xmlFile)
            end
        end
    end
end

function modEventListener:loadedMissionInGameUI(mission, wasSuccessful)
    if wasSuccessful and g_currentMission then
        local saveDir = g_currentMission.missionInfo.savegameDirectory
        if saveDir then
            local xmlFile = loadXMLFile("FarmNotifySave", saveDir .. "farmnotify.xml")
            if xmlFile ~= nil then
                FarmNotify:loadFromXML(xmlFile, "FarmNotify")
                deleteXMLFile(xmlFile)
            end
        end
    end
end

function modEventListener:deleteSavegame(savegameIndex)
    -- Optional: cleanup saved notification file
end

addModEventListener(modEventListener)
