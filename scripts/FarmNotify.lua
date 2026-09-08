-- FarmNotify.lua
-- Main entry point — wires all subsystems together

FarmNotify = {}
FarmNotify.MOD_NAME   = g_currentModName
FarmNotify.VERSION    = "1.1.1"
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
    self.headless = g_dedicatedServer ~= nil and g_dedicatedServer ~= false
    self.historyLoaded = false
    self.saveGeneration = 0
    self.lastSavePath = nil
    self.started = false

    NotificationManager:init()

    -- A dedicated server does not need local notification detection or UI.
    if self.headless then
        self.initialized = true
        print("[FarmNotify] Dedicated Server detected — running in headless compatibility mode.")
        return
    end

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

    -- Wire animator callbacks
    self.animator.onSlideInComplete = function()
        -- Notification is now fully visible — play sound once
    end
    self.animator.onSlideOutComplete = function()
        -- Check if next notification is waiting
        FarmNotify:_tryShowNextNotification()
    end

    self.initialized = true
    print("[FarmNotify] All systems initialized.")
end

function FarmNotify:isGameStarted()
    local mission = g_currentMission
    if mission == nil then return false end
    if mission.getIsMissionStarted ~= nil then return mission:getIsMissionStarted() end
    if mission.isMissionStarted ~= nil then return mission.isMissionStarted end
    return mission.isRunning == true
end

function FarmNotify:isGuiVisible()
    return g_gui ~= nil and g_gui:getIsGuiVisible()
end

function FarmNotify:update(dt)
    if not self.initialized or self.headless then return end
    if not self:isGameStarted() then return end
    if not self.started then
        self.started = true
        self:loadHistory()
        self:installSaveHook()
        self:registerInputActions()
    end
    dt = math.max(0, tonumber(dt) or 0)
    local previousFarm = NotificationManager.farmId
    EventDetector:syncFarm()
    if previousFarm ~= NotificationManager.farmId then
        PhoneAnimator:init(self.settings:get("popupDuration"))
        self:_setInboxMouseCursor(false)
    end
    self:updateInputActions()

    EventDetector:update(dt)
    MapNavigator:update(dt)
    if not self:isGuiVisible() then PhoneAnimator:update(dt) end

    -- Check for new notifications to show
    if self.animator ~= nil and self.animator.state == PhoneAnimator.STATE.HIDDEN then
        self:_tryShowNextNotification()
    end
end

function FarmNotify:draw()
    if not self.initialized or self.headless or g_currentMission == nil then return end
    if not self.started or self:isGuiVisible() then return end
    PhoneUI:draw()
end

-- ─── Notification Display ──────────────────────────────────────────────────

function FarmNotify:_tryShowNextNotification()
    if self.headless or self.settings == nil or self:isGuiVisible() then return end
    if not self.settings:get("showPopups") then
        NotificationManager:clearPendingPopups()
        return
    end
    local notif = NotificationManager:peekNext()
    if notif == nil then return end

    if PhoneAnimator:showNotification(notif) then
        NotificationManager:markDisplayed(notif.id)
        SoundController:play(notif.type)
    end
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
    self:updateInputActions()
end

function FarmNotify:updateInputActions()
    if g_inputBinding == nil or g_inputBinding.setActionEventActive == nil then return end
    local available = self.started and not self:isGuiVisible()
    for i, eventId in ipairs(self.actionEventIds) do
        local active = available and (i == 1 or (i == 2 and self.animator:isVisible())
            or (i > 2 and self.animator:isInboxInteractive()))
        g_inputBinding:setActionEventActive(eventId, active)
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
        if not self._mouseCursorOwned then
            self._previousCursorVisible = g_inputBinding.getShowMouseCursor ~= nil
                and g_inputBinding:getShowMouseCursor() or false
        end
        g_inputBinding:setShowMouseCursor(true)
        self._mouseCursorOwned = true
    elseif self._mouseCursorOwned then
        if not self:isGuiVisible() then
            g_inputBinding:setShowMouseCursor(self._previousCursorVisible == true)
        end
        self._mouseCursorOwned = false
    end
end

function FarmNotify:onToggleInbox()
    if self.animator == nil or self:isGuiVisible() then return end
    self.animator:toggleInbox()
    local isOpen = self.animator:isInboxOpen()
    self:_setInboxMouseCursor(isOpen)
