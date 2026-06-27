-- FarmNotifySettings.lua
-- Persists player preferences (phone model, volume, etc.) to user profile

FarmNotifySettings = {}
FarmNotifySettings.SETTINGS_FILE = "FarmNotifySettings.xml"

FarmNotifySettings.defaults = {
    phoneModel    = "iphone",   -- "iphone" | "samsung"
    volume        = 0.8,
    showPopups    = true,
    popupDuration = 7000,       -- ms
    position      = "bottomRight"
}

FarmNotifySettings.current = {}

function FarmNotifySettings:init()
    for k, v in pairs(self.defaults) do
        self.current[k] = v
    end
    self:load()
end

function FarmNotifySettings:getFilePath()
    return getUserProfileAppPath() .. self.SETTINGS_FILE
end

function FarmNotifySettings:load()
    local path = self:getFilePath()
    local xmlFile = loadXMLFile("FarmNotifySettings", path)
    if xmlFile == nil then
        print("[FarmNotify] No settings file found — using defaults.")
        return
    end

    self.current.phoneModel    = getXMLString(xmlFile, "FarmNotifySettings.phoneModel")
                                 or self.defaults.phoneModel
    self.current.volume        = getXMLFloat(xmlFile, "FarmNotifySettings.volume")
                                 or self.defaults.volume
    self.current.showPopups    = getXMLBool(xmlFile, "FarmNotifySettings.showPopups")
    if self.current.showPopups == nil then
        self.current.showPopups = self.defaults.showPopups
    end
    self.current.popupDuration = getXMLInt(xmlFile, "FarmNotifySettings.popupDuration")
                                 or self.defaults.popupDuration
    self.current.position      = getXMLString(xmlFile, "FarmNotifySettings.position")
                                 or self.defaults.position

    deleteXMLFile(xmlFile)
    print("[FarmNotify] Settings loaded.")
end

function FarmNotifySettings:save()
    local path = self:getFilePath()
    local xmlFile = createXMLFile("FarmNotifySettings", path, "FarmNotifySettings")
    if xmlFile == nil then
        print("[FarmNotify] ERROR: Could not save settings.")
        return
    end

    setXMLString(xmlFile, "FarmNotifySettings.phoneModel",    self.current.phoneModel)
    setXMLFloat (xmlFile, "FarmNotifySettings.volume",        self.current.volume)
    setXMLBool  (xmlFile, "FarmNotifySettings.showPopups",    self.current.showPopups)
    setXMLInt   (xmlFile, "FarmNotifySettings.popupDuration", self.current.popupDuration)
    setXMLString(xmlFile, "FarmNotifySettings.position",      self.current.position)

    saveXMLFile(xmlFile)
    deleteXMLFile(xmlFile)
    print("[FarmNotify] Settings saved.")
end

function FarmNotifySettings:get(key)
    return self.current[key]
end

function FarmNotifySettings:set(key, value)
    if self.defaults[key] == nil then
        print("[FarmNotify] Unknown setting: " .. tostring(key))
        return
    end
    if self.current[key] == value then return end  -- L05: skip save if unchanged
    self.current[key] = value
    self:save()
end
