-- PhoneUI.lua
-- Renders WhatsApp-style notification popups and notification inbox

PhoneUI = {}
PhoneUI.isInboxOpen = false
PhoneUI.slideInTime = 400 -- ms animation
PhoneUI.animTimer = {}

-- Colors (RGBA 0-1)
PhoneUI.COLORS = {
    bg = {0.10, 0.10, 0.10, 0.92},
    accent = {0.20, 0.78, 0.35, 1.0},  -- WhatsApp green
    text = {1.0, 1.0, 1.0, 1.0},
    subtext = {0.75, 0.75, 0.75, 1.0},
    unread_dot = {0.20, 0.78, 0.35, 1.0},
    shadow = {0.0, 0.0, 0.0, 0.5}
}

-- Notification popup dimensions (normalized screen coords)
PhoneUI.POPUP = {
    width = 0.28,
    height = 0.07,
    marginRight = 0.01,
    marginTop = 0.02,
    gap = 0.01,
    cornerRadius = 0.008
}

function PhoneUI:init()
    self.isInboxOpen = false
    self.animTimer = {}
    -- Register key binding for inbox toggle (I key)
    -- Note: proper key binding registration via LS25 InputAction XML recommended
    print("[FarmNotify] PhoneUI initialized.")
end

function PhoneUI:update(dt)
    NotificationManager:tickVisible(dt)

    -- Animate slide-in timers
    local visible = NotificationManager:getVisible()
    for i, notif in ipairs(visible) do
        if self.animTimer[notif.id] == nil then
            self.animTimer[notif.id] = 0
        end
        if self.animTimer[notif.id] < self.slideInTime then
            self.animTimer[notif.id] = self.animTimer[notif.id] + dt
        end
    end
end

function PhoneUI:draw()
    if not g_gui:getIsGuiVisible() then
        self:drawPopups()
    end
    if self.isInboxOpen then
        self:drawInbox()
    end
end

function PhoneUI:drawPopups()
    local visible = NotificationManager:getVisible()
    local p = self.POPUP

    for i, notif in ipairs(visible) do
        local slideProgress = math.min(1.0, (self.animTimer[notif.id] or 0) / self.slideInTime)
        local ease = 1 - (1 - slideProgress) ^ 3 -- ease-out cubic

        local x = 1.0 - p.width - p.marginRight
        local y = 1.0 - p.marginTop - (i - 1) * (p.height + p.gap) - p.height

        -- Slide from right
        local offsetX = (1 - ease) * (p.width + p.marginRight)
        x = x + offsetX

        self:drawNotificationCard(x, y, p.width, p.height, notif)
    end
end

function PhoneUI:drawNotificationCard(x, y, w, h, notif)
    local c = self.COLORS

    -- Shadow
    self:setColor(c.shadow)
    self:drawRect(x + 0.002, y - 0.002, w, h)

    -- Background
    self:setColor(c.bg)
    self:drawRect(x, y, w, h)

    -- Left accent bar (WhatsApp style)
    self:setColor(c.accent)
    self:drawRect(x, y, 0.004, h)

    -- Title
    self:setColor(c.text)
    self:drawText(x + 0.012, y + h - 0.022, 0.013, notif.title)

    -- Message
    self:setColor(c.subtext)
    self:drawText(x + 0.012, y + 0.010, 0.011, notif.message)
end

function PhoneUI:drawInbox()
    -- Full notification inbox overlay — to be extended
    local c = self.COLORS
    self:setColor({0.08, 0.08, 0.08, 0.96})
    self:drawRect(0.55, 0.1, 0.40, 0.80)

    self:setColor(c.accent)
    self:drawRect(0.55, 0.86, 0.40, 0.04)
    self:setColor(c.text)
    self:drawText(0.565, 0.875, 0.016, "FarmNotify — Benachrichtigungen")

    local all = NotificationManager:getAll()
    for i, notif in ipairs(all) do
        local y = 0.84 - (i - 1) * 0.065
        if y < 0.12 then break end
        self:setColor(notif.isNew and c.bg or {0.06, 0.06, 0.06, 0.9})
        self:drawRect(0.56, y - 0.055, 0.37, 0.058)
        self:setColor(c.text)
        self:drawText(0.572, y - 0.012, 0.013, notif.title)
        self:setColor(c.subtext)
        self:drawText(0.572, y - 0.032, 0.011, notif.message)
        if notif.isNew then
            self:setColor(c.unread_dot)
            self:drawRect(0.563, y - 0.028, 0.007, 0.007)
        end
    end
end

function PhoneUI:toggleInbox()
    self.isInboxOpen = not self.isInboxOpen
    -- Mark all visible as read when opening
    if self.isInboxOpen then
        for _, n in ipairs(NotificationManager:getVisible()) do
            NotificationManager:markRead(n.id)
        end
    end
end

-- Helpers wrapping LS25 render API
function PhoneUI:setColor(rgba)
    setTextColor(rgba[1], rgba[2], rgba[3], rgba[4])
end

function PhoneUI:drawRect(x, y, w, h)
    drawFilledRect(x, y, w, h)
end

function PhoneUI:drawText(x, y, size, text)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(x, y, size, tostring(text))
end
