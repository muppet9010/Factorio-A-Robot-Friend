local LoggingUtils = require("utility.helper-utils.logging-utils")

---@class Task_WalkToLocation_Data : Task_Data
---@field taskData Task_WalkToLocation_BespokeData
---@field robotsTaskData table<Robot, Task_WalkToLocation_Robot_BespokeData>

---@class Task_WalkToLocation_BespokeData
---@field targetLocation MapPosition
---@field surface LuaSurface

---@class Task_WalkToLocation_Robot_BespokeData : Task_Data_Robot
---@field pathToWalk? PathfinderWaypoint[]
---@field pathToWalkDebugRenderIds? uint64[]

local WalkToLocation = {} ---@class Task_WalkToLocation_Interface : Task_Interface
WalkToLocation.taskName = "WalkToLocation"

WalkToLocation._OnLoad = function()
    MOD.Interfaces.Tasks.WalkToLocation = WalkToLocation
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param targetLocation MapPosition
---@param surface LuaSurface
---@return Task_WalkToLocation_Data
WalkToLocation.ActivateTask = function(job, parentTask, targetLocation, surface)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(WalkToLocation.taskName, job, parentTask) ---@cast thisTask Task_WalkToLocation_Data

    -- Store the task wide data.
    thisTask.taskData = {
        targetLocation = targetLocation,
        surface = surface,
    }

    return thisTask
end

--- Called to do work on the task by on_tick by each robot.
---@param thisTask Task_WalkToLocation_Data
---@param robot Robot
---@return uint ticksToWait
WalkToLocation.Progress = function(thisTask, robot)
    local taskData = thisTask.taskData

    -- Handle if this is the very first robot to Progress() this Task.
    if thisTask.currentTaskIndex == 0 then
        -- Activate both tasks initially as there's no meaningful variation in the second task based on the first tasks output.
        thisTask.tasks[#thisTask.tasks + 1] = MOD.Interfaces.Tasks.GetWalkingPath.ActivateTask(thisTask.job, thisTask, taskData.targetLocation, taskData.surface)
        thisTask.tasks[#thisTask.tasks + 1] = MOD.Interfaces.Tasks.WalkPath.ActivateTask(thisTask.job, thisTask)
        thisTask.currentTaskIndex = 1
    end

    -- Handle if this is the first Progress() for a robot.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData == nil then
        -- Record robot specific details to this task.
        robotTaskData = MOD.Interfaces.TaskManager.CreateGenericRobotTaskData(robot, thisTask.currentTaskIndex, thisTask) --[[@as Task_WalkToLocation_Robot_BespokeData]]
        thisTask.robotsTaskData[robot] = robotTaskData

        -- Call the first task Progress() and return its wait.
        return MOD.Interfaces.Tasks.GetWalkingPath.Progress(thisTask.tasks[robotTaskData.currentTaskIndex]--[[@as Task_GetWalkingPath_Data]] , robot, robot.entity.position)
    end

    -------------------------------------------------------------------------------
    -- Handle child task Progress() fully per robot as both have no shared data. --
    -------------------------------------------------------------------------------

    -- If still waiting for path to be found.
    if robotTaskData.pathToWalk == nil then
        local getWalkingPathTask = thisTask.tasks[robotTaskData.currentTaskIndex] --[[@as Task_GetWalkingPath_Data]]
        local getWalkingPathTask_taskData = getWalkingPathTask.taskData
        local getWalkingPathTask_robotTaskData = getWalkingPathTask.robotsTaskData[robot]

        -- Check if the pathfinder has completed.
        if getWalkingPathTask_robotTaskData.state == "completed" then
            -- Handle if the path finder timed out.
            if getWalkingPathTask_robotTaskData.pathFinderTimeout == true then
                LoggingUtils.LogPrintWarning("Path finder timed out from " .. LoggingUtils.PositionToString(getWalkingPathTask_robotTaskData.startPosition) .. " to " .. LoggingUtils.PositionToString(getWalkingPathTask_taskData.endPosition) .. " so trying again.")

                -- Just keep on trying until we get a proper result. Each attempt is a reset of this sub tasks robot data. So next poll it will start that request again in the hope the pathfinder is less busy.
                getWalkingPathTask.robotsTaskData[robot] = nil
                return 1
            end

            -- Handle if no path was found.
            if getWalkingPathTask_robotTaskData.pathFound == nil then
                LoggingUtils.LogPrintWarning("No path found from " .. LoggingUtils.PositionToString(getWalkingPathTask_robotTaskData.startPosition) .. " to " .. LoggingUtils.PositionToString(getWalkingPathTask_taskData.endPosition) .. " so giving up as no better handler is currently coded.")
                -- FUTURE: callback to original calling task/job via interface name and let it decide what to do. I think this should escalate up to the job and have the final logic a that level as every task is should be coded just as a middleman?
                return 1
            end

            -- Record the path ready for the robot to call progress in future ticks and utilise the result.
            robotTaskData.pathToWalk = getWalkingPathTask_robotTaskData.pathFound

            -- Draw the path in the game as a one off if the debug setting is enabled.
            if global.Settings.Debug.showPathWalking then
                robotTaskData.pathToWalkDebugRenderIds = LoggingUtils.DrawPath(robotTaskData.pathToWalk, taskData.surface, robotTaskData.robot.fontColor, "start", "end")
            end

            -- As we have a path flow in to the walking process.
            robotTaskData.currentTaskIndex = robotTaskData.currentTaskIndex + 1
        else
            -- Still waiting for the pathfinder to complete so this is all we need to do this Progress().
            return MOD.Interfaces.Tasks.GetWalkingPath.Progress(getWalkingPathTask, robot)
        end
    end

    -- Walk the path as we have one at this point.
    local walkPathTask = thisTask.tasks[robotTaskData.currentTaskIndex] --[[@as Task_WalkPath_Data]]
    local walkPathTask_robotTaskData = walkPathTask.robotsTaskData[robot]
    local ticksToWait = MOD.Interfaces.Tasks.WalkPath.Progress(walkPathTask, robot, robotTaskData.pathToWalk)
    if walkPathTask_robotTaskData.state == "completed" then
        -- Have walked to location.
        walkPathTask_robotTaskData.state = "completed"

        -- Tidy up any renders that existed for the duration of the task.
        if robotTaskData.pathToWalkDebugRenderIds ~= nil then
            for _, renderId in pairs(robotTaskData.pathToWalkDebugRenderIds) do
                rendering.destroy(renderId)
            end
        end

        return 0
    end

    return ticksToWait
end

--- Called to remove a task. This will propagates down to all sub tasks to tidy up any non task managed globals and other active effects.
---@param thisTask Task_WalkToLocation_Data
WalkToLocation.Remove = function(thisTask)
    -- Nothing unique this task needs to do.
    MOD.Interfaces.TaskManager.GenericTaskPropagateRemove(thisTask)
end

return WalkToLocation
