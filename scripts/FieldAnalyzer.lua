-- FieldAnalyzer.lua
-- Scans all fields, calculates harvest readiness and priority score

FieldAnalyzer = {}
FieldAnalyzer.fields = {}

function FieldAnalyzer:init()
    self.fields = {}
    print("[SmartWorker] FieldAnalyzer initialized.")
end

-- Returns list of fields with readiness data, sorted by priority
function FieldAnalyzer:analyze()
    self.fields = {}

    if g_farmlandManager == nil or g_fieldManager == nil then
        return self.fields
    end

    for _, field in pairs(g_fieldManager:getFields()) do
        local data = self:evaluateField(field)
        if data ~= nil then
            table.insert(self.fields, data)
        end
    end

    -- Sort: highest priority first
    table.sort(self.fields, function(a, b)
        return a.priority > b.priority
    end)

    return self.fields
end

function FieldAnalyzer:evaluateField(field)
    if field == nil then return nil end

    local fruitType = field:getFruitType()
    if fruitType == nil or fruitType == FruitType.UNKNOWN then return nil end

    local growthState = field:getFruitGrowthState()
    local maxState = field:getFruitMaxGrowthState()
    local isHarvestReady = (growthState >= maxState)

    -- Priority score: ready fields get high base, others get 0
    local priority = 0
    if isHarvestReady then
        priority = 100
        -- Bonus if fruit will wilt soon (state > max)
        if growthState > maxState then
            priority = priority + 50
        end
    end

    return {
        field = field,
        fieldId = field:getFieldId(),
        fruitType = fruitType,
        fruitName = g_fruitTypeManager:getFruitTypeByIndex(fruitType) and
                    g_fruitTypeManager:getFruitTypeByIndex(fruitType).name or "Unknown",
        growthState = growthState,
        maxGrowthState = maxState,
        isHarvestReady = isHarvestReady,
        priority = priority
    }
end

function FieldAnalyzer:getReadyFields()
    local all = self:analyze()
    local ready = {}
    for _, data in ipairs(all) do
        if data.isHarvestReady then
            table.insert(ready, data)
        end
    end
    return ready
end
