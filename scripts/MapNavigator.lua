-- MapNavigator.lua
-- Opens the in-game map and centers it on a field. Never teleports the player.

MapNavigator = {}
MapNavigator.NAV_RETRY_INTERVAL = 100
MapNavigator.NAV_MAX_ATTEMPTS = 20

function MapNavigator:init()
    self._pendingNavigation = nil
    print("[FarmNotify] MapNavigator initialized.")
end

function MapNavigator:navigateToField(fieldId)
    if fieldId == nil then
        print("[FarmNotify] MapNavigator: no fieldId provided.")
        return false
    end

    if g_fieldManager == nil then
        print("[FarmNotify] MapNavigator: g_fieldManager not available.")
        return false
    end

    local field = nil
    if g_fieldManager.getFieldById ~= nil then
        field = g_fieldManager:getFieldById(fieldId)
    end

    if field == nil and g_fieldManager.fields ~= nil then
        for _, candidate in pairs(g_fieldManager.fields) do
            local candidateId = candidate.getId and candidate:getId() or candidate.fieldId
            if candidateId == fieldId then
                field = candidate
                break
            end
        end
    end

    if field == nil then
        print("[FarmNotify] MapNavigator: Field " .. tostring(fieldId) .. " not found.")
        return false
    end

    local x, z = self:_getFieldCenter(field)
    if x == nil then
        print("[FarmNotify] MapNavigator: Could not determine field position.")
        return false
    end

    print(string.format("[FarmNotify] Opening map for Field %s at (%.1f, %.1f)", tostring(fieldId), x, z))

    if g_gui == nil or g_inGameMenu == nil then
        print("[FarmNotify] MapNavigator: In-game map UI is not available; navigation cancelled safely.")
        return false
    end

    self._pendingNavigation = {
        fieldId = fieldId,
        x = x,
        z = z,
        timer = 0,
        attempts = 0
    }

    if not g_inGameMenu.isOpen then
        g_gui:showGui("InGameMenu")
    end

    -- The menu and its map page become active asynchronously. update() will
    -- switch to the overview page and pan as soon as all GUI elements exist.
    return true
end

function MapNavigator:update(dt)
    local pending = self._pendingNavigation
    if pending == nil then return end

    pending.timer = pending.timer - dt
    if pending.timer > 0 then return end

    pending.timer = self.NAV_RETRY_INTERVAL
    pending.attempts = pending.attempts + 1

    if self:_focusMapPosition(pending.x, pending.z) then
        self._pendingNavigation = nil
    elseif pending.attempts >= self.NAV_MAX_ATTEMPTS then
        print("[FarmNotify] MapNavigator: Map could not be focused; no player position was changed.")
        self._pendingNavigation = nil
    end
end

function MapNavigator:_focusMapPosition(x, z)
    local menu = g_inGameMenu
    if menu == nil or not menu.isOpen then return false end

    local page = menu.pageMapOverview
    if page == nil then return false end

    if menu.currentPage ~= page and menu.pagingElement ~= nil then
        local mappingIndex = nil
        if menu.pagingElement.getPageMappingIndexByElement ~= nil then
            mappingIndex = menu.pagingElement:getPageMappingIndexByElement(page)
        end
        if mappingIndex ~= nil and menu.pagingElement.setPage ~= nil then
            menu.pagingElement:setPage(mappingIndex)
        end
    end

    local mapElement = page.ingameMap
    if mapElement == nil or mapElement.panToHotspot == nil or mapElement.ingameMap == nil then
        return false
    end

    -- panToHotspot only needs getWorldPosition(). A tiny transient target lets
    -- us center on the exact field label position without registering a fake
    -- hotspot in the game's map or changing world state.
    local target = {
        worldX = x,
        worldZ = z,
        getWorldPosition = function(self)
            return self.worldX, self.worldZ
        end
    }

    mapElement:panToHotspot(target)
    return true
end

function MapNavigator:_getFieldCenter(field)
    if field.getCenterOfFieldWorldPosition ~= nil then
        local x, z = field:getCenterOfFieldWorldPosition()
        if x ~= nil and z ~= nil then return x, z end
    end

    local points = nil
    if field.getPolygonPoints ~= nil then
        points = field:getPolygonPoints()
    else
        points = field.polygonPoints
    end

    if points == nil then return nil end

    local sumX = 0
    local sumZ = 0
    local count = 0

    for _, point in ipairs(points) do
        local ok, x, _, z = pcall(getWorldTranslation, point)
        if ok and x ~= nil then
            sumX = sumX + x
            sumZ = sumZ + z
            count = count + 1
        end
    end

    if count == 0 then return nil end
    return sumX / count, sumZ / count
end
