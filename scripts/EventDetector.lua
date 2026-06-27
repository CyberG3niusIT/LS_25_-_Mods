-- EventDetector.lua
-- Detects all in-game events and pushes notifications

EventDetector = {}
EventDetector.FIELD_CHECK_INTERVAL   = 30000  -- 30s
EventDetector.VEHICLE_CHECK_INTERVAL = 15000  -- 15s
EventDetector.WEATHER_CHECK_INTERVAL = 60000  -- 60s
EventDetector.FUEL_THRESHOLD         = 0.15   -- 15% tank

EventDetector.fieldTimer   = 0
EventDetector.vehicleTimer = 0
EventDetector.weatherTimer = 0

-- State tracking
EventDetector.fieldStates   = {}  -- fieldId -> { growthState, notifiedReady, notifiedOverdue }
EventDetector.vehicleStates = {}  -- vehicleName -> { wasWorking, lastFuelPct }
EventDetector.weatherState  = { wasRaining = false, wasStorming = false }

function EventDetector:init()
    self.fieldStates   = {}
    self.vehicleStates = {}
    self.weatherState  = { wasRaining = false, wasStorming = false }
    self.fieldTimer    = self.FIELD_CHECK_INTERVAL
    self.vehicleTimer  = self.VEHICLE_CHECK_INTERVAL
    self.weatherTimer  = self.WEATHER_CHECK_INTERVAL
    print("[FarmNotify] EventDetector initialized.")
end

function EventDetector:update(dt)
    self.fieldTimer   = self.fieldTimer   + dt
    self.vehicleTimer = self.vehicleTimer + dt
    self.weatherTimer = self.weatherTimer + dt

    if self.fieldTimer >= self.FIELD_CHECK_INTERVAL then
        self.fieldTimer = 0
        self:checkFields()
    end
    if self.vehicleTimer >= self.VEHICLE_CHECK_INTERVAL then
        self.vehicleTimer = 0
        self:checkVehicles()
    end
    if self.weatherTimer >= self.WEATHER_CHECK_INTERVAL then
        self.weatherTimer = 0
        self:checkWeather()
    end
end

-- ─── Field Events ──────────────────────────────────────────────────────────

function EventDetector:checkFields()
    if g_fieldManager == nil then return end

    for _, field in pairs(g_fieldManager:getFields()) do
        local fieldId   = field:getFieldId()
        local fruitType = field:getFruitType()

        if fruitType ~= nil and fruitType ~= FruitType.UNKNOWN then
            local growthState = field:getFruitGrowthState()
            local maxState    = field:getFruitMaxGrowthState()
            local fruitName   = self:_getFruitName(fruitType)
            local state       = self.fieldStates[fieldId] or {}

            -- Harvest ready
            if growthState >= maxState and not state.notifiedReady then
                state.notifiedReady   = true
                state.notifiedOverdue = false
                NotificationManager:push(
                    NotificationManager.TYPE.HARVEST_READY,
                    string.format(g_i18n:getText("farmnotify_harvest_ready_title"), fieldId),
                    string.format(g_i18n:getText("farmnotify_harvest_ready_msg"), fruitName),
                    fieldId
                )
            end

            -- Harvest overdue (growth > max+1 = wilting in LS25)
            if growthState > maxState + 1 and not state.notifiedOverdue then
                state.notifiedOverdue = true
                NotificationManager:push(
                    NotificationManager.TYPE.HARVEST_OVERDUE,
                    string.format(g_i18n:getText("farmnotify_harvest_overdue_title"), fieldId),
                    string.format(g_i18n:getText("farmnotify_harvest_overdue_msg"), fruitName),
                    fieldId
                )
            end

            -- Reset if replanted
            if growthState < maxState - 1 then
                state.notifiedReady   = false
                state.notifiedOverdue = false
            end

            state.growthState      = growthState
            self.fieldStates[fieldId] = state
        else
            -- Field empty — reset
            if self.fieldStates[fieldId] then
                self.fieldStates[fieldId].notifiedReady   = false
                self.fieldStates[fieldId].notifiedOverdue = false
            end
        end
    end
end

-- ─── Vehicle / Worker Events ───────────────────────────────────────────────

