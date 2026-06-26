-- SoundController.lua
-- Plays notification sounds using LS25 sample API

SoundController = {}
SoundController.modDir  = nil
SoundController.samples = {}
SoundController.volume  = 0.8

-- Sound files expected in sounds/ folder
SoundController.SOUND_FILES = {
    harvest_ready   = "sounds/notify_harvest.wav",
    harvest_overdue = "sounds/notify_urgent.wav",
    worker_done     = "sounds/notify_done.wav",
    worker_stuck    = "sounds/notify_alert.wav",
    fuel_low        = "sounds/notify_alert.wav",
    silo_full       = "sounds/notify_info.wav",
    weather_rain    = "sounds/notify_weather.wav",
    weather_storm   = "sounds/notify_urgent.wav",
    default         = "sounds/notify_default.wav",
}

function SoundController:init(modDir, volume)
    self.modDir  = modDir
    self.volume  = volume or 0.8
    self.samples = {}
    self:_loadSamples()
    print("[FarmNotify] SoundController initialized.")
end

function SoundController:_loadSamples()
    local loaded = {}
    for key, file in pairs(self.SOUND_FILES) do
        if loaded[file] == nil then
            local path   = self.modDir .. file
            local sample = createSample(key)
            if sample ~= nil then
                if loadSample(sample, path, false) then
                    loaded[file] = sample
                    self.samples[key] = sample
                    print("[FarmNotify] Sound loaded: " .. file)
                else
                    print("[FarmNotify] WARNING: Could not load sound: " .. path)
                    deleteSample(sample)
                end
            end
        else
            self.samples[key] = loaded[file]
        end
    end
end

function SoundController:play(notifType)
    local sample = self.samples[notifType] or self.samples["default"]
    if sample == nil then return end
    -- playSample(sample, loopCount, volume, pitch, startOffset, randomPitch)
    playSample(sample, 0, self.volume, 0, 0, 0)
end

function SoundController:setVolume(vol)
    self.volume = math.max(0, math.min(1, vol))
end

function SoundController:delete()
    for key, sample in pairs(self.samples) do
        if sample ~= nil then
            stopSample(sample)
            deleteSample(sample)
        end
    end
    self.samples = {}
end
