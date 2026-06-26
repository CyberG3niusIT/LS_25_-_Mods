-- NotificationManager.lua
-- Creates, queues, and manages lifecycle of notifications

NotificationManager = {}
NotificationManager.queue = {}
NotificationManager.MAX_VISIBLE = 3
NotificationManager.DISPLAY_DURATION = 8000 -- ms

-- Notification types
NotificationManager.TYPE = {
    HARVEST_READY = "harvest_ready",
    SILO_FULL = "silo_full",
    MACHINE_ALERT = "machine_alert",
    WEATHER_WARNING = "weather_warning"
}

-- Icons per type (texture keys, to be loaded in PhoneUI)
NotificationManager.ICONS = {
    harvest_ready = "harvest",
    silo_full = "silo",
    machine_alert = "machine",
    weather_warning = "weather"
}

function NotificationManager:init()
    self.queue = {}
    print("[FarmNotify] NotificationManager initialized.")
end

function NotificationManager:push(notifType, title, message, fieldId)
    local notif = {
        id = self:_generateId(),
        type = notifType,
        title = title,
        message = message,
        fieldId = fieldId or nil,
        timestamp = g_currentMission and g_currentMission.environment and
                    g_currentMission.environment.currentMonotonicDay or 0,
        timeRemaining = self.DISPLAY_DURATION,
        isNew = true
    }
    table.insert(self.queue, 1, notif) -- newest first
    -- Cap queue length
    if #self.queue > 20 then
        table.remove(self.queue, #self.queue)
    end
    print(string.format("[FarmNotify] Notification: [%s] %s — %s", notifType, title, message))
    return notif
end

function NotificationManager:getVisible()
    local visible = {}
    for _, n in ipairs(self.queue) do
        if n.isNew then
            table.insert(visible, n)
            if #visible >= self.MAX_VISIBLE then break end
        end
    end
    return visible
end

function NotificationManager:getAll()
    return self.queue
end

function NotificationManager:markRead(id)
    for _, n in ipairs(self.queue) do
        if n.id == id then
            n.isNew = false
            break
        end
    end
end

function NotificationManager:tickVisible(dt)
    for _, n in ipairs(self.queue) do
        if n.isNew and n.timeRemaining > 0 then
            n.timeRemaining = n.timeRemaining - dt
            if n.timeRemaining <= 0 then
                n.isNew = false
            end
        end
    end
end

function NotificationManager:_generateId()
    return tostring(math.floor((g_time or 0) * 1000) + math.random(1000))
end
