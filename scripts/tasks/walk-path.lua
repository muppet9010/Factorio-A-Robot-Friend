local showRobotState = require("scripts.show-robot-state")

---@class Task_WalkPath_Data : Task_Data
---@field taskData Task_WalkPath_BespokeData

---@class Task_WalkPath_BespokeData
---@field pathToWalk PathfinderWaypoint[]

local WalkPath = {} ---@class Task_WalkPath_Interface : Task_Interface
WalkPath.taskName = "WalkPath"

WalkPath._OnLoad = function()
    MOD.Interfaces.Tasks.WalkPath = WalkPath
end

--- Called to create the task and start the process when an active robot first reaches this task.
---@param robot Robot
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param parentCallbackFunctionName? string # The name this task calls when it wants to give its parent a status update of some sort.
---@param pathToWalk PathfinderWaypoint[]
---@return Task_WalkPath_Data
---@return uint ticksToWait
WalkPath.Begin = function(robot, job, parentTask, parentCallbackFunctionName, pathToWalk)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(WalkPath.taskName, robot, job, parentTask, parentCallbackFunctionName) ---@cast thisTask Task_WalkPath_Data

    -- Store the request data.
    thisTask.taskData = {
        pathToWalk = pathToWalk
    }

    -- Just do a progression once to start.
    local ticksToWait = WalkPath.Progress(thisTask)
    return thisTask, ticksToWait
end

--- Called to continue progression on the task by on_tick.
---@param thisTask Task_WalkPath_Data
---@return uint ticksToWait
WalkPath.Progress = function(thisTask)
    if global.Settings.showRobotState then
        showRobotState.ShowNormalState(thisTask.robot, "Walking the path", 1)
    end

    -- TODO: walk the path.
    local direction = math.random(0, 7) --[[@as defines.direction]]
    thisTask.robot.entity.walking_state = { walking = true, direction = direction }

    return 1
end



return WalkPath
