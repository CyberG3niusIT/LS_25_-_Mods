-- PhoneUI.lua
-- Phone HUD renderer, inbox/settings views and bounded pointer interaction.

PhoneUI = {}

PhoneUI.C = {
    screenBg  = {0.01, 0.01, 0.02, 1.00},
    headerBg  = {0.04, 0.04, 0.06, 0.96},
    accent    = {0.20, 0.78, 0.35, 1.00},
    white     = {1.00, 1.00, 1.00, 1.00},
    subtext   = {0.72, 0.72, 0.75, 1.00},
    separator = {0.18, 0.18, 0.22, 1.00},
    timeText  = {0.55, 0.55, 0.60, 1.00},
    buttonBg  = {0.14, 0.14, 0.19, 1.00},
    rowRead   = {0.07, 0.07, 0.10, 0.96},
    rowUnread = {0.11, 0.11, 0.16, 0.98},
    notifBg   = {0.08, 0.08, 0.12, 0.94},
}

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

PhoneUI.TEXT = {
    en = {
        inbox = "Inbox",
        settings = "Settings",
        all = "ALL",
        set = "SET",
        back = "BACK",
        close = "X",
        empty = "No notifications",
        model = "Phone model",
        popups = "Popups",
        volume = "Volume",
        duration = "Duration",
        markAll = "Mark all read",
        on = "ON",
        off = "OFF",
        seconds = "%d s",
        unread = "%d unread",
        openInbox = "Tap header for inbox",
        navigate = "Tap card to navigate",
    },
    de = {
        inbox = "Posteingang",
        settings = "Einstellungen",
        all = "ALLE",
        set = "SET",
        back = "ZURUECK",
        close = "X",
        empty = "Keine Meldungen",
        model = "Handy-Modell",
        popups = "Popups",
        volume = "Lautstaerke",
        duration = "Anzeigedauer",
        markAll = "Alle als gelesen",
        on = "AN",
        off = "AUS",
        seconds = "%d s",
        unread = "%d ungelesen",
        openInbox = "Kopfzeile: Posteingang",
        navigate = "Meldung: zum Feld",
    },
}

PhoneUI.VIEW_INBOX = "inbox"
PhoneUI.VIEW_SETTINGS = "settings"
PhoneUI.DURATION_VALUES = {3000, 5000, 7000, 10000, 15000, 20000}

PhoneUI.modDir = nil
PhoneUI.wallpaper = nil
PhoneUI.view = PhoneUI.VIEW_INBOX
PhoneUI.scrollY = 0
PhoneUI.maxScroll = 0
PhoneUI.ROW_HEIGHT = 0

function PhoneUI:init(modDir)
    self:delete()
    self.modDir = modDir
    self.view = self.VIEW_INBOX
    self.scrollY = 0
    self.maxScroll = 0

    local path = modDir .. "textures/phones/phone_wallpaper.png"
    local exists = fileExists == nil or fileExists(path)
    if exists and Overlay ~= nil and Overlay.new ~= nil then
        self.wallpaper = Overlay.new(path, 0, 0, 0.1, 0.1)
        if self.wallpaper.overlayId ~= nil and self.wallpaper.overlayId == 0 then
            self.wallpaper:delete()
            self.wallpaper = nil
        end
    end

    if self.wallpaper == nil then
        print("[FarmNotify] Wallpaper unavailable; using fallback background: " .. path)
    end
    print("[FarmNotify] PhoneUI initialized.")
end

function PhoneUI:showInbox()
    self.view = self.VIEW_INBOX
    self.scrollY = 0
end

function PhoneUI:draw()
    local animator = FarmNotify and FarmNotify.animator
    if animator == nil or not animator:isVisible() then return end

    PhoneModel:render(animator:getCurrentY())
    local sx, sy, sw, sh = PhoneModel:getScreenRect()
    if sw <= 0 or sh <= 0 then return end
    if sx + sw <= 0 or sx >= 1 or sy + sh <= 0 or sy >= 1 then return end

    self:_fillRect(sx, sy, sw, sh, self.C.screenBg)
    self:_drawWallpaper(sx, sy, sw, sh)

    if animator.isInboxVisible ~= nil and animator:isInboxVisible() then
        if self.view == self.VIEW_SETTINGS then
            self:_drawSettings(sx, sy, sw, sh)
        else
            self:_drawInbox(sx, sy, sw, sh)
        end
    else
        local notif = animator.activeNotif
        if notif ~= nil then self:_drawNotificationScreen(sx, sy, sw, sh, notif) end
    end

    self:_drawStatusBar(sx, sy, sw, sh)
    self:_resetTextState()
