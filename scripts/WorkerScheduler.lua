-- WorkerScheduler.lua
-- Assigns workers to prioritized fields, monitors task completion

WorkerScheduler = {}
WorkerScheduler.UPDATE_INTERVAL = 60000 -- ms, re-evaluate every 60s
WorkerScheduler.timer = 0
WorkerScheduler.taskQueue = nil
WorkerScheduler.activeTasks = {}

function WorkerScheduler:init()
    self.taskQueue = PriorityQueue.new()
    self.activeTasks = {}
    self.timer = self.UPDATE_INTERVAL -- trigger immediately on first update
    print("[SmartWorker] WorkerScheduler initialized.")
end

function WorkerScheduler:update(dt)
    self.timer = self.timer + dt
    if self.timer < self.UPDATE_INTERVAL then return end
    self.timer = 0
    self:scheduleTasks()
end

function WorkerScheduler:scheduleTasks()
    local readyFields = FieldAnalyzer:getReadyFields()

    if #readyFields == 0 then return end

    -- Rebuild queue
    self.taskQueue = PriorityQueue.new()
    for _, fieldData in ipairs(readyFields) do
        self.taskQueue:push(fieldData)
    end

    print(string.format("[SmartWorker] %d fields ready for harvest, queued.", #readyFields))

    -- Assign available workers
    self:assignWorkers()
end

function WorkerScheduler:assignWorkers()
    -- Find all hired workers not currently busy
    local freeWorkers = self:getFreeWorkers()

    for _, worker in ipairs(freeWorkers) do
        if self.taskQueue:isEmpty() then break end
        local task = self.taskQueue:pop()
        self:assignWorkerToField(worker, task)
    end
end

function WorkerScheduler:getFreeWorkers()
    local free = {}
    -- LS25: iterate hired helpers via g_hireableVehicleManager or active vehicles
    -- Placeholder — extend with actual hired helper API
    if g_currentMission and g_currentMission.vehicles then
        for _, vehicle in pairs(g_currentMission.vehicles) do
            if vehicle.getIsAIActive and not vehicle:getIsAIActive() then
                if vehicle.startFieldWorker then
                    table.insert(free, vehicle)
                end
            end
        end
    end
    return free
end

function WorkerScheduler:assignWorkerToField(vehicle, fieldData)
    if vehicle == nil or fieldData == nil then return end

    print(string.format("[SmartWorker] Assigning worker to Field %d (%s)",
        fieldData.fieldId, fieldData.fruitName))

    -- LS25 AI field worker activation — extend with actual API calls
    if vehicle.startFieldWorker then
        vehicle:startFieldWorker()
    end

    self.activeTasks[vehicle] = fieldData
end
