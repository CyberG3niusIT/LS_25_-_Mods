-- EventDetector.lua
-- Detects supported in-game events and pushes local-farm notifications.

EventDetector = {}
EventDetector.FIELD_CHECK_INTERVAL   = 30000  -- 30s
EventDetector.VEHICLE_CHECK_INTERVAL = 15000  -- 15s
EventDetector.WEATHER_CHECK_INTERVAL = 60000  -- 60s
EventDetector.SILO_CHECK_INTERVAL    = 30000  -- 30s
EventDetector.FUEL_THRESHOLD         = 0.15   -- 15% propellant remaining
EventDetector.SILO_FULL_THRESHOLD    = 0.999  -- effectively full (matches the notification text)
EventDetector.SILO_RESET_THRESHOLD   = 0.95

EventDetector.fieldTimer   = 0
EventDetector.vehicleTimer = 0
EventDetector.weatherTimer = 0
EventDetector.siloTimer    = 0

-- State tracking
EventDetector.fieldStates  = {} -- fieldId -> {growthState, notifiedReady, notifiedOverdue}
EventDetector.vehicleStates = {} -- vehicle key -> {lastFuelPct}
EventDetector.weatherState = { initialized = false, wasRaining = false }
EventDetector.siloStates   = {} -- silo key -> {notifiedFull, lastFillPct}
EventDetector.activeAIJobs = {} -- job -> stable data captured when the job starts

function EventDetector:init()
    self.fieldStates   = {}
    self.vehicleStates = {}
    self.weatherState  = { initialized = false, wasRaining = false }
    self.siloStates    = {}
    self.activeAIJobs  = {}
    self.fieldTimer    = self.FIELD_CHECK_INTERVAL
    self.vehicleTimer  = self.VEHICLE_CHECK_INTERVAL
    self.weatherTimer  = self.WEATHER_CHECK_INTERVAL
    self.siloTimer     = self.SILO_CHECK_INTERVAL

    -- AI job stop messages carry the real completion reason. Polling
    -- getIsAIActive() cannot distinguish success, an error, and a user stop.
    if g_messageCenter ~= nil then
        g_messageCenter:unsubscribeAll(self)

        if MessageType.AI_JOB_STARTED ~= nil then
            g_messageCenter:subscribe(MessageType.AI_JOB_STARTED, self.onAIJobStarted, self)
        end
        if MessageType.AI_JOB_STOPPED ~= nil then
            g_messageCenter:subscribe(MessageType.AI_JOB_STOPPED, self.onAIJobStopped, self)
        end
    end

    print("[FarmNotify] EventDetector initialized.")
end

function EventDetector:update(dt)
    self.fieldTimer   = self.fieldTimer   + dt
    self.vehicleTimer = self.vehicleTimer + dt
    self.weatherTimer = self.weatherTimer + dt
    self.siloTimer    = self.siloTimer    + dt

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
    if self.siloTimer >= self.SILO_CHECK_INTERVAL then
        self.siloTimer = 0
        self:checkSilos()
    end
end

-- Field events -------------------------------------------------------------

function EventDetector:checkFields()
    local fields = g_fieldManager and g_fieldManager.fields
    local myFarmId = self:_getLocalFarmId()
    if fields == nil or myFarmId == nil then return end

    for _, field in pairs(fields) do
        local fieldId = self:_getFieldId(field)

        if fieldId ~= nil and self:_isFieldOwnedByFarm(field, myFarmId) then
            local fieldState = nil
            if field.getFieldState ~= nil then
                fieldState = field:getFieldState()
            else
                fieldState = field.fieldState
            end

            if fieldState ~= nil and fieldState.isValid then
                local fruitTypeIndex = fieldState.fruitTypeIndex
                local growthState = fieldState.growthState
                local fruitTypeDesc = g_fruitTypeManager and g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
                local state = self.fieldStates[fieldId] or {}

                if fruitTypeDesc ~= nil and fruitTypeIndex ~= FruitType.UNKNOWN and growthState ~= nil then
                    local isWithered = fruitTypeDesc:getIsWithered(growthState)
                    local isHarvestReady = fruitTypeDesc:getIsHarvestReady(growthState)
                    local fruitName = self:_getFruitName(fruitTypeIndex)

                    -- A withered state is no longer harvest-ready. Test it first
                    -- so one scan can never emit both notifications.
                    if isWithered then
                        if not state.notifiedOverdue then
                            state.notifiedOverdue = true
                            state.notifiedReady = false
                            NotificationManager:push(
                                NotificationManager.TYPE.HARVEST_OVERDUE,
                                string.format(g_i18n:getText("farmnotify_harvest_overdue_title"), fieldId),
                                string.format(g_i18n:getText("farmnotify_harvest_overdue_msg"), fruitName),
                                fieldId
                            )
                        end
                    elseif isHarvestReady then
                        if not state.notifiedReady then
                            state.notifiedReady = true
                            state.notifiedOverdue = false
                            NotificationManager:push(
                                NotificationManager.TYPE.HARVEST_READY,
                                string.format(g_i18n:getText("farmnotify_harvest_ready_title"), fieldId),
                                string.format(g_i18n:getText("farmnotify_harvest_ready_msg"), fruitName),
                                fieldId
                            )
                        end
                    else
                        -- Cut, growing, or replanted: arm the next crop cycle.
                        state.notifiedReady = false
                        state.notifiedOverdue = false
                    end

                    state.growthState = growthState
                else
                    state.notifiedReady = false
                    state.notifiedOverdue = false
                    state.growthState = nil
                end

                self.fieldStates[fieldId] = state
            end
        end
    end