end

function PhoneUI:_drawWallpaper(sx, sy, sw, sh)
    if self.wallpaper == nil then
        self:_fillRect(sx, sy, sw, sh * 0.5, {0.05, 0.08, 0.15, 1.0})
        self:_fillRect(sx, sy + sh * 0.5, sw, sh * 0.5, {0.02, 0.04, 0.08, 1.0})
        return
    end
    self.wallpaper:setPosition(sx, sy)
    self.wallpaper:setDimension(sw, sh)
    local clipX1 = math.max(0, sx)
    local clipY1 = math.max(0, sy)
    local clipX2 = math.min(1, sx + sw)
    local clipY2 = math.min(1, sy + sh)
    if clipX2 > clipX1 and clipY2 > clipY1 then
        self.wallpaper:render(clipX1, clipY1, clipX2, clipY2)
    end
    self:_fillRect(sx, sy, sw, sh, {0.0, 0.0, 0.0, 0.38})
end

function PhoneUI:_getStatusHeight(sh)
    local model = PhoneModel.current
    return sh * ((model and model.statusBarH) or 0.05)
end

function PhoneUI:_getHeaderLayout(sx, sy, sw, sh)
    local statusH = self:_getStatusHeight(sh)
    local headerH = sh * 0.105
    local headerY = sy + sh - statusH - headerH
    return headerY, headerH, statusH
end

function PhoneUI:_drawNotificationScreen(sx, sy, sw, sh, notif)
    local accent = self.NOTIF_COLOR[notif.type] or self.C.accent
    local headerY, headerH = self:_getHeaderLayout(sx, sy, sw, sh)
    self:_fillRect(sx, headerY, sw, headerH, self.C.headerBg)
    self:_setColor(accent)
    self:_setBold(true)
    self:_drawText(sx + sw * 0.05, headerY + headerH * 0.33, sh * 0.023, "FarmNotify")
    self:_setBold(false)

    local unread = NotificationManager:getUnreadCount()
    if unread > 0 then
        local bx = sx + sw * 0.78
        local bw = sw * 0.17
        self:_fillRect(bx, headerY + headerH * 0.22, bw, headerH * 0.56, accent)
        self:_setColor(self.C.white)
        self:_drawTextCentered(bx + bw * 0.5, headerY + headerH * 0.34, sh * 0.018, tostring(unread))
    end

    local cardX, cardY, cardW, cardH = self:_getNotificationCardRect(sx, sy, sw, sh)
    self:_fillRect(cardX, cardY, cardW, cardH, self.C.notifBg)
    self:_fillRect(cardX, cardY + cardH - sh * 0.008, cardW, sh * 0.008, accent)

    self:_setColor(self.C.white)
    self:_setBold(true)
    self:_drawText(cardX + sw * 0.04, cardY + cardH - sh * 0.062, sh * 0.025,
        self:_truncate(notif.title, cardW * 0.88, sh * 0.025))
    self:_setBold(false)

    self:_setColor(self.C.subtext)
    local lines = self:_wrapText(notif.message, cardW * 0.88, sh * 0.020, 4)
    for i, line in ipairs(lines) do
        self:_drawText(cardX + sw * 0.04, cardY + cardH - sh * 0.125 - (i - 1) * sh * 0.028,
            sh * 0.020, line)
    end

    self:_setColor(self.C.timeText)
    local hint = notif.fieldId and self:_t("navigate") or self:_t("openInbox")
    self:_drawText(sx + sw * 0.06, sy + sh * 0.072, sh * 0.016,
        self:_truncate(hint, sw * 0.88, sh * 0.016))

    local duration = math.max(1, tonumber(FarmNotify.animator.DISPLAY_DURATION) or 1)
    local elapsed = math.max(0, tonumber(FarmNotify.animator.displayTimer) or 0)
    local progress = math.max(0, math.min(1, 1 - elapsed / duration))
    self:_fillRect(sx + sw * 0.06, sy + sh * 0.035, sw * 0.88, sh * 0.006, self.C.separator)
    self:_fillRect(sx + sw * 0.06, sy + sh * 0.035, sw * 0.88 * progress, sh * 0.006, accent)
