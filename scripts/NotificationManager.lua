-- NotificationManager.lua
-- Notification queue, lifecycle management, and savegame persistence

NotificationManager = {}
NotificationManager.MAX_HISTORY  = 50
NotificationManager.MAX_QUEUE = 50
NotificationManager.MAX_COOLDOWNS = 512
NotificationManager.MAX_FARMS = 254 -- network farm IDs; 0/255 are non-player farms
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
    self._lastCooldownCleanup = nil
    self.farms = {}
    self.farmId = nil
    self.queue     = {}
    self.history   = {}
    self.cooldowns = {}
    self._idSeq    = 0
end

-- The public arrays always belong to the selected farm. Spectators get an
-- empty view; data loaded before the first farm selection stays in farms.
function NotificationManager:setFarmId(farmId)
    if type(farmId) ~= "number" or farmId < 1 or farmId > self.MAX_FARMS
        or farmId ~= math.floor(farmId) then farmId = nil end
    if self.farmId == farmId then return end
    if self.farmId ~= nil then
        self.farms[self.farmId] = {queue=self.queue, history=self.history, cooldowns=self.cooldowns}
    end
    self.farmId = farmId
    local data = farmId and self.farms[farmId] or nil
    if data == nil then data = {queue={}, history={}, cooldowns={}} end
    self.queue, self.history, self.cooldowns = data.queue, data.history, data.cooldowns
    if farmId ~= nil then self.farms[farmId] = data end
    self:cleanupCooldowns()
end

function NotificationManager:cleanupCooldowns(force)
    local now = g_time or 0
    local last = self._lastCooldownCleanup
    if not force and last ~= nil and now >= last and now - last < 1000 then return end
    self._lastCooldownCleanup = now
    for _, data in pairs(self.farms or {}) do
        for key, expires in pairs(data.cooldowns) do
            if expires <= now then data.cooldowns[key] = nil end
        end
    end
end

