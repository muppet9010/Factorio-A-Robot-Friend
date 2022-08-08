--[[
    Tasks manage the robots doing the actual work and are fully modular (black box) from each other. Allowing unlimited task stacking.

    All Tasks are required to implement Task_Interface and Task_Data within their bespoke classes.

    There is a single instance of a Task under a Job in the task hierarchy. With all robots sharing the Task, however they can have per robot state data.
]]

local WalkPath = require("scripts.tasks.walk-path")
local GetWalkingPath = require("scripts.tasks.get-walking-path")
local WalkToLocation = require("scripts.tasks.walk-to-location")
local CompleteArea = require("scripts.tasks.complete-area")
local ScanAreasForActionsToComplete = require("scripts.tasks.scan-areas-for-actions-to-complete")


--- The generic characteristics of a Task Interface that all instances must implement. Stored in MOD.Interfaces.Tasks and each task must register itself during OnLoad() with a key of its taskName and the value of its bespoke Task Interface object.
---@class Task_Interface
---@field taskName string # The internal name of the task. Recorded in here to avoid having to hard code it all over the code.
---@field ActivateTask fun(job:Job_Data, parentTask:Task_Data, ...): Task_Data # Called ONCE per Task to create the task when the first robot first reaches this task in the job. It is robot agnostic and returns the Task data for the bespoke task.
---@field Progress fun(thisTask:Task_Data, robot:Robot, ...): uint, ShowRobotState_NewRobotStateDetails|nil # Called to do work on the task by on_tick by each robot. Returns how many ticks to wait before next Progress() call for that robot and the robot state details object for storing by the robot. The return tick wait of 0 will make the robot moveThe robot state can be nil if there is no state being set by this Task.
---@field PauseTask function # Called to pause any activity, i.e. task has been interrupted by another higher priority task. NOT DEFINED - OLD MINDSET IN DESCRIPTION
---@field ResumeTask function # Called to resume a previously paused task. This will need some state checking to be done as anything could have changed from before. NOT DEFINED - OLD MINDSET IN DESCRIPTION
---@field RemovingTask fun(thisTask:Task_Data) # Called when a task is being removed and any task globals or ongoing activities need to be stopped. This will propagates down to all sub tasks.
---@field RemovingRobotFromTask fun(thisTask:Task_Data, robot:Robot) # Called when a specific robot is being removed from a task. Removes any robot specific task data and any robot related task globals or ongoing activities will be stopped. This will propagates down to all sub tasks.
---@field PausingRobotForTask fun(thisTask:Task_Data, robot:Robot) # Called when a robot has been paused and so all of its activities within the job's tasks need to pause. This will propagates down to all sub tasks to pause active effects for this robot.

--- The generic characteristics of an Task Global that all instances must implement. Stored under its parent Task or under its robot in the parent Job if its the primary task for the Job.
---@class Task_Data
---@field taskName string # The name registered under global.Tasks and MOD.Interfaces.Tasks.
---@field taskData table # Any task wide (all robot) data that the task needs to store about itself goes in here. Each task will have its own BespokeData class for this.
---@field robotsTaskData table<Robot, Task_Data_Robot> # Any per robot data that the task needs to store about each robot goes in here. Each task will have its own BespokeData class for this.
---@field state "active"|"completed" # The state of the overall task. Some individual robots may be completed on an active task as recorded under the robotsTaskData.
---@field plannedTasks Task_Data[] # The planned child tasks of this task.
---@field currentTaskIndex uint # The current task in the `tasks` list that is the active task. This is for all robots. Some individual robots will be on different current task as recorded under the robotsTaskData. Starts at 0 for a generic Task.
---@field job Job_Data # The job related to the lead task in this hierarchy.
---@field parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job. Not currently used other than detecting when its nil, however, it does no real harm having at present.

--- The generic characteristics of the robot specific Task Data that all Task instances must implement if they have per robot data.
---@class Task_Data_Robot
---@field robot Robot
---@field state "active"|"completed" # The state of this robot in this task. Some specific task types may add their own states per robot.
---@field currentTaskIndex uint # The current task in the `tasks` list that is the active task for just this robot.
---@field task Task_Data # The Task that this robot specific data is for.

local TaskManager = {} ---@class TaskManager

TaskManager._CreateGlobals = function()
    global.TaskManager = global.TaskManager or {} ---@class Global_TaskManager # Used by the TaskManager for its own global data.

    global.Tasks = global.Tasks or {} ---@class Global_Tasks # All Tasks can put their own global table under this. Keyed by their Task Name.
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
    CompleteArea._OnLoad()
    ScanAreasForActionsToComplete._OnLoad()
end

