--[[
    Manages a collection of robots analysing the actions and materials needed for a given group of areas to "complete" it.
    It captures and generates a list of the actions by type to be done. Plus the number of items needed to complete everything and the guaranteed items to be returned by any deconstruction. The number of items gained by deconstruction will only be known post deconstruction as chests and machines can have things in them. See the non private (non "_") fields in the taskData (class Task_ScanAreasForActionsToComplete_TaskData).
    Takes in an array of areas to be completed. These can overlap and will be deduped. Is to allow flexibility in selecting multiple smaller areas to be done while avoiding others, thus an odd overall shape to be completed.

    Action types:
        - Deconstruct: anything on the robots force and all trees and rocks types that are marked for deconstruction.
        - Upgrade: anything that is marked for upgrade on the robots force; fast replacing from 1 entity to another but also fast replacing an entity over itself to change its direction, but keep its other attributes, connections, etc. Will have an input item and sometimes an output item. A rotation only fast replace requires the placer to have another of said item and build it over the current one. This is better than deconstructing and rebuilding it, or rotating it, as it avoids the intermediate states that may be invalid or leave empty space in the map, etc. It is item input/output neutral however, but you have to start with the item and you get whatever is in the entity when done.
        - ghosts to build: any ghosts on the robots force.

    All robots are processed within this task as a collective. With each robot contributing some anonymised processing of the combined workload.
]]


local StringUtils = require("utility.helper-utils.string-utils")
local MathUtils = require("utility.helper-utils.math-utils")
local PrototypeAttributes = require("utility.functions.prototype-attributes")
local math_floor = math.floor

---@class Task_ScanAreasForActionsToComplete_Details : Task_Details
---@field taskData Task_ScanAreasForActionsToComplete_TaskData

---@class Task_ScanAreasForActionsToComplete_TaskData
---@field surface LuaSurface
---@field areasToComplete BoundingBox[]
---@field force LuaForce
---@field reviewingAreasDebugRenderIds? uint64[]
---
---@field _entitiesToBeDeconstructed_raw Task_ScanAreasForActionsToComplete_EntitiesRaw @ An array per area of the raw entities found needing to be deconstructed. The inner table for entities is keyed by sequential index numbers that will become gappy when processed, eventually being reduced down to an empty single depth table.
---@field _natureToBeDeconstructed_raw Task_ScanAreasForActionsToComplete_EntitiesRaw @ An array per area of the raw trees and rocks found needing to be deconstructed. These are marked for deconstruction by any force and may belong to the robots force and thus included already in _entitiesToBeDeconstructed_raw. The inner table for entities is keyed by sequential index numbers that will become gappy when processed, eventually being reduced down to an empty single depth table.
---@field _entitiesToBeUpgraded_raw Task_ScanAreasForActionsToComplete_EntitiesRaw @ An array per area of the raw entities found needing to be upgraded. The inner table for entities is keyed by sequential index numbers that will become gappy when processed, eventually being reduced down to an empty single depth table.
---@field _ghostsToBeBuilt_raw Task_ScanAreasForActionsToComplete_EntitiesRaw @ An array per area of the raw entities found needing to be built. The inner table for entities is keyed by sequential index numbers that will become gappy when processed, eventually being reduced down to an empty single depth table.
---@field _allRawDataObtained boolean # Flag to say when all raw data has been obtained and we can just skip that whole checking code bloc.
---
---@field _entitiesToBeDeconstructed_deduped Task_ScanAreasForActionsToComplete_EntitiesDeduped @ A table of all the raw entities (deduped) needing to be deconstructed across all areas merged together. Keyed by the entities unit_number or "destroyedId_[UNIQUE_NUMBER_PER_ENTITY]".
---@field _natureToBeDeconstructed_deduped Task_ScanAreasForActionsToComplete_EntitiesDeduped @ A table of all the trees and rocks (deduped) needing to be deconstructed across all areas merged together. These are marked for deconstruction by any force and may belong to the robots force and thus included already in _entitiesToBeDeconstructed_raw. Keyed by the entities unit_number or "destroyedId_[UNIQUE_NUMBER_PER_ENTITY]". Post deduping this list is checked for force and duplicates and merged in to _entitiesToBeDeconstructed_deduped ready for actual usage.
---@field _entitiesToBeUpgraded_deduped Task_ScanAreasForActionsToComplete_EntitiesDeduped @ A table of all the raw entities (deduped) needing to be upgraded across all areas merged together. Keyed by the entities unit_number or "destroyedId_[UNIQUE_NUMBER_PER_ENTITY]".
---@field _ghostsToBeBuilt_deduped Task_ScanAreasForActionsToComplete_EntitiesDeduped @ A table of all the raw entities (deduped) needing to be built across all areas merged together. Keyed by the entities unit_number or "destroyedId_[UNIQUE_NUMBER_PER_ENTITY]".
---@field _allDataDeduped boolean # Flag to say when all data has been deduped and we can just skip that whole checking code bloc.
---
---@field entitiesToBeDeconstructed table<uint, Task_ScanAreasForActionsToComplete_EntityDetails> @ Keyed by a sequential number, used by calling functions to handle the data.
---@field entitiesToBeUpgraded table<uint, Task_ScanAreasForActionsToComplete_EntityDetails> @ Keyed by a sequential number, used by calling functions to handle the data.
---@field ghostsToBeBuilt table<uint, Task_ScanAreasForActionsToComplete_EntityDetails> @ Keyed by a sequential number, used by calling functions to handle the data.
---@field _requiredManipulateItems table<string, true> @ Item name of items needed for manipulation upgrades only. As you need an item to do the manipulation, even though its item neutral. Is merged in to requiredInputItems at the end of the review process.
---@field requiredInputItems table<string, uint> @ Item name to count of items needed as input to build and upgrade. Includes at least 1 of each item that needs manipulating as you need an item to do the manipulation, even though its item neutral.
---@field guaranteedOutputItems table<string, uint> @ Item name to count of items we are guaranteed to get. This ignores things in chests, machines, etc, as they are only known once they entities have been mined.
---
---@field chunksInCombinedAreas Task_ScanAreasForActionsToComplete_ChunksInCombinedAreas # An object with the included chunks grouped by their x and y values.

