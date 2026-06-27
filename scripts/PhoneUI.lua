-- PhoneUI.lua
-- Full phone UI renderer: notification cards on phone screen + inbox view
-- Handles click detection, scroll, notification tap → navigate

PhoneUI = {}

-- Colors (r,g,b,a 0-1)
PhoneUI.C = {
    screenBg     = {0.00,  0.00,  0.00,  0.0 },   -- transparent — wallpaper shows through
    headerBg     = {0.04,  0.04,  0.06,  0.82},
    accent       = {0.20,  0.78,  0.35,  1.0 },  -- WhatsApp/message green
    accentOrange = {0.95,  0.60,  0.10,  1.0 },  -- warnings
    accentRed    = {0.90,  0.20,  0.20,  1.0 },  -- urgent
    accentBlue   = {0.20,  0.55,  0.95,  1.0 },  -- info
    accentGrey   = {0.45,  0.45,  0.50,  1.0 },  -- read
    white        = {1.0,   1.0,   1.0,   1.0 },
    subtext      = {0.72,  0.72,  0.75,  1.0 },
    separator    = {0.18,  0.18,  0.22,  1.0 },
    unreadDot    = {0.20,  0.78,  0.35,  1.0 },
    timeText     = {0.55,  0.55,  0.60,  1.0 },
    pressedBg    = {0.15,  0.15,  0.20,  0.9 },
    notifBg      = {0.08,  0.08,  0.12,  0.88},
}

-- Icon characters (rendered as text — for proper icons, use DDS overlay)
PhoneUI.ICONS = {
    harvest_ready   = "🌾",
    harvest_overdue = "⚠️",
    worker_done     = "✅",
    worker_stuck    = "🚜",
    fuel_low        = "⛽",
    silo_full       = "🏗️",
    weather_rain    = "🌧️",
    weather_storm   = "⛈️",
}

-- Accent color per notification type
PhoneUI.NOTIF_COLOR = {
    harvest_ready   = {0.20, 0.78, 0.35, 1.0},
    harvest_overdue = {0.95, 0.60, 0.10, 1.0},
    worker_done     = {0.20, 0.78, 0.35, 1.0},
    worker_stuck    = {0.95, 0.40, 0.10, 1.0},
    fuel_low        = {0.90, 0.80, 0.10, 1.0},
    silo_full       = {0.20, 0.55, 0.95, 1.0},
    weather_rain    = {0.40, 0.65, 0.95, 1.0},
    weather_storm   = {0.90, 0.20, 0.20, 1.0},
}

PhoneUI.modDir        = nil
PhoneUI.scrollY       = 0
PhoneUI.maxScroll     = 0
PhoneUI.INBOX_ROWS_VISIBLE = 6
PhoneUI.ROW_HEIGHT    = 0
PhoneUI.hoveredId     = nil
PhoneUI.wallpaper     = nil   -- Overlay for phone wallpaper

function PhoneUI:init(modDir)
    self.modDir  = modDir
    self.scrollY = 0
    local wpPath = modDir .. "textures/phones/phone_wallpaper.png"
    self.wallpaper = Overlay.new(wpPath, 0, 0, 0.1, 0.1)
    if self.wallpaper == nil then
        print("[FarmNotify] Wallpaper not found: " .. wpPath)
    else
        print("[FarmNotify] Wallpaper loaded.")
    end
    print("[FarmNotify] PhoneUI initialized.")
end

-- ─── Main Draw ─────────────────────────────────────────────────────────────

function PhoneUI:draw()
    local animator = FarmNotify.animator
    if not animator:isVisible() then return end

    -- Render phone frame
    local bottomY = animator:getCurrentY()
    PhoneModel:render(bottomY)

    -- Get screen content area
    local sx, sy, sw, sh = PhoneModel:getScreenRect()
    if sw <= 0 or sh <= 0 then return end

    -- Black screen background
    self:_fillRect(sx, sy, sw, sh, self.C.screenBg)

    -- Wallpaper always behind everything
    self:_drawWallpaper(sx, sy, sw, sh)

    if animator:isInboxOpen() then
        self:_drawInbox(sx, sy, sw, sh)
    else
        local notif = animator.activeNotif
        if notif ~= nil then
            self:_drawNotificationScreen(sx, sy, sw, sh, notif)
        end
    end

    -- Status bar (time + signal) always visible
    self:_drawStatusBar(sx, sy, sw, sh)
