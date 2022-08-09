--[[
    Manages a collection of robots analysing the actions and materials needed for a given group of areas to "complete" it. Returns a list of the actions by type to be done. Plus the number of items needed to complete everything and the guaranteed items to be returned by any deconstruction. The number of items gained by deconstruction will only be known post deconstruction as chests and machines can have things in them.
    Takes in an array of areas to be completed. These can overlap and will be deduped. Is to allow flexibility in selecting multiple smaller areas to be done while avoiding others, thus an odd overall shape to be completed.

    Action types:
        - Deconstruct: anything on the robots force and all trees and rocks types that are marked for deconstruction.
        - Upgrade: anything that is marked for upgrade on the robots force, also includes entities marked for rotation.
        - ghosts to build: any ghosts on the robots force.
        - Future: tiles not included at all.

    All robots are processed within this task as a collective. With each robot contributing some processing of the areas.
]]


local ShowRobotState = require("scripts.common.show-robot-state")
local math_floor = math.floor

---@class Task_ScanAreasForActionsToComplete_Data : Task_Data
---@field taskData Task_ScanAreasForActionsToComplete_BespokeData
---@field robotsTaskData table<Robot, Task_ScanAreasForActionsToComplete_Robot_BespokeData>

---@class Task_ScanAreasForActionsToComplete_BespokeData
---@field surface LuaSurface
---@field areasToComplete BoundingBox[]
---@field force LuaForce
---
---@field entitiesToBeDeconstructed_raw Task_ScanAreasForActionsToComplete_EntitiesRaw @ An array per area of the raw entities found needing to be deconstructed. The keys are sequential index numbers that will become gappy when processed dow to being an empty single depth table.
---@field natureToBeDeconstructed_raw Task_ScanAreasForActionsToComplete_EntitiesRaw @ An array per area of the raw trees and rocks found needing to be deconstructed. These are marked for deconstruction by any force and may belong to the robots force and thus included already in entitiesToBeDeconstructed_raw. The keys are sequential index numbers that will become gappy when processed dow to being an empty single depth table.
---@field entitiesToBeUpgraded_raw Task_ScanAreasForActionsToComplete_EntitiesRaw @ An array per area of the raw entities found needing to be upgraded. The keys are sequential index numbers that will become gappy when processed dow to being an empty single depth table.
---@field ghostsToBeBuilt_raw Task_ScanAreasForActionsToComplete_EntitiesRaw @ An array per area of the raw entities found needing to be built. The keys are sequential index numbers that will become gappy when processed dow to being an empty single depth table.
---@field allRawDataObtained boolean # Flag to say when all raw data has been obtained and we can just skip that whole checking code bloc.
---
---@field entitiesToBeDeconstructed_deduped Task_ScanAreasForActionsToComplete_EntitiesDeduped @ A table of all the raw entities (deduped) needing to be deconstructed across all areas. Keyed by the entities unit_number or its name and position as a string.
---@field natureToBeDeconstructed_deduped Task_ScanAreasForActionsToComplete_EntitiesDeduped @ A table of all the trees and rocks (deduped) needing to be deconstructed across all areas.  These are marked for deconstruction by any force and may belong to the robots force and thus included already in entitiesToBeDeconstructed_raw. Keyed by the entities unit_number or its name and position as a string. Post deduping this list is checked for force and duplicates and merged in to entitiesToBeDeconstructed_deduped ready for actual usage.
---@field entitiesToBeUpgraded_deduped Task_ScanAreasForActionsToComplete_EntitiesDeduped @ A table of all the raw entities (deduped) needing to be upgraded across all areas. Keyed by the entities unit_number or its name and position as a string.
---@field ghostsToBeBuilt_deduped Task_ScanAreasForActionsToComplete_EntitiesDeduped @ A table of all the raw entities (deduped) needing to be built across all areas. Keyed by the entities unit_number or its name and position as a string.
---@field allDataDeduped boolean # Flag to say when all data has been deduped and we can just skip that whole checking code bloc.
---
---@field entitiesToBeDeconstructed table<uint, Task_ScanAreasForActionsToComplete_EntityDetails> @ Keyed by a sequential number, used by calling functions to handle the data.
---@field entitiesToBeUpgraded table<uint, Task_ScanAreasForActionsToComplete_EntityDetails> @ Keyed by a sequential number, used by calling functions to handle the data.
---@field ghostsToBeBuilt table<uint, Task_ScanAreasForActionsToComplete_EntityDetails> @ Keyed by a sequential number, used by calling functions to handle the data.
---@field requiredInputItems table<string, uint> @ Item name to count of items needed as input to build and upgrade (not manipulate).
---@field guaranteedOutputItems table<string, uint> @ Item name to count of items we are guaranteed to get. This ignores things in chests, machines, etc, as they are only known once they entities have been mined.
---
---@field chunksInCombinedAreas Task_ScanAreasForActionsToComplete_ChunkXValues # A table of the chunk X values to chunk Y values to chunk details. A way to allow us to "iterate" the chunks and map out the connected chunks. We will assume that you can walk between touching chunks for this high level planning.

