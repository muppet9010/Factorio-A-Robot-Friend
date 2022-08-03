local SettingsManager = {} ---@class SettingsManager

SettingsManager._CreateGlobals = function()
    global.Settings = global.Settings or {} ---@class Global_Settings
    global.Settings.showRobotState = global.Settings.showRobotState or true ---@type boolean -- Just hardcode for now.
end

return SettingsManager