--- Called to make a generic Task object by the specific task before it adds its bespoke elements to it. This task is persisted in global via its hierarchy from the Job. The return should be casted to the bespoke Task specific class.
---@param taskName string # The name registered under global.Tasks and MOD.Interfaces.Tasks.
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@return Task_Data
TaskManager.CreateGenericTask = function(taskName, job, parentTask)
    ---@type Task_Data
    local task = { taskName = taskName, taskData = {}, robotsTaskData = {}, state = "active", plannedTasks = {}, currentTaskIndex = 0, job = job, parentTask = parentTask }
    return task
end

--- Called to make a generic Robot Task Data object by the specific task before it adds its bespoke elements to it. The return should be casted to the bespoke Task specific class.
---@param robot Robot
---@param currentTaskIndex uint # The current task in the `plannedTasks` list that is the active task for just this robot.
---@param task Task_Data # The Task that this robot specific data is for.
---@return Task_Data_Robot
TaskManager.CreateGenericRobotTaskData = function(robot, currentTaskIndex, task)
    ---@type Task_Data_Robot
    local task = { robot = robot, currentTaskIndex = currentTaskIndex, task = task, state = "active" }
    return task
end

--- Called when removing a robot from the primary task of a job. This will propagates down to all sub tasks to tidy up any non task managed globals and other active effects for this robot.
---@param primaryTask Task_Data
---@param robot Robot
TaskManager.RemovingRobotFromPrimaryTask = function(primaryTask, robot)
    MOD.Interfaces.Tasks[primaryTask.taskName]--[[@as Task_Interface]] .RemovingRobotFromTask(primaryTask, robot)
end

--- Called by a task to let its child tasks know they about a robot being removed from the task hierarchy. The bespoke task will do any unique actions for it in addition to calling this.
---@param thisTask Task_Data
---@param robot Robot
TaskManager.GenericTaskPropagateRemoveRobot = function(thisTask, robot)
    for _, childTask in pairs(thisTask.plannedTasks) do
        MOD.Interfaces.Tasks[childTask.taskName]--[[@as Task_Interface]] .RemovingRobotFromTask(childTask, robot)
    end
end

--- Called when removing the primary task of a job. This will propagates down to all sub tasks to tidy up any non task managed globals and other active effects for this robot.
---@param primaryTask Task_Data
TaskManager.RemovingPrimaryTaskFromJob = function(primaryTask)
    MOD.Interfaces.Tasks[primaryTask.taskName]--[[@as Task_Interface]] .RemovingTask(primaryTask)
end

--- Called by a task to let its child tasks know they are all being removed. The bespoke task will do any unique actions for it in addition to calling this.
---@param thisTask Task_Data
TaskManager.GenericTaskPropagateRemove = function(thisTask)
    for _, childTask in pairs(thisTask.plannedTasks) do
        MOD.Interfaces.Tasks[childTask.taskName]--[[@as Task_Interface]] .RemovingTask(childTask)
    end
end

--- Called by a job to progress the primary task of the job. This task will then propagate down as required for this robot.
---@param primaryTask Task_Data
---@param robot Robot
---@return uint ticksToWait
---@return ShowRobotState_NewRobotStateDetails|nil robotStateDetails # nil if there is no state being set by this Task
TaskManager.ProgressPrimaryTask = function(primaryTask, robot)
    return MOD.Interfaces.Tasks[primaryTask.taskName]--[[@as Task_Interface]] .Progress(primaryTask, robot)
end

--- Called by a job to check if the primary task of the job is complete for a given robot. If there is no robot data for this Task then it returns nil.
---@param primaryTask Task_Data
---@param robot Robot
---@return boolean|nil # Is nil if this robot doesn't have an instance of this Task.
TaskManager.IsPrimaryTaskCompleteForRobot = function(primaryTask, robot)
    local robotTaskData = primaryTask.robotsTaskData[robot]
    if robotTaskData == nil then return nil end
    if robotTaskData.state == "completed" then return true end
    return false
end

--- Called when pausing a robot and so all of its activities within the job's tasks need to pause. This will propagates down to all sub tasks to pause active effects for this robot.
---@param primaryTask Task_Data
---@param robot Robot
TaskManager.PausingRobotForPrimaryTask = function(primaryTask, robot)
    MOD.Interfaces.Tasks[primaryTask.taskName]--[[@as Task_Interface]] .PausingRobotForTask(primaryTask, robot)
end

--- Called by a task to let its child tasks know that a robot is being paused. The bespoke task will do any unique actions for it in addition to calling this.
---@param thisTask Task_Data
---@param robot Robot
TaskManager.GenericTaskPropagatePausingRobot = function(thisTask, robot)
    for _, childTask in pairs(thisTask.plannedTasks) do
        MOD.Interfaces.Tasks[childTask.taskName]--[[@as Task_Interface]] .PausingRobotForTask(childTask, robot)
    end
end

return TaskManager