end

-- Vehicle fuel events ------------------------------------------------------

function EventDetector:checkVehicles()
    local mission = g_currentMission
    local myFarmId = self:_getLocalFarmId()
    if mission == nil or mission.vehicles == nil or myFarmId == nil then return end

    local seenVehicleKeys = {}

    for _, vehicle in pairs(mission.vehicles) do
        local vehicleFarmId = vehicle.getOwnerFarmId and vehicle:getOwnerFarmId()

        if vehicleFarmId == myFarmId then
            local vehicleKey = tostring(vehicle)
            seenVehicleKeys[vehicleKey] = true

            local fuelPct = self:_getFuelPercentage(vehicle)
            if fuelPct ~= nil then
                local state = self.vehicleStates[vehicleKey] or {}

                if fuelPct <= self.FUEL_THRESHOLD
                    and (state.lastFuelPct == nil or state.lastFuelPct > self.FUEL_THRESHOLD) then
                    local vehicleName = self:_getVehicleName(vehicle)
                    NotificationManager:push(
                        NotificationManager.TYPE.FUEL_LOW,
                        g_i18n:getText("farmnotify_fuel_low_title"),
                        string.format(g_i18n:getText("farmnotify_fuel_low_msg"), vehicleName, math.floor(fuelPct * 100)),
                        nil,
                        vehicleKey
                    )
                end

                state.lastFuelPct = fuelPct
                self.vehicleStates[vehicleKey] = state
            end
        end
    end

    -- Do not retain deleted vehicles forever during a long session.
    for vehicleKey, _ in pairs(self.vehicleStates) do
        if not seenVehicleKeys[vehicleKey] then
            self.vehicleStates[vehicleKey] = nil
        end
    end
end

-- AI worker events ---------------------------------------------------------

function EventDetector:onAIJobStarted(job, startedFarmId)
    if job == nil or startedFarmId ~= self:_getLocalFarmId() then return end

    local vehicle = self:_getAIJobVehicle(job)
    self.activeAIJobs[job] = {
        farmId = startedFarmId,
        vehicle = vehicle,
        vehicleName = self:_getVehicleName(vehicle),
        vehicleKey = vehicle and tostring(vehicle) or tostring(job),
        fieldId = self:_getFieldIdAtVehicle(vehicle)
    }
end

function EventDetector:onAIJobStopped(job, aiMessage)
    if job == nil then return end

    local tracked = self.activeAIJobs[job]
    self.activeAIJobs[job] = nil

    local farmId = tracked and tracked.farmId or job.startedFarmId
    if farmId == nil or farmId ~= self:_getLocalFarmId() then return end

    local vehicle = (tracked and tracked.vehicle) or self:_getAIJobVehicle(job)
    local vehicleName = (tracked and tracked.vehicleName) or self:_getVehicleName(vehicle)
    local vehicleKey = (tracked and tracked.vehicleKey) or (vehicle and tostring(vehicle)) or tostring(job)
    local fieldId = (tracked and tracked.fieldId) or self:_getFieldIdAtVehicle(vehicle)

    local finishedNormally = aiMessage ~= nil
        and AIMessageSuccessFinishedJob ~= nil
        and aiMessage.isa ~= nil
        and aiMessage:isa(AIMessageSuccessFinishedJob)

    local failed = aiMessage ~= nil
        and aiMessage.getType ~= nil
        and AIMessageType ~= nil
        and aiMessage:getType() == AIMessageType.ERROR

    if finishedNormally then
        NotificationManager:push(
            NotificationManager.TYPE.WORKER_DONE,
            g_i18n:getText("farmnotify_worker_done_title"),
            string.format(g_i18n:getText("farmnotify_worker_done_msg"), vehicleName),
            fieldId,
            vehicleKey
        )
    elseif failed then
        NotificationManager:push(
            NotificationManager.TYPE.WORKER_STUCK,
            g_i18n:getText("farmnotify_worker_stuck_title"),
            string.format(g_i18n:getText("farmnotify_worker_stuck_msg"), vehicleName),
            fieldId,
            vehicleKey
        )
    end
    -- Successful user stops and other informational endings are intentionally
    -- ignored: they are neither a completed task nor a failure.