end

function FarmNotify:onDismiss()
    if self:isGuiVisible() then return end
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
    if eventUsed or self.headless or self:isGuiVisible() or self.animator == nil or not self.animator:isVisible() then
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

-- Two alternating snapshots avoid deleting the last known-good history.
-- No os.rename/remove dependency in the GIANTS mod sandbox.
function FarmNotify:getSavePaths()
    local info = g_currentMission and g_currentMission.missionInfo
    local directory = info and info.savegameDirectory
    if directory == nil then return nil end
    return {directory .. "/farmnotify.xml", directory .. "/farmnotify.backup.xml"}
end

function FarmNotify:loadHistory()
    local paths = self:getSavePaths()
    self.historyLoaded = true
    if paths == nil then return end
    local best, bestGeneration, bestPath = nil, -1, nil
    for _, path in ipairs(paths) do
        local xml = fileExists(path) and loadXMLFile("FarmNotifyHistory", path) or nil
        if xml ~= nil and xml ~= 0 then
            local generation = getXMLInt(xml, "FarmNotify#generation")
            local complete = getXMLBool(xml, "FarmNotify#complete")
            local count = getXMLInt(xml, "FarmNotify.notifications#count")
            local valid = (generation ~= nil and complete == true) or
                (generation == nil and count ~= nil and getXMLString(xml, "FarmNotify#version") ~= nil)
            if valid and (generation or 0) > bestGeneration then
                if best ~= nil then delete(best) end
                best, bestGeneration, bestPath = xml, generation or 0, path
            else
                delete(xml)
            end
        end
    end
    if best ~= nil then
        self:loadFromXML(best, "FarmNotify")
        delete(best)
        self.saveGeneration, self.lastSavePath = bestGeneration, bestPath
    end
end

function FarmNotify:saveHistory()
    if not self.initialized or self.headless or not self.historyLoaded then return false end
    local paths = self:getSavePaths()
    if paths == nil then return false end
    local target = self.lastSavePath == paths[1] and paths[2] or paths[1]
    local xml = createXMLFile("FarmNotifyHistory", target, "FarmNotify")
    if xml == nil or xml == 0 then return false end
    local generation = self.saveGeneration + 1
    local ok, result = pcall(function()
        self:saveToXML(xml, "FarmNotify")
        setXMLInt(xml, "FarmNotify#generation", generation)
        setXMLBool(xml, "FarmNotify#complete", true)
        return saveXMLFile(xml)
    end)
    delete(xml)
    if not ok or result ~= true then
        print("[FarmNotify] History write failed; previous snapshot preserved.")
        return false
    end
    self.saveGeneration, self.lastSavePath = generation, target
    return true
end

function FarmNotify:installSaveHook()
    local mission = g_currentMission
    if mission == nil or type(mission.saveSavegame) ~= "function" then
        print("[FarmNotify] No saveSavegame method; history will save on map exit.")
        return
    end
    self._saveMission = mission
    self._saveOwnMethod = rawget(mission, "saveSavegame")
    local original = mission.saveSavegame
    local function pack(...) return {n = select("#", ...), ...} end
    self._saveWrapper = function(instance, ...)
        local results = pack(original(instance, ...))
        if FarmNotify.initialized and FarmNotify._saveMission == instance then
            FarmNotify:saveHistory()
        end
        return unpack(results, 1, results.n)
    end
    mission.saveSavegame = self._saveWrapper
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
    self:saveHistory()
    if self._saveMission ~= nil and self._saveMission.saveSavegame == self._saveWrapper then
        self._saveMission.saveSavegame = self._saveOwnMethod
    end
    self._saveMission, self._saveWrapper, self._saveOwnMethod = nil, nil, nil
    self:removeInputActions()
    self:_setInboxMouseCursor(false)
    if not self.headless then
        EventDetector:delete()
        SoundController:delete()
        PhoneModel:delete()
        PhoneUI:delete()
    end
    self.animator = nil
    self.settings = nil
    self.headless = false
    self.initialized = false
    self.started = false
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

function modEventListener:deleteMap()
    FarmNotify:delete()
end

addModEventListener(modEventListener)
