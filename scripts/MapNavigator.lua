-- MapNavigator.lua
-- Navigates the in-game map/world to a specific field when player taps a notification

MapNavigator = {}

function MapNavigator:init()
    print("[FarmNotify] MapNavigator initialized.")
end

-- Navigate to fieldId: opens map and centers on field if possible,
-- otherwise teleports camera above field center
function MapNavigator:navigateToField(fieldId)
    if fieldId == nil then
        print("[FarmNotify] MapNavigator: no fieldId provided.")
        return
    end

    local field = g_fieldManager:getFieldByIndex(fieldId)
    if field == nil then
        -- Some versions use getFields() and iterate
        if g_fieldManager.getFields then
            for _, f in pairs(g_fieldManager:getFields()) do
                if f:getFieldId() == fieldId then
                    field = f
                    break
                end
            end
        end
    end

    if field == nil then
        print("[FarmNotify] MapNavigator: Field " .. fieldId .. " not found.")
        return
    end

    local x, y, z = field:getFieldPosition()
    if x == nil then
        -- Fallback: field center from polygon
        x, y, z = self:_getFieldCenter(field)
    end

    if x == nil then
        print("[FarmNotify] MapNavigator: Could not determine field position.")
        return
    end

    print(string.format("[FarmNotify] Navigating to Field %d at (%.1f, %.1f, %.1f)", fieldId, x, y or 0, z))

    -- Try to open in-game map and focus
    if g_currentMission and g_currentMission.inGameMenu then
        local ingameMap = g_currentMission.inGameMenu.ingameMap
        if ingameMap and ingameMap.setMapPosition then
            -- Open the pause menu map
            g_currentMission.inGameMenu:setIsOpen(true)
            -- Small delay hack: set position after menu opens
            -- We use a deferred action
            MapNavigator._pendingNavX = x
            MapNavigator._pendingNavZ = z
            MapNavigator._pendingNavTimer = 300  -- ms
            return
        end
    end

    -- Fallback: move camera directly to field
    self:_moveCameraToWorld(x, y, z)
end

function MapNavigator:update(dt)
    if self._pendingNavTimer and self._pendingNavTimer > 0 then
        self._pendingNavTimer = self._pendingNavTimer - dt
        if self._pendingNavTimer <= 0 then
            self._pendingNavTimer = nil
            self:_moveCameraToWorld(self._pendingNavX, 0, self._pendingNavZ)
        end
    end
end

function MapNavigator:_moveCameraToWorld(x, y, z)
    if g_currentMission == nil then return end
    local camera = g_currentMission.controlledVehicle == nil
                   and g_currentMission.player
                   or nil
    if camera and camera.setPosition then
        local groundY = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) or 0
        camera:setPosition(x, groundY + 2, z)
    elseif g_currentMission.cameraSystem then
        -- Spectator/free camera
        local sys = g_currentMission.cameraSystem
        if sys.setTargetPosition then
            sys:setTargetPosition(x, y or 0, z)
        end
    end
end

function MapNavigator:_getFieldCenter(field)
    -- Average of field polygon points
    if field.fieldDimensions == nil then return nil end
    local count = getNumOfChildren(field.fieldDimensions)
    if count == 0 then return nil end
    local sumX, sumZ = 0, 0
    for i = 0, count - 1 do
        local child = getChildAt(field.fieldDimensions, i)
        local cx, cy, cz = getWorldTranslation(child)
        sumX = sumX + cx
        sumZ = sumZ + cz
    end
    local cx = sumX / count
    local cz = sumZ / count
    local cy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, cx, 0, cz) or 0
    return cx, cy, cz
end