---@alias Task_ScanAreasForActionsToComplete_EntitiesRaw table<uint, table<uint, LuaEntity>> @ An array per area of the raw entities found needing to be handled for their specific action type. The inner table for entities is keyed by sequential index numbers that will become gappy when processed, eventually being reduced down to an empty single depth table.
---@alias Task_ScanAreasForActionsToComplete_EntitiesDeduped table<uint|string, LuaEntity> @ A single table of all the raw entities (deduped) across all areas needing to be handled for their specific action type. Keyed by the entities unit_number or "destroyedId_[UNIQUE_NUMBER_PER_ENTITY]".

---@class Task_ScanAreasForActionsToComplete_ChunksInCombinedAreas # Is effectively the XChunks class, as no parent object with extra meta data is needed.
---@field minXValue int # The lowest X chunk position value in the xChunks table.
---@field maxXValue int # The highest X chunk position value in the xChunks table.
---@field minYValueAcrossAllXValues int # The lowest Y chunk position value across all of the X chunk tables. Just to save iterating them all each time to find it.
---@field maxYValueAcrossAllXValues int # The highest Y chunk position value across all of the X chunk tables. Just to save iterating them all each time to find it.
---@field xChunks table<int, Task_ScanAreasForActionsToComplete_ChunksInCombinedAreas_XChunkObject> # A table of X values that have included chunks within them. This can be a gappy list.

---@class Task_ScanAreasForActionsToComplete_ChunksInCombinedAreas_XChunkObject
---@field minYValue int # The lowest Y chunk position value in the yChunks table.
---@field maxYValue int # The highest Y chunk position value in the yChunks table.
---@field yChunks table<int, Task_ScanAreasForActionsToComplete_ChunkDetails> # A table of Y values that have included chunks within them. This can be a gappy list.

