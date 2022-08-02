--[[
    All Tasks are required to register themselves in the dictionary MOD.Interfaces.Tasks. With a key of their Task.taskName and a value of a dictionary of interface functions. At a minimum this must include:

]]

local WalkPath = require("scripts.tasks.walk-path")
local GetWalkingPath = require("scripts.tasks.get-walking-path")

--- The generic characteristics of a Task Interface that all instances must implement. Stored in MOD.Interfaces.Tasks and each task must register itself during OnLoad() with a key of its taskName and the value of its bespoke Task Interface object.
---@class Task_Interface
---@field jobName string # The internal name of the job.
---@field Begin fun(job:Job_Data, parentTask:Task_Data, parentCallbackFunctionName:string, robot:Robot): Task_Data # Called to create the task and start the process when an active robot first reaches this task. This will often involve some scanning or other activity before the robot is assigned actions.
---@field Progress fun(task:Task_Data, robot:Robot) # Called to continue progression on the task by on_tick.
---@field Pause function # Called to pause any activity, i.e. task has been interrupted by another higher priority task.
---@field Resume function # Called to resume a previously paused task. This will need some state checking to be done as anything could have changed from before.

--- The generic characteristics of an Task GLobal that all instances must implement. Stored within global under its parent Task or directly in its Job if its the primary task for the Job.
---@class Task_Data
---@field taskName string # The name registered under global.Tasks and MOD.Interfaces.Tasks.
---@field taskData? table # Any data that the task needs to store about itself goes in here. Each task will have its own BespokeData class for this.
---@field state "active"|"completed"
---@field tasks Task_Data[]
---@field job Job_Data # The job related to the lead task in this hierarchy.
---@field parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@field parentCallbackFunctionName? string # The name this task calls when it wants to give its parent a status update of some sort.

local TaskManager = {} ---@class TaskManager

TaskManager._CreateGlobals = function()
    global.TaskManager = global.TaskManager or {} ---@class Global_TaskManager # Used by the TaskManager for its own global data.

    global.Tasks = global.Tasks or {} ---@class Global_Tasks # All Tasks can put their own global table under this.
    -- Call any task types that need globals making.
    GetWalkingPath._CreateGlobals()
end

TaskManager._OnLoad = function()
    MOD.Interfaces.TaskManager = MOD.Interfaces.TaskManager or {} ---@class MOD_InternalInterfaces_TaskManager # Used by the TaskManager for its own public function registrations (save/load safe).
    MOD.Interfaces.TaskManager.CreateGenericTask = TaskManager.CreateGenericTask

    MOD.Interfaces.Tasks = MOD.Interfaces.Tasks or {} ---@class MOD_InternalInterfaces_Tasks # Used by all Tasks to register their public functions on by name (save/load safe).
    -- Call all task types.
    WalkPath._OnLoad()
    GetWalkingPath._OnLoad()
end

--- Called to make a generic Task object by the specific task before it adds its bespoke elements to it. This task is persisted in global via its hierarchy from the Job. The return should be casted to the bespoke Task specific class.
---@param taskName string # The name registered under global.Tasks and MOD.Interfaces.Tasks.
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param parentCallbackFunctionName? string # The name this task calls when it wants to give its parent a status update of some sort.
---@return Task_Data
TaskManager.CreateGenericTask = function(taskName, job, parentTask, parentCallbackFunctionName)
    ---@type Task_Data
    local task = { taskName = taskName, taskData = {}, state = "active", tasks = {}, job = job, parentTask = parentTask, parentCallbackFunctionName = parentCallbackFunctionName }
    return task
end

return TaskManager
