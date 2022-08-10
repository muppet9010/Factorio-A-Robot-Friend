--[[
    Manages robots deconstructing the entities in a ChunkDetails list. Takes the output of ScanAreasForActionsToComplete and updates it as it progresses it.
    Only 1 robot will be assigned to a chunk at a time.
]]

local ShowRobotState = require("scripts.common.show-robot-state")

---@class Task_DeconstructEntitiesInChunkDetails_Data : Task_Data
---@field taskData Task_DeconstructEntitiesInChunkDetails_BespokeData
---@field robotsTaskData table<Robot, Task_DeconstructEntitiesInChunkDetails_Robot_BespokeData>

---@class Task_DeconstructEntitiesInChunkDetails_BespokeData
---@field surface LuaSurface
---@field chunkDetailsByAxis Task_ScanAreasForActionsToComplete_ChunksInCombinedAreas
---@field entitiesToBeDeconstructed table<uint, Task_ScanAreasForActionsToComplete_EntityDetails>

---@class Task_DeconstructEntitiesInChunkDetails_Robot_BespokeData : Task_Data_Robot
---@field state "active"|"completed"

local DeconstructEntitiesInChunkDetails = {} ---@class Task_DeconstructEntitiesInChunkDetails_Interface : Task_Interface
DeconstructEntitiesInChunkDetails.taskName = "DeconstructEntitiesInChunkDetails"

DeconstructEntitiesInChunkDetails._OnLoad = function()
    MOD.Interfaces.Tasks.DeconstructEntitiesInChunkDetails = DeconstructEntitiesInChunkDetails
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param surface LuaSurface
---@param chunkDetailsByAxis Task_ScanAreasForActionsToComplete_ChunksInCombinedAreas
---@param startingChunkPosition ChunkPosition
---@param entitiesToBeDeconstructed table<uint, Task_ScanAreasForActionsToComplete_EntityDetails>
---@return Task_DeconstructEntitiesInChunkDetails_Data
DeconstructEntitiesInChunkDetails.ActivateTask = function(job, parentTask, surface, chunkDetailsByAxis, entitiesToBeDeconstructed, startingChunkPosition)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(DeconstructEntitiesInChunkDetails.taskName, job, parentTask) ---@cast thisTask Task_DeconstructEntitiesInChunkDetails_Data

    -- Store the task wide data.
    thisTask.taskData = {
        surface = surface,
        chunkDetailsByAxis = chunkDetailsByAxis,
        entitiesToBeDeconstructed = entitiesToBeDeconstructed,
        startingChunkPosition = startingChunkPosition
    }

    return thisTask
end

--- Called to do work on the task by on_tick by each robot.
---@param thisTask Task_DeconstructEntitiesInChunkDetails_Data
---@param robot Robot
---@return uint ticksToWait
---@return ShowRobotState_NewRobotStateDetails|nil robotStateDetails # nil if there is no state being set by this Task
DeconstructEntitiesInChunkDetails.Progress = function(thisTask, robot)
    local taskData = thisTask.taskData

    -- Handle if this is the first Progress() for a specific robot.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData == nil then
        -- Record robot specific details to this task.
        robotTaskData = MOD.Interfaces.TaskManager.CreateGenericRobotTaskData(robot, thisTask.currentTaskIndex, thisTask) --[[@as Task_DeconstructEntitiesInChunkDetails_Robot_BespokeData]]
        thisTask.robotsTaskData[robot] = robotTaskData
    end

    -- TODO: if the robot doesn't have a chunk to work on assign it one. If it had one before find it one near by, otherwise find it one nearest the startingChunk.

    -- TODO: if the robot has a chunk to work on continue processing it

    ---@type uint,ShowRobotState_NewRobotStateDetails
    local ticksToWait, robotStateDetails = 0, { stateText = "Some state text", level = ShowRobotState.StateLevel.normal }

    return ticksToWait, robotStateDetails
end

--TODO: functions below here untouched from template.

--- Called when a specific robot is being removed from a task.
---@param thisTask Task_DeconstructEntitiesInChunkDetails_Data
---@param robot Robot
DeconstructEntitiesInChunkDetails.RemovingRobotFromTask = function(thisTask, robot)
    -- Tidy up any robot specific stuff.
    local robotTaskData = thisTask.robotsTaskData[robot]

    -- Remove any robot specific task data.
    thisTask.robotsTaskData[robot] = nil

    MOD.Interfaces.TaskManager.GenericTaskPropagateRemoveRobot(thisTask, robot)
end

--- Called when a task is being removed and any task globals or ongoing activities need to be stopped.
---@param thisTask Task_DeconstructEntitiesInChunkDetails_Data
DeconstructEntitiesInChunkDetails.RemovingTask = function(thisTask)
    -- Remove any per robot bits if the robot is still active.
    for _, robotTaskData in pairs(thisTask.robotsTaskData) do
        if robotTaskData.state == "active" then
        end
    end

    MOD.Interfaces.TaskManager.GenericTaskPropagateRemove(thisTask)
end

--- Called when pausing a robot and so all of its activities within the this task and sub tasks need to pause.
---@param thisTask Task_DeconstructEntitiesInChunkDetails_Data
---@param robot Robot
DeconstructEntitiesInChunkDetails.PausingRobotForTask = function(thisTask, robot)
    -- If the robot was being actively used in some way stop it.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData ~= nil and robotTaskData.state == "active" then
    end

    MOD.Interfaces.TaskManager.GenericTaskPropagatePausingRobot(thisTask, robot)
end

return DeconstructEntitiesInChunkDetails