---@alias Task_ScanAreasForActionsToComplete_EntitiesRaw table<uint, table<uint, LuaEntity>> @ An array per area of the raw entities found needing to be handled for their specific action type. The keys are sequential index numbers that will become gappy when processed dow to being an empty single depth table.
---@alias Task_ScanAreasForActionsToComplete_EntitiesDeduped table<uint|string, LuaEntity> @ A single table of all the raw entities (deduped) across all areas needing to be handled for their specific action type. Keyed by the entities unit_number or its name and position as a string.

---@alias Task_ScanAreasForActionsToComplete_ChunkXValues table<uint, Task_ScanAreasForActionsToComplete_ChunkYValues>
---@alias Task_ScanAreasForActionsToComplete_ChunkYValues table<uint, Task_ScanAreasForActionsToComplete_ChunkDetails>

---@class Task_ScanAreasForActionsToComplete_ChunkDetails
---@field chunkPosition ChunkPosition
---@field toBeDeconstructedEntityDetails table<uint, Task_ScanAreasForActionsToComplete_EntityDetails> # Keyed by the Id of the entity details. These Id keys list will be very gappy.
---@field toBeManipulated table<uint, Task_ScanAreasForActionsToComplete_EntityDetails> # Keyed by the Id of the entity details. These Id keys list will be very gappy. Will be the entities that need manipulating in place, i.e. rotating,
---@field toBeUpgradedTypes table<string, table<uint, Task_ScanAreasForActionsToComplete_EntityDetails>> # Grouped by the entity item used to upgrade it first and then keyed by the Id of the entity details. These Id keys list will be very gappy.
---@field toBeBuiltTypes table<string, table<uint, Task_ScanAreasForActionsToComplete_EntityDetails>> # Grouped by the entity item type used to build it first and then keyed by the Id of the entity details. These Id keys list will be very gappy.

---@class Task_ScanAreasForActionsToComplete_EntityDetails
---@field entityListKey uint # Key in the entitiesToBe[X] table.
---@field identifier string|uint # The entities unit_number or its name and position as a string
---@field entity LuaEntity
---@field entity_type string
---@field entity_name string
---@field position MapPosition
---@field chunkDetails Task_ScanAreasForActionsToComplete_ChunkDetails
---@field actionType Task_ScanAreasForActionsToComplete_ActionType
---@field builtByItemName? string # The name of the item type used to build it for the action type, or nil if no item is required for the action type.

---@class Task_ScanAreasForActionsToComplete_Robot_BespokeData : Task_Data_Robot
---@field state "active"|"completed"

local ScanAreasForActionsToComplete = {} ---@class Task_ScanAreasForActionsToComplete_Interface : Task_Interface
ScanAreasForActionsToComplete.taskName = "ScanAreasForActionsToComplete"

---@enum Task_ScanAreasForActionsToComplete_ActionType
ScanAreasForActionsToComplete.ActionType = {
    deconstruct = "deconstruct",
    upgrade = "upgrade",
    build = "build"
}