end

-- ─── Wallpaper ─────────────────────────────────────────────────────────────

function PhoneUI:_drawWallpaper(sx, sy, sw, sh)
    if self.wallpaper == nil then
        -- Fallback: dark gradient background
        self:_fillRect(sx, sy, sw, sh * 0.5, {0.05, 0.08, 0.15, 1.0})
        self:_fillRect(sx, sy + sh * 0.5, sw, sh * 0.5, {0.02, 0.04, 0.08, 1.0})
        return
    end
    -- Render wallpaper scaled to fit screen area
    self.wallpaper:setPosition(sx, sy)
    self.wallpaper:setDimension(sw, sh)
    self.wallpaper:render()
    -- Dim overlay so text stays readable
    self:_fillRect(sx, sy, sw, sh, {0.0, 0.0, 0.0, 0.35})
end

-- ─── Notification Screen ───────────────────────────────────────────────────

function PhoneUI:_drawNotificationScreen(sx, sy, sw, sh, notif)
    local accentColor = self.NOTIF_COLOR[notif.type] or self.C.accent

    -- App header bar
    local headerH = sh * 0.08
    self:_fillRect(sx, sy + sh - headerH, sw, headerH, self.C.headerBg)

    -- App name in header
    self:_setColor(accentColor)
    self:_drawText(sx + sw * 0.05, sy + sh - headerH + headerH * 0.3, sh * 0.022, "FarmNotify")

    -- Unread badge (top-right of header)
    local unread = NotificationManager:getUnreadCount()
    if unread > 0 then
        local badgeStr = tostring(unread)
        self:_fillRect(sx + sw * 0.80, sy + sh - headerH + headerH * 0.25, sw * 0.15, headerH * 0.5, accentColor)
        self:_setColor(self.C.white)
        self:_drawTextCentered(sx + sw * 0.875, sy + sh - headerH + headerH * 0.28, sh * 0.020, badgeStr, sw * 0.15)
    end

    -- Accent left stripe
    self:_fillRect(sx, sy, sw * 0.012, sh, accentColor)

    -- Main notification card area (centered on screen)
    local cardX = sx + sw * 0.06
    local cardW = sw * 0.88
    local cardH = sh * 0.30
    local cardY = sy + sh * 0.35

    -- Card background
    self:_fillRect(cardX, cardY, cardW, cardH, self.C.notifBg)
    -- Card accent top line
    self:_fillRect(cardX, cardY + cardH - sh * 0.008, cardW, sh * 0.008, accentColor)

    -- Title
    self:_setColor(self.C.white)
    setTextBold(true)
    self:_drawText(cardX + sw * 0.04, cardY + cardH - sh * 0.065, sh * 0.026, notif.title)
    setTextBold(false)

    -- Message (word-wrapped — LS25 has no auto-wrap, split manually)
    self:_setColor(self.C.subtext)
    local lines = self:_wrapText(notif.message, cardW * 0.88, sh * 0.021)
    for i, line in ipairs(lines) do
        self:_drawText(cardX + sw * 0.04, cardY + cardH - sh * 0.13 - (i - 1) * sh * 0.028, sh * 0.021, line)
    end

    -- Tap hint at bottom
    self:_setColor(self.C.timeText)
    if notif.fieldId then
        self:_drawText(sx + sw * 0.06, sy + sh * 0.10, sh * 0.018, g_i18n:getText("farmnotify_tap_navigate"))
    end

    -- Dismiss hint
    self:_drawText(sx + sw * 0.06, sy + sh * 0.05, sh * 0.016, g_i18n:getText("farmnotify_inbox_open_hint"))

    -- Progress bar (time remaining)
    local elapsed  = FarmNotify.animator.displayTimer
    local duration = FarmNotify.animator.DISPLAY_DURATION
    local progress = math.max(0, 1 - elapsed / duration)
    local barW = sw * 0.88 * progress
    self:_fillRect(sx + sw * 0.06, sy + sh * 0.025, sw * 0.88, sh * 0.006, self.C.separator)
    self:_fillRect(sx + sw * 0.06, sy + sh * 0.025, barW, sh * 0.006, accentColor)
end

-- ─── Inbox View ────────────────────────────────────────────────────────────