end

-- Weather events -----------------------------------------------------------

function EventDetector:checkWeather()
    local environment = g_currentMission and g_currentMission.environment
    local weather = environment and environment.weather
    if weather == nil or weather.getIsRaining == nil then return end

    local isRaining = weather:getIsRaining()

    -- The first scan establishes a baseline. Loading a save while it already
    -- rains is not the same as rain starting during this session.
    if not self.weatherState.initialized then
        self.weatherState.initialized = true
        self.weatherState.wasRaining = isRaining
        return
    end

    if isRaining and not self.weatherState.wasRaining then
        local title = g_i18n:getText("farmnotify_weather_rain_title")
        NotificationManager:push(
            NotificationManager.TYPE.WEATHER_RAIN,
            title,
            title,
            nil
        )
    end

    self.weatherState.wasRaining = isRaining

    -- FS25 exposes a reliable rain predicate here, but no verified generic
    -- "storm" predicate. Do not invent storms from an arbitrary wind value.
end

-- Silo events --------------------------------------------------------------

function EventDetector:checkSilos()
    local mission = g_currentMission
    local placeableSystem = mission and mission.placeableSystem
    local myFarmId = self:_getLocalFarmId()
    if placeableSystem == nil or placeableSystem.getPlaceables == nil or myFarmId == nil then return end

    local placeables = placeableSystem:getPlaceables()
    if placeables == nil then return end

    for _, placeable in pairs(placeables) do
        local silo = placeable.spec_silo

        if silo ~= nil and silo.storages ~= nil then
            local placeableFarmId = placeable.getOwnerFarmId and placeable:getOwnerFarmId()
            local isRelevantSilo = silo.storagePerFarm or placeableFarmId == myFarmId

            if isRelevantSilo then
                local totalLevel = 0
                local totalCapacity = 0

                for _, storage in ipairs(silo.storages) do
                    local storageFarmId = nil
                    if storage.getOwnerFarmId ~= nil then
                        storageFarmId = storage:getOwnerFarmId()
                    else
                        storageFarmId = storage.ownerFarmId
                    end

                    if not silo.storagePerFarm or storageFarmId == myFarmId then
                        local level, capacity = self:_getStorageUsage(storage)
                        totalLevel = totalLevel + level
                        totalCapacity = totalCapacity + capacity
                    end
                end

                if totalCapacity > 0 then
                    local fillPct = math.min(totalLevel / totalCapacity, 1)
                    local siloKey = tostring(placeable) .. "|" .. tostring(myFarmId)
                    local state = self.siloStates[siloKey] or {}

                    if fillPct >= self.SILO_FULL_THRESHOLD and not state.notifiedFull then
                        state.notifiedFull = true
                        local siloName = nil
                        if placeable.getName ~= nil then
                            siloName = placeable:getName()
                        end
                        if siloName == nil or siloName == "" then
                            siloName = g_i18n:getText("farmnotify_silo_full_title")
                        end

                        NotificationManager:push(
                            NotificationManager.TYPE.SILO_FULL,
                            g_i18n:getText("farmnotify_silo_full_title"),
                            string.format(g_i18n:getText("farmnotify_silo_full_msg"), siloName),
                            nil
                        )
                    elseif fillPct < self.SILO_RESET_THRESHOLD then
                        state.notifiedFull = false
                    end

                    state.lastFillPct = fillPct
                    self.siloStates[siloKey] = state
                end
            end
        end
    end
end

-- Helpers ------------------------------------------------------------------

function EventDetector:_getLocalFarmId()
    local mission = g_currentMission
    if mission == nil then return nil end

    local farmId = nil
    if mission.getFarmId ~= nil then
        farmId = mission:getFarmId()
    elseif g_localPlayer ~= nil then
        farmId = g_localPlayer.farmId
    end

    if farmId == nil or farmId <= 0 then return nil end
    return farmId
end

function EventDetector:_getFieldId(field)
    if field == nil then return nil end
    if field.getId ~= nil then return field:getId() end
    return field.fieldId
end

function EventDetector:_isFieldOwnedByFarm(field, farmId)
    if field == nil or farmId == nil or g_farmlandManager == nil then return false end

    local farmland = nil
    if field.getFarmland ~= nil then
        farmland = field:getFarmland()
    else
        farmland = field.farmland
    end

    local farmlandId = farmland and farmland.id
    if farmlandId == nil or g_farmlandManager.getFarmlandOwner == nil then return false end
    return g_farmlandManager:getFarmlandOwner(farmlandId) == farmId
end