-- Push new notification. Returns notification object or nil if cooldown active.
function NotificationManager:push(notifType, title, message, fieldId, vehicleId)
    if self.farmId == nil then return nil end
    self:cleanupCooldowns()
    local cooldownKey = notifType .. "|" .. tostring(fieldId or "") .. "|" .. tostring(vehicleId or "")
    local now = g_time or 0
    local cooldown = self.COOLDOWNS[notifType] or 0

    if self.cooldowns[cooldownKey] and now < self.cooldowns[cooldownKey] then
        return nil
    end
    if #self.queue >= self.MAX_QUEUE then return nil end
    local cooldownCount = 0
    for _ in pairs(self.cooldowns) do cooldownCount = cooldownCount + 1 end
    if cooldown > 0 and cooldownCount >= self.MAX_COOLDOWNS then return nil end
    if cooldown > 0 then self.cooldowns[cooldownKey] = now + cooldown end

    local notif = {
        id        = self:_newId(),
        type      = notifType,
        title     = title,
        message   = message,
        fieldId   = fieldId,
        vehicleId = vehicleId,
        farmId    = self.farmId,
        time      = now,
        isRead    = false,
        displayed = false,
    }

    table.insert(self.queue, notif)
    table.insert(self.history, 1, notif)

    if #self.history > self.MAX_HISTORY then
        local removed = table.remove(self.history, #self.history)
        for i, queued in ipairs(self.queue) do
            if queued == removed then table.remove(self.queue, i); break end
        end
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
            -- The queue contains pending popups only. Unread state lives in history.
            table.remove(self.queue, i)
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
    for i = #self.queue, 1, -1 do table.remove(self.queue, i) end
end

function NotificationManager:clearPendingPopups()
    for _, n in ipairs(self.queue) do
        n.displayed = true
    end
    for i = #self.queue, 1, -1 do table.remove(self.queue, i) end
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

-- Schema 2 stores separate farm histories and remaining cooldown durations.
-- Legacy unscoped data cannot safely be attributed to a multiplayer farm.
function NotificationManager:saveToXML(xmlFile, baseKey)
    self:cleanupCooldowns(true)
    setXMLInt(xmlFile, baseKey .. "#schema", 2)
    local farmIds = {}
    for id in pairs(self.farms) do table.insert(farmIds, id) end
    table.sort(farmIds)
    setXMLInt(xmlFile, baseKey .. "#farmCount", math.min(#farmIds, self.MAX_FARMS))
    for index, id in ipairs(farmIds) do
        if index > self.MAX_FARMS then break end
        local data = self.farms[id]
        local root = string.format("%s.farm(%d)", baseKey, index - 1)
        setXMLInt(xmlFile, root .. "#id", id)
        setXMLInt(xmlFile, root .. "#count", math.min(#data.history, self.MAX_HISTORY))
        for i, n in ipairs(data.history) do
            if i > self.MAX_HISTORY then break end
            local key = string.format("%s.notification(%d)", root, i - 1)
            for _, attr in ipairs({"type", "title", "message"}) do
                setXMLString(xmlFile, key .. "#" .. attr, n[attr])
            end
            setXMLString(xmlFile, key .. "#vehicleId", n.vehicleId and tostring(n.vehicleId) or "")
            setXMLInt(xmlFile, key .. "#fieldId", n.fieldId or -1)
            setXMLFloat(xmlFile, key .. "#time", n.time)
            setXMLBool(xmlFile, key .. "#isRead", n.isRead)
            setXMLBool(xmlFile, key .. "#displayed", n.displayed)
        end
        local keys = {}
        for key in pairs(data.cooldowns) do
            -- Session-only identities must never suppress a different object on reload.
            if not key:find("session:", 1, true) then table.insert(keys, key) end
        end
        table.sort(keys)
        setXMLInt(xmlFile, root .. "#cooldownCount", math.min(#keys, self.MAX_COOLDOWNS))
        for i, key in ipairs(keys) do
            if i > self.MAX_COOLDOWNS then break end
            local path = string.format("%s.cooldown(%d)", root, i - 1)
            setXMLString(xmlFile, path .. "#key", key)
            setXMLFloat(xmlFile, path .. "#remaining", data.cooldowns[key] - (g_time or 0))
        end
    end
end

function NotificationManager:loadFromXML(xmlFile, baseKey)
    self._lastCooldownCleanup = nil
    local selectedFarm = self.farmId
    self.farms = {}
    self.farmId = nil
    self.queue, self.history, self.cooldowns = {}, {}, {}
    if getXMLInt(xmlFile, baseKey .. "#schema") ~= 2 then
        -- Do not leak an old save's unscoped history into whichever farm joins first.
        self:setFarmId(selectedFarm)
        return
    end
    local count = math.max(0, math.min(getXMLInt(xmlFile, baseKey .. "#farmCount") or 0, self.MAX_FARMS))
    for index = 0, count - 1 do
        local root = string.format("%s.farm(%d)", baseKey, index)
        local farmId = getXMLInt(xmlFile, root .. "#id")
        if farmId ~= nil and farmId >= 1 and farmId <= self.MAX_FARMS then
            local data = {queue={}, history={}, cooldowns={}}
            self.farms[farmId] = data
            local length = math.max(0, math.min(getXMLInt(xmlFile, root .. "#count") or 0, self.MAX_HISTORY))
            for i = 0, length - 1 do
                local key = string.format("%s.notification(%d)", root, i)
                local notifType = getXMLString(xmlFile, key .. "#type")
                if self.COOLDOWNS[notifType] ~= nil then
                    local n = {
                        id=self:_newId(), farmId=farmId, type=notifType,
                        title=getXMLString(xmlFile, key .. "#title") or "",
                        message=getXMLString(xmlFile, key .. "#message") or "",
                        vehicleId=getXMLString(xmlFile, key .. "#vehicleId"),
                        fieldId=getXMLInt(xmlFile, key .. "#fieldId"),
                        time=getXMLFloat(xmlFile, key .. "#time") or 0,
                        isRead=getXMLBool(xmlFile, key .. "#isRead") == true,
                        displayed=getXMLBool(xmlFile, key .. "#displayed") ~= false
                    }
                    if n.fieldId == -1 then n.fieldId = nil end
                    -- Validate actual field IDs, never array indices. If the
                    -- manager is not populated yet, leave navigation to its
                    -- normal safe lookup when the notification is clicked.
                    local fields = g_fieldManager and g_fieldManager.fields
                    if n.fieldId ~= nil and fields ~= nil then
                        local found = false
                        for _, field in pairs(fields) do
                            local id = field.getId and field:getId() or field.fieldId
                            if id == n.fieldId then found = true; break end
                        end
                        if not found then n.fieldId = nil end
                    end
                    if n.vehicleId == "" then n.vehicleId = nil end
                    table.insert(data.history, n)
                    if not n.displayed and not n.isRead and #data.queue < self.MAX_QUEUE then
                        -- History is newest first; popup queue is oldest first.
                        table.insert(data.queue, 1, n)
                    end
                end
            end
            local lengthCooldowns = math.max(0, math.min(getXMLInt(xmlFile, root .. "#cooldownCount") or 0, self.MAX_COOLDOWNS))
            for i = 0, lengthCooldowns - 1 do
                local path = string.format("%s.cooldown(%d)", root, i)
                local key = getXMLString(xmlFile, path .. "#key")
                local remaining = getXMLFloat(xmlFile, path .. "#remaining") or 0
                local duration = key and self.COOLDOWNS[key:match("^([^|]+)")] or nil
                if duration ~= nil and remaining > 0 and not key:find("session:", 1, true) then
                    data.cooldowns[key] = (g_time or 0) + math.min(remaining, duration)
                end
            end
        end
    end
    self:setFarmId(selectedFarm)
end
function NotificationManager:_newId()
    self._idSeq = (self._idSeq or 0) + 1
    return string.format("%d_%d", math.floor(g_time or 0), self._idSeq)
end