function EventDetector:checkVehicles()
    if g_currentMission == nil or g_currentMission.vehicles == nil then return end

    for _, vehicle in pairs(g_currentMission.vehicles) do
        local name = tostring(vehicle)

        -- Fuel check (vehicles with fillUnits)
        if vehicle.getFillUnitFillLevel and vehicle.getFillUnitCapacity then
            local fuelUnitIdx = self:_getFuelUnitIndex(vehicle)
            if fuelUnitIdx ~= nil then
                local level    = vehicle:getFillUnitFillLevel(fuelUnitIdx)
                local capacity = vehicle:getFillUnitCapacity(fuelUnitIdx)
                if capacity > 0 then
                    local pct = level / capacity
                    local state = self.vehicleStates[name] or {}

                    if pct <= self.FUEL_THRESHOLD and (state.lastFuelPct == nil or state.lastFuelPct > self.FUEL_THRESHOLD) then
                        local vName = vehicle:getFullName() or "Fahrzeug"
                        NotificationManager:push(
                            NotificationManager.TYPE.FUEL_LOW,
                            g_i18n:getText("farmnotify_fuel_low_title"),
                            string.format(g_i18n:getText("farmnotify_fuel_low_msg"), vName, math.floor(pct * 100)),
                            nil, name
                        )
                    end
                    state.lastFuelPct = pct
                    self.vehicleStates[name] = state
                end
            end
        end

        -- Worker done / stuck
        if vehicle.getIsAIActive then
            local state = self.vehicleStates[name] or {}
            local isWorking = vehicle:getIsAIActive()

            if state.wasWorking and not isWorking then
                -- Worker just stopped
                local vName = vehicle:getFullName() or "Helfer"
                -- Distinguish done vs stuck via last known state
                if state.workerFinishedNormally then
                    NotificationManager:push(
                        NotificationManager.TYPE.WORKER_DONE,
                        g_i18n:getText("farmnotify_worker_done_title"),
                        string.format(g_i18n:getText("farmnotify_worker_done_msg"), vName),
                        state.workerFieldId, name
                    )
                else
                    NotificationManager:push(
                        NotificationManager.TYPE.WORKER_STUCK,
                        g_i18n:getText("farmnotify_worker_stuck_title"),
                        string.format(g_i18n:getText("farmnotify_worker_stuck_msg"), vName),
                        state.workerFieldId, name
                    )
                end
            end

            -- Hook worker finish callback if available
            if isWorking and not state.wasWorking then
                state.workerFieldId = nil
                if vehicle.aiFieldWorker and vehicle.aiFieldWorker.lastFieldId then
                    state.workerFieldId = vehicle.aiFieldWorker.lastFieldId
                end
            end

            state.wasWorking = isWorking
            self.vehicleStates[name] = state
        end
    end
end

-- ─── Weather Events ────────────────────────────────────────────────────────

function EventDetector:checkWeather()
    local env = g_currentMission and g_currentMission.environment
    if env == nil then return end

    -- LS25 weather API: env.weather
    local weather = env.weather
    if weather == nil then return end

    -- Rain check
    local isRaining = false
    local isStorming = false

    if weather.getIsRaining then
        isRaining = weather:getIsRaining()
    elseif weather.isRaining ~= nil then
        isRaining = weather.isRaining
    end

    -- Storm / thunder (strong wind + rain)
    if env.windSpeed and env.windSpeed > 15 and isRaining then
        isStorming = true
    end

    if isRaining and not self.weatherState.wasRaining then
        NotificationManager:push(
            NotificationManager.TYPE.WEATHER_RAIN,
            g_i18n:getText("farmnotify_weather_rain_title"),
            g_i18n:getText("farmnotify_weather_rain_msg"),
            nil
        )
    end

    if isStorming and not self.weatherState.wasStorming then
        NotificationManager:push(
            NotificationManager.TYPE.WEATHER_STORM,
            g_i18n:getText("farmnotify_weather_storm_title"),
            g_i18n:getText("farmnotify_weather_storm_msg"),
            nil
        )
    end

    self.weatherState.wasRaining  = isRaining
    self.weatherState.wasStorming = isStorming
end

-- ─── Helpers ──────────────────────────────────────────────────────────────

function EventDetector:_getFruitName(fruitTypeIndex)
    if g_fruitTypeManager == nil then return "Unbekannte Frucht" end
    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    if fruitDesc == nil then return "Unbekannte Frucht" end
    if fruitDesc.fillType and g_fillTypeManager then
        local fillDesc = g_fillTypeManager:getFillTypeByIndex(fruitDesc.fillType)
        if fillDesc and fillDesc.title then
            return fillDesc.title
        end
    end
    return fruitDesc.name or "Frucht"
end

function EventDetector:_getFuelUnitIndex(vehicle)
    if vehicle.getFillUnits == nil then return nil end
    local units = vehicle:getFillUnits()
    if units == nil then return nil end
    for idx, unit in ipairs(units) do
        local fillType = unit.fillType
        if fillType == FillType.DIESEL or fillType == FillType.DEF or fillType == FillType.ELECTRICCHARGE then
            return idx
        end
    end
    return nil
end