end

function PhoneUI:_getNotificationCardRect(sx, sy, sw, sh)
    return sx + sw * 0.06, sy + sh * 0.30, sw * 0.88, sh * 0.34
end

function PhoneUI:_drawInboxHeader(sx, sy, sw, sh)
    local headerY, headerH = self:_getHeaderLayout(sx, sy, sw, sh)
    self:_fillRect(sx, headerY, sw, headerH, self.C.headerBg)

    local unread = NotificationManager:getUnreadCount()
    local title = self:_t("inbox")
    if unread > 0 then title = title .. " (" .. tostring(unread) .. ")" end
    self:_setColor(self.C.accent)
    self:_setBold(true)
    self:_drawText(sx + sw * 0.04, headerY + headerH * 0.34, sh * 0.021,
        self:_truncate(title, sw * 0.48, sh * 0.021))
    self:_setBold(false)

    local areas = self:_getInboxHeaderAreas(sx, headerY, sw, headerH)
    self:_drawButton(areas.all, self:_t("all"), sh * 0.014)
    self:_drawButton(areas.settings, self:_t("set"), sh * 0.014)
    self:_drawButton(areas.close, self:_t("close"), sh * 0.016)
    return headerY
end

function PhoneUI:_getInboxHeaderAreas(sx, headerY, sw, headerH)
    local gap = sw * 0.012
    local y = headerY + headerH * 0.18
    local h = headerH * 0.64
    local closeW = sw * 0.10
    local settingsW = sw * 0.15
    local allW = sw * 0.15
    local closeX = sx + sw - gap - closeW
    local settingsX = closeX - gap - settingsW
    local allX = settingsX - gap - allW
    return {
        all = {x = allX, y = y, w = allW, h = h},
        settings = {x = settingsX, y = y, w = settingsW, h = h},
        close = {x = closeX, y = y, w = closeW, h = h},
    }
end

function PhoneUI:_getInboxLayout(sx, sy, sw, sh, historyCount)
    local headerY = self:_getHeaderLayout(sx, sy, sw, sh)
    local rowH = sh * 0.125
    local availableH = math.max(0, headerY - sy)
    local maxRows = math.max(1, math.floor(availableH / rowH))
    local maxScroll = math.max(0, historyCount - maxRows)
    self.maxScroll = maxScroll
    self.scrollY = math.max(0, math.min(maxScroll, math.floor(self.scrollY or 0)))
    self.ROW_HEIGHT = rowH
    return headerY, rowH, maxRows
end