---@class Task_ScanAreasForActionsToComplete_ChunkDetails
---@field chunkPosition ChunkPosition
---@field chunkPositionString string # A string of the chunk position. Used by other tasks making use of this data set.
---@field toBeDeconstructedEntityDetails table<uint, Task_ScanAreasForActionsToComplete_EntityDetails> # Keyed by the entityListKey of the entity details.
---@field toBeUpgradedTypes table<string, table<uint, Task_ScanAreasForActionsToComplete_EntityDetails>> # Grouped by the entity item used to upgrade it first and then keyed by the entityListKey of the entity details.
---@field toBeBuiltTypes table<string, table<uint, Task_ScanAreasForActionsToComplete_EntityDetails>> # Grouped by the entity item type used to build it first and then keyed by the entityListKey of the entity details.

---@class Task_ScanAreasForActionsToComplete_EntityDetails
---@field entityListKey uint # Key in the Tasks global entitiesToBe[X] table.
---@field identifier string|uint # The entities unit_number or "destroyedId_[UNIQUE_NUMBER_PER_ENTITY]".
---@field entity LuaEntity
---@field entity_type string # The type of the entity in relation to the actionType. For deconstruction this is the entity to be removed, for build it is the new entity, for upgrades it is the new entity being upgraded too.
---@field entity_name string # The name of the entity in relation to the actionType. For deconstruction this is the entity to be removed, for build it is the new entity, for upgrades it is the new entity being upgraded too.
---@field position MapPosition
---@field chunkDetails Task_ScanAreasForActionsToComplete_ChunkDetails
---@field actionType Task_ScanAreasForActionsToComplete_ActionType
---@field builtByItemName? string # The name of the item type used to build it for the action type, or nil if no item is required for the action type.
---@field builtByItemCount? uint # The count of the item type used to build it for the action type, or nil if no item is required for the action type. Most are 1, but curved rails are more and some modded things could also be >1.

---@alias Task_ScanAreasForActionsToComplete_ActionType "deconstruct"|"upgrade"|"build"

local ScanAreasForActionsToComplete = {} ---@class Task_ScanAreasForActionsToComplete_Interface : Task_Interface
ScanAreasForActionsToComplete.taskName = "ScanAreasForActionsToComplete"


-- Robot thinking settings. Want a balance between avoiding UPS overhead from excessive loop executions and having spiky UPS load from large irregular parses.
local EntitiesDedupedPerBatch = 1000 -- Just getting unit_number via API calls.
local EntitiesHandledPerBatch = 100 -- Multiple API calls to get item types, etc.
local TicksPerBatchLoop = 60 -- How long a robot spends "thinking" for each loop of the batch. There is a minimal loops of the Progress regardless of small size as well.

ScanAreasForActionsToComplete._OnLoad = function()
    MOD.Interfaces.Tasks.ScanAreasForActionsToComplete = ScanAreasForActionsToComplete
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Details # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Details # The parent Task or nil if this is a primary Task of a Job.
---@param surface LuaSurface
---@param areasToComplete BoundingBox[]
---@param force LuaForce
---@return Task_ScanAreasForActionsToComplete_Details
ScanAreasForActionsToComplete.ActivateTask = function(job, parentTask, surface, areasToComplete, force)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(ScanAreasForActionsToComplete.taskName, job, parentTask) ---@cast thisTask Task_ScanAreasForActionsToComplete_Details

    -- Store the task wide data.
    thisTask.taskData = {
        surface = surface,
        areasToComplete = areasToComplete,
        force = force,

        _entitiesToBeDeconstructed_raw = {},
        _natureToBeDeconstructed_raw = {},
        _entitiesToBeUpgraded_raw = {},
        _ghostsToBeBuilt_raw = {},
        _allRawDataObtained = false,

        _entitiesToBeDeconstructed_deduped = {},
        _natureToBeDeconstructed_deduped = {},
        _entitiesToBeUpgraded_deduped = {},
        _ghostsToBeBuilt_deduped = {},
        _allDataDeduped = false,

        entitiesToBeDeconstructed = {},
        entitiesToBeUpgraded = {},
        ghostsToBeBuilt = {},
        _requiredManipulateItems = {},
        requiredInputItems = {},
        guaranteedOutputItems = {},
        chunksInCombinedAreas = {
            xChunks = {},
            minXValue = MathUtils.intMax, -- Start at highest possible value so first new value is always lower.
            maxXValue = MathUtils.intMin, -- Start at lowest possible value so first new value is always higher.
            minYValueAcrossAllXValues = MathUtils.intMax, -- Start at highest possible value so first new value is always lower.
            maxYValueAcrossAllXValues = MathUtils.intMin -- Start at lowest possible value so first new value is always higher.
        }
    }

    return thisTask
