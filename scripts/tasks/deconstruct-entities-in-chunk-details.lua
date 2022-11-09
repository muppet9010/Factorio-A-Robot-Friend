--[[
    Manages robots deconstructing the entities in a ChunkDetails list, taken as the output from ScanAreasForActionsToComplete. It will update the core data of this output as it progresses it.

    Basic logic is being used for now:
        - Have only 1 robot assigned to a single chunk at a time.
        - The robot will do everything it can within that chunk before moving on.
        - Next chunk will be the nearest one that it can do something for, while favouring chunks on the edge of the combined areas if 2 are found at same chunk distance.
        - The robot will path to within range of the nearest target, mine it, then look for a new target in range (any) or the nearest one out of range and start pathing to it. This is simple logic and does may cause some stuttered moving/mining if targets are close together (i.e. in a line away from the robot).

    Mining will be done by calling the LuaControl.mine_entity API function to instantly mine the target. The robot will then wait for the mining time to expire before it looks for another action. Use of this instant mine over setting the mining state is mainly to avoid issues if the target entity is removed another way, the robot is moved by being on a belt or killed. The effect should be the same, but the code is just much simpler.
]]

local PositionUtils = require("utility.helper-utils.position-utils")
local PrototypeAttributes = require("utility.functions.prototype-attributes")
local math_ceil = math.ceil

---@class Task_DeconstructEntitiesInChunkDetails_Details : Task_Details
---@field taskData Task_DeconstructEntitiesInChunkDetails_TaskData
---@field robotsTaskData table<Robot, Task_DeconstructEntitiesInChunkDetails_Robot_TaskData>

---@class Task_DeconstructEntitiesInChunkDetails_TaskData
---@field surface LuaSurface
---@field chunkDetailsByAxis Task_ScanAreasForActionsToComplete_ChunksInCombinedAreas
---@field chunksState table<string, Task_DeconstructEntitiesInChunkDetails_ChunkState> # Keyed by the chunks position as a string.
---@field entitiesToBeDeconstructed table<EntityIdentifier, Task_ScanAreasForActionsToComplete_EntityDetails> # The main list of entities to be deconstructed that is used by things outside of this task. So remove entries from it as we do them.
---@field startingChunkPosition ChunkPosition

---@class Task_DeconstructEntitiesInChunkDetails_Robot_TaskData : TaskData_Robot
---@field assignedChunkDetails Task_ScanAreasForActionsToComplete_ChunkDetails
---@field assignedChunkState Task_DeconstructEntitiesInChunkDetails_ChunkState
---@field currentTarget Task_ScanAreasForActionsToComplete_EntityDetails
---@field robotWalkingTask? Task_WalkToLocation_Details # A robot specific task to walk to a given location to get to its current target. This is semi invisible to the the current task as a whole. Will be truly unique walking target per robot per instance.

---@class Task_DeconstructEntitiesInChunkDetails_ChunkState
---@field positionString string # The Id of this in the table.
---@field state "available"|"assigned"|"completed"
---@field assignedRobot? Robot
---@field chunkDetails Task_ScanAreasForActionsToComplete_ChunkDetails

local DeconstructEntitiesInChunkDetails = {} ---@class Task_DeconstructEntitiesInChunkDetails_Interface : Task_Interface
DeconstructEntitiesInChunkDetails.taskName = "DeconstructEntitiesInChunkDetails"

local DeconstructTimeDelay = 30 -- How many extra ticks each deconstruct takes to simulate a player having to change mining target.

DeconstructEntitiesInChunkDetails._OnLoad = function()
    MOD.Interfaces.Tasks.DeconstructEntitiesInChunkDetails = DeconstructEntitiesInChunkDetails
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Details # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Details # The parent Task or nil if this is a primary Task of a Job.
---@param surface LuaSurface
---@param chunkDetailsByAxis Task_ScanAreasForActionsToComplete_ChunksInCombinedAreas
---@param entitiesToBeDeconstructed table<EntityIdentifier, Task_ScanAreasForActionsToComplete_EntityDetails>
---@param startingChunkPosition ChunkPosition
---@return Task_DeconstructEntitiesInChunkDetails_Details
DeconstructEntitiesInChunkDetails.ActivateTask = function(job, parentTask, surface, chunkDetailsByAxis, entitiesToBeDeconstructed, startingChunkPosition)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(DeconstructEntitiesInChunkDetails.taskName, job, parentTask) ---@cast thisTask Task_DeconstructEntitiesInChunkDetails_Details

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
            if next(chunkDetails.toBeDeconstructedEntityDetails) ~= nil then
                chunksState[chunkDetails.chunkPositionString] = {
                    positionString = chunkDetails.chunkPositionString,
                    state = "available",
                    assignedRobot = nil,
                    chunkDetails = chunkDetails
                }
            end
        end
    end

    return thisTask
