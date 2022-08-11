--[[
    Manages robots deconstructing the entities in a ChunkDetails list. Takes the output of ScanAreasForActionsToComplete and updates it as it progresses it.
    Basic logic is being used for now:
        - Have only 1 robot assigned to a single chunk at a time.
        - The robot will do everything it can within that chunk before moving on.
        - Next chunk will be the nearest one that it can do something for, while favouring chunks on the edge of the combined areas if 2 are found at same chunk distance.
]]

local ShowRobotState = require("scripts.common.show-robot-state")

-- TODO: isn't this task state data? making the bespokeData actual task data. If so rename all.
---@class Task_DeconstructEntitiesInChunkDetails_Data : Task_Details
---@field taskData Task_DeconstructEntitiesInChunkDetails_TaskData
---@field robotsTaskData table<Robot, Task_DeconstructEntitiesInChunkDetails_Robot_TaskData>

---@class Task_DeconstructEntitiesInChunkDetails_TaskData
---@field surface LuaSurface
---@field chunkDetailsByAxis Task_ScanAreasForActionsToComplete_ChunksInCombinedAreas
---@field chunksState table<string, Task_DeconstructEntitiesInChunkDetails_ChunkState> # Keyed by the chunks position as a string.
---@field entitiesToBeDeconstructed table<uint, Task_ScanAreasForActionsToComplete_EntityDetails> # The main list of entities to be deconstructed that is used by things outside of this task. So remove entries from it as we do them.
---@field startingChunkPosition ChunkPosition

---@class Task_DeconstructEntitiesInChunkDetails_Robot_TaskData : TaskData_Robot
---@field assignedChunkDetails Task_ScanAreasForActionsToComplete_ChunkDetails
---@field assignedChunkState Task_DeconstructEntitiesInChunkDetails_ChunkState

---@class Task_DeconstructEntitiesInChunkDetails_ChunkState
---@field positionString string # The Id of this in the table.
---@field state Task_DeconstructEntitiesInChunkDetails_ChunkStates
---@field assignedRobot? Robot
---@field chunkDetails Task_ScanAreasForActionsToComplete_ChunkDetails

local DeconstructEntitiesInChunkDetails = {} ---@class Task_DeconstructEntitiesInChunkDetails_Interface : Task_Interface
DeconstructEntitiesInChunkDetails.taskName = "DeconstructEntitiesInChunkDetails"

---@enum Task_DeconstructEntitiesInChunkDetails_ChunkStates
DeconstructEntitiesInChunkDetails.ChunkStates = {
    available = "available",
    assigned = "assigned",
    completed = "completed"
}

DeconstructEntitiesInChunkDetails._OnLoad = function()
    MOD.Interfaces.Tasks.DeconstructEntitiesInChunkDetails = DeconstructEntitiesInChunkDetails
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Details # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Details # The parent Task or nil if this is a primary Task of a Job.
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
        chunksState = {},
        entitiesToBeDeconstructed = entitiesToBeDeconstructed,
        startingChunkPosition = startingChunkPosition,
        robotAssignedChunks = {}
    }

    -- Populate the chunk deconstruction states list with all the chunks that need things doing.
    local chunksState = thisTask.taskData.chunksState
    for _, xChunkObject in pairs(chunkDetailsByAxis.xChunks) do
        for _, chunkDetails in pairs(xChunkObject.yChunks) do
            if #chunkDetails.toBeDeconstructedEntityDetails > 0 then
                chunksState[chunkDetails.chunkPositionString] = {
                    positionString = chunkDetails.chunkPositionString,
                    state = DeconstructEntitiesInChunkDetails.ChunkStates.available,
                    assignedRobot = nil,
                    chunkDetails = chunkDetails
                }
            end
        end
    end

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
        robotTaskData = MOD.Interfaces.TaskManager.CreateGenericRobotTaskData(robot, thisTask.currentTaskIndex, thisTask) --[[@as Task_DeconstructEntitiesInChunkDetails_Robot_TaskData]]
        thisTask.robotsTaskData[robot] = robotTaskData
    end

    -- If the robot doesn't have a chunk to work on or its chunk has been marked as completed assign it a new one.
    if robotTaskData.assignedChunkState == nil or robotTaskData.assignedChunkState.state == DeconstructEntitiesInChunkDetails.ChunkStates.completed then
        local chunkFound = DeconstructEntitiesInChunkDetails.FindChunkForRobot(robotTaskData, taskData)
        if chunkFound == nil then
            -- No chunks left to be done.

            -- If no robot has an active chunk its working on, then the job is done as we couldn't find a new one.
            local aChunkIsStillActive = false
            for _, chunksState in pairs(taskData.chunksState) do
                if chunksState ~= DeconstructEntitiesInChunkDetails.ChunkStates.completed then
                    aChunkIsStillActive = true
                    break
                end
            end
            if not aChunkIsStillActive then
                thisTask.state = "completed"
                return 60, { stateText = "Thinking about post deconstructing tasks", level = ShowRobotState.StateLevel.normal }
            end

            -- So just wait where it is for a second and check back.
            return 60, { stateText = "Waiting for other robots to finish deconstructing", level = ShowRobotState.StateLevel.normal }
        end
        -- Chunk found so record it.
        local chunkState = taskData.chunksState[chunkFound.chunkPositionString]
        chunkState.state = DeconstructEntitiesInChunkDetails.ChunkStates.assigned
        chunkState.assignedRobot = robotTaskData.robot
        robotTaskData.assignedChunkDetails = chunkFound
        robotTaskData.assignedChunkState = chunkState
    end

    -- TODO: as the robot has a chunk to work on, continue processing it. Return if it's got another thing to do on the current chunk.
    -- TODO: here we loop over if any actions are within range and if not then move towards the nearest one and then start deconstructing there. Should try to move "near" the target and if that fails then further away. Will need enhancements to the path finder.



    -- As the robot has completed everything on this chunk then mark the chunk as done for deconstruction. It will find a new chunk on next loop. We leave the robot assigned to the chunk as the searching for chunk will use this data before overwriting it.
    robotTaskData.assignedChunkState.state = DeconstructEntitiesInChunkDetails.ChunkStates.completed

    ---@type uint,ShowRobotState_NewRobotStateDetails
    local ticksToWait, robotStateDetails = 60, { stateText = "Thinking about next deconstruction chunk", level = ShowRobotState.StateLevel.normal }

    return ticksToWait, robotStateDetails
