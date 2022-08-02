local LoggingUtils = require("utility.helper-utils.logging-utils")

---@class Task_WalkToLocation_RequestDetails
---@field callbackTaskInterfaceName string
---@field callbackData? table<any, any>

local WalkToLocation = {} ---@class WalkToLocation : Task

WalkToLocation.OnLoad = function()
    MOD.Interfaces.Tasks.WalkToLocation = WalkToLocation
end

--- Request a new task to be created.
---@param targetLocation? MapPosition
---@param targetEntity? LuaEntity
---@param job Job # The job related to the lead task in this hierarchy.
---@param parentTask? Task # The parent Task or nil if this is a primary Task of a Job.
---@param parentCallbackFunctionName? string # The name this task calls when it wants to give its parent a status update of some sort.
---@return Task
WalkToLocation.Create = function(targetLocation, targetEntity, job, parentTask, parentCallbackFunctionName)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(WalkToLocation.taskName, job, parentTask, parentCallbackFunctionName)
    thisTask.tasks = {
        MOD.Interfaces.Tasks.GetWalkingPath.Create(targetLocation, targetEntity, job, thisTask, "_WalkToLocation_PathRequestResponseCallback"),
        -- TODO do the walking path task.
    }
end

--- Request a robot to walk to a given location.
---@param robot Robot
WalkToLocation.Initialise = function(robot)
    MOD.Interfaces.Tasks.GetWalkingPath(robot, robot.entity.surface, robot.entity.position, targetLocation, targetEntity, "_WalkToLocation_FoundPathCallback", eventData)
end

--- Called by the path finder when it has a result. Implements: Task_GetWalkingPath_FindPath_ResultInterface
---@param event EventData.on_script_path_request_finished
---@param requestDetails GetWalkingPath_RequestDetails
---@param eventData Task_WalkToLocation_RequestDetails
WalkToLocation._WalkToLocation_PathRequestResponseCallback = function(event, requestDetails, eventData)
    -- Handle if the path finder timed out.
    if event.try_again_later == true then
        LoggingUtils.LogPrintWarning("Path finder timed out from " .. LoggingUtils.PositionToString(requestDetails.startPosition) .. " to " .. LoggingUtils.PositionToString(requestDetails.endPosition) .. " so trying again.")

        -- Check the target entity is still valid, just warn if its not for now.
        if not requestDetails.endPositionEntity.valid then
            LoggingUtils.LogPrintWarning("The target entity is no longer valid, so being dropped from repeat path finder request.")
            requestDetails.endPositionEntity = nil
        end

        -- Just keep on trying until we get a proper result.
        MOD.Interfaces.Tasks.GetWalkingPath(requestDetails.robot, requestDetails.robot.entity.surface, requestDetails.robot.entity.position, requestDetails.endPosition, requestDetails.endPositionEntity, "_WalkToLocation_FoundPathCallback", data)
        return
    end

    -- Handle if no path was found.
    if event.path == nil then
        local callbackTaskInterfaceName, callbackData = eventData.callbackTaskInterfaceName, eventData.callbackData
        game.print("Debug: no path found - no passing to caller implemented yet")
        --TODO: callback to original calling function via interface name and let it decide what to do.
        return
    end

    -- Hand off to the walking path task to manage the walking process.
    MOD.Interfaces.Tasks.WalkPath(requestDetails.robot, event.path)
end

return WalkToLocation
