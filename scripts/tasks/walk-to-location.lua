local LoggingUtils = require("utility.helper-utils.logging-utils")

---@class Task_WalkToLocation_Data : Task_Data
---@field taskData Task_WalkToLocation_BespokeData

---@class Task_WalkToLocation_BespokeData
---@field targetLocation MapPosition
---@field surface LuaSurface
---@field pathToWalk? PathfinderWaypoint[]

local WalkToLocation = {} ---@class Task_WalkToLocation_Interface : Task_Interface
WalkToLocation.taskName = "WalkToLocation"

WalkToLocation._OnLoad = function()
    MOD.Interfaces.Tasks.WalkToLocation = WalkToLocation
end

--- Called to create the task and start the process when an active robot first reaches this task.
---@param robot Robot
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param parentCallbackFunctionName? string # The name this task calls when it wants to give its parent a status update of some sort.
---@param targetLocation MapPosition
---@param surface LuaSurface
---@return Task_WalkToLocation_Data
---@return uint ticksToWait
WalkToLocation.Begin = function(robot, job, parentTask, parentCallbackFunctionName, targetLocation, surface)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(WalkToLocation.taskName, robot, job, parentTask, parentCallbackFunctionName) ---@cast thisTask Task_WalkToLocation_Data

    -- Store the target data.
    thisTask.taskData = {
        targetLocation = targetLocation,
        surface = surface,
    }

    -- Start the first child task straight away. Other tasks will be added/started on the Progress() as getting a path is async.
    local ticksToWait
    thisTask.tasks[#thisTask.tasks + 1], ticksToWait = MOD.Interfaces.Tasks.GetWalkingPath.Begin(robot, job, thisTask, "_WalkToLocation_GetWalkingPathCallback", robot.entity.position, targetLocation, surface)
    thisTask.currentTaskIndex = #thisTask.tasks

    return thisTask, ticksToWait
end

--- Called by GetWalkingPath when it has a result. Implements: GetWalkingPath_Begin_ResponseInterface
---@param getWalkingPathTask Task_GetWalkingPath_Data
---@param event EventData.on_script_path_request_finished
---@param requestData Task_GetWalkingPath_BespokeData
WalkToLocation._WalkToLocation_GetWalkingPathCallback = function(getWalkingPathTask, event, requestData)
    local thisTask = getWalkingPathTask.parentTask ---@cast thisTask Task_WalkToLocation_Data

    -- Handle if the path finder timed out.
    if event.try_again_later == true then
        LoggingUtils.LogPrintWarning("Path finder timed out from " .. LoggingUtils.PositionToString(requestData.startPosition) .. " to " .. LoggingUtils.PositionToString(requestData.endPosition) .. " so trying again.")

        -- Just keep on trying until we get a proper result. Each attempt is a new task.
        thisTask.tasks[#thisTask.tasks + 1] = MOD.Interfaces.Tasks.GetWalkingPath.Begin(thisTask.robot, thisTask.job, thisTask, "_WalkToLocation_GetWalkingPathCallback", thisTask.robot.entity.position, thisTask.taskData.targetLocation, thisTask.taskData.surface)
        thisTask.currentTaskIndex = #thisTask.tasks
        return
    end

    -- Handle if no path was found.
    if event.path == nil then
        game.print("Debug: no path found - no passing to caller implemented yet")
        -- FUTURE: callback to original calling task/job via interface name and let it decide what to do. I think this should escalate up to the job and have the final logic a that level as every task is should be coded just as a middleman?
        return
    end

    -- Record the path ready for the robot to call progress in future ticks and utilise the result.
    thisTask.taskData.pathToWalk = event.path
end

--- Called to continue progression on the task by on_tick.
---@param thisTask Task_WalkToLocation_Data
---@return uint ticksToWait
WalkToLocation.Progress = function(thisTask)
    -- If still waiting for path to be found.
    if thisTask.taskData.pathToWalk == nil then
        return MOD.Interfaces.Tasks.GetWalkingPath.Progress(thisTask.tasks[thisTask.currentTaskIndex]--[[@as Task_GetWalkingPath_Data]] )
    end

    -- Walk the path.
    local ticksToWait
    if thisTask.tasks[#thisTask.tasks].taskName == "GetWalkingPath" then
        -- We have a path, but no task to actually walk it, so start one.
        thisTask.tasks[#thisTask.tasks + 1], ticksToWait = MOD.Interfaces.Tasks.WalkPath.Begin(thisTask.robot, thisTask.job, thisTask, nil, thisTask.taskData.pathToWalk)
        thisTask.currentTaskIndex = #thisTask.tasks
    else
        ticksToWait = MOD.Interfaces.Tasks.WalkPath.Progress(thisTask.tasks[thisTask.currentTaskIndex]--[[@as Task_WalkPath_Data]] )
    end
    return ticksToWait
end

return WalkToLocation
