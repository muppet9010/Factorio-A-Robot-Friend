--[[
    Manages a collection of robots analysing the actions and materials needed for a given group of areas to "complete" it. Returns a list of the actions by type to be done and the difference in items needed to complete everything and the excess items.
    Takes in an array of areas to be completed. These can overlap and will be deduped. Is to allow flexibility in selecting multiple smaller areas to be done while avoiding others, thus an odd overall shape to be completed.

    Action types:
        - Deconstruct: anything on the robots force and all trees and rocks types that are marked for deconstruction.
        - Upgrade: anything that is marked for upgrade on the robots force, also includes entities marked for rotation.
        - ghosts to build: any ghosts on the robots force.
        - Future: tiles not included at all.

    All robots are processed within this task as a collective. With each robot contributing some processing of the areas.
]]


local ShowRobotState = require("scripts.common.show-robot-state")

---@class Task_ScanAreasForActionsToComplete_Data : Task_Data
---@field taskData Task_ScanAreasForActionsToComplete_BespokeData
---@field robotsTaskData table<Robot, Task_ScanAreasForActionsToComplete_Robot_BespokeData>

---@class Task_ScanAreasForActionsToComplete_BespokeData
---@field surface LuaSurface
---@field areasToComplete BoundingBox[]
---@field force LuaForce
---
---@field entitiesToBeDeconstructed_raw table<uint, table<uint, LuaEntity>> @ An array per area of the raw entities found needing to be deconstructed. The keys are sequential index numbers that will become gappy when processed dow to being an empty single depth table.
---@field natureToBeDeconstructed_raw table<uint, table<uint, LuaEntity>> @ An array per area of the raw trees and rocks found needing to be deconstructed. These are marked for deconstruction by any force and may belong to the robots force and thus included already in entitiesToBeDeconstructed_raw. The keys are sequential index numbers that will become gappy when processed dow to being an empty single depth table.
---@field entitiesToBeUpgraded_raw table<uint, table<uint, LuaEntity>> @ An array per area of the raw entities found needing to be upgraded. The keys are sequential index numbers that will become gappy when processed dow to being an empty single depth table.
---@field ghostsToBeBuilt_raw table<uint, table<uint, LuaEntity>> @ An array per area of the raw entities found needing to be built. The keys are sequential index numbers that will become gappy when processed dow to being an empty single depth table.
---
---@field entitiesToBeDeconstructed_deduped table<uint|string, LuaEntity> @ A table of all the raw entities (deduped) needing to be deconstructed across all areas. Keyed by the entities unit_number or its name and position as a string.
---@field natureToBeDeconstructed_deduped table<uint|string, LuaEntity> @ A table of all the trees and rocks (deduped) needing to be deconstructed across all areas.  These are marked for deconstruction by any force and may belong to the robots force and thus included already in entitiesToBeDeconstructed_raw. Keyed by the entities unit_number or its name and position as a string. Post deduping this list is checked for force and duplicates and merged in to entitiesToBeDeconstructed_deduped ready for actual usage.
---@field entitiesToBeUpgraded_deduped table<uint|string, LuaEntity> @ A table of all the raw entities (deduped) needing to be upgraded across all areas. Keyed by the entities unit_number or its name and position as a string.
---@field ghostsToBeBuilt_deduped table<uint|string, LuaEntity> @ A table of all the raw entities (deduped) needing to be built across all areas. Keyed by the entities unit_number or its name and position as a string.
---@field allDataDeduped boolean # Flag to say when all data has been deduped and we can just skip that whole checking code bloc.
---
---@field entitiesToBeDeconstructed table<uint, LuaEntity> @ Keyed by a sequential number, used by calling functions to handle the data. This has been deduped.
---@field entitiesToBeUpgraded table<uint, LuaEntity> @ Keyed by a sequential number, used by calling functions to handle the data. This has been deduped.
---@field ghostsToBeBuilt table<uint, LuaEntity> @ Keyed by a sequential number, used by calling functions to handle the data. This has been deduped.
---@field requiredInputItems table<string, uint> @ Item name to count of items needed as input.
---@field excessOutputItems table<string, uint> @ Item name to count of items that will be generated as output.

---@class Task_ScanAreasForActionsToComplete_Robot_BespokeData : Task_Data_Robot
---@field state "active"|"completed"

local ScanAreasForActionsToComplete = {} ---@class Task_ScanAreasForActionsToComplete_Interface : Task_Interface
ScanAreasForActionsToComplete.taskName = "ScanAreasForActionsToComplete"

