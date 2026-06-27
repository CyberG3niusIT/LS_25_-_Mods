-- NotificationManager.lua
-- Notification queue, lifecycle management, and savegame persistence

NotificationManager = {}
NotificationManager.MAX_HISTORY  = 50
NotificationManager.MAX_VISIBLE  = 1  -- one notification shown at a time on phone

NotificationManager.TYPE = {
    HARVEST_READY   = "harvest_ready",
    HARVEST_OVERDUE = "harvest_overdue",
    WORKER_DONE     = "worker_done",
    WORKER_STUCK    = "worker_stuck",
    FUEL_LOW        = "fuel_low",
    SILO_FULL       = "silo_full",
    WEATHER_RAIN    = "weather_rain",
    WEATHER_STORM   = "weather_storm",
}

-- Cooldown per field+type to avoid spam (ms)
NotificationManager.COOLDOWNS = {
    harvest_ready   = 600000,  -- 10 min
    harvest_overdue = 300000,  -- 5 min
    worker_done     = 10000,
    worker_stuck    = 60000,
    fuel_low        = 120000,
    silo_full       = 300000,
    weather_rain    = 600000,
    weather_storm   = 300000,
}

NotificationManager.queue     = {}  -- unread / pending display
NotificationManager.history   = {}  -- all notifications
NotificationManager.cooldowns = {}  -- key: type..fieldId -> last triggered time (g_time ms)
NotificationManager._idSeq    = 0   -- L02: monotonic counter avoids ID collisions

function NotificationManager:init()
    self.queue     = {}
    self.history   = {}
    self.cooldowns = {}
end

-- Push new notification. Returns notification object or nil if cooldown active.
function NotificationManager:push(notifType, title, message, fieldId, vehicleId)
    local cooldownKey = notifType .. "_" .. tostring(fieldId or "") .. tostring(vehicleId or "")
    local now = g_time or 0
    local cooldown = self.COOLDOWNS[notifType] or 0

    if self.cooldowns[cooldownKey] and (now - self.cooldowns[cooldownKey]) < cooldown then
        return nil
    end

    self.cooldowns[cooldownKey] = now

    local notif = {
        id        = self:_newId(),
        type      = notifType,
        title     = title,
        message   = message,
        fieldId   = fieldId,
        vehicleId = vehicleId,
        time      = now,
        isRead    = false,
        displayed = false,
    }

    table.insert(self.queue, notif)
    table.insert(self.history, 1, notif)

    if #self.history > self.MAX_HISTORY then
        table.remove(self.history, #self.history)
    end

    print(string.format("[FarmNotify] [%s] %s — %s", notifType, title, message))
    return notif
end

-- Returns next notification that hasn't been displayed yet
function NotificationManager:peekNext()
    for _, n in ipairs(self.queue) do
        if not n.displayed then
            return n
        end
    end
    return nil
end

function NotificationManager:markDisplayed(id)
    for i, n in ipairs(self.queue) do
        if n.id == id then
            n.displayed = true
            return
        end
    end
end

function NotificationManager:markRead(id)
    for _, n in ipairs(self.history) do
        if n.id == id then
            n.isRead = true
            break
        end
    end
    for i, n in ipairs(self.queue) do
        if n.id == id then
            table.remove(self.queue, i)
            break
        end
    end
end

function NotificationManager:markAllRead()
    for _, n in ipairs(self.history) do
        n.isRead = true
    end
    self.queue = {}
end

function NotificationManager:getUnreadCount()
    local count = 0
    for _, n in ipairs(self.history) do
        if not n.isRead then count = count + 1 end
    end
    return count
end

function NotificationManager:getHistory()
    return self.history
end

-- Save notification history to savegame XML
function NotificationManager:saveToXML(xmlFile, baseKey)
    setXMLInt(xmlFile, baseKey .. "#count", math.min(#self.history, 20))
    for i, n in ipairs(self.history) do
        if i > 20 then break end
        local key = string.format("%s.notification(%d)", baseKey, i - 1)
        setXMLString(xmlFile, key .. "#id",        n.id)
        setXMLString(xmlFile, key .. "#type",      n.type)
        setXMLString(xmlFile, key .. "#title",     n.title)
        setXMLString(xmlFile, key .. "#message",   n.message)
        setXMLInt   (xmlFile, key .. "#fieldId",   n.fieldId or -1)
        setXMLFloat (xmlFile, key .. "#time",      n.time)
        setXMLBool  (xmlFile, key .. "#isRead",    n.isRead)
    end

    -- Persist active cooldowns so duplicate notifications don't fire on reload.
    -- g_time resets to ~0 on reload, so we only save the cooldown key (not the
    -- absolute timestamp). On load, we set the timestamp to `now`, meaning the
    -- player waits one full cooldown cycle before the event can re-trigger.
    local now = g_time or 0
    local activeCooldowns = {}
    for k, v in pairs(self.cooldowns) do
        local cooldownType = k:match("^([^_]+)")
        local maxCooldown  = self.COOLDOWNS[cooldownType] or 0
        if (now - v) < maxCooldown then
            table.insert(activeCooldowns, k)
        end
    end
    setXMLInt(xmlFile, baseKey .. ".cooldowns#count", #activeCooldowns)
    for i, k in ipairs(activeCooldowns) do
        setXMLString(xmlFile, string.format("%s.cooldown(%d)#key", baseKey, i - 1), k)
    end
end

function NotificationManager:loadFromXML(xmlFile, baseKey)
    self.history = {}
    self.queue   = {}
    local count = getXMLInt(xmlFile, baseKey .. "#count") or 0
    for i = 0, count - 1 do
        local key = string.format("%s.notification(%d)", baseKey, i)
        local n = {
            id        = getXMLString(xmlFile, key .. "#id")      or self:_newId(),
            type      = getXMLString(xmlFile, key .. "#type")    or "unknown",
            title     = getXMLString(xmlFile, key .. "#title")   or "",
            message   = getXMLString(xmlFile, key .. "#message") or "",
            fieldId   = getXMLInt   (xmlFile, key .. "#fieldId"),
            time      = getXMLFloat (xmlFile, key .. "#time")    or 0,
            isRead    = getXMLBool  (xmlFile, key .. "#isRead"),
            displayed = true,
        }
        if n.fieldId == -1 then n.fieldId = nil end

        -- P2-3: Discard stale fieldIds that no longer exist in the loaded map
        if n.fieldId ~= nil and g_fieldManager ~= nil then
            local found = g_fieldManager:getFieldByIndex(n.fieldId) ~= nil
            if not found and g_fieldManager.getFields then
                for _, f in pairs(g_fieldManager:getFields()) do
                    if f:getFieldId() == n.fieldId then found = true; break end
                end
            end
            if not found then n.fieldId = nil end
        end

        table.insert(self.history, n)
    end

    -- Restore active cooldowns. Timestamp set to `now` so the full cooldown
    -- period must pass before the same event can trigger again after reload.
    self.cooldowns = {}
    local now = g_time or 0
    local cooldownCount = getXMLInt(xmlFile, baseKey .. ".cooldowns#count") or 0
    for i = 0, cooldownCount - 1 do
        local k = getXMLString(xmlFile, string.format("%s.cooldown(%d)#key", baseKey, i))
        if k ~= nil then
            self.cooldowns[k] = now
        end
    end

    print(string.format("[FarmNotify] Loaded %d notifications, %d cooldowns from savegame.", count, cooldownCount))
end

function NotificationManager:_newId()
    self._idSeq = (self._idSeq or 0) + 1
    return string.format("%d_%d", math.floor(g_time or 0), self._idSeq)
end
