-- SoundController.lua
-- Plays notification sounds — event-specific WAV primary, phone-specific WAV override

SoundController = {}
SoundController.modDir  = nil
SoundController.volume  = 0.8
SoundController.samples = {}

-- Event-type → dedicated WAV file (all generated, copyright-free)
SoundController.EVENT_WAV = {
    harvest_ready   = "sounds/notify_harvest.wav",
    harvest_overdue = "sounds/notify_urgent.wav",
    worker_done     = "sounds/notify_done.wav",
    worker_stuck    = "sounds/notify_alert.wav",
    fuel_low        = "sounds/notify_alert.wav",
    silo_full       = "sounds/notify_info.wav",
    weather_rain    = "sounds/notify_weather.wav",
    weather_storm   = "sounds/notify_urgent.wav",
}
SoundController.DEFAULT_WAV = "sounds/notify_default.wav"

-- Phone-specific WAV overrides (CC0, Kenney Interface Sounds — see sounds/custom/LICENSE.txt)
SoundController.PHONE_SOUNDS_OPTIONAL = {
    iphone  = { message = "sounds/custom/iphone_message.wav",  ringtone = "sounds/custom/iphone_ringtone.wav"  },
    samsung = { message = "sounds/custom/samsung_message.wav", ringtone = "sounds/custom/samsung_ringtone.wav" },
}

-- Which events count as "ringtone" category for phone-specific override
SoundController.URGENT_EVENTS = {
    harvest_overdue = true,
    worker_stuck    = true,
    weather_storm   = true,
}

function SoundController:init(modDir, volume)
    self.modDir  = modDir
    self.volume  = volume or 0.8
    self.samples = {}
    self:_loadAll()
    print("[FarmNotify] SoundController initialized.")
end

function SoundController:_loadAll()
    -- Load per-event WAV files
    self.samples.event = {}
    for eventType, file in pairs(self.EVENT_WAV) do
        if self.samples.event[file] == nil then
            self.samples.event[file] = self:_loadFile("wav_" .. eventType, file)
        end
    end
    self.samples.default = self:_loadFile("wav_default", self.DEFAULT_WAV)

    -- Try loading optional phone-specific WAV overrides (silent on failure)
    self.samples.phone = {}
    for modelId, files in pairs(self.PHONE_SOUNDS_OPTIONAL) do
        self.samples.phone[modelId] = {}
        for soundType, file in pairs(files) do
            local sample = self:_loadFileOptional(modelId .. "_" .. soundType, file)
            self.samples.phone[modelId][soundType] = sample
        end
    end
end

function SoundController:_loadFile(key, relPath)
    local path   = self.modDir .. relPath
    local sample = createSample(key)
    if sample == nil or sample == 0 then
        print("[FarmNotify] createSample failed: " .. key)
        return nil
    end
    if loadSample(sample, path, false) then
        return sample
    else
        print("[FarmNotify] Could not load: " .. path)
        delete(sample)
        return nil
    end
end

function SoundController:_loadFileOptional(key, relPath)
    local path   = self.modDir .. relPath
    if fileExists ~= nil and not fileExists(path) then return nil end
    local sample = createSample(key)
    if sample == nil or sample == 0 then return nil end
    if loadSample(sample, path, false) then
        return sample
    end
    delete(sample)
    return nil
end

function SoundController:play(notifType)
    local sample = self:_resolveSample(notifType)
    if sample == nil then
        print("[FarmNotify] No sound for: " .. tostring(notifType))
        return
    end
    -- playSample(sample, loops, volume, offsetMs, delayMs, playAfterSample)
    playSample(sample, 0, self.volume, 0, 0, 0)
end

function SoundController:_resolveSample(notifType)
    -- 1. Try phone-specific override if loaded
    local currentModel = PhoneModel.current and PhoneModel.current.id or "iphone"
    local phoneModelSounds = self.samples.phone[currentModel]
    if phoneModelSounds ~= nil then
        local soundType = self.URGENT_EVENTS[notifType] and "ringtone" or "message"
        if phoneModelSounds[soundType] ~= nil then
            return phoneModelSounds[soundType]
        end
    end

    -- 2. Event-specific WAV (primary)
    local wavFile = self.EVENT_WAV[notifType]
    if wavFile and self.samples.event[wavFile] then
        return self.samples.event[wavFile]
    end

    -- 3. Generic default WAV
    return self.samples.default
end

function SoundController:setVolume(vol)
    self.volume = math.max(0.0, math.min(1.0, vol))
end

function SoundController:stopAll()
    for _, sample in pairs(self.samples.event or {}) do
        if sample ~= nil then stopSample(sample) end
    end
    if self.samples.default then stopSample(self.samples.default) end
    for _, modelSounds in pairs(self.samples.phone or {}) do
        for _, sample in pairs(modelSounds) do
            if sample ~= nil then stopSample(sample) end
        end
    end
end

function SoundController:delete()
    self:stopAll()
    for _, sample in pairs(self.samples.event or {}) do
        if sample ~= nil then delete(sample) end
    end
    if self.samples.default then delete(self.samples.default) end
    for _, modelSounds in pairs(self.samples.phone or {}) do
        for _, sample in pairs(modelSounds) do
            if sample ~= nil then delete(sample) end
        end
    end
    self.samples = {}
end