end

--- Called to do work on the task by on_tick by each robot.
---@param thisTask Task_ScanAreasForActionsToComplete_Details
---@param robot Robot
---@return uint ticksToWait
---@return ShowRobotState_NewRobotStateDetails robotStateDetails
ScanAreasForActionsToComplete.Progress = function(thisTask, robot)
    local taskData = thisTask.taskData

    -- The response times and text are always the same unless the task is complete. The time is our
    ---@type uint,ShowRobotState_NewRobotStateDetails
    local ticksToWait, robotStateDetails = TicksPerBatchLoop, { stateText = "Reviewing area for actions to complete", level = "normal" }

    -- Handle if this is the very first robot to Progress() this Task. We leave the tables constructed but empty once used, so this check is safe throughout the tasks life.
    if not taskData._allRawDataObtained then
        -- CODE NOTE: I am assuming that getting lists of entities to be completed will be quick and so can be done in all in one go. This may prove wrong and require this to be done spread over multiple seconds as a series of smaller queries.

        -- Highlight the areas being checked if debug is enabled.
        if global.Settings.Debug.showCompleteAreas then
            taskData.reviewingAreasDebugRenderIds = {}
            for _, area in pairs(taskData.areasToComplete) do
                taskData.reviewingAreasDebugRenderIds[#taskData.reviewingAreasDebugRenderIds + 1] = rendering.draw_rectangle({
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
            taskData._entitiesToBeDeconstructed_raw[#taskData._entitiesToBeDeconstructed_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, to_be_deconstructed = true })
        end
        for _, area in pairs(taskData.areasToComplete) do
            -- These are marked for deconstruction by any force and may belong to the robots force and thus included already in _entitiesToBeDeconstructed_raw. Simple-entity is a stand-in for "rock". It might need better filter logic in future, although not sure how to further filter it either here or in post checking.
            taskData._natureToBeDeconstructed_raw[#taskData._natureToBeDeconstructed_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, type = { "tree", "simple-entity" }, to_be_deconstructed = true })
        end
        for _, area in pairs(taskData.areasToComplete) do
            taskData._entitiesToBeUpgraded_raw[#taskData._entitiesToBeUpgraded_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, to_be_upgraded = true })
        end
        for _, area in pairs(taskData.areasToComplete) do
            taskData._ghostsToBeBuilt_raw[#taskData._ghostsToBeBuilt_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, type = "entity-ghost" })
        end

        -- Record all raw data obtained so this logic block can be skipped in future.
        taskData._allRawDataObtained = true

        -- First robot just does these as they will take some UPS/thinking time.
        return ticksToWait, robotStateDetails
    end

    -- If there's raw data we need to dedupe it in to the deduped tables so its clean for later processing. The processing clears out the raw tables as it goes.
    if not taskData._allDataDeduped then
        local entitiesDeduped = 0
        if next(taskData._entitiesToBeDeconstructed_raw) ~= nil then
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData._entitiesToBeDeconstructed_raw, taskData._entitiesToBeDeconstructed_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end
        if next(taskData._natureToBeDeconstructed_raw) ~= nil then
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData._natureToBeDeconstructed_raw, taskData._natureToBeDeconstructed_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end
        if next(taskData._entitiesToBeUpgraded_raw) ~= nil then
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData._entitiesToBeUpgraded_raw, taskData._entitiesToBeUpgraded_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end
        if next(taskData._ghostsToBeBuilt_raw) ~= nil then
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData._ghostsToBeBuilt_raw, taskData._ghostsToBeBuilt_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end

        -- Nature entities need additional validation and then when clear moving in to the main entities to be deconstructed list.
        if next(taskData._natureToBeDeconstructed_deduped) ~= nil then
            for identifier, entity in pairs(taskData._natureToBeDeconstructed_deduped) do
                -- Only check if they are for our force if we haven't already got them listed. Saves making un-needed API requests.
                if taskData._entitiesToBeDeconstructed_deduped[identifier] == nil then
                    -- Nature isn't already in the deconstructed list so continue checking it for inclusion.
                    if entity.is_registered_for_deconstruction(taskData.force) then
                        -- Is registered with our force for deconstruction, so add it to the main list.
                        taskData._entitiesToBeDeconstructed_deduped[identifier] = entity
                    end
                end
                taskData._natureToBeDeconstructed_deduped[identifier] = nil
                entitiesDeduped = entitiesDeduped + 1
                if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
            end
        end

        -- Record all data deduped so this logic block can be skipped in future.
        taskData._allDataDeduped = true

        -- The robot that completes the last deduping activity ends this cycle as they will take some UPS/thinking time.
        return ticksToWait, robotStateDetails
    end

    -- The final processing of the entities in to their chunk groups and the complicated interconnected tables.

    local entitiesHandled = 0
    -- Process the deconstruction list if there's any remaining in the dedupe list.
    if next(taskData._entitiesToBeDeconstructed_deduped) ~= nil then
        entitiesHandled = ScanAreasForActionsToComplete._ProcessDedupedTableToProcessedTable(taskData, "deconstruct", entitiesHandled)
        if entitiesHandled >= EntitiesHandledPerBatch then return ticksToWait, robotStateDetails end
    end
    if next(taskData._entitiesToBeUpgraded_deduped) ~= nil then
        entitiesHandled = ScanAreasForActionsToComplete._ProcessDedupedTableToProcessedTable(taskData, "upgrade", entitiesHandled)
        if entitiesHandled >= EntitiesHandledPerBatch then return ticksToWait, robotStateDetails end
    end
    if next(taskData._ghostsToBeBuilt_deduped) ~= nil then
        entitiesHandled = ScanAreasForActionsToComplete._ProcessDedupedTableToProcessedTable(taskData, "build", entitiesHandled)
        if entitiesHandled >= EntitiesHandledPerBatch then return ticksToWait, robotStateDetails end
    end

    -- Merge the manipulation items in to the input items so we have a single list of stuff needed to complete everything.
    for itemName in pairs(taskData._requiredManipulateItems) do
        taskData.requiredInputItems[itemName] = taskData.requiredInputItems[itemName] or 1
    end
    taskData._requiredManipulateItems = {}

    -- If a robot has reached this far then it has just finished the job, but it will still need to completing it's thinking it started this second.
    thisTask.state = "completed"

    -- Clean up any debug renders.
    if taskData.reviewingAreasDebugRenderIds ~= nil then
        for _, renderId in pairs(taskData.reviewingAreasDebugRenderIds) do
            rendering.destroy(renderId)
        end
    end

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
            -- Get the unit_number if it has one or an ID for the entity via the on_destroyed_event. Each call of this API function on the same entity will return the same sequential number, so it will be the same across each of the raw tables for the same real entity.
            local entity_identifier = entity.unit_number or ("destroyedId_" .. script.register_on_entity_destroyed(entity))
            -- Just record every one as its cheaper overall to record it than check for the rare duplicate that may exist.
            dedupedTable[entity_identifier] = entity
            entitiesDeduped = entitiesDeduped + 1
            areasEntities[entityIndex] = nil
            if entitiesDeduped >= EntitiesDedupedPerBatch then return entitiesDeduped end
        end
        rawTable[areaIndex] = nil
    end
    return entitiesDeduped
end

--- Process some of a table of deduped results TaskData in to a the final TaskData table.
---@param taskData Task_ScanAreasForActionsToComplete_TaskData
---@param actionType Task_ScanAreasForActionsToComplete_ActionType
---@param entitiesHandled uint # How many entities this robot has already handled.
---@return uint entitiesHandled
ScanAreasForActionsToComplete._ProcessDedupedTableToProcessedTable = function(taskData, actionType, entitiesHandled)
    local dedupedTable, finalTable
    if actionType == "deconstruct" then
        dedupedTable = taskData._entitiesToBeDeconstructed_deduped
        finalTable = taskData.entitiesToBeDeconstructed
    elseif actionType == "upgrade" then
        dedupedTable = taskData._entitiesToBeUpgraded_deduped
        finalTable = taskData.entitiesToBeUpgraded
    elseif actionType == "build" then
        dedupedTable = taskData._ghostsToBeBuilt_deduped
        finalTable = taskData.ghostsToBeBuilt
    else
        error("unsupported action type")
    end

    for identifier, entity in pairs(dedupedTable) do
        local entity_position, entity_name, entity_type = entity.position, entity.name, entity.type

        -- Get the ChunkDetails for this chunk or make it if needed.
        local chunkXValue, chunkYValue = math_floor(entity_position.x / 32), math_floor(entity_position.y / 32)
        local chunkPosition = { x = chunkXValue, y = chunkYValue }
        local chunkXObject = taskData.chunksInCombinedAreas.xChunks[chunkXValue]
        if chunkXObject == nil then
            -- This X value column of chunks hasn't been recorded yet, so create it.
            taskData.chunksInCombinedAreas.xChunks[chunkXValue] = {
                yChunks = {},
                minYValue = MathUtils.intMax, -- Start at highest possible value so first new value is always lower.
                maxYValue = MathUtils.intMin -- Start at lowest possible value so first new value is always higher.
            }
            chunkXObject = taskData.chunksInCombinedAreas.xChunks[chunkXValue]
            if taskData.chunksInCombinedAreas.minXValue > chunkXValue then
                taskData.chunksInCombinedAreas.minXValue = chunkXValue
            end
            if taskData.chunksInCombinedAreas.maxXValue < chunkXValue then
                taskData.chunksInCombinedAreas.maxXValue = chunkXValue
            end
        end
        local chunkDetails = chunkXObject.yChunks[chunkYValue]
        if chunkDetails == nil then
            -- A chunk for this Y value of the X value hasn't been recorded yet, so create it.
            chunkXObject.yChunks[chunkYValue] = {
                chunkPosition = chunkPosition,
                chunkPositionString = StringUtils.FormatPositionToString(chunkPosition),
                toBeDeconstructedEntityDetails = {},
                toBeUpgradedTypes = {},
                toBeBuiltTypes = {}
            }
            chunkDetails = chunkXObject.yChunks[chunkYValue]
            if chunkXObject.minYValue > chunkYValue then
                chunkXObject.minYValue = chunkYValue
                if taskData.chunksInCombinedAreas.minYValueAcrossAllXValues > chunkYValue then
                    taskData.chunksInCombinedAreas.minYValueAcrossAllXValues = chunkYValue
                end
            end
            if chunkXObject.maxYValue < chunkYValue then
                chunkXObject.maxYValue = chunkYValue
                if taskData.chunksInCombinedAreas.maxYValueAcrossAllXValues < chunkYValue then
                    taskData.chunksInCombinedAreas.maxYValueAcrossAllXValues = chunkYValue
                end
            end
        end

        -- Record input and output items.
        local minedProducts, requiredItem_name, requiredItem_count, requiredItemUsedPerAction
        if actionType == "deconstruct" then
            minedProducts = PrototypeAttributes.GetAttribute("entity", entity_name, "mineable_properties")--[[@as LuaEntityPrototype.mineable_properties]] .products
        elseif actionType == "upgrade" then
            -- Based on if this is a true upgrade or a rotate.
            local upgradeTargetPrototype = entity.get_upgrade_target() ---@cast upgradeTargetPrototype -nil
            local upgradeTargetPrototype_name, upgradeTargetPrototype_type = upgradeTargetPrototype.name, upgradeTargetPrototype.type

            local requiredItems = upgradeTargetPrototype.items_to_place_this[1] -- Same as construction bots, just use the first one.
            requiredItem_name, requiredItem_count = requiredItems.name, requiredItems.count

            if upgradeTargetPrototype_name == entity_name then
                -- Is a like for like replacement, so just doing a rotate.

                -- Record the required item (not input), with no output items.
                requiredItemUsedPerAction = false
                taskData._requiredManipulateItems[upgradeTargetPrototype_name] = true
            else
                -- Is an actual upgrade to change entity types.

                -- Record the inputs and output items.
                minedProducts = PrototypeAttributes.GetAttribute("entity", entity_name, "mineable_properties")--[[@as LuaEntityPrototype.mineable_properties]] .products
                requiredItemUsedPerAction = true
            end

            -- Use the new entity details.
            entity_name = upgradeTargetPrototype_name
            entity_type = upgradeTargetPrototype_type
        elseif actionType == "build" then
            local itemsToPlaceThis = PrototypeAttributes.GetAttribute("entity", entity_name, "items_to_place_this") --[[@as SimpleItemStack[]? ]]
            if itemsToPlaceThis ~= nil then
                local requiredItems = itemsToPlaceThis[1] -- Same as construction bots, just use the first one.
                requiredItem_name, requiredItem_count = requiredItems.name, requiredItems.count
                requiredItemUsedPerAction = true
            end
        else
            error("unsupported action type")
        end
        if minedProducts ~= nil then
            for _, minedProduct in pairs(minedProducts) do
                -- This is intended to capture the standard player buildable type entity being mined/replaced. Rather than resource rock mining, etc.
                -- Get either the guaranteed amount or the minimum amount or 0.
                local itemQuantity = minedProduct.amount ~= nil and minedProduct.amount or minedProduct.amount_min ~= nil and minedProduct.amount_min or 0
                if minedProduct.probability == 1 and itemQuantity > 0 then
                    taskData.guaranteedOutputItems[minedProduct.name] = (taskData.guaranteedOutputItems[minedProduct.name] or 0) + math.floor(itemQuantity)
                end
            end
        end
        if requiredItemUsedPerAction then
            taskData.requiredInputItems[requiredItem_name] = (taskData.requiredInputItems[requiredItem_name] or 0) + requiredItem_count
        end

        --- Create the EntityDetails object and add it to the main list for this action type
        ---@type Task_ScanAreasForActionsToComplete_EntityDetails
        local entityDetails = {
            entityListKey = #finalTable + 1 --[[@as uint]] ,
            identifier = identifier,
            entity = entity,
            entity_name = entity_name,
            entity_type = entity_type,
            position = entity_position,
            chunkDetails = chunkDetails,
            actionType = actionType,
            builtByItemName = requiredItem_name,
            builtByItemCount = requiredItem_count
        }
        finalTable[entityDetails.entityListKey] = entityDetails

        -- Record the EntityDetails in to the Chunk Details. Some of these are grouped.
        if actionType == "deconstruct" then
            chunkDetails.toBeDeconstructedEntityDetails[entityDetails.entityListKey] = entityDetails
        elseif actionType == "upgrade" then
            chunkDetails.toBeUpgradedTypes[entity_name] = chunkDetails.toBeUpgradedTypes[entity_name] or {}
            chunkDetails.toBeUpgradedTypes[entity_name][entityDetails.entityListKey] = entityDetails
        elseif actionType == "build" then
            chunkDetails.toBeBuiltTypes[entity_name] = chunkDetails.toBeBuiltTypes[entity_name] or {}
            chunkDetails.toBeBuiltTypes[entity_name][entityDetails.entityListKey] = entityDetails
        else
            error("unsupported action type")
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
---@param thisTask Task_ScanAreasForActionsToComplete_Details
---@param robot Robot
ScanAreasForActionsToComplete.RemovingRobotFromTask = function(thisTask, robot)
    -- There is no robot specific activity to be stopped.

    -- There are no child tasks of this task.
end

--- Called when a task is being removed and any task globals or ongoing activities need to be stopped.
---@param thisTask Task_ScanAreasForActionsToComplete_Details
ScanAreasForActionsToComplete.RemovingTask = function(thisTask)
    -- There is no robot specific activity to be stopped.

    -- There are no child tasks of this task.
end

--- Called when pausing a robot and so all of its activities within the this task and sub tasks need to pause.
---@param thisTask Task_ScanAreasForActionsToComplete_Details
---@param robot Robot
ScanAreasForActionsToComplete.PausingRobotForTask = function(thisTask, robot)
    -- There is no robot specific activity to be stopped.

    -- There are no child tasks of this task.
end

return ScanAreasForActionsToComplete
