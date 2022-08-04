local LoggingUtils = require("utility.helper-utils.logging-utils")

---@class Task_WalkToLocation_Data : Task_Data
---@field taskData Task_WalkToLocation_BespokeData

---@class Task_WalkToLocation_BespokeData
---@field targetLocation MapPosition
---@field surface LuaSurface
---@field pathToWalk? PathfinderWaypoint[]
---@field pathToWalkDebugRenderIds? uint64[]

local WalkToLocation = {} ---@class Task_WalkToLocation_Interface : Task_Interface
WalkToLocation.taskName = "WalkToLocation"

WalkToLocation._OnLoad = function()
    MOD.Interfaces.Tasks.WalkToLocation = WalkToLocation
end

--- Called to create the task and start the process when an active robot first reaches this task.
---@param robot Robot
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param targetLocation MapPosition
---@param surface LuaSurface
---@return Task_WalkToLocation_Data
---@return uint ticksToWait
WalkToLocation.Begin = function(robot, job, parentTask, targetLocation, surface)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(WalkToLocation.taskName, robot, job, parentTask) ---@cast thisTask Task_WalkToLocation_Data

    -- Store the target data.
    thisTask.taskData = {
        targetLocation = targetLocation,
        surface = surface,
    }

    -- Start the first child task straight away. Other tasks will be added/started on the Progress() as getting a path is async.
    local ticksToWait
    thisTask.tasks[#thisTask.tasks + 1], ticksToWait = MOD.Interfaces.Tasks.GetWalkingPath.Begin(robot, job, thisTask, robot.entity.position, targetLocation, surface)
    thisTask.currentTaskIndex = #thisTask.tasks

    return thisTask, ticksToWait
end

--- Called to continue progression on the task by on_tick.
---@param thisTask Task_WalkToLocation_Data
---@return uint ticksToWait
WalkToLocation.Progress = function(thisTask)
    local ticksToWait

    -- If still waiting for path to be found.
    if thisTask.taskData.pathToWalk == nil then
        local getWalkingPathTask = thisTask.tasks[thisTask.currentTaskIndex] --[[@as Task_GetWalkingPath_Data]]

        -- Check if the pathfinder has completed.
        if getWalkingPathTask.state == "completed" then
            -- Handle if the path finder timed out.
            if getWalkingPathTask.taskData.pathFinderTimeout == true then
                LoggingUtils.LogPrintWarning("Path finder timed out from " .. LoggingUtils.PositionToString(getWalkingPathTask.taskData.startPosition) .. " to " .. LoggingUtils.PositionToString(getWalkingPathTask.taskData.endPosition) .. " so trying again.")

                -- Just keep on trying until we get a proper result. Each attempt is a new task.
                thisTask.tasks[#thisTask.tasks + 1], ticksToWait = MOD.Interfaces.Tasks.GetWalkingPath.Begin(thisTask.robot, thisTask.job, thisTask, thisTask.robot.entity.position, thisTask.taskData.targetLocation, thisTask.taskData.surface)
                thisTask.currentTaskIndex = #thisTask.tasks
                return ticksToWait
            end

            -- Handle if no path was found.
            if getWalkingPathTask.taskData.pathFound == nil then
                game.print("Debug: no path found - no passing to caller implemented yet")
                -- FUTURE: callback to original calling task/job via interface name and let it decide what to do. I think this should escalate up to the job and have the final logic a that level as every task is should be coded just as a middleman?
                return 0
            end

            -- Record the path ready for the robot to call progress in future ticks and utilise the result.
            thisTask.taskData.pathToWalk = getWalkingPathTask.taskData.pathFound

            if global.Settings.Debug.showPathWalking then
                thisTask.taskData.pathToWalkDebugRenderIds = LoggingUtils.DrawPath(thisTask.taskData.pathToWalk, thisTask.taskData.surface, thisTask.robot.fontColor, "start", "end")
            end

            -- As we have a path flow in to the walking process.
        else
            -- Still waiting for the pathfinder to complete so this is all we need to do this Progress().
            return MOD.Interfaces.Tasks.GetWalkingPath.Progress(thisTask.tasks[thisTask.currentTaskIndex]--[[@as Task_GetWalkingPath_Data]] )
        end
    end

    -- Walk the path.
    if thisTask.tasks[#thisTask.tasks].taskName == "GetWalkingPath" then
        -- We have a path, but no task to actually walk it, so start one.
        thisTask.tasks[#thisTask.tasks + 1], ticksToWait = MOD.Interfaces.Tasks.WalkPath.Begin(thisTask.robot, thisTask.job, thisTask, thisTask.taskData.pathToWalk)
        thisTask.currentTaskIndex = #thisTask.tasks
    else
        ticksToWait = MOD.Interfaces.Tasks.WalkPath.Progress(thisTask.tasks[thisTask.currentTaskIndex]--[[@as Task_WalkPath_Data]] )
        if thisTask.tasks[thisTask.currentTaskIndex]--[[@as Task_WalkPath_Data]] .state == "completed" then
            -- Have walked to location.
            MOD.Interfaces.TaskManager.TaskCompleted(thisTask)

            -- Tidy up any renders that existed for the duration of the task.
            if thisTask.taskData.pathToWalkDebugRenderIds ~= nil then
                for _, renderId in pairs(thisTask.taskData.pathToWalkDebugRenderIds) do
                    rendering.destroy(renderId)
                end
            end

            return 0
        end
    end
    return ticksToWait
end

return WalkToLocation