function PhoneUI:_drawInbox(sx, sy, sw, sh)
    local history = NotificationManager:getHistory() or {}
    local headerY = self:_drawInboxHeader(sx, sy, sw, sh)
    local _, rowH, maxRows = self:_getInboxLayout(sx, sy, sw, sh, #history)

    if #history == 0 then
        self:_setColor(self.C.subtext)
        self:_drawTextCentered(sx + sw * 0.5, sy + (headerY - sy) * 0.5, sh * 0.021, self:_t("empty"))
        return
    end

    local startIdx = 1 + self.scrollY
    local endIdx = math.min(#history, startIdx + maxRows - 1)
    for i = startIdx, endIdx do
        local notif = history[i]
        local rowY = headerY - (i - startIdx + 1) * rowH
        local isRead = notif.isRead == true
        local accent = self.NOTIF_COLOR[notif.type] or self.C.accent
        self:_fillRect(sx, rowY, sw, rowH - sh * 0.003, isRead and self.C.rowRead or self.C.rowUnread)
        if not isRead then self:_fillRect(sx, rowY, sw * 0.014, rowH - sh * 0.003, accent) end
        self:_fillRect(sx, rowY, sw, sh * 0.002, self.C.separator)

        self:_setColor(isRead and self.C.subtext or self.C.white)
        self:_setBold(not isRead)
        self:_drawText(sx + sw * 0.05, rowY + rowH * 0.57, sh * 0.020,
            self:_truncate(notif.title, sw * 0.82, sh * 0.020))
        self:_setBold(false)
        self:_setColor(self.C.subtext)
        self:_drawText(sx + sw * 0.05, rowY + rowH * 0.24, sh * 0.016,
            self:_truncate(notif.message, sw * 0.82, sh * 0.016))

        if not isRead then
            local dot = math.min(sw * 0.023, rowH * 0.16)
            self:_fillRect(sx + sw * 0.93, rowY + rowH * 0.43, dot, dot, accent)
        end
    end

    if #history > maxRows then
        local trackY = sy
        local trackH = math.max(0.01, headerY - sy)
        local thumbH = math.max(sh * 0.05, trackH * maxRows / #history)
        local fraction = self.maxScroll > 0 and (self.scrollY / self.maxScroll) or 0
        local thumbY = trackY + (trackH - thumbH) * (1 - fraction)
        self:_fillRect(sx + sw * 0.975, thumbY, sw * 0.012, thumbH, self.C.timeText)
    end
end

function PhoneUI:_drawSettings(sx, sy, sw, sh)
    local headerY, headerH = self:_getHeaderLayout(sx, sy, sw, sh)
    self:_fillRect(sx, headerY, sw, headerH, self.C.headerBg)
    local areas = self:_getSettingsHeaderAreas(sx, headerY, sw, headerH)
    self:_drawButton(areas.back, self:_t("back"), sh * 0.012)
    self:_drawButton(areas.close, self:_t("close"), sh * 0.016)
    self:_setColor(self.C.accent)
    self:_setBold(true)
    self:_drawText(sx + sw * 0.30, headerY + headerH * 0.34, sh * 0.020,
        self:_truncate(self:_t("settings"), sw * 0.52, sh * 0.020))
    self:_setBold(false)

    local rows = self:_getSettingsRows(sx, sy, sw, headerY)
    local settings = FarmNotify and FarmNotify.settings
    local model = settings and settings:get("phoneModel") or (PhoneModel.current and PhoneModel.current.id) or "iphone"
    local showPopups = settings == nil or settings:get("showPopups") == true
    local volume = settings and tonumber(settings:get("volume")) or 0.8
    local duration = settings and tonumber(settings:get("popupDuration")) or 7000
    local unread = NotificationManager:getUnreadCount()

    self:_drawSettingRow(rows.model, self:_t("model"), model == "samsung" and "Samsung" or "iPhone", sh)
    self:_drawSettingRow(rows.popups, self:_t("popups"), self:_t(showPopups and "on" or "off"), sh)
    self:_drawSettingRow(rows.volume, self:_t("volume"), string.format("%d%%", math.floor(volume * 100 + 0.5)), sh, true)
    self:_drawSettingRow(rows.duration, self:_t("duration"), string.format(self:_t("seconds"), math.floor(duration / 1000 + 0.5)), sh, true)
    self:_drawSettingRow(rows.markAll, self:_t("markAll"), tostring(unread), sh)
end

function PhoneUI:_getSettingsHeaderAreas(sx, headerY, sw, headerH)
    return {
        back = {x = sx + sw * 0.02, y = headerY + headerH * 0.18, w = sw * 0.24, h = headerH * 0.64},
        close = {x = sx + sw * 0.88, y = headerY + headerH * 0.18, w = sw * 0.10, h = headerH * 0.64},
    }
end

function PhoneUI:_getSettingsRows(sx, sy, sw, headerY)
    local count = 5
    local rowH = math.max(0.001, (headerY - sy) / count)
    local rows = {}
    local names = {"model", "popups", "volume", "duration", "markAll"}
    for i, name in ipairs(names) do
        rows[name] = {x = sx, y = headerY - i * rowH, w = sw, h = rowH}
    end
    return rows
end

function PhoneUI:_drawSettingRow(rect, label, value, sh, hasStepper)
    self:_fillRect(rect.x, rect.y, rect.w, rect.h - sh * 0.003, self.C.rowRead)
    self:_fillRect(rect.x, rect.y, rect.w, sh * 0.002, self.C.separator)
    self:_setColor(self.C.white)
    self:_drawText(rect.x + rect.w * 0.05, rect.y + rect.h * 0.56, sh * 0.018,
        self:_truncate(label, rect.w * (hasStepper and 0.42 or 0.55), sh * 0.018))
    self:_setColor(self.C.subtext)
    self:_drawText(rect.x + rect.w * 0.05, rect.y + rect.h * 0.22, sh * 0.016,
        self:_truncate(value, rect.w * 0.48, sh * 0.016))
    if hasStepper then
        local minus, plus = self:_getStepperAreas(rect)
        self:_drawButton(minus, "-", sh * 0.022)
        self:_drawButton(plus, "+", sh * 0.022)
    else
        local bw = rect.w * 0.28
        self:_drawButton({x = rect.x + rect.w - bw - rect.w * 0.04, y = rect.y + rect.h * 0.20, w = bw, h = rect.h * 0.60}, value, sh * 0.015)
    end
end

function PhoneUI:_getStepperAreas(rect)
    local buttonW = rect.w * 0.16
    local gap = rect.w * 0.025
    local xPlus = rect.x + rect.w - rect.w * 0.04 - buttonW
    local xMinus = xPlus - gap - buttonW
    local y = rect.y + rect.h * 0.20
    local h = rect.h * 0.60
    return {x = xMinus, y = y, w = buttonW, h = h}, {x = xPlus, y = y, w = buttonW, h = h}
end

function PhoneUI:_drawButton(rect, label, fontSize)
    self:_fillRect(rect.x, rect.y, rect.w, rect.h, self.C.buttonBg)
    self:_setColor(self.C.white)
    self:_drawTextCentered(rect.x + rect.w * 0.5, rect.y + rect.h * 0.30, fontSize,
        self:_truncate(label, rect.w * 0.88, fontSize))
end

function PhoneUI:_drawStatusBar(sx, sy, sw, sh)
    local h = self:_getStatusHeight(sh)
    local y = sy + sh - h
    self:_fillRect(sx, y, sw, h, {0, 0, 0, 0.82})
    self:_setColor(self.C.white)
    self:_drawText(sx + sw * 0.05, y + h * 0.22, sh * 0.016, self:_getGameTime())
    self:_drawText(sx + sw * 0.70, y + h * 0.22, sh * 0.014, "|||| WiFi")
end

function PhoneUI:handleClick(screenX, screenY)
    local animator = FarmNotify and FarmNotify.animator
    if animator == nil or not animator:isVisible() then return false end

    local px, py, pw, ph = PhoneModel:getRenderRect()
    if not self:_isInRect(screenX, screenY, {x = px, y = py, w = pw, h = ph}) then return false end

    local sx, sy, sw, sh = PhoneModel:getScreenRect()
    if not self:_isInRect(screenX, screenY, {x = sx, y = sy, w = sw, h = sh}) then
        return true
    end

    if animator.isInboxVisible ~= nil and animator:isInboxVisible() then
        if animator.isInboxInteractive ~= nil and not animator:isInboxInteractive() then return true end
        if self.view == self.VIEW_SETTINGS then
            self:_handleSettingsClick(screenX, screenY, sx, sy, sw, sh)
        else
            self:_handleInboxClick(screenX, screenY, sx, sy, sw, sh)
        end
        return true
    end

    local headerY, headerH = self:_getHeaderLayout(sx, sy, sw, sh)
    if self:_isInRect(screenX, screenY, {x = sx, y = headerY, w = sw, h = headerH}) then
        animator:openInbox()
        if FarmNotify._setInboxMouseCursor then FarmNotify:_setInboxMouseCursor(true) end
        return true
    end

    local cx, cy, cw, ch = self:_getNotificationCardRect(sx, sy, sw, sh)
    if self:_isInRect(screenX, screenY, {x = cx, y = cy, w = cw, h = ch}) then
        local notif = animator.activeNotif
        if notif ~= nil then
            NotificationManager:markRead(notif.id)
            if notif.fieldId ~= nil then MapNavigator:navigateToField(notif.fieldId) end
            animator:slideOut()
        end
    end
    return true
end

function PhoneUI:_handleInboxClick(screenX, screenY, sx, sy, sw, sh)
    local history = NotificationManager:getHistory() or {}
    local headerY, headerH = self:_getHeaderLayout(sx, sy, sw, sh)
    local areas = self:_getInboxHeaderAreas(sx, headerY, sw, headerH)
    if self:_isInRect(screenX, screenY, areas.close) then
        self:_closeInbox()
        return
    elseif self:_isInRect(screenX, screenY, areas.settings) then
        self.view = self.VIEW_SETTINGS
        return
    elseif self:_isInRect(screenX, screenY, areas.all) then
        NotificationManager:markAllRead()
        return
    end

    local _, rowH, maxRows = self:_getInboxLayout(sx, sy, sw, sh, #history)
    local startIdx = 1 + self.scrollY
    local endIdx = math.min(#history, startIdx + maxRows - 1)
    for i = startIdx, endIdx do
        local rowY = headerY - (i - startIdx + 1) * rowH
        if self:_isInRect(screenX, screenY, {x = sx, y = rowY, w = sw, h = rowH}) then
            local notif = history[i]
            NotificationManager:markRead(notif.id)
            if notif.fieldId ~= nil then
                self:_closeInbox()
                MapNavigator:navigateToField(notif.fieldId)
            end
            return
        end
    end
end

function PhoneUI:_handleSettingsClick(screenX, screenY, sx, sy, sw, sh)
    local headerY, headerH = self:_getHeaderLayout(sx, sy, sw, sh)
    local header = self:_getSettingsHeaderAreas(sx, headerY, sw, headerH)
    if self:_isInRect(screenX, screenY, header.back) then
        self.view = self.VIEW_INBOX
        return
    elseif self:_isInRect(screenX, screenY, header.close) then
        self:_closeInbox()
        return
    end

    local rows = self:_getSettingsRows(sx, sy, sw, headerY)
    local settings = FarmNotify.settings
    if settings == nil then return end

    if self:_isInRect(screenX, screenY, rows.model) then
        local current = settings:get("phoneModel")
        FarmNotify:setPhoneModel(current == "samsung" and "iphone" or "samsung")
    elseif self:_isInRect(screenX, screenY, rows.popups) then
        FarmNotify:setShowPopups(settings:get("showPopups") ~= true)
    elseif self:_isInRect(screenX, screenY, rows.volume) then
        local minus, plus = self:_getStepperAreas(rows.volume)
        local value = tonumber(settings:get("volume")) or 0.8
        if self:_isInRect(screenX, screenY, minus) then
            FarmNotify:setVolume(math.max(0, (math.floor(value * 10 + 0.5) - 1) / 10))
        elseif self:_isInRect(screenX, screenY, plus) then
            FarmNotify:setVolume(math.min(1, (math.floor(value * 10 + 0.5) + 1) / 10))
        end
    elseif self:_isInRect(screenX, screenY, rows.duration) then
        local minus, plus = self:_getStepperAreas(rows.duration)
        local value = tonumber(settings:get("popupDuration")) or 7000
        if self:_isInRect(screenX, screenY, minus) then
            FarmNotify:setPopupDuration(self:_adjacentDuration(value, -1))
        elseif self:_isInRect(screenX, screenY, plus) then
            FarmNotify:setPopupDuration(self:_adjacentDuration(value, 1))
        end
    elseif self:_isInRect(screenX, screenY, rows.markAll) then
        NotificationManager:markAllRead()
    end
end

function PhoneUI:_adjacentDuration(value, direction)
    local values = self.DURATION_VALUES
    local closest = 1
    local distance = math.abs(value - values[1])
    for i = 2, #values do
        local nextDistance = math.abs(value - values[i])
        if nextDistance < distance then
            closest = i
            distance = nextDistance
        end
    end
    closest = math.max(1, math.min(#values, closest + direction))
    return values[closest]
end

function PhoneUI:_closeInbox()
    self.view = self.VIEW_INBOX
    if FarmNotify and FarmNotify.animator then FarmNotify.animator:closeInbox() end
    if FarmNotify and FarmNotify._setInboxMouseCursor then FarmNotify:_setInboxMouseCursor(false) end
end

function PhoneUI:handleScroll(direction)
    local animator = FarmNotify and FarmNotify.animator
    if animator == nil or animator.isInboxInteractive == nil or not animator:isInboxInteractive() then return false end
    if self.view ~= self.VIEW_INBOX then return false end
    local delta = tonumber(direction) or 0
    if delta == 0 then return false end
    delta = delta > 0 and 1 or -1
    local old = self.scrollY
    self.scrollY = math.max(0, math.min(self.maxScroll, self.scrollY + delta))
    return self.scrollY ~= old
end

function PhoneUI:_getGameTime()
    local env = g_currentMission and g_currentMission.environment
    if env == nil then return "00:00" end
    local minutes = math.max(0, math.floor(tonumber(env.currentMinute) or 0)) % 60
    local hours = math.max(0, math.floor(tonumber(env.currentHour) or 0)) % 24
    return string.format("%02d:%02d", hours, minutes)
end

function PhoneUI:_t(key)
    local language = string.lower(tostring(g_languageShort or "en"))
    local translations = language:sub(1, 2) == "de" and self.TEXT.de or self.TEXT.en
    return translations[key] or self.TEXT.en[key] or key
end

function PhoneUI:_measureText(text, fontSize)
    text = tostring(text or "")
    if getTextWidth ~= nil then return getTextWidth(fontSize, text) end
    return #text * fontSize * 0.52
end

function PhoneUI:_utf8Chars(text)
    local chars = {}
    local i = 1
    text = tostring(text or "")
    while i <= #text do
        local byte = text:byte(i)
        local length = 1
        if byte >= 240 then
            length = 4
        elseif byte >= 224 then
            length = 3
        elseif byte >= 192 then
            length = 2
        end
        table.insert(chars, text:sub(i, math.min(#text, i + length - 1)))
        i = i + length
    end
    return chars
end

function PhoneUI:_truncate(text, maxWidth, fontSize)
    text = tostring(text or "")
    if maxWidth <= 0 then return "" end
    if self:_measureText(text, fontSize) <= maxWidth then return text end
    local suffix = "..."
    local result = ""
    for _, char in ipairs(self:_utf8Chars(text)) do
        if self:_measureText(result .. char .. suffix, fontSize) > maxWidth then break end
        result = result .. char
    end
    return result .. suffix
end

function PhoneUI:_wrapText(text, maxWidth, fontSize, maxLines)
    text = tostring(text or "")
    local lines = {}
    local current = ""
    for word in text:gmatch("%S+") do
        local candidate = current == "" and word or (current .. " " .. word)
        if self:_measureText(candidate, fontSize) <= maxWidth then
            current = candidate
        else
            if current ~= "" then table.insert(lines, current) end
            current = self:_truncate(word, maxWidth, fontSize)
        end
        if maxLines ~= nil and #lines >= maxLines then break end
    end
    if current ~= "" and (maxLines == nil or #lines < maxLines) then table.insert(lines, current) end
    if #lines == 0 then table.insert(lines, "") end
    if maxLines ~= nil and #lines == maxLines and self:_measureText(text, fontSize) > maxWidth * maxLines then
        lines[maxLines] = self:_truncate(lines[maxLines] .. "...", maxWidth, fontSize)
    end
    return lines
end

function PhoneUI:_isInRect(x, y, rect)
    return rect ~= nil and rect.w > 0 and rect.h > 0
        and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

function PhoneUI:_fillRect(x, y, w, h, color)
    if drawFilledRect == nil or w <= 0 or h <= 0 then return end
    drawFilledRect(x, y, w, h, color[1], color[2], color[3], color[4] or 1)
end

function PhoneUI:_setColor(color)
    setTextColor(color[1], color[2], color[3], color[4] or 1)
end

function PhoneUI:_setBold(enabled)
    if setTextBold ~= nil then setTextBold(enabled == true) end
end

function PhoneUI:_drawText(x, y, size, text)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(x, y, size, tostring(text or ""))
end

function PhoneUI:_drawTextCentered(x, y, size, text)
    setTextAlignment(RenderText.ALIGN_CENTER)
    renderText(x, y, size, tostring(text or ""))
    setTextAlignment(RenderText.ALIGN_LEFT)
end

function PhoneUI:_resetTextState()
    self:_setBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

function PhoneUI:delete()
    if self.wallpaper ~= nil then
        self.wallpaper:delete()
        self.wallpaper = nil
    end
    self.view = self.VIEW_INBOX
    self.scrollY = 0
    self.maxScroll = 0
end
