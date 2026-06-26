-- FieldMonitor.lua
-- Polls field growth states and fires notifications on state changes

FieldMonitor = {}
FieldMonitor.CHECK_INTERVAL = 30000 -- ms, check every 30s
FieldMonitor.timer = 0
FieldMonitor.knownStates = {} -- fieldId -> last known growthState

function FieldMonitor:init()
    self.timer = self.CHECK_INTERVAL
    self.knownStates = {}
    print("[FarmNotify] FieldMonitor initialized.")
end

function FieldMonitor:update(dt)
    self.timer = self.timer + dt
    if self.timer < self.CHECK_INTERVAL then return end
    self.timer = 0
    self:checkFields()
end

function FieldMonitor:checkFields()
    if g_fieldManager == nil then return end

    for _, field in pairs(g_fieldManager:getFields()) do
        self:evaluateField(field)
    end
end

function FieldMonitor:evaluateField(field)
    if field == nil then return end

    local fieldId = field:getFieldId()
    local fruitType = field:getFruitType()

    if fruitType == nil or fruitType == FruitType.UNKNOWN then
        self.knownStates[fieldId] = nil
        return
    end

    local growthState = field:getFruitGrowthState()
    local maxState = field:getFruitMaxGrowthState()
    local lastState = self.knownStates[fieldId]

    -- Transition INTO harvest-ready
    if growthState >= maxState and (lastState == nil or lastState < maxState) then
        local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitType)
        local fruitName = fruitDesc and fruitDesc.fillType and
                          g_fillTypeManager:getFillTypeByIndex(fruitDesc.fillType) and
                          g_fillTypeManager:getFillTypeByIndex(fruitDesc.fillType).title or "Frucht"

        NotificationManager:push(
            NotificationManager.TYPE.HARVEST_READY,
            string.format("Feld %d erntereif", fieldId),
            string.format("%s kann jetzt geerntet werden.", fruitName),
            fieldId
        )
    end

    -- Transition INTO wilting (overgrown past max)
    if growthState > maxState + 1 and (lastState == nil or lastState <= maxState + 1) then
        NotificationManager:push(
            NotificationManager.TYPE.HARVEST_ALERT,
            string.format("Feld %d — Ernte überfällig!", fieldId),
            "Frucht droht zu verwelken. Sofort ernten!",
            fieldId
        )
    end

    self.knownStates[fieldId] = growthState
end
