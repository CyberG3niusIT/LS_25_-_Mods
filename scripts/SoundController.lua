-- SoundController.lua
-- Plays notification sounds — phone-model-aware (iPhone vs Samsung specific tones)

SoundController = {}
SoundController.modDir  = nil
SoundController.volume  = 0.8
SoundController.samples = {}

-- Per phone-model: message notification + ringtone
SoundController.PHONE_SOUNDS = {
    iphone = {
        message  = "sounds/iphone_message.mp3",
        ringtone = "sounds/iphone_ringtone.mp3",
    },
    samsung = {
        message  = "sounds/samsung_message.mp3",
        ringtone = "sounds/samsung_ringtone.mp3",
    },
}

-- Event-type → sound category
-- "message" = short notification ping, "ringtone" = long call tone
SoundController.EVENT_SOUND = {
    harvest_ready   = "message",
    harvest_overdue = "ringtone",   -- urgent: full ringtone
    worker_done     = "message",
    worker_stuck    = "ringtone",   -- urgent
    fuel_low        = "message",
    silo_full       = "message",
    weather_rain    = "message",
    weather_storm   = "ringtone",   -- urgent
}

-- Generated WAV fallbacks (used when phone-specific MP3 not loaded)
SoundController.WAV_FALLBACK = {
    message  = "sounds/notify_default.wav",
    ringtone = "sounds/notify_urgent.wav",
}

function SoundController:init(modDir, volume)
    self.modDir  = modDir
    self.volume  = volume or 0.8
    self.samples = {}
    self:_loadAll()
    print("[FarmNotify] SoundController initialized.")
end

function SoundController:_loadAll()
    -- Load phone-specific sounds for each model
    for modelId, files in pairs(self.PHONE_SOUNDS) do
        self.samples[modelId] = {}
        for soundType, file in pairs(files) do
            local sample = self:_loadFile(modelId .. "_" .. soundType, file)
            self.samples[modelId][soundType] = sample
        end
    end

    -- Load WAV fallbacks
    self.samples.fallback = {}
    for soundType, file in pairs(self.WAV_FALLBACK) do
        self.samples.fallback[soundType] = self:_loadFile("fallback_" .. soundType, file)
    end
end

function SoundController:_loadFile(key, relPath)
    local path   = self.modDir .. relPath
    local sample = createSample(key)
    if sample == nil then
        print("[FarmNotify] createSample failed: " .. key)
        return nil
    end
    if loadSample(sample, path, false) then
        return sample
    else
        print("[FarmNotify] Could not load: " .. path)
        deleteSample(sample)
        return nil
    end
end

-- Play sound for given event type, using current phone model
function SoundController:play(notifType)
    local currentModel = PhoneModel.current and PhoneModel.current.id or "iphone"
    local soundType    = self.EVENT_SOUND[notifType] or "message"

    -- Try phone-specific sound first
    local sample = self.samples[currentModel] and self.samples[currentModel][soundType]

    -- Fallback to generated WAV
    if sample == nil then
        sample = self.samples.fallback and self.samples.fallback[soundType]
    end

    if sample == nil then
        print("[FarmNotify] No sound available for: " .. notifType)
        return
    end

    -- playSample(sample, loopCount, volume, pitch, startOffset, randomPitch)
    playSample(sample, 0, self.volume, 0, 0, 0)
end

-- Play ringtone explicitly (e.g. for urgent events)
function SoundController:playRingtone()
    local currentModel = PhoneModel.current and PhoneModel.current.id or "iphone"
    local sample = self.samples[currentModel] and self.samples[currentModel].ringtone
                   or self.samples.fallback.ringtone
    if sample then
        playSample(sample, 0, self.volume, 0, 0, 0)
    end
end

function SoundController:stopAll()
    for _, modelSounds in pairs(self.samples) do
        for _, sample in pairs(modelSounds) do
            if sample ~= nil then
                stopSample(sample)
            end
        end
    end
end

function SoundController:setVolume(vol)
    self.volume = math.max(0.0, math.min(1.0, vol))
end

function SoundController:delete()
    self:stopAll()
    for _, modelSounds in pairs(self.samples) do
        for _, sample in pairs(modelSounds) do
            if sample ~= nil then
                deleteSample(sample)
            end
        end
    end
    self.samples = {}
end