function PhoneUI:_drawInbox(sx, sy, sw, sh)
    local history = NotificationManager:getHistory()

    -- Header
    local headerH = sh * 0.09
    self:_fillRect(sx, sy + sh - headerH, sw, headerH, self.C.headerBg)
    self:_setColor(self.C.accent)
    setTextBold(true)
    self:_drawText(sx + sw * 0.05, sy + sh - headerH + headerH * 0.32, sh * 0.024, g_i18n:getText("farmnotify_inbox_title"))
    setTextBold(false)

    -- Unread count
    local unread = NotificationManager:getUnreadCount()
    if unread > 0 then
        self:_setColor(self.C.subtext)
        self:_drawText(sx + sw * 0.05, sy + sh - headerH + headerH * 0.08, sh * 0.018,
            string.format(g_i18n:getText("farmnotify_unread_count"), unread))
    end

    -- Close hint
    self:_setColor(self.C.timeText)
    self:_drawText(sx + sw * 0.60, sy + sh - headerH + headerH * 0.32, sh * 0.016, g_i18n:getText("farmnotify_inbox_close_hint"))

    -- Row layout
    local rowH   = sh * 0.13
    local listY  = sy + sh - headerH - rowH
    local maxRows = math.floor(sh * (1 - 0.09) / rowH)
    self.ROW_HEIGHT = rowH
    self.maxScroll  = math.max(0, #history - maxRows)

    if #history == 0 then
        self:_setColor(self.C.subtext)
        self:_drawText(sx + sw * 0.1, sy + sh * 0.5, sh * 0.022, g_i18n:getText("farmnotify_no_notifications"))
        return
    end

    local startIdx = 1 + self.scrollY
    local endIdx   = math.min(#history, startIdx + maxRows - 1)

    for i = startIdx, endIdx do
        local notif  = history[i]
        local rowY   = listY - (i - startIdx) * rowH
        local isRead = notif.isRead
        local accent = self.NOTIF_COLOR[notif.type] or self.C.accent

        -- Row background
        local bgColor = isRead and {0.07, 0.07, 0.10, 1.0} or {0.11, 0.11, 0.16, 1.0}
        self:_fillRect(sx, rowY, sw, rowH - sh * 0.004, bgColor)

        -- Unread indicator
        if not isRead then
            self:_fillRect(sx, rowY, sw * 0.015, rowH - sh * 0.004, accent)
        end

        -- Separator
        self:_fillRect(sx, rowY, sw, sh * 0.002, self.C.separator)

        -- Title
        self:_setColor(isRead and self.C.subtext or self.C.white)
        if not isRead then setTextBold(true) end
        self:_drawText(sx + sw * 0.06, rowY + rowH * 0.58, sh * 0.021, notif.title)
        if not isRead then setTextBold(false) end

        -- Message (truncated)
        self:_setColor(self.C.subtext)
        local shortMsg = self:_truncate(notif.message, sw * 0.80, sh * 0.018)
        self:_drawText(sx + sw * 0.06, rowY + rowH * 0.24, sh * 0.018, shortMsg)

        -- Accent dot (right side)
        if not isRead then
            self:_fillRect(sx + sw * 0.92, rowY + rowH * 0.42, sw * 0.025, sw * 0.025, accent)
        end

        -- Field ID badge
        if notif.fieldId then
            self:_setColor(self.C.timeText)
            self:_drawText(sx + sw * 0.06, rowY + rowH * 0.04, sh * 0.015,
                g_i18n:getText("farmnotify_field_badge") .. " " .. tostring(notif.fieldId))
        end
    end

    -- Scroll indicator
    if #history > maxRows then
        local indicatorH = (maxRows / #history) * (sh * 0.85)
        local indicatorY = sy + sh * 0.09 + (self.scrollY / #history) * (sh * 0.85 - indicatorH)
        self:_fillRect(sx + sw - sw * 0.025, indicatorY, sw * 0.015, indicatorH, self.C.accentGrey)
    end
end

-- ─── Status Bar ────────────────────────────────────────────────────────────

function PhoneUI:_drawStatusBar(sx, sy, sw, sh)
    local sbH = sh * PhoneModel.current.statusBarH
    self:_fillRect(sx, sy + sh - sbH, sw, sbH, {0, 0, 0, 0.7})

    -- Time
    self:_setColor(self.C.white)
    local timeStr = self:_getGameTime()
    self:_drawText(sx + sw * 0.05, sy + sh - sbH + sbH * 0.22, sh * 0.018, timeStr)

    -- Signal bars (static decorative)
    self:_setColor(self.C.white)
    self:_drawText(sx + sw * 0.72, sy + sh - sbH + sbH * 0.22, sh * 0.016, "▂▄▆█ WiFi")
end

-- ─── Input Handling ────────────────────────────────────────────────────────

function PhoneUI:handleClick(screenX, screenY)
    local animator = FarmNotify.animator
    if not animator:isVisible() then return false end

    local sx, sy, sw, sh = PhoneModel:getScreenRect()

    -- Click within phone screen?
    if screenX < sx or screenX > sx + sw or screenY < sy or screenY > sy + sh then
        return false
    end

    if animator:isInboxOpen() then
        return self:_handleInboxClick(screenX, screenY, sx, sy, sw, sh)
    else
        -- Tap notification → navigate to field
        local notif = animator.activeNotif
        if notif and notif.fieldId then
            MapNavigator:navigateToField(notif.fieldId)
            NotificationManager:markRead(notif.id)
            animator:slideOut()
            return true
        end
    end
    return false
end

function PhoneUI:_handleInboxClick(screenX, screenY, sx, sy, sw, sh)
    local history = NotificationManager:getHistory()
    local headerH = sh * 0.09
    local rowH    = sh * 0.13
    local listTopY = sy + sh - headerH

    local startIdx = 1 + self.scrollY

    for i = startIdx, #history do
        local rowY = listTopY - (i - startIdx + 1) * rowH
        if screenY >= rowY and screenY <= rowY + rowH then
            local notif = history[i]
            NotificationManager:markRead(notif.id)
            if notif.fieldId then
                MapNavigator:navigateToField(notif.fieldId)
                FarmNotify.animator:closeInbox()
            end
            return true
        end
    end
    return false
end

function PhoneUI:handleScroll(direction)
    if not FarmNotify.animator:isInboxOpen() then return end
    self.scrollY = math.max(0, math.min(self.maxScroll, self.scrollY + direction))
end

-- ─── Helpers ───────────────────────────────────────────────────────────────

function PhoneUI:_getGameTime()
    local env = g_currentMission and g_currentMission.environment
    if env == nil then return "00:00" end
    local minutes = env.currentMinute or 0
    local hours   = env.currentHour   or 0
    return string.format("%02d:%02d", hours, minutes)
end

function PhoneUI:_wrapText(text, maxWidth, fontSize)
    -- Rough character-count wrap (LS25 has no built-in text measure)
    local charsPerLine = math.floor(maxWidth / (fontSize * 0.55))
    local lines = {}
    local remaining = text
    while #remaining > charsPerLine do
        local cut = remaining:sub(1, charsPerLine)
        local lastSpace = cut:match(".*()%s")
        if lastSpace then
            table.insert(lines, cut:sub(1, lastSpace - 1))
            remaining = remaining:sub(lastSpace + 1)
        else
            table.insert(lines, cut)
            remaining = remaining:sub(charsPerLine + 1)
        end
    end
    if #remaining > 0 then
        table.insert(lines, remaining)
    end
    return lines
end

function PhoneUI:_truncate(text, maxWidth, fontSize)
    local charsPerLine = math.floor(maxWidth / (fontSize * 0.55))
    if #text <= charsPerLine then return text end
    return text:sub(1, charsPerLine - 3) .. "..."
end

function PhoneUI:_fillRect(x, y, w, h, color)
    setOverlayColor(nil, color[1], color[2], color[3], color[4] or 1)
    drawFilledRect(x, y, w, h)
end

function PhoneUI:_setColor(color)
    setTextColor(color[1], color[2], color[3], color[4] or 1)
end

function PhoneUI:_drawText(x, y, size, text)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(x, y, size, tostring(text))
end

function PhoneUI:_drawTextCentered(x, y, size, text, width)
    setTextAlignment(RenderText.ALIGN_CENTER)
    renderText(x + width * 0.5, y, size, tostring(text))
    setTextAlignment(RenderText.ALIGN_LEFT)
end

function PhoneUI:delete()
    if self.wallpaper ~= nil then
        self.wallpaper:delete()
        self.wallpaper = nil
    end
end