end

--- Called to do work on the task by on_tick by each robot.
---@param thisTask Task_DeconstructEntitiesInChunkDetails_Details
---@param robot Robot
---@return uint ticksToWait
---@return ShowRobotState_NewRobotStateDetails robotStateDetails
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
    if robotTaskData.assignedChunkState == nil or robotTaskData.assignedChunkState.state == "completed" then
        local chunkFound = DeconstructEntitiesInChunkDetails.FindAvailableChunkForRobot(robotTaskData, taskData)
        if chunkFound == nil then
            -- No chunks left to be done.

            -- So just wait where it is for a second and check back. As the robot(s) assigned to the outstanding chunks could leave and thus those chunks will need a new robot to work on them.
            return global.Settings.Robot.EndOfTaskWaitTicks, { stateText = "Waiting for other robots to finish deconstructing", level = "normal" }
        end
        -- Chunk found so record it.
        local chunkState = taskData.chunksState[chunkFound.chunkPositionString]
        chunkState.state = "assigned"
        chunkState.assignedRobot = robotTaskData.robot
        robotTaskData.assignedChunkDetails = chunkFound
        robotTaskData.assignedChunkState = chunkState
    end

    ------------------------------------------------------------------
    -- As the robot has a chunk to work on, continue processing it. --
    ------------------------------------------------------------------

    local robot_position = robotTaskData.robot.entity.position

    -- If the robot doesn't have a target then it needs to find one and then start the appropriate action.
    if robotTaskData.currentTarget == nil then
        -- CODE NOTE: this is quite UPS expensive when the robot has to cycle through a lot to find the nearest one. There isn't an easy way to avoid this, I think it needs to use some sort of sub chunk divider and just look at those in its own sub chunk and then look for any in neighbouring sub chunks? But this is then somewhat mining distance dependant, will have more overhead and code complexity. The chunk grouping already does this to a degree.
        -- Option 1: thinking about 4x4 tile blocks. As by default if you are within mining range-3 (accounts for diagonal) of the middle you can reach everywhere. Would then find the nearest 4x4 block to the robot and move to within mining range -3 of its center, then can mine everything within that block. It's a lot of blocks, but each one would require no searching within. Would need a fallback of if it can't path near to the middle of the block it has to path specifically at the nearest target in the old way. To handle oddities in cliffs and water patches.
        -- Option 2: thinking about 8x8 tile blocks. Big enough that you can't just assume mining range to anywhere and so would have to do a search within these small subsets. Would keep logic simple as we would just path to the nearest one if none in range and then loop, as we currently do.
        robotTaskData.currentTarget = PositionUtils.GetNearest(robot_position, robotTaskData.assignedChunkDetails.toBeDeconstructedEntityDetails, "position", robot.miningDistance)

        if robotTaskData.currentTarget == nil then
            -- As the robot can't find anything to do on this chunk then mark the chunk as done for deconstruction. It will then start looking for a new chunk. We leave the robot assigned to the chunk as the searching for chunk will use this data before overwriting it.
            robotTaskData.assignedChunkState.state = "completed"
            return DeconstructEntitiesInChunkDetails.Progress(thisTask, robot)
        end
    end

    local ticksToWait, robotStateDetails
    -- Check if we are not currently walking and can mine the target from our current position, or if we are/need to walk to the target.
    if robotTaskData.robotWalkingTask == nil and PositionUtils.GetDistance(robot_position, robotTaskData.currentTarget.position) <= robot.miningDistance then
        -- In reach and not walking so can mine it now and then sleep.
        ticksToWait = DeconstructTimeDelay + math_ceil(PrototypeAttributes.GetAttribute("entity", robotTaskData.currentTarget.entity_name, "mineable_properties")--[[@as LuaEntityPrototype.mineable_properties]] .mining_time * 60 / robot.miningSpeed) --[[@as uint # We can safely just cast this in reality. ]]
        if global.Settings.Debug.fastDeconstruct then ticksToWait = math.ceil(ticksToWait / 10) --[[@as uint # We can safely just cast this in reality. ]] end

        -- local constructionRobot = robot.surface.create_entity({ name = "construction-robot", surface = robot.surface, position = robot_position, force = robot.force }) ---@cast constructionRobot - nil -- 2
        -- local minedItemsAllFittedInInventory = robotTaskData.currentTarget.entity.mine({ force = false, ignore_minable = false, raise_destroyed = true, inventory = constructionRobot.get_inventory(defines.inventory.robot_cargo) }) -- 2
        -- constructionRobot.destroy() -- 2

        -- local oldMasterCharacter = robot.master.character -- 1
        -- robot.master.character = robot.entity -- 1
        -- local minedItemsAllFittedInInventory = robot.entity.mine_entity(robotTaskData.currentTarget.entity, false) -1
        -- CODE NOTE: do the mine from the entity in to the robot's inventory as this handles failed mine attempts and when to raised script_destroyed events automatically. Mining from the character entity would need me to raise the event before I try and mine so the entity is valid for the event. Thus needing more checks on inventory space, etc; for no benefit to me.
        local minedItemsAllFittedInInventory = robotTaskData.currentTarget.entity.mine({ inventory = robot.inventories.main }) -- Raises script_raised_destroyed if it succeeded. --3
        if minedItemsAllFittedInInventory == false then
            -- Robot's inventory is now full so couldn't complete mining the entity.
            error("not handled full robot inventory yet")
            -- Later: Robot needs to go and empty its inventory and also release this chunk. As it may take the robot a while and another robot may be abe to start it quicker. This seems like something for the V2 of this feature and so in initial Proof Of Concept version we will just avoid a test reaching this state.
        end
        -- robot.master.character = oldMasterCharacter -- 1

        -- The mining was successful so update the lists and then wait for the mining time before starting anything new.
        robotTaskData.assignedChunkDetails.toBeDeconstructedEntityDetails[robotTaskData.currentTarget.identifier] = nil
        taskData.entitiesToBeDeconstructed[robotTaskData.currentTarget.identifier] = nil
        robotTaskData.currentTarget = nil
        robotStateDetails = { stateText = "Deconstructing target", level = "normal" }

        -- As this robot just mined an entity then check if it has completed this chunk. If it has then it may have been the last chunk needing anything deconstructed. Basically no need to check for everything being completed otherwise.
        if next(robotTaskData.assignedChunkDetails.toBeDeconstructedEntityDetails) == nil then
            -- Robot just finished the last thing in this chunk.

            -- As the robot has completed everything on this chunk then mark the chunk as done for deconstruction. It will find a new chunk on next loop. We leave the robot assigned to the chunk as the searching for chunk will use this data before overwriting it.
            robotTaskData.assignedChunkState.state = "completed"

            -- As a chunk was just completed check if there is anything left that needs doing in any chunk within the task.
            if next(taskData.entitiesToBeDeconstructed) == nil then
                -- Nothing left to be done in any chunk, so it should all be complete.
                thisTask.state = "completed"
                robotStateDetails = { stateText = "Deconstruction completed", level = "normal" }
            else
                -- Other chunks still have stuff to be done.
                robotStateDetails = { stateText = "Thinking about next chunk to deconstruct", level = "normal" }
            end
        end
    else
        -- Out of reach so need to move towards it. Or if walking complete this so that the task ends neatly.

        -- The path request and following it can just be stored in the robot data. As it will be unique to each robot and we will have this task manage the state texts.
        if robotTaskData.robotWalkingTask == nil then
            -- Get safely within mining range, but no real risk of having issues getting really close to it due to non mined entities, etc.
            robotTaskData.robotWalkingTask = MOD.Interfaces.Tasks.WalkToLocation.ActivateTask(thisTask.job, thisTask.parentTask, robotTaskData.currentTarget.position, taskData.surface, robot.miningDistance - 1)
        end
        ticksToWait, robotStateDetails = MOD.Interfaces.Tasks.WalkToLocation.Progress(robotTaskData.robotWalkingTask, robot)
        robotStateDetails.stateText = "Pathing to deconstruction target: " .. robotStateDetails.stateText

        -- Check if the walking task was declared complete on this last pass (means the robot had arrived at its destination at the start of this tick).
        if robotTaskData.robotWalkingTask.robotsTaskData[robot].state == "completed" then
            -- Kill the task and clear it so we know we have reached our destination.
            MOD.Interfaces.Tasks.WalkToLocation.RemovingTask(robotTaskData.robotWalkingTask)
            robotTaskData.robotWalkingTask = nil

            -- Call this progress function again now to see if we can start mining something, or to put the robot in to a completed state.
            return DeconstructEntitiesInChunkDetails.Progress(thisTask, robot)
        end
    end

    -- Return the state and time to wait.
    return ticksToWait, robotStateDetails
end

--- Find the robot an available chunk to work on.
---@param robotTaskData Task_DeconstructEntitiesInChunkDetails_Robot_TaskData
---@param taskData Task_DeconstructEntitiesInChunkDetails_TaskData
---@return Task_ScanAreasForActionsToComplete_ChunkDetails|nil # Nil is only returned if there are no available chunks to be assigned.
DeconstructEntitiesInChunkDetails.FindAvailableChunkForRobot = function(robotTaskData, taskData)
    --  If it had one before find it one near by, otherwise find it one nearest the startingChunk.
    local startSearchingChunkPosition = robotTaskData.assignedChunkDetails and robotTaskData.assignedChunkDetails.chunkPosition or taskData.startingChunkPosition

    -- Check if the starting chunk needs to be done. As the loopy searching will always check around the robot's current chunk.
    local startingChunk = taskData.chunkDetailsByAxis.xChunks[taskData.startingChunkPosition.x].yChunks[taskData.startingChunkPosition.y]
    if taskData.chunksState[startingChunk.chunkPositionString] ~= nil and taskData.chunksState[startingChunk.chunkPositionString].state == "available" then
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
    while distanceToCheck <= maxDistanceAcrossIncludedChunks do
        for xMod = 0 + xIteratorPrimary, 0 - xIteratorPrimary, 0 - xIteratorPrimary do
            xPosition = centerXPosition + (xMod * distanceToCheck)
            if xPosition >= taskData.chunkDetailsByAxis.minXValue and xPosition <= taskData.chunkDetailsByAxis.maxXValue then
                xChunkObject = taskData.chunkDetailsByAxis.xChunks[xPosition]
                if xChunkObject ~= nil then
                    for yMod = 0 + yIteratorPrimary, 0 - yIteratorPrimary, 0 - yIteratorPrimary do
                        yPosition = centerYPosition + (yMod * distanceToCheck)
                        if yPosition >= xChunkObject.minYValue and yPosition <= xChunkObject.maxYValue then
                            foundChunk = xChunkObject.yChunks[yPosition]
                            if foundChunk ~= nil and taskData.chunksState[foundChunk.chunkPositionString] ~= nil and taskData.chunksState[foundChunk.chunkPositionString].state == "available" then
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

-- TODO: functions below here untouched from template.

--- Called when a specific robot is being removed from a task.
---@param thisTask Task_DeconstructEntitiesInChunkDetails_Details
---@param robot Robot
DeconstructEntitiesInChunkDetails.RemovingRobotFromTask = function(thisTask, robot)
    -- Tidy up any robot specific stuff.
    local robotTaskData = thisTask.robotsTaskData[robot]

    -- TODO: per robot walk tasks.

    -- Remove any robot specific task data.
    thisTask.robotsTaskData[robot] = nil

    MOD.Interfaces.TaskManager.GenericTaskPropagateRemoveRobot(thisTask, robot)
end

--- Called when a task is being removed and any task globals or ongoing activities need to be stopped.
---@param thisTask Task_DeconstructEntitiesInChunkDetails_Details
DeconstructEntitiesInChunkDetails.RemovingTask = function(thisTask)
    -- TODO: per robot walk tasks.

    -- Remove any per robot bits if the robot is still active.
    for _, robotTaskData in pairs(thisTask.robotsTaskData) do
        if robotTaskData.state == "active" then
        end
    end

    MOD.Interfaces.TaskManager.GenericTaskPropagateRemove(thisTask)
end

--- Called when pausing a robot and so all of its activities within the this task and sub tasks need to pause.
---@param thisTask Task_DeconstructEntitiesInChunkDetails_Details
---@param robot Robot
DeconstructEntitiesInChunkDetails.PausingRobotForTask = function(thisTask, robot)
    -- TODO: per robot walk tasks.

    -- If the robot was being actively used in some way stop it.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData ~= nil and robotTaskData.state == "active" then
    end

    MOD.Interfaces.TaskManager.GenericTaskPropagatePausingRobot(thisTask, robot)
end

return DeconstructEntitiesInChunkDetails
