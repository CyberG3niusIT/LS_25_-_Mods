-- PhoneModel.lua
-- Manages phone frame overlays for iPhone 16 Pro Max and Samsung Galaxy S26 Ultra.

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
        frameTexture = "textures/phones/iphone16promax_frame.png",
        aspectRatio  = 9 / 19.5,
        screen = {
            x = 0.080,
            y = 0.040,
            w = 0.840,
            h = 0.920,
        },
        notch = { style = "dynamic_island", relX = 0.35, relY = 0.93, relW = 0.30, relH = 0.04 },
        statusBarH = 0.050,
    },
    samsung = {
        id           = "samsung",
        displayName  = "Samsung Galaxy S26 Ultra",
        frameTexture = "textures/phones/samsung_s26ultra_frame.png",
        aspectRatio  = 9 / 19.3,
        screen = {
            x = 0.066,
            y = 0.033,
            w = 0.867,
            h = 0.934,
        },
        notch = { style = "punch_hole", relX = 0.46, relY = 0.96, relW = 0.08, relH = 0.04 },
        statusBarH = 0.042,
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

local function getViewportAspectRatio()
    if type(g_screenAspectRatio) == "number" and g_screenAspectRatio > 0 then
        return g_screenAspectRatio
    end
    if type(g_screenWidth) == "number" and type(g_screenHeight) == "number" and g_screenHeight > 0 then
        return g_screenWidth / g_screenHeight
    end
    return 16 / 9
end

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

    if self.modDir == nil then
        print("[FarmNotify] WARNING: Phone model initialized without a mod directory.")
        return false
    end

    local texPath = self.modDir .. model.frameTexture
    -- Overlay.new(texturePath, x, y, width, height)
    -- Position/size updated every draw call via overlay:setPosition / overlay:setDimension
    local textureExists = fileExists == nil or fileExists(texPath)
    if textureExists and Overlay ~= nil and Overlay.new ~= nil then
        self.overlay = Overlay.new(texPath, 0, 0, 0.1, 0.1)
    end
    if self.overlay == nil or (self.overlay.overlayId ~= nil and self.overlay.overlayId == 0) then
        if self.overlay ~= nil then
            self.overlay:delete()
            self.overlay = nil
        end
        print("[FarmNotify] WARNING: Phone texture not found: " .. texPath)
        print("[FarmNotify] Using the built-in fallback frame.")
    end

    print(string.format("[FarmNotify] Phone model: %s", model.displayName))
    return true
end

-- Returns phone render rect for given bottom-center Y position (from animator)
function PhoneModel:computeRect(bottomY)
    if self.current == nil then return 0, 0, 0, 0 end

    local viewportAspect = getViewportAspectRatio()
    local h = math.max(0.1, math.min(0.95, self.PHONE_HEIGHT))
    local w = h * self.current.aspectRatio / viewportAspect
    local maxW = math.max(0.1, 1.0 - 2 * self.PHONE_MARGIN_X)
    if w > maxW then
        local scale = maxW / w
        w = maxW
        h = h * scale
    end
    local x = 1.0 - w - self.PHONE_MARGIN_X
    local y = tonumber(bottomY) or -h

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

function PhoneModel:getRenderRect()
    return self.renderX, self.renderY, self.renderW, self.renderH
end

function PhoneModel:render(bottomY)
    local x, y, w, h = self:computeRect(bottomY)
    if self.overlay ~= nil then
        self.overlay:setPosition(x, y)
        self.overlay:setDimension(w, h)
        self.overlay:render()
    elseif drawFilledRect ~= nil then
        -- Keep the UI usable even if a texture cannot be loaded.
        drawFilledRect(x, y, w, h, 0.015, 0.015, 0.02, 0.98)
    end
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
