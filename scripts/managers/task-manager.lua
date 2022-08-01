local WalkPath = require("scripts.tasks.walk-path")
local GetWalkingPath = require("scripts.tasks.get-walking-path")

local TaskManager = {} ---@class TaskManager

--- The generic characteristics of an Task that all instances must implement.
---@class Task

TaskManager.CreateGlobals = function()
    global.TaskManager = global.TaskManager or {} ---@class Global_TaskManager
    global.Tasks = global.Tasks or {} ---@class Global_Tasks

    -- Call all child tasks.
    GetWalkingPath.CreateGlobals()
end

TaskManager.OnLoad = function()
    MOD.Interfaces.Tasks = MOD.Interfaces.Tasks or {} ---@class MOD_InternalInterfaces_Tasks

    -- Call all child tasks.
    WalkPath.OnLoad()
    GetWalkingPath.OnLoad()
end

return TaskManager
