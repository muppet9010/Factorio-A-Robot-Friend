--[[
    Walks a robot to the target location by finding a path and then walking that path. If the path is blocked it tries to obtain an alternative path. Failure to find a path is a failure for the robot and it goes in to standby.

    Each robot is processed fully separately to the others as both sub tasks are action tasks and there's no shared elements between robots in any task.
]]

local LoggingUtils = require("utility.helper-utils.logging-utils")
local ShowRobotState = require("scripts.common.show-robot-state")

---@class Task_WalkToLocation_Details : Task_Details
---@field taskData Task_WalkToLocation_TaskData
---@field robotsTaskData table<Robot, Task_WalkToLocation_Robot_TaskData>

---@class Task_WalkToLocation_TaskData
---@field targetLocation MapPosition
---@field surface LuaSurface
---@field closenessToTargetLocation double

---@class Task_WalkToLocation_Robot_TaskData : TaskData_Robot
---@field pathToWalk? PathfinderWaypoint[]
---@field pathToWalkDebugRenderIds? uint64[]
---@field state TaskData_Robot.state|"noPath"

local WalkToLocation = {} ---@class Task_WalkToLocation_Interface : Task_Interface
WalkToLocation.taskName = "WalkToLocation"

WalkToLocation._OnLoad = function()
    MOD.Interfaces.Tasks.WalkToLocation = WalkToLocation
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Details # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Details # The parent Task or nil if this is a primary Task of a Job.
---@param targetLocation MapPosition
---@param surface LuaSurface
---@param closenessToTargetLocation double # How close we need the path to get to the targetLocation
---@return Task_WalkToLocation_Details
WalkToLocation.ActivateTask = function(job, parentTask, targetLocation, surface, closenessToTargetLocation)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(WalkToLocation.taskName, job, parentTask) ---@cast thisTask Task_WalkToLocation_Details

    -- Store the task wide data.
    thisTask.taskData = {
        targetLocation = targetLocation,
        surface = surface,
        closenessToTargetLocation = closenessToTargetLocation
    }

    return thisTask
end

