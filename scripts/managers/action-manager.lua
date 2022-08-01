-- This currently just handles registering the Actions.

local Action_Walking = require("scripts.actions.walking")

local ActionManager = {} ---@class ActionManager

--- The generic characteristics of an Action that all instances must implement.
---@class Action

ActionManager.CreateGlobals = function()
    global.ActionManager = global.ActionManager or {} ---@class Global_ActionManager
end

ActionManager.OnLoad = function()
    MOD.Interfaces.Actions = MOD.Interfaces.Actions or {} ---@class MOD_InternalInterfaces_Actions

    -- Call all child actions.
    Action_Walking.OnLoad()
end

return ActionManager
