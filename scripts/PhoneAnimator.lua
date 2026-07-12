-- PhoneAnimator.lua
-- Handles all phone slide animations and state machine

PhoneAnimator = {}

PhoneAnimator.STATE = {
    HIDDEN      = "hidden",       -- fully below screen
    SLIDING_IN  = "sliding_in",   -- animating into view (notification)
    VISIBLE     = "visible",      -- showing notification, timer running
    SLIDING_OUT = "sliding_out",  -- animating back down
    INBOX_OPENING = "inbox_opening", -- animating to the full inbox view
    INBOX_OPEN  = "inbox_open",      -- full inbox view
    INBOX_CLOSING = "inbox_closing", -- animating back from inbox
}

-- Duration constants (ms)
PhoneAnimator.SLIDE_DURATION    = 450
PhoneAnimator.DISPLAY_DURATION  = 7000  -- overridden by settings
PhoneAnimator.INBOX_SLIDE_DUR   = 350

-- Y positions (bottom of phone frame, in screen coords 0=bottom, 1=top)
-- Phone height ≈ 0.55, so:
PhoneAnimator.Y_HIDDEN          = -0.56   -- fully off-screen below
PhoneAnimator.Y_PEEK            = 0.02    -- just peeking at bottom (notifications)
PhoneAnimator.Y_INBOX           = 0.22    -- centered for inbox view (more of phone visible)

PhoneAnimator.state         = nil
PhoneAnimator.currentY      = 0
PhoneAnimator.targetY       = 0
PhoneAnimator.startY        = 0
PhoneAnimator.animTimer     = 0
PhoneAnimator.displayTimer  = 0
PhoneAnimator.activeNotif   = nil  -- notification currently being shown

PhoneAnimator.onSlideInComplete  = nil  -- callback
PhoneAnimator.onSlideOutComplete = nil
PhoneAnimator.onDisplayTimeout   = nil
PhoneAnimator.onInboxOpenComplete = nil
PhoneAnimator.onInboxCloseComplete = nil

function PhoneAnimator:init(displayDuration)
    self.state        = self.STATE.HIDDEN
    self.currentY     = self.Y_HIDDEN
    self.targetY      = self.Y_HIDDEN
    self.startY       = self.Y_HIDDEN
    self.animTimer    = 0
    self.displayTimer = 0
    self.activeNotif  = nil
    self.DISPLAY_DURATION = math.max(1, tonumber(displayDuration) or 7000)
    print("[FarmNotify] PhoneAnimator initialized.")
end

function PhoneAnimator:update(dt)
    dt = math.max(0, tonumber(dt) or 0)

    if self.state == self.STATE.SLIDING_IN then
        self:_animate(dt, self.SLIDE_DURATION, function()
            self.state = self.STATE.VISIBLE
            self.displayTimer = 0
            if self.onSlideInComplete then self.onSlideInComplete() end
        end)

    elseif self.state == self.STATE.VISIBLE then
        self.displayTimer = self.displayTimer + dt
        if self.displayTimer >= self.DISPLAY_DURATION then
            if self.onDisplayTimeout then self.onDisplayTimeout() end
            self:slideOut()
        end

    elseif self.state == self.STATE.SLIDING_OUT then
        self:_animate(dt, self.SLIDE_DURATION, function()
            self.state = self.STATE.HIDDEN
            self.activeNotif = nil
            if self.onSlideOutComplete then self.onSlideOutComplete() end
        end)

    elseif self.state == self.STATE.INBOX_OPENING then
        self:_animate(dt, self.INBOX_SLIDE_DUR, function()
            self.state = self.STATE.INBOX_OPEN
            if self.onInboxOpenComplete then self.onInboxOpenComplete() end
        end)

    elseif self.state == self.STATE.INBOX_OPEN then
        -- Static: stays open until explicitly closed.

    elseif self.state == self.STATE.INBOX_CLOSING then
        self:_animate(dt, self.INBOX_SLIDE_DUR, function()
            self.state = self.STATE.HIDDEN
            self.activeNotif = nil
            if self.onInboxCloseComplete then self.onInboxCloseComplete() end
        end)
    end
end

-- Animate phone in from bottom to peek position (notification)
function PhoneAnimator:showNotification(notif)
    if notif == nil or self:isInboxVisible() then return false end
    self.activeNotif = notif
    self:_startAnim(self.currentY or self.Y_HIDDEN, self.Y_PEEK)
    self.state = self.STATE.SLIDING_IN
    self.displayTimer = 0
    return true
end

-- Slide back down
function PhoneAnimator:slideOut()
    if self:isInboxVisible() then
        return self:closeInbox()
    end
    if self.state ~= self.STATE.VISIBLE and self.state ~= self.STATE.SLIDING_IN then
        return false
    end
    self:_startAnim(self.currentY, self.Y_HIDDEN)
    self.state = self.STATE.SLIDING_OUT
    return true
end

-- Open full inbox
function PhoneAnimator:openInbox()
    if self.state == self.STATE.INBOX_OPEN or self.state == self.STATE.INBOX_OPENING then
        return false
    end
    self:_startAnim(self.currentY, self.Y_INBOX)
    self.state = self.STATE.INBOX_OPENING
    self.displayTimer = 0
    self.activeNotif = nil
    if PhoneUI ~= nil and PhoneUI.showInbox ~= nil then PhoneUI:showInbox() end
    return true
end

-- Close inbox
function PhoneAnimator:closeInbox()
    if not self:isInboxVisible() then return false end
    self:_startAnim(self.currentY, self.Y_HIDDEN)
    self.state = self.STATE.INBOX_CLOSING
    return true
end

function PhoneAnimator:toggleInbox()
    if self.state == self.STATE.INBOX_OPEN or self.state == self.STATE.INBOX_OPENING then
        return self:closeInbox()
    else
        return self:openInbox()
    end
end

function PhoneAnimator:isVisible()
    return self.state ~= self.STATE.HIDDEN
end

function PhoneAnimator:isInboxOpen()
    return self.state == self.STATE.INBOX_OPEN or self.state == self.STATE.INBOX_OPENING
end

-- True while any part of the inbox transition is visible. Rendering uses this
-- so closing never flashes a notification screen for one frame.
function PhoneAnimator:isInboxVisible()
    return self.state == self.STATE.INBOX_OPENING
        or self.state == self.STATE.INBOX_OPEN
        or self.state == self.STATE.INBOX_CLOSING
end

function PhoneAnimator:isInboxInteractive()
    return self.state == self.STATE.INBOX_OPEN
end

function PhoneAnimator:getCurrentY()
    return self.currentY
end

function PhoneAnimator:getState()
    return self.state
end

-- ─── Internal ──────────────────────────────────────────────────────────────

function PhoneAnimator:_startAnim(fromY, toY)
    self.startY    = tonumber(fromY) or self.currentY or self.Y_HIDDEN
    self.targetY   = tonumber(toY) or self.startY
    self.currentY  = self.startY
    self.animTimer = 0
end

function PhoneAnimator:_animate(dt, duration, onComplete)
    self.animTimer = self.animTimer + dt
    duration = math.max(1, tonumber(duration) or 1)
    local t = math.min(1.0, self.animTimer / duration)
    -- Ease-out cubic
    local ease = 1 - (1 - t) ^ 3
    self.currentY = self.startY + (self.targetY - self.startY) * ease

    if t >= 1.0 then
        self.currentY = self.targetY
        onComplete()
    end
end