--- Called to do work on the task by on_tick by each robot.
---@param thisTask Task_WalkToLocation_Details
---@param robot Robot
---@return uint ticksToWait
---@return ShowRobotState_NewRobotStateDetails robotStateDetails
WalkToLocation.Progress = function(thisTask, robot)
    local taskData = thisTask.taskData

    -- Handle if this is the very first robot to Progress() this Task.
    if thisTask.currentTaskIndex == 0 then
        -- Activate both tasks initially as there's no meaningful variation in the second task based on the first tasks output.
        thisTask.plannedTasks[#thisTask.plannedTasks + 1] = MOD.Interfaces.Tasks.GetWalkingPath.ActivateTask(thisTask.job, thisTask, taskData.targetLocation, taskData.surface, taskData.closenessToTargetLocation)
        thisTask.plannedTasks[#thisTask.plannedTasks + 1] = MOD.Interfaces.Tasks.WalkPath.ActivateTask(thisTask.job, thisTask)
        thisTask.currentTaskIndex = 1
    end

    -- Handle if this is the first Progress() for a robot.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData == nil then
        -- Record robot specific details to this task.
        robotTaskData = MOD.Interfaces.TaskManager.CreateGenericRobotTaskData(robot, thisTask.currentTaskIndex, thisTask) --[[@as Task_WalkToLocation_Robot_TaskData]]
        thisTask.robotsTaskData[robot] = robotTaskData

        -- Call the first task Progress() and return its wait.
        return MOD.Interfaces.Tasks.GetWalkingPath.Progress(thisTask.plannedTasks[robotTaskData.currentTaskIndex]--[[@as Task_GetWalkingPath_Details]] , robot, robot.entity.position)
    end

    -------------------------------------------------------------------------------
    -- Handle child task Progress() fully per robot as both have no shared data. --
    -------------------------------------------------------------------------------

    -- If this Task hasn't process a found path yet.
    if robotTaskData.pathToWalk == nil then
        local getWalkingPathTask = thisTask.plannedTasks[robotTaskData.currentTaskIndex] --[[@as Task_GetWalkingPath_Details]]
        local getWalkingPathTask_taskData = getWalkingPathTask.taskData
        local getWalkingPathTask_robotTaskData = getWalkingPathTask.robotsTaskData[robot]

        -- Check if the pathfinder has completed.
        if getWalkingPathTask_robotTaskData.state == "completed" then
            -- Handle if the path finder timed out.
            if getWalkingPathTask_robotTaskData.pathFinderTimeout == true then
                LoggingUtils.LogPrintWarning(robot.name .. "'s path finder timed out from " .. LoggingUtils.PositionToString(getWalkingPathTask_robotTaskData.startPosition) .. " to " .. LoggingUtils.PositionToString(getWalkingPathTask_taskData.endPosition) .. " so trying again.")

                -- Just keep on trying until we get a proper result. Each attempt is a reset of this sub tasks robot data. So next poll it will start that request again in the hope the pathfinder is less busy.
                -- CODE NOTE: this is on the assumption that if a path is found the robot can try and follow it.
                getWalkingPathTask.robotsTaskData[robot] = nil
                ---@type ShowRobotState_NewRobotStateDetails
                local robotStateDetails = { stateText = "Going to start a new path search", level = "warning" }
                return 60, robotStateDetails
            end

            -- Handle if no path was found.
            if getWalkingPathTask_robotTaskData.pathFound == nil then
                LoggingUtils.LogPrintWarning(robot.name .. " failed to get a path from " .. LoggingUtils.PositionToString(getWalkingPathTask_robotTaskData.startPosition) .. " to " .. LoggingUtils.PositionToString(getWalkingPathTask_taskData.endPosition))
                ---@type ShowRobotState_NewRobotStateDetails
                local robotStateDetails = { stateText = "No path found", level = "warning" }
                robotTaskData.state = "noPath"

                -- If this is the primary task then deal with the issue, otherwise it gets passed up the chain.
                if thisTask.parentTask == nil then
                    MOD.Interfaces.RobotManager.SetRobotInStandby(robot)
                end

                return 0, robotStateDetails
            end

            -- Record the path for the robot to use in future calls of Progress().
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
    local walkPathTask = thisTask.plannedTasks[robotTaskData.currentTaskIndex] --[[@as Task_WalkPath_Details]]
    local ticksToWait, robotStateDetails = MOD.Interfaces.Tasks.WalkPath.Progress(walkPathTask, robot, robotTaskData.pathToWalk)
    local walkPathTask_robotTaskData = walkPathTask.robotsTaskData[robot]

    -- Check and handle if the path walker got stuck.
    if walkPathTask_robotTaskData.state == "stuck" then
        LoggingUtils.LogPrintWarning(robot.name .. " got stuck, so trying to path around issue")

        -- Clear the data from the task and its children for just this robot. Then re-run the process again to try and find a fresh valid path.
        WalkToLocation.RemovingRobotFromTask(thisTask, robot)
        return WalkToLocation.Progress(thisTask, robot)
    end

    -- Check and handle if the path walker completed.
    if walkPathTask_robotTaskData.state == "completed" then
        -- Have walked to location.
        robotTaskData.state = "completed"

        -- Tidy up any renders that existed for the duration of the task.
        if robotTaskData.pathToWalkDebugRenderIds ~= nil then
            for _, renderId in pairs(robotTaskData.pathToWalkDebugRenderIds) do
                rendering.destroy(renderId)
            end
        end

        ---@type ShowRobotState_NewRobotStateDetails
        local robotStateDetails = { stateText = "Robot arrived at requested location", level = "normal" }

        return 0, robotStateDetails
    end

    return ticksToWait, robotStateDetails
end

--- Called when a specific robot is being removed from a task.
---@param thisTask Task_WalkToLocation_Details
---@param robot Robot
WalkToLocation.RemovingRobotFromTask = function(thisTask, robot)
    -- Tidy up any renders that existed for the duration of the task.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData ~= nil and robotTaskData.pathToWalkDebugRenderIds ~= nil then
        for _, renderId in pairs(robotTaskData.pathToWalkDebugRenderIds) do
            rendering.destroy(renderId)
        end
    end

    -- Remove any robot specific task data.
    thisTask.robotsTaskData[robot] = nil

    MOD.Interfaces.TaskManager.GenericTaskPropagateRemoveRobot(thisTask, robot)
end

--- Called when a task is being removed and any task globals or ongoing activities need to be stopped.
---@param thisTask Task_WalkToLocation_Details
WalkToLocation.RemovingTask = function(thisTask)
    -- Nothing unique this task needs to do.

    MOD.Interfaces.TaskManager.GenericTaskPropagateRemove(thisTask)
end

--- Called when pausing a robot and so all of its activities within the this task and sub tasks need to pause.
---@param thisTask Task_WalkToLocation_Details
---@param robot Robot
WalkToLocation.PausingRobotForTask = function(thisTask, robot)
    -- Nothing unique this task needs to do.

    MOD.Interfaces.TaskManager.GenericTaskPropagatePausingRobot(thisTask, robot)
end

return WalkToLocation
