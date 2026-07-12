-- FarmNotify.lua
-- Main entry point — wires all subsystems together

FarmNotify = {}
FarmNotify.MOD_NAME   = g_currentModName
FarmNotify.VERSION    = "1.1.0"
FarmNotify.modDir     = g_currentModDirectory

-- Subsystem references (set in :init)
FarmNotify.settings   = nil
FarmNotify.animator   = nil

FarmNotify.SAVE_KEY   = "FarmNotify"
FarmNotify.initialized = false
FarmNotify.headless    = false
FarmNotify.actionEventIds = {}
FarmNotify._mouseCursorOwned = false

-- ─── Lifecycle ─────────────────────────────────────────────────────────────

function FarmNotify:init()
    print(string.format("[FarmNotify] v%s starting — %s", self.VERSION, self.modDir))

    if self.initialized then
        print("[FarmNotify] Already initialized — cleaning up before reinit.")
        self:delete()
    end
    self.initialized = true
    self.headless = g_dedicatedServer == true

    NotificationManager:init()

    -- A dedicated server does not need local notification detection or UI.
    if self.headless then
        print("[FarmNotify] Dedicated Server detected — running in headless compatibility mode.")
        return
    end

    math.randomseed(getTime())

    -- Settings (phone model, volume, etc.)
    FarmNotifySettings:init()
    self.settings = FarmNotifySettings

    -- Core subsystems
    EventDetector:init()
    SoundController:init(self.modDir, self.settings:get("volume"))
    MapNavigator:init()
    PhoneUI:init(self.modDir)

    -- Phone model (loads texture overlay)
    PhoneModel:init(self.modDir, self.settings:get("phoneModel"))

    -- Animator
    PhoneAnimator:init(self.settings:get("popupDuration"))
    self.animator = PhoneAnimator
    self:registerInputActions()

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
    if not self.initialized or self.headless then return end
    if g_currentMission == nil then return end
    local dynamicInfo = g_currentMission.missionDynamicInfo
    if dynamicInfo ~= nil and not dynamicInfo.isStarted then return end

    EventDetector:update(dt)
    MapNavigator:update(dt)
    PhoneAnimator:update(dt)

    -- Check for new notifications to show
    if self.animator ~= nil and self.animator.state == PhoneAnimator.STATE.HIDDEN then
        self:_tryShowNextNotification()
    end
end

function FarmNotify:draw()
    if not self.initialized or self.headless or g_currentMission == nil then return end
    if g_gui ~= nil and g_gui:getIsGuiVisible() and not PhoneAnimator:isInboxOpen() then return end
    PhoneUI:draw()
end

-- ─── Notification Display ──────────────────────────────────────────────────

function FarmNotify:_tryShowNextNotification()
    if self.headless or self.settings == nil then return end
    if not self.settings:get("showPopups") then
        NotificationManager:clearPendingPopups()
        return
    end
    local notif = NotificationManager:peekNext()
    if notif == nil then return end

    NotificationManager:markDisplayed(notif.id)
    SoundController:play(notif.type)
    PhoneAnimator:showNotification(notif)
end

-- ─── Input ─────────────────────────────────────────────────────────────────

function FarmNotify:registerInputActions()
    self:removeInputActions()
    if g_inputBinding == nil then return end

    local actions = {
        { "FARMNOTIFY_TOGGLE_INBOX", self.onToggleInbox, "input_FARMNOTIFY_TOGGLE_INBOX" },
        { "FARMNOTIFY_DISMISS",      self.onDismiss,     "input_FARMNOTIFY_DISMISS" },
        { "FARMNOTIFY_SCROLL_UP",    self.onScrollUp,    "input_FARMNOTIFY_SCROLL_UP" },
        { "FARMNOTIFY_SCROLL_DOWN",  self.onScrollDown,  "input_FARMNOTIFY_SCROLL_DOWN" },
    }

    for _, action in ipairs(actions) do
        local _, eventId = g_inputBinding:registerActionEvent(
            action[1], self, action[2], false, true, false, true
        )
        if eventId ~= nil then
            table.insert(self.actionEventIds, eventId)
            if g_i18n ~= nil then
                g_inputBinding:setActionEventText(eventId, g_i18n:getText(action[3]))
            end
            if GS_PRIO_LOW ~= nil then
                g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_LOW)
            end
        end
    end