end

--- Find the robot a chunk to work on.
---@param robotTaskData Task_DeconstructEntitiesInChunkDetails_Robot_TaskData
---@param taskData Task_DeconstructEntitiesInChunkDetails_TaskData
---@return Task_ScanAreasForActionsToComplete_ChunkDetails|nil # Nil is only returned if there are no available chunks to be assigned.
DeconstructEntitiesInChunkDetails.FindChunkForRobot = function(robotTaskData, taskData)
    --  If it had one before find it one near by, otherwise find it one nearest the startingChunk.
    local startSearchingChunkPosition = robotTaskData.assignedChunkDetails and robotTaskData.assignedChunkDetails.chunkPosition or taskData.startingChunkPosition

    -- Check if the starting chunk needs to be done. As the loopy searching will always check around the robot's current chunk.
    local startingChunk = taskData.chunkDetailsByAxis.xChunks[taskData.startingChunkPosition.x].yChunks[taskData.startingChunkPosition.y]
    if taskData.chunksState[startingChunk.chunkPositionString] ~= nil and taskData.chunksState[startingChunk.chunkPositionString].state == DeconstructEntitiesInChunkDetails.ChunkStates.available then
        return startingChunk
    end

    -- Next chunk will be the nearest one that it can do something for, while favouring chunks on the edge of the combined areas if 2 are found at same chunk distance.
    local xIteratorPrimary, yIteratorPrimary
    if startSearchingChunkPosition.x < taskData.chunkDetailsByAxis.minXValue + ((taskData.chunkDetailsByAxis.maxXValue - taskData.chunkDetailsByAxis.minXValue) / 2) then
        xIteratorPrimary = -1
    else
        xIteratorPrimary = 1
    end
    if startSearchingChunkPosition.y < taskData.chunkDetailsByAxis.minYValueAcrossAllXValues + ((taskData.chunkDetailsByAxis.maxYValueAcrossAllXValues - taskData.chunkDetailsByAxis.minYValueAcrossAllXValues) / 2) then
        yIteratorPrimary = -1
    else
        yIteratorPrimary = 1
    end

    -- Look for a chunk we can do something in. Only check the included chunks.
    local distanceToCheck = 1
    local centerXPosition, centerYPosition = startSearchingChunkPosition.x, startSearchingChunkPosition.y
    local xPosition, yPosition, xChunkObject, foundChunk
    local maxDistanceAcrossIncludedChunks = math.max((taskData.chunkDetailsByAxis.maxXValue - taskData.chunkDetailsByAxis.minXValue), (taskData.chunkDetailsByAxis.maxYValueAcrossAllXValues - taskData.chunkDetailsByAxis.minYValueAcrossAllXValues))
    while distanceToCheck < maxDistanceAcrossIncludedChunks do
        for xMod = 0 + xIteratorPrimary, 0 - xIteratorPrimary, 0 - xIteratorPrimary do
            xPosition = centerXPosition + (xMod * distanceToCheck)
            if xPosition >= taskData.chunkDetailsByAxis.minXValue and xPosition <= taskData.chunkDetailsByAxis.maxXValue then
                xChunkObject = taskData.chunkDetailsByAxis.xChunks[xPosition]
                if xChunkObject ~= nil then
                    for yMod = 0 + yIteratorPrimary, 0 - yIteratorPrimary, 0 - yIteratorPrimary do
                        yPosition = centerYPosition + (yMod * distanceToCheck)
                        if yPosition >= xChunkObject.minYValue and yPosition <= xChunkObject.maxYValue then
                            foundChunk = xChunkObject.yChunks[yPosition]
                            if foundChunk ~= nil and taskData.chunksState[foundChunk.chunkPositionString] ~= nil and taskData.chunksState[foundChunk.chunkPositionString].state == DeconstructEntitiesInChunkDetails.ChunkStates.available then
                                return foundChunk
                            end
                        end
                    end
                end
            end
        end
        distanceToCheck = distanceToCheck + 1
    end

    -- No chunks left need doing.
    return nil
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
