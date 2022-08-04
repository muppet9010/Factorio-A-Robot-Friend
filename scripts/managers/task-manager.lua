--[[
    All Tasks are required to register themselves in the dictionary MOD.Interfaces.Tasks. With a key of their Task.taskName and a value of a dictionary of interface functions.
    Tasks are per robot under a shared Job entry.
]]

local WalkPath = require("scripts.tasks.walk-path")
local GetWalkingPath = require("scripts.tasks.get-walking-path")
local WalkToLocation = require("scripts.tasks.walk-to-location")

--- The generic characteristics of a Task Interface that all instances must implement. Stored in MOD.Interfaces.Tasks and each task must register itself during OnLoad() with a key of its taskName and the value of its bespoke Task Interface object.
---@class Task_Interface
---@field taskName string # The internal name of the task. Recorded in here to avoid having to hard code it all over the code.
---@field Begin fun(robot:Robot, job:Job_Data, parentTask:Task_Data): Task_Data, uint # Called to create the task and start the process when an active robot first reaches this task. This will often involve some scanning or other activity before the robot is assigned actions. Returns the Task data and the ticksToWait. In some cases it will call its own Progress() if its initial action is the same as subsequent ones.
---@field Progress fun(thisTask:Task_Data): uint # Called to continue progression on the task by on_tick. Returns how many ticks to wait before next Progress() call.
---@field Pause function # Called to pause any activity, i.e. task has been interrupted by another higher priority task.
---@field Resume function # Called to resume a previously paused task. This will need some state checking to be done as anything could have changed from before.
---@field Remove fun(thisTask:Task_Data) # Called to remove a task. This propagates down to all sub tasks to tidy up any globals and other active effects.

--- The generic characteristics of an Task Global that all instances must implement. Stored under its parent Task or under its robot in the parent Job if its the primary task for the Job.
---@class Task_Data
---@field taskName string # The name registered under global.Tasks and MOD.Interfaces.Tasks.
---@field taskData? table # Any data that the task needs to store about itself goes in here. Each task will have its own BespokeData class for this.
---@field state "active"|"completed"
---@field robot Robot
---@field tasks Task_Data[]
---@field currentTaskIndex int # The current task in the `tasks` list that is the active task.
---@field job Job_Data # The job related to the lead task in this hierarchy.
---@field parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.

local TaskManager = {} ---@class TaskManager

TaskManager._CreateGlobals = function()
    global.TaskManager = global.TaskManager or {} ---@class Global_TaskManager # Used by the TaskManager for its own global data.

    global.Tasks = global.Tasks or {} ---@class Global_Tasks # All Tasks can put their own global table under this.
    -- Call any task types that need globals making.
    GetWalkingPath._CreateGlobals()
end

TaskManager._OnLoad = function()
    MOD.Interfaces.TaskManager = TaskManager

    MOD.Interfaces.Tasks = MOD.Interfaces.Tasks or {} ---@class MOD_InternalInterfaces_Tasks # Used by all Tasks to register their public functions on by name (save/load safe).
    -- Call all task types.
    WalkPath._OnLoad()
    GetWalkingPath._OnLoad()
    WalkToLocation._OnLoad()
end

--- Called to make a generic Task object by the specific task before it adds its bespoke elements to it. This task is persisted in global via its hierarchy from the Job. The return should be casted to the bespoke Task specific class.
---@param taskName string # The name registered under global.Tasks and MOD.Interfaces.Tasks.
---@param robot Robot
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@return Task_Data
TaskManager.CreateGenericTask = function(taskName, robot, job, parentTask)
    ---@type Task_Data
    local task = { taskName = taskName, taskData = {}, state = "active", tasks = {}, currentTaskIndex = 0, robot = robot, job = job, parentTask = parentTask }
    return task
end

--- Called by the Task when it is completed, so it can update it's status and do any configured alerts, etc.
---@param task Task_Data
TaskManager.TaskCompleted = function(task)
    task.state = "completed"
end

--- Called to remove a primary task from a job (so robot instance specific). This will propagates down to all sub tasks to tidy up any globals and other active effects.
---@param primaryTask Task_Data
TaskManager.RemovePrimaryTask = function(primaryTask)
    MOD.Interfaces.Tasks[primaryTask.taskName]--[[@as Task_Interface]] .Remove(primaryTask) --TODO: not yet implemented and code test gets this far.
end

---@param primaryTask Task_Data
---@return uint ticksToWait
TaskManager.ProgressPrimaryTask = function(primaryTask)
    return MOD.Interfaces.Tasks[primaryTask.taskName]--[[@as Task_Interface]] .Progress(primaryTask)
end

return TaskManager
