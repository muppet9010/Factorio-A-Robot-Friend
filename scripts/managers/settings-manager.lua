local SettingsManager = {} ---@class SettingsManager

SettingsManager._CreateGlobals = function()
    global.Settings = global.Settings or {} ---@class Global_Settings
    global.Settings.showRobotState = true ---@type boolean -- Just hardcode for now.

    global.Settings.Debug = global.Settings.Debug or {} ---@class Global_Settings_Debug
    global.Settings.Debug.showPathWalking = true ---@type boolean # Just hardcode for now.
    global.Settings.Debug.showCompleteAreas = true ---@type boolean # Just hardcode for now.
    global.Settings.Debug.fastDeconstruct = true ---@type boolean # Just hardcode for now.

    global.Settings.Robot = global.Settings.Robot or {} ---@class Global_Settings_Robot
    global.Settings.Robot.EndOfTaskWaitTicks = 60 ---@type uint # How long the robot will wait when it finishes something before flowing in to the next major thing. Some tasks may overwrite/ignore this and just start the next task instantly.
end

return SettingsManager
