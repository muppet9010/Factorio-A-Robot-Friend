local LoggingUtils = require("utility.helper-utils.logging-utils")

---@class Task_WalkToLocation_Data : Task_Data
---@field taskData Task_WalkToLocation_BespokeData

---@class Task_WalkToLocation_BespokeData
---@field targetLocation MapPosition
---@field surface LuaSurface
---@field robot Robot

local WalkToLocation = {} ---@class Task_WalkToLocation_Interface : Task_Interface
WalkToLocation.taskName = "WalkToLocation"

WalkToLocation._OnLoad = function()
    MOD.Interfaces.Tasks.WalkToLocation = WalkToLocation
end

--- Called to create the task and start the process when an active robot first reaches this task.
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param parentCallbackFunctionName? string # The name this task calls when it wants to give its parent a status update of some sort.
---@param robot Robot
---@param targetLocation MapPosition
---@param surface LuaSurface
---@return Task_WalkToLocation_Data
WalkToLocation.Begin = function(job, parentTask, parentCallbackFunctionName, robot, targetLocation, surface)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(WalkToLocation.taskName, job, parentTask, parentCallbackFunctionName) ---@cast thisTask Task_WalkToLocation_Data

    -- Store the target data.
    thisTask.taskData = {
        targetLocation = targetLocation,
        surface = surface,
        robot = robot
    }

    -- Start the first child task straight away. Other tasks will be added/started based on this response.
    thisTask.tasks[#thisTask.tasks + 1] = MOD.Interfaces.Tasks.GetWalkingPath.Begin(job, thisTask, "_WalkToLocation_GetWalkingPathCallback", robot, robot.entity.position, targetLocation, surface)

    return thisTask
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
        thisTask.tasks[#thisTask.tasks + 1] = MOD.Interfaces.Tasks.GetWalkingPath.Begin(thisTask.job, thisTask, "_WalkToLocation_GetWalkingPathCallback", thisTask.taskData.robot, thisTask.taskData.robot.entity.position, thisTask.taskData.targetLocation, thisTask.taskData.surface)
        return
    end

    -- Handle if no path was found.
    if event.path == nil then
        game.print("Debug: no path found - no passing to caller implemented yet")
        -- FUTURE: callback to original calling task/job via interface name and let it decide what to do. I think this should escalate up to the job and have the final logic a that level as every task is should be coded just as a middleman?
        return
    end

    -- Hand off to the walking path task to manage the walking process.
    -- TODO: up to here
    --MOD.Interfaces.Tasks.WalkPath.Begin(requestDetails.robot, event.path)
end

return WalkToLocation
