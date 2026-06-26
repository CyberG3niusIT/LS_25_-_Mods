-- PhoneModel.lua
-- Manages phone frame overlays for iPhone 16 Pro Max and Samsung Galaxy S26 Ultra
-- Textures must be provided as DDS files in textures/phones/

PhoneModel = {}

--[[
    Screen area = normalized coordinates WITHIN the phone frame overlay (0-1).
    These define where the "screen content" is rendered inside the phone image.

    Phone overlay is rendered at world-space position (phoneX, phoneY, phoneW, phoneH).
    Screen content is rendered at:
        contentX = phoneX + screenOffsetX * phoneW
        contentY = phoneY + screenOffsetY * phoneH
        contentW = screenW * phoneW
        contentH = screenH * phoneH
]]
PhoneModel.MODELS = {
    iphone = {
        id           = "iphone",
        displayName  = "iPhone 16 Pro Max",
        frameTexture = "textures/phones/iphone16promax_frame.dds",
        -- Aspect ratio of the phone image (portrait)
        aspectRatio  = 9 / 19.5,
        -- Screen content bounds inside phone frame (0-1 of frame dimensions)
        screen = {
            x = 0.058,
            y = 0.042,
            w = 0.884,
            h = 0.886,
        },
        -- Dynamic Island position (top-center of screen) — for decoration only
        notch = { style = "dynamic_island", relX = 0.35, relY = 0.93, relW = 0.30, relH = 0.04 },
        -- Status bar height within screen (relative to screen height)
        statusBarH = 0.055,
    },
    samsung = {
        id           = "samsung",
        displayName  = "Samsung Galaxy S26 Ultra",
        frameTexture = "textures/phones/samsung_s26ultra_frame.dds",
        aspectRatio  = 9 / 19.3,
        screen = {
            x = 0.042,
            y = 0.025,
            w = 0.916,
            h = 0.950,
        },
        notch = { style = "punch_hole", relX = 0.46, relY = 0.96, relW = 0.08, relH = 0.04 },
        statusBarH = 0.045,
    },
}

-- Phone display position on screen (bottom-right, portrait)
-- phoneH drives everything; phoneW is derived from aspectRatio
PhoneModel.PHONE_HEIGHT     = 0.55  -- relative to screen height
PhoneModel.PHONE_MARGIN_X   = 0.025
PhoneModel.PHONE_MARGIN_Y   = 0.02  -- gap above bottom when fully visible

PhoneModel.current  = nil
PhoneModel.overlay  = nil
PhoneModel.modDir   = nil

-- Computed each frame based on animator position
PhoneModel.renderX  = 0
PhoneModel.renderY  = 0
PhoneModel.renderW  = 0
PhoneModel.renderH  = 0

function PhoneModel:init(modDir, modelId)
    self.modDir = modDir
    self:setModel(modelId or "iphone")
end

function PhoneModel:setModel(modelId)
    local model = self.MODELS[modelId]
    if model == nil then
        print("[FarmNotify] Unknown phone model: " .. tostring(modelId) .. " — falling back to iphone")
        model = self.MODELS.iphone
    end
    self.current = model

    if self.overlay ~= nil then
        self.overlay:delete()
        self.overlay = nil
    end

    local texPath = self.modDir .. model.frameTexture
    -- Overlay.new(texturePath, x, y, width, height)
    -- Position/size updated every draw call via overlay:setPosition / overlay:setDimension
    self.overlay = Overlay.new(texPath, 0, 0, 0.1, 0.1)
    if self.overlay == nil then
        print("[FarmNotify] WARNING: Phone texture not found: " .. texPath)
        print("[FarmNotify] Place artist-created DDS file at: " .. texPath)
    end

    print(string.format("[FarmNotify] Phone model: %s", model.displayName))
end

-- Returns phone render rect for given bottom-center Y position (from animator)
function PhoneModel:computeRect(bottomY)
    if self.current == nil then return 0, 0, 0, 0 end

    local h = self.PHONE_HEIGHT
    local w = h * self.current.aspectRatio * (9 / 16)  -- correct for screen AR
    local x = 1.0 - w - self.PHONE_MARGIN_X
    local y = bottomY

    self.renderX = x
    self.renderY = y
    self.renderW = w
    self.renderH = h
    return x, y, w, h
end

-- Returns screen content rect (absolute screen coords) for current render rect
function PhoneModel:getScreenRect()
    if self.current == nil then return 0, 0, 0, 0 end
    local s = self.current.screen
    return
        self.renderX + s.x * self.renderW,
        self.renderY + s.y * self.renderH,
        s.w * self.renderW,
        s.h * self.renderH
end

function PhoneModel:render(bottomY)
    if self.overlay == nil then return end
    local x, y, w, h = self:computeRect(bottomY)
    self.overlay:setPosition(x, y)
    self.overlay:setDimension(w, h)
    self.overlay:render()
end

function PhoneModel:delete()
    if self.overlay ~= nil then
        self.overlay:delete()
        self.overlay = nil
    end
end

function PhoneModel:getModelList()
    local list = {}
    for id, m in pairs(self.MODELS) do
        table.insert(list, { id = id, name = m.displayName })
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end