local EntitiesDedupedPerBatch = 100 -- Just getting unit_number via API calls.
local EntitiesHandledPerBatch = 10 -- Multiple API calls to get item types, etc.

ScanAreasForActionsToComplete._OnLoad = function()
    MOD.Interfaces.Tasks.ScanAreasForActionsToComplete = ScanAreasForActionsToComplete
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param surface LuaSurface
---@param areasToComplete BoundingBox[]
---@param force LuaForce
---@return Task_ScanAreasForActionsToComplete_Data
ScanAreasForActionsToComplete.ActivateTask = function(job, parentTask, surface, areasToComplete, force)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(ScanAreasForActionsToComplete.taskName, job, parentTask) ---@cast thisTask Task_ScanAreasForActionsToComplete_Data

    -- Store the task wide data.
    thisTask.taskData = {
        surface = surface,
        areasToComplete = areasToComplete,
        force = force,

        entitiesToBeDeconstructed_raw = {},
        natureToBeDeconstructed_raw = {},
        entitiesToBeUpgraded_raw = {},
        ghostsToBeBuilt_raw = {},
        allRawDataObtained = false,

        entitiesToBeDeconstructed_deduped = {},
        natureToBeDeconstructed_deduped = {},
        entitiesToBeUpgraded_deduped = {},
        ghostsToBeBuilt_deduped = {},
        allDataDeduped = false,

        entitiesToBeDeconstructed = {},
        entitiesToBeUpgraded = {},
        ghostsToBeBuilt = {},
        requiredInputItems = {},
        guaranteedOutputItems = {},
        chunksInCombinedAreas = {}
    }

    return thisTask
end