local EntitiesDedupedPerBatch = 100 -- Just getting unit_number via API calls.
local EntitiesReviewPerBatch = 10 -- Multiple API calls to get item types, etc.
local TicksPerBatch = 60

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
        allDataDeduped = false
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

    -- The response times are always the same unless the task is complete.
    ---@type uint,ShowRobotState_NewRobotStateDetails
    local ticksToWait, robotStateDetails = 60, { stateText = "Reviewing area for actions to complete", level = ShowRobotState.StateLevel.normal }

    -- Handle if this is the very first robot to Progress() this Task. We leave the tables constructed but empty once used, so this check is safe throughout the tasks life.
    if taskData.entitiesToBeDeconstructed_raw == nil then
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
        taskData.entitiesToBeDeconstructed_raw = {}
        for _, area in pairs(taskData.areasToComplete) do
            taskData.entitiesToBeDeconstructed_raw[#taskData.entitiesToBeDeconstructed_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, to_be_deconstructed = true })
        end
        taskData.natureToBeDeconstructed_raw = {}
        for _, area in pairs(taskData.areasToComplete) do
            -- These are marked for deconstruction by any force and may belong to the robots force and thus included already in entitiesToBeDeconstructed_raw.
            taskData.natureToBeDeconstructed_raw[#taskData.natureToBeDeconstructed_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, type = { "tree", "rock" }, to_be_deconstructed = true })
        end
        taskData.entitiesToBeUpgraded_raw = {}
        for _, area in pairs(taskData.areasToComplete) do
            taskData.entitiesToBeUpgraded_raw[#taskData.entitiesToBeUpgraded_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, to_be_upgraded = true })
        end
        taskData.ghostsToBeBuilt_raw = {}
        for _, area in pairs(taskData.areasToComplete) do
            taskData.ghostsToBeBuilt_raw[#taskData.ghostsToBeBuilt_raw + 1--[[@as uint]] ] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, type = "entity-ghost" })
        end

        -- First robot just does these as they will take some UPS/thinking time.
        return ticksToWait, robotStateDetails
    end

    -- If there's raw data we need to dedupe it in to the deduped tables so its clean for later processing. The processing clears out the raw tables as it goes.
    if not taskData.allDataDeduped then
        local entitiesDeduped = 0
        if next(taskData.entitiesToBeDeconstructed_raw) ~= nil then
            taskData.entitiesToBeDeconstructed_deduped = taskData.entitiesToBeDeconstructed_deduped or {}
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData.entitiesToBeDeconstructed_raw, taskData.entitiesToBeDeconstructed_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end
        if next(taskData.natureToBeDeconstructed_raw) ~= nil then
            taskData.natureToBeDeconstructed_deduped = taskData.natureToBeDeconstructed_deduped or {}
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData.natureToBeDeconstructed_raw, taskData.natureToBeDeconstructed_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end
        if next(taskData.entitiesToBeUpgraded_raw) ~= nil then
            taskData.entitiesToBeUpgraded_deduped = taskData.entitiesToBeUpgraded_deduped or {}
            entitiesDeduped = ScanAreasForActionsToComplete._DedupeRawTableToDedupedTable(taskData.entitiesToBeUpgraded_raw, taskData.entitiesToBeUpgraded_deduped, entitiesDeduped)
            if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
        end
        if next(taskData.ghostsToBeBuilt_raw) ~= nil then
            taskData.ghostsToBeBuilt_deduped = taskData.ghostsToBeBuilt_deduped or {}
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
                if entitiesDeduped >= EntitiesDedupedPerBatch then return ticksToWait, robotStateDetails end
            end
            taskData.allDataDeduped = true
        end
    end

    --TODO: up to here




    -- Process the data to make our lists.



    -- TEMPLATE: If there's robot specific data or child tasks.
    -- Handle if this is the first Progress() for a specific robot.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData == nil then
        -- Record robot specific details to this task.
        robotTaskData = MOD.Interfaces.TaskManager.CreateGenericRobotTaskData(robot, thisTask.currentTaskIndex, thisTask) --[[@as Task_ScanAreasForActionsToComplete_Robot_BespokeData]]
        thisTask.robotsTaskData[robot] = robotTaskData
    end



    return ticksToWait, robotStateDetails
end

--- Process a table of raw results TaskData in to a deduped TaskData table.
---@param rawTable table<uint, table<uint, LuaEntity>> # Reference to the "raw" TaskData table.
---@param dedupedTable table<uint|string, LuaEntity> # Reference to the "deduped" TaskData table.
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
            if entitiesDeduped >= EntitiesDedupedPerBatch then
                return entitiesDeduped
            end
        end
        rawTable[areaIndex] = nil
    end
    return entitiesDeduped
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
