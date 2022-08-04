local SettingsManager = {} ---@class SettingsManager

SettingsManager._CreateGlobals = function()
    global.Settings = global.Settings or {} ---@class Global_Settings
    global.Settings.showRobotState = true ---@type boolean -- Just hardcode for now.

    global.Settings.Debug = global.Settings.Debug or {} ---@class Global_Settings_Debug
    global.Settings.Debug.showPathWalking = true ---@type boolean # Just hardcode for now.
end

return SettingsManager
