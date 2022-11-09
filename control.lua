local Constants = require("constants")
local TaskManager = require("scripts.managers.task-manager")
local TestingManager = require("scripts.testing.testing-manager")
local RobotManager = require("scripts.managers.robot-manager")
local JobManager = require("scripts.managers.job-manager")
local SettingsManager = require("scripts.managers.settings-manager")
local EventScheduler = require("utility.manager-libraries.event-scheduler")

local function CreateGlobals()
    SettingsManager._CreateGlobals()
    JobManager._CreateGlobals()
    TaskManager._CreateGlobals()
    RobotManager._CreateGlobals()

    TestingManager.CreateGlobals()
end

local function OnLoad()
    JobManager._OnLoad()
    TaskManager._OnLoad()

    RobotManager._OnLoad()

    TestingManager.OnLoad()

    -- Register all remotes recorded during module's OnLoad().
    remote.remove_interface(Constants.ModName)
    remote.add_interface(Constants.ModName, MOD.RemoteInterfaces)

    ------------------------------------------------
    --
    -- Testing Utility Temp - START
    --
    ------------------------------------------------
    EventScheduler.RegisterScheduler()
    local testFunc = function(event)
        local x = event
    end
    EventScheduler.RegisterScheduledEventType("testFunc", testFunc)

    EventScheduler.ScheduleEventOnce(game.tick + 1, "testFunc", 1)
    EventScheduler.ScheduleEventOnce(game.tick + 2, "testFunc", 2)
    EventScheduler.ScheduleEventOnce(game.tick + 3, "testFunc", 2)
    EventScheduler.ScheduleEventOnce(game.tick + 5, "testFunc", 2)
    EventScheduler.ScheduleEventOnce(game.tick + 3, "testFunc", 3)
    EventScheduler.ScheduleEventOnce(game.tick + 4, "testFunc", 4)

    local a = EventScheduler.RemoveScheduledOnceEvents("testFunc", 2, game.tick + 1)

    local b = EventScheduler.RemoveScheduledOnceEvents("testFunc", 2, game.tick + 2)

    local b2 = EventScheduler.RemoveScheduledOnceEvents("testFunc", 2)

    local c = EventScheduler.RemoveScheduledOnceEvents("testFunc", 4)

    local d = EventScheduler.RemoveScheduledOnceEvents("testFunc")

    EventScheduler.ScheduleEventEachTick("testFunc", "a")
    EventScheduler.ScheduleEventEachTick("testFunc", "b")

    local x = EventScheduler.RemoveScheduledEventFromEachTick("testFunc", "a")

    local y = EventScheduler.RemoveScheduledEventFromEachTick("testFunc", "c")

    local endTest = 1

    ------------------------------------------------
    --
    -- Testing Utility Temp - END
    --
    ------------------------------------------------
end

local function OnSettingChanged(event)
    --if event == nil or event.setting == "xxxxx" then
    --	local x = tonumber(settings.global["xxxxx"].value)
    --end
end

local function OnStartup()
    CreateGlobals()
    OnLoad()
    OnSettingChanged(nil)
end

script.on_init(OnStartup)
script.on_configuration_changed(OnStartup)
script.on_event(defines.events.on_runtime_mod_setting_changed, OnSettingChanged)
script.on_load(OnLoad)


MOD = MOD or {} ---@class MOD

-- Mod wide function interface table creation. Means EmmyLua can support it.
MOD.Interfaces = MOD.Interfaces or {} ---@class MOD_InternalInterfaces

-- So things can register their remote interface functions within their module during OnLoad() and then control can register them all in bulk.
MOD.RemoteInterfaces = MOD.RemoteInterfaces or {} ---@type table<string, function>
