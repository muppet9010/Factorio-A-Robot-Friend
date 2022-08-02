--[[
    All Tasks are required to register themselves in the dictionary MOD.Interfaces.Tasks. With a key of their Task.taskName and a value of a dictionary of interface functions. At a minimum this must include:
        - Create()   =   Called to create the task when it's initially added.
        - Initialise()   =   Called to begin the task when it initially becomes the active task.
        - Progress()   =   Called to continue progress on the task by on_tick.
        - Pause()   =   Called to pause any activity, i.e. task has been interrupted by another higher priority task.
        - Resume()   =   Called to resume a previously paused task. This will need some state checking to be done as anything could have changed from before.
]]

local WalkPath = require("scripts.tasks.walk-path")
local GetWalkingPath = require("scripts.tasks.get-walking-path")

local TaskManager = {} ---@class TaskManager

--- The generic characteristics of an Task that all instances must implement. Stored under its parent Task or directly in its Job if its the primary task for the Job.
---@class Task
---@field taskName string # The name registered under global.Tasks and MOD.Interfaces.Tasks.
---@field taskData? table # Any data that the task needs to store about itself goes in here.
---@field state "pending"|"active"|"completed"
---@field tasks Task[]
---@field job Job # The job related to the lead task in this hierarchy.
---@field parentTask? Task # The parent Task or nil if this is a primary Task of a Job.
---@field parentCallbackFunctionName? string # The name this task calls when it wants to give its parent a status update of some sort.

TaskManager.CreateGlobals = function()
    global.TaskManager = global.TaskManager or {} ---@class Global_TaskManager # Used by the TaskManager for its own global data.

    global.Tasks = global.Tasks or {} ---@class Global_Tasks # All Tasks can put their own global table under this.
    -- Call any task types that need globals making.
    GetWalkingPath.CreateGlobals()
end

TaskManager.OnLoad = function()
    MOD.Interfaces.TaskManager = MOD.Interfaces.TaskManager or {} ---@class MOD_InternalInterfaces_TaskManager # Used by the TaskManager for its own public function registrations (save/load safe).
    MOD.Interfaces.TaskManager.CreateGenericTask = TaskManager.CreateGenericTask

    MOD.Interfaces.Tasks = MOD.Interfaces.Tasks or {} ---@class MOD_InternalInterfaces_Tasks # Used by all Tasks to register their public functions on by name (save/load safe).
    -- Call all task types.
    WalkPath.OnLoad()
    GetWalkingPath.OnLoad()
end

--- Called to make a generic Task object by the specific task before it adds its bespoke elements to it.
---@param taskName string # The name registered under global.Tasks and MOD.Interfaces.Tasks.
---@param job Job # The job related to the lead task in this hierarchy.
---@param parentTask? Task # The parent Task or nil if this is a primary Task of a Job.
---@param parentCallbackFunctionName? string # The name this task calls when it wants to give its parent a status update of some sort.
---@return Task
TaskManager.CreateGenericTask = function(taskName, job, parentTask, parentCallbackFunctionName)
    ---@type Task
    local task = { taskName = taskName, taskData = {}, state = "pending", tasks = {}, job = job, parentTask = parentTask, parentCallbackFunctionName = parentCallbackFunctionName }
    return task
end

return TaskManager
