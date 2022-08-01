local Constants = require("constants")
local ActionManager = require("scripts.managers.action-manager")
local TestingManager = require("scripts.testing.testing-manager")
local RobotManager = require("scripts.managers.robot-manager")

local function CreateGlobals()
    ActionManager.CreateGlobals()

    RobotManager.CreateGlobals()

    TestingManager.CreateGlobals()
end

local function OnLoad()
    ActionManager.OnLoad()

    RobotManager.OnLoad()

    TestingManager.OnLoad()

    -- Register all remotes recorded during module's OnLoad().
    remote.remove_interface(Constants.ModName)
    remote.add_interface(Constants.ModName, MOD.RemoteInterfaces)
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
--[[
    Populate and use from within module's OnLoad() functions with simple table reference structures, i.e:
        MOD.Interfaces.Tunnel = MOD.Interfaces.Tunnel or {} ---@class InternalInterfaces_XXXXXX
        MOD.Interfaces.Tunnel.CompleteTunnel = Tunnel.CompleteTunnel
--]]
--

-- So things can register their remote interface functions within their module during OnLoad() and then control can register them all in bulk.
MOD.RemoteInterfaces = MOD.RemoteInterfaces or {} ---@type table<string, function>