function EventDetector:_getFruitName(fruitTypeIndex)
    if g_fruitTypeManager == nil then return "Unknown crop" end
    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    if fruitDesc == nil then return "Unknown crop" end

    if fruitDesc.fillType ~= nil and g_fillTypeManager ~= nil then
        local fillDesc = g_fillTypeManager:getFillTypeByIndex(fruitDesc.fillType)
        if fillDesc ~= nil and fillDesc.title ~= nil then
            return fillDesc.title
        end
    end

    return fruitDesc.name or "Crop"
end

function EventDetector:_getVehicleName(vehicle)
    if vehicle ~= nil and vehicle.getFullName ~= nil then
        local name = vehicle:getFullName()
        if name ~= nil and name ~= "" then return name end
    end
    return "Vehicle"
end

function EventDetector:_getFuelPercentage(vehicle)
    if vehicle == nil
        or vehicle.getConsumerFillUnitIndex == nil
        or vehicle.getFillUnitFillLevelPercentage == nil then
        return nil
    end

    local propellantTypes = {}
    if FillType ~= nil then
        if FillType.DIESEL ~= nil then table.insert(propellantTypes, FillType.DIESEL) end
        if FillType.ELECTRICCHARGE ~= nil then table.insert(propellantTypes, FillType.ELECTRICCHARGE) end
        if FillType.METHANE ~= nil then table.insert(propellantTypes, FillType.METHANE) end
    end

    local lowestPct = nil
    local checkedUnits = {}

    for _, fillTypeIndex in ipairs(propellantTypes) do
        local fillUnitIndex = vehicle:getConsumerFillUnitIndex(fillTypeIndex)
        if fillUnitIndex ~= nil and not checkedUnits[fillUnitIndex] then
            checkedUnits[fillUnitIndex] = true
            local pct = vehicle:getFillUnitFillLevelPercentage(fillUnitIndex)
            if pct ~= nil and (lowestPct == nil or pct < lowestPct) then
                lowestPct = pct
            end
        end
    end

    return lowestPct
end

function EventDetector:_getAIJobVehicle(job)
    local parameter = job and job.vehicleParameter
    if parameter ~= nil and parameter.getVehicle ~= nil then
        return parameter:getVehicle()
    end

    if job ~= nil and job.getNamedParameter ~= nil then
        parameter = job:getNamedParameter("vehicle")
        if parameter ~= nil and parameter.getVehicle ~= nil then
            return parameter:getVehicle()
        end
    end

    return nil
end

function EventDetector:_getFieldIdAtVehicle(vehicle)
    if vehicle == nil or vehicle.rootNode == nil
        or g_farmlandManager == nil or g_fieldManager == nil then
        return nil
    end

    local ok, x, _, z = pcall(getWorldTranslation, vehicle.rootNode)
    if not ok or x == nil then return nil end

    local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
    local mapping = g_fieldManager.farmlandIdFieldMapping
    local field = mapping and mapping[farmlandId]
    return self:_getFieldId(field)
end

function EventDetector:_getStorageUsage(storage)
    if storage == nil or storage.getFillLevels == nil then return 0, 0 end

    local fillLevels = storage:getFillLevels()
    if fillLevels == nil then return 0, 0 end

    local totalLevel = 0
    local totalCapacity = 0

    if storage.supportsMultipleFillTypes then
        local sharedLevel = 0
        local sharedFillType = nil

        for fillTypeIndex, fillLevel in pairs(fillLevels) do
            local specificCapacity = storage.capacities and storage.capacities[fillTypeIndex]
            if specificCapacity ~= nil then
                totalLevel = totalLevel + (fillLevel or 0)
                totalCapacity = totalCapacity + specificCapacity
            else
                sharedLevel = sharedLevel + (fillLevel or 0)
                sharedFillType = sharedFillType or fillTypeIndex
            end
        end

        if sharedFillType ~= nil then
            local sharedCapacity = nil
            if storage.getCapacity ~= nil then
                sharedCapacity = storage:getCapacity(sharedFillType)
            end
            sharedCapacity = sharedCapacity or storage.capacity or 0
            totalLevel = totalLevel + sharedLevel
            totalCapacity = totalCapacity + sharedCapacity
        end
    else
        -- A single-fill storage may advertise many fill types, but only the
        -- currently occupied type consumes its capacity.
        local activeFillType = nil
        for fillTypeIndex, fillLevel in pairs(fillLevels) do
            if fillLevel ~= nil and fillLevel > 0 then
                activeFillType = fillTypeIndex
                totalLevel = totalLevel + fillLevel
            end
        end

        if activeFillType ~= nil then
            if storage.getCapacity ~= nil then
                totalCapacity = storage:getCapacity(activeFillType) or 0
            else
                totalCapacity = storage.capacity or 0
            end
        end
    end

    return totalLevel, totalCapacity
end