end

function FarmNotify:removeInputActions()
    if g_inputBinding ~= nil then
        for _, eventId in ipairs(self.actionEventIds or {}) do
            g_inputBinding:removeActionEvent(eventId)
        end
    end
    self.actionEventIds = {}
end

function FarmNotify:_setInboxMouseCursor(show)
    if g_inputBinding == nil or g_inputBinding.setShowMouseCursor == nil then return end
    if show then
        g_inputBinding:setShowMouseCursor(true)
        self._mouseCursorOwned = true
    elseif self._mouseCursorOwned then
        g_inputBinding:setShowMouseCursor(false)
        self._mouseCursorOwned = false
    end
end

function FarmNotify:onToggleInbox()
    if self.animator == nil then return end
    self.animator:toggleInbox()
    local isOpen = self.animator:isInboxOpen()
    self:_setInboxMouseCursor(isOpen)
end

function FarmNotify:onDismiss()
    if self.animator ~= nil and self.animator:isInboxOpen() then
        self.animator:closeInbox()
        self:_setInboxMouseCursor(false)
    elseif self.animator ~= nil then
        self.animator:slideOut()
    end
end

function FarmNotify:onScrollUp()
    if PhoneUI ~= nil then PhoneUI:handleScroll(-1) end
end

function FarmNotify:onScrollDown()
    if PhoneUI ~= nil then PhoneUI:handleScroll(1) end
end

function FarmNotify:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if eventUsed or self.headless or self.animator == nil or not self.animator:isVisible() then
        return eventUsed
    end
    if isDown and button == Input.MOUSE_BUTTON_LEFT and PhoneUI:handleClick(posX, posY) then
        return true
    end
    return eventUsed
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

function FarmNotify:setShowPopups(enabled)
    self.settings:set("showPopups", enabled == true)
    if not enabled then NotificationManager:clearPendingPopups() end
end

function FarmNotify:setPopupDuration(duration)
    self.settings:set("popupDuration", duration)
    if self.animator ~= nil then
        self.animator.DISPLAY_DURATION = self.settings:get("popupDuration")
    end
end

-- ─── Cleanup ───────────────────────────────────────────────────────────────

function FarmNotify:delete()
    if not self.initialized then return end
    self:removeInputActions()
    self:_setInboxMouseCursor(false)
    if not self.headless then
        SoundController:delete()
        PhoneModel:delete()
        PhoneUI:delete()
    end
    self.animator = nil
    self.settings = nil
    self.headless = false
    self.initialized = false
    print("[FarmNotify] Shutdown complete.")
end

-- ─── Game Event Hooks ──────────────────────────────────────────────────────

local modEventListener = {}

function modEventListener:loadMap()
    FarmNotify:init()
end

function modEventListener:update(dt)
    FarmNotify:update(dt)
end

function modEventListener:draw()
    FarmNotify:draw()
end

function modEventListener:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    return FarmNotify:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
end

function modEventListener:saveSavegame()
    if FarmNotify.initialized and not FarmNotify.headless and g_currentMission and g_currentMission.missionInfo then
        local saveDir = g_currentMission.missionInfo.savegameDirectory
        if saveDir then
            local finalPath = saveDir .. "/farmnotify.xml"
            local xmlFile = createXMLFile("FarmNotifySave", finalPath, "FarmNotify")
            if xmlFile ~= nil then
                FarmNotify:saveToXML(xmlFile, "FarmNotify")
                saveXMLFile(xmlFile)
                delete(xmlFile)
            end
        end
    end
end

function modEventListener:loadMapFinished()
    if FarmNotify.initialized and not FarmNotify.headless and g_currentMission then
        local saveDir = g_currentMission.missionInfo.savegameDirectory
        if saveDir then
            local path = saveDir .. "/farmnotify.xml"
            local xmlFile = fileExists(path) and loadXMLFile("FarmNotifySave", path) or nil
            if xmlFile ~= nil then
                FarmNotify:loadFromXML(xmlFile, "FarmNotify")
                delete(xmlFile)
            end
        end
    end
end

function modEventListener:deleteMap()
    FarmNotify:delete()
end

addModEventListener(modEventListener)