--- Called to do work on the task by on_tick by each robot.
---@param thisTask Task_ScanAreasForActionsToComplete_Data
---@param robot Robot
---@return uint ticksToWait
---@return ShowRobotState_NewRobotStateDetails|nil robotStateDetails # nil if there is no state being set by this Task
ScanAreasForActionsToComplete.Progress = function(thisTask, robot)
    local taskData = thisTask.taskData

    -- The response times and text are always the same unless the task is complete.
    ---@type uint,ShowRobotState_NewRobotStateDetails
    local ticksToWait, robotStateDetails = 60, { stateText = "Reviewing area for actions to complete", level = ShowRobotState.StateLevel.normal }

    -- Handle if this is the very first robot to Progress() this Task. We leave the tables constructed but empty once used, so this check is safe throughout the tasks life.
    if not taskData.allRawDataObtained then
        -- CODE NOTE: I am assuming that getting lists of entities to be completed will be quick and so can be done in all in one go. This may prove wrong and require this to be done spread over multiple seconds as a series of smaller queries.

        -- Highlight the areas being checked if debug is enabled.
        if global.Settings.Debug.showCompleteAreas then
            for _, area in pairs(taskData.areasToComplete) do
                rendering.draw_rectangle({
                    color = robot.fontColor,
                    width = 4.0,
                    filled = true,
                    left_top = area.left_top,
                    right_bottom = area.right_bottom,
                    surface = taskData.surface,
                    scale_with_zoom = true,
                    draw_on_ground = true
                })
            end
        end

        -- Check the various actions needed over the areas and record the raw results for later processing.
        for _, area in pairs(taskData.areasToComplete) do
            taskData.entitiesToBeDeconstructed_raw[#taskData.entitiesToBeDeconstructed_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, to_be_deconstructed = true })
        end
        for _, area in pairs(taskData.areasToComplete) do
            -- These are marked for deconstruction by any force and may belong to the robots force and thus included already in entitiesToBeDeconstructed_raw.
            taskData.natureToBeDeconstructed_raw[#taskData.natureToBeDeconstructed_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, type = { "tree", "rock" }, to_be_deconstructed = true })
        end
        for _, area in pairs(taskData.areasToComplete) do
            taskData.entitiesToBeUpgraded_raw[#taskData.entitiesToBeUpgraded_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, to_be_upgraded = true })
        end
        for _, area in pairs(taskData.areasToComplete) do
            taskData.ghostsToBeBuilt_raw[#taskData.ghostsToBeBuilt_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, type = "entity-ghost" })
        end

        -- Record all raw data obtained so this logic block can be skipped in future.
        taskData.allRawDataObtained = true

        -- First robot just does these as they will take some UPS/thinking time.
        return ticksToWait, robotStateDetails
    end

    -- If there's raw data we need to dedupe it in to the deduped tables so its clean for later processing. The processing clears out the raw tables as it goes.
    if not taskData.allDataDeduped then
        local entitiesDeduped = 0
        if next(taskData.entitiesToBeDeconstructed_raw) ~= nil then
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData.entitiesToBeDeconstructed_raw, taskData.entitiesToBeDeconstructed_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end
        if next(taskData.natureToBeDeconstructed_raw) ~= nil then
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData.natureToBeDeconstructed_raw, taskData.natureToBeDeconstructed_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end
        if next(taskData.entitiesToBeUpgraded_raw) ~= nil then
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData.entitiesToBeUpgraded_raw, taskData.entitiesToBeUpgraded_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end
        if next(taskData.ghostsToBeBuilt_raw) ~= nil then
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData.ghostsToBeBuilt_raw, taskData.ghostsToBeBuilt_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end

        -- Nature entities need additional validation and then when clear moving in to the main entities to be deconstructed list.
        if next(taskData.natureToBeDeconstructed_deduped) ~= nil then
            for identifier, entity in pairs(taskData.natureToBeDeconstructed_deduped) do
                if taskData.entitiesToBeDeconstructed_deduped[identifier] == nil then
                    -- Nature isn't already in the deconstructed list so continue checking it for inclusion.
                    if entity.is_registered_for_deconstruction(taskData.force) then
                        -- Is registered with our force for deconstruction, so add it to the main list.
                        taskData.entitiesToBeDeconstructed_deduped[identifier] = entity
                    end
                end
                taskData.natureToBeDeconstructed_deduped[identifier] = nil
                entitiesDeduped = entitiesDeduped + 1
                if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
            end
        end

        -- Record all data deduped so this logic block can be skipped in future.
        taskData.allDataDeduped = true

        -- The robot that completes the last deduping activity ends this cycle as they will take some UPS/thinking time.
        return ticksToWait, robotStateDetails
    end

    -- The final processing of the entities in to their chunk groups and the complicated interconnected tables.

    local entitiesHandled = 0
    -- Process the deconstruction list if there's any remaining in the dedupe list.
    if next(taskData.entitiesToBeDeconstructed_deduped) ~= nil then
        entitiesHandled = ScanAreasForActionsToComplete._ProcessDedupedTableToProcessedTable(taskData, ScanAreasForActionsToComplete.ActionType.deconstruct, entitiesHandled)
        if entitiesHandled >= EntitiesHandledPerBatch then return ticksToWait, robotStateDetails end
    end
    if next(taskData.entitiesToBeUpgraded_deduped) ~= nil then
        entitiesHandled = ScanAreasForActionsToComplete._ProcessDedupedTableToProcessedTable(taskData, ScanAreasForActionsToComplete.ActionType.upgrade, entitiesHandled)
        if entitiesHandled >= EntitiesHandledPerBatch then return ticksToWait, robotStateDetails end
    end
    if next(taskData.ghostsToBeBuilt_deduped) ~= nil then
        entitiesHandled = ScanAreasForActionsToComplete._ProcessDedupedTableToProcessedTable(taskData, ScanAreasForActionsToComplete.ActionType.build, entitiesHandled)
        if entitiesHandled >= EntitiesHandledPerBatch then return ticksToWait, robotStateDetails end
    end

    -- If a robot has reached this far then it has just finished the job, but it will still need to completing it's thinking it started this second.
    thisTask.state = "completed"

    return ticksToWait, robotStateDetails
end

--- Processes some of a table of raw results TaskData in to a deduped TaskData table.
---@param rawTable Task_ScanAreasForActionsToComplete_EntitiesRaw # Reference to the "raw" TaskData table.
---@param dedupedTable Task_ScanAreasForActionsToComplete_EntitiesDeduped # Reference to the "deduped" TaskData table.
---@param entitiesDeduped uint # How many entities this robot has already deduped.
---@return uint entitiesDeduped
ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable = function(rawTable, dedupedTable, entitiesDeduped)
    for areaIndex, areasEntities in pairs(rawTable) do
        for entityIndex, entity in pairs(areasEntities) do
            local entity_identifier = entity.unit_number ---@type uint|string
            if entity_identifier == nil then
                local entity_Position = entity.position
                entity_identifier = entity.name .. ":" .. entity_Position.x .. "," .. entity_Position.y
            end
            if dedupedTable[entity_identifier] == nil then
                dedupedTable[entity_identifier] = entity
            end
            entitiesDeduped = entitiesDeduped + 1
            areasEntities[entityIndex] = nil
            if entitiesDeduped >= EntitiesDedupedPerBatch then return entitiesDeduped end
        end
        rawTable[areaIndex] = nil
    end
    return entitiesDeduped
end

--- Process some of a table of deduped results TaskData in to a the final TaskData table.
---@param taskData Task_ScanAreasForActionsToComplete_BespokeData
---@param actionType Task_ScanAreasForActionsToComplete_ActionType
---@param entitiesHandled uint # How many entities this robot has already handled.
---@return uint entitiesHandled
ScanAreasForActionsToComplete._ProcessDedupedTableToProcessedTable = function(taskData, actionType, entitiesHandled)
    local dedupedTable, finalTable
    if actionType == ScanAreasForActionsToComplete.ActionType.deconstruct then
        dedupedTable = taskData.entitiesToBeDeconstructed_deduped
        finalTable = taskData.entitiesToBeDeconstructed
    elseif actionType == ScanAreasForActionsToComplete.ActionType.upgrade then
        dedupedTable = taskData.entitiesToBeUpgraded_deduped
        finalTable = taskData.entitiesToBeUpgraded
    elseif actionType == ScanAreasForActionsToComplete.ActionType.build then
        dedupedTable = taskData.ghostsToBeBuilt_deduped
        finalTable = taskData.ghostsToBeBuilt
    else
        error("unsupported action type")
    end

    local entity_position, chunkXValue, chunkYValue, chunkYList, chunkDetails
    for identifier, entity in pairs(dedupedTable) do
        entity_position = entity.position

        -- Get the ChunkDetails for this chunk or make it if needed.
        ---@type uint, uint
        chunkXValue, chunkYValue = math_floor(entity_position.x / 32), math_floor(entity_position.y / 32)
        chunkYList = taskData.chunksInCombinedAreas[chunkXValue]
        if chunkYList == nil then
            -- This X value column of chunks hasn't been recorded yet, so create it.
            taskData.chunksInCombinedAreas[chunkXValue] = {}
            chunkYList = taskData.chunksInCombinedAreas[chunkXValue]
        end
        chunkDetails = chunkYList[chunkYValue]
        if chunkDetails == nil then
            -- A chunk for this Y value of the X value hasn't been recorded yet, so create it.
            ---@type Task_ScanAreasForActionsToComplete_ChunkDetails
            chunkDetails = {
                chunkPosition = { x = chunkXValue, y = chunkYValue },
                toBeDeconstructedEntityDetails = {},
                toBeManipulated = {},
                toBeUpgradedTypes = {},
                toBeBuiltTypes = {}
            }
            chunkYList[chunkYValue] = chunkDetails
        end

        --- Create the EntityDetails object and add it to the main list for this action type.
        ---@type Task_ScanAreasForActionsToComplete_EntityDetails
        local entityDetails = {
            entityListKey = #finalTable + 1 --[[@as uint]] ,
            identifier = identifier,
            entity = entity,
            entity_name = entity.name,
            entity_type = entity.type,
            position = entity_position,
            chunkDetails = chunkDetails,
            actionType = ScanAreasForActionsToComplete.ActionType.deconstruct,
            builtByItemName = nil
        }
        finalTable[entityDetails.entityListKey] = entityDetails

        -- Record the EntityDetails in to the Chunk Details.
        if actionType == ScanAreasForActionsToComplete.ActionType.deconstruct then
            chunkDetails.toBeDeconstructedEntityDetails[entityDetails.entityListKey] = entityDetails
        elseif actionType == ScanAreasForActionsToComplete.ActionType.upgrade then
            --TODO: based on if this is a true upgrade or a rotate. Also it may take an input item.
        elseif actionType == ScanAreasForActionsToComplete.ActionType.build then
            chunkDetails.toBeBuiltTypes[entity.type] = chunkDetails.toBeBuiltTypes[entity.type] or {}
            chunkDetails.toBeBuiltTypes[entity.type][entityDetails.entityListKey] = entityDetails
        else
            error("unsupported action type")
        end

        -- Record input and output items.
        --TODO: should cache these results per entity name.
        local minedProducts, requiredItems
        if actionType == ScanAreasForActionsToComplete.ActionType.deconstruct then
            minedProducts = entity.prototype.mineable_properties.products
        elseif actionType == ScanAreasForActionsToComplete.ActionType.upgrade then
            --TODO: based on if this is a true upgrade or a rotate. Also it may take an input item.
        elseif actionType == ScanAreasForActionsToComplete.ActionType.build then
            if entity.prototype.items_to_place_this ~= nil then
                requiredItems = entity.prototype.items_to_place_this[1] -- Same as construction bots.
            end
        else
            error("unsupported action type")
        end
        if minedProducts ~= nil then
            for _, minedProduct in pairs(minedProducts) do
                -- This is intended to capture the standard player buildable type entity being mined/replaced. Rather than resource rock mining, etc.
                if minedProduct.probability == 1 and minedProduct.amount >= 1 then
                    taskData.guaranteedOutputItems[minedProduct.name] = (taskData.guaranteedOutputItems[minedProduct.name] or 0) + math.floor(minedProduct.amount)
                end
            end
        end
        if requiredItems ~= nil then
            taskData.requiredInputItems[requiredItems.name] = (taskData.requiredInputItems[requiredItems.name] or 0) + requiredItems.count
        end

        -- Remove the entry from the deduped table.
        dedupedTable[identifier] = nil

        -- Record the work done and check if this robot is done for this cycle.
        entitiesHandled = entitiesHandled + 1
        if entitiesHandled >= EntitiesHandledPerBatch then return entitiesHandled end
    end

    return entitiesHandled
end

--- Called when a specific robot is being removed from a task.
---@param thisTask Task_ScanAreasForActionsToComplete_Data
---@param robot Robot
ScanAreasForActionsToComplete.RemovingRobotFromTask = function(thisTask, robot)
    -- Tidy up any robot specific stuff.
    local robotTaskData = thisTask.robotsTaskData[robot]

    -- Remove any robot specific task data.
    thisTask.robotsTaskData[robot] = nil

    MOD.Interfaces.TaskManager.GenericTaskPropagateRemoveRobot(thisTask, robot)
end

--- Called when a task is being removed and any task globals or ongoing activities need to be stopped.
---@param thisTask Task_ScanAreasForActionsToComplete_Data
ScanAreasForActionsToComplete.RemovingTask = function(thisTask)
    -- Remove any per robot bits if the robot is still active.
    for _, robotTaskData in pairs(thisTask.robotsTaskData) do
        if robotTaskData.state == "active" then
        end
    end

    MOD.Interfaces.TaskManager.GenericTaskPropagateRemove(thisTask)
end

--- Called when pausing a robot and so all of its activities within the this task and sub tasks need to pause.
---@param thisTask Task_ScanAreasForActionsToComplete_Data
---@param robot Robot
ScanAreasForActionsToComplete.PausingRobotForTask = function(thisTask, robot)
    -- If the robot was being actively used in some way stop it.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData ~= nil and robotTaskData.state == "active" then
    end

    MOD.Interfaces.TaskManager.GenericTaskPropagatePausingRobot(thisTask, robot)
end

return ScanAreasForActionsToComplete
