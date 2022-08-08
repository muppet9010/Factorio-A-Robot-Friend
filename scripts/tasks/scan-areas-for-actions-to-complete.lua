--[[
    Manages a collection of robots analysing the actions and materials needed for a given group of areas to "complete" it. Returns a list of the actions by type to be done and the difference in items needed to complete everything and the excess items.
    Takes in an array of areas to be completed. These can overlap and will be de-duped. Is to allow flexibility in selecting multiple smaller areas to be done while avoiding others, thus an odd overall shape to be completed.

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
---@field entitiesToBeDeconstructed_raw LuaEntity[] @ An array per area of the raw entities found needing to be deconstructed.
---@field natureToBeDeconstructed_raw LuaEntity[] @ An array per area of the raw trees and rocks found needing to be deconstructed. These are marked for deconstruction by any force and may belong to the robots force and thus included already in entitiesToBeDeconstructed_raw.
---@field entitiesToBeUpgraded_raw LuaEntity[][] @ An array per area of the raw entities found needing to be upgraded.
---@field ghostsToBeBuilt_raw LuaEntity[][] @ An array per area of the raw entities found needing to be built.
---@field entitiesToBeDeconstructed table<uint, LuaEntity> @ Keyed by a sequential number, used by calling functions to handle the data. This has been de-duped.
---@field entitiesToBeUpgraded table<uint, LuaEntity> @ Keyed by a sequential number, used by calling functions to handle the data. This has been de-duped.
---@field ghostsToBeBuilt table<uint, LuaEntity> @ Keyed by a sequential number, used by calling functions to handle the data. This has been de-duped.
---@field requiredInputItems table<string, uint> @ Item name to count of items needed as input.
---@field excessOutputItems table<string, uint> @ Item name to count of items that will be generated as output.

---@class Task_ScanAreasForActionsToComplete_Robot_BespokeData : Task_Data_Robot
---@field state "active"|"completed"

local ScanAreasForActionsToComplete = {} ---@class Task_ScanAreasForActionsToComplete_Interface : Task_Interface
ScanAreasForActionsToComplete.taskName = "ScanAreasForActionsToComplete"

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
        force = force
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

    -- Handle if this is the very first robot to Progress() this Task.
    if taskData.entitiesToBeDeconstructed_raw == nil then
        -- CODE NOTE: I am assuming the getting lists of entities to be completed will be quick and so can be done in all in one go. This may prove wrong and require this to be done spread over multiple seconds as a series of smaller queries.
        -- TODO: check that all the action typed are actually found and recorded by this process.
        -- Check the various actions needed over the areas and record the raw results for later processing.
        taskData.entitiesToBeDeconstructed_raw = {}
        for _, area in pairs(taskData.areasToComplete) do
            taskData.entitiesToBeDeconstructed_raw[#taskData.entitiesToBeDeconstructed_raw + 1] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, to_be_deconstructed = true })
        end
        taskData.natureToBeDeconstructed_raw = {}
        for _, area in pairs(taskData.areasToComplete) do
            -- These are marked for deconstruction by any force and may belong to the robots force and thus included already in entitiesToBeDeconstructed_raw.
            taskData.natureToBeDeconstructed_raw[#taskData.natureToBeDeconstructed_raw + 1] = taskData.surface.find_entities_filtered({ area = area, type = { "tree", "rock" }, to_be_deconstructed = true })
        end
        taskData.entitiesToBeUpgraded_raw = {}
        for _, area in pairs(taskData.areasToComplete) do
            taskData.entitiesToBeUpgraded_raw[#taskData.entitiesToBeUpgraded_raw + 1] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, to_be_upgraded = true })
        end
        taskData.ghostsToBeBuilt_raw = {}
        for _, area in pairs(taskData.areasToComplete) do
            taskData.ghostsToBeBuilt_raw[#taskData.ghostsToBeBuilt_raw + 1] = taskData.surface.find_entities_filtered({ area = area, force = taskData.force, type = "entity-ghost" })
        end
    end

    --TODO: up to here

    -- TEMPLATE: If there's robot specific data or child tasks.
    -- Handle if this is the first Progress() for a specific robot.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData == nil then
        -- Record robot specific details to this task.
        robotTaskData = MOD.Interfaces.TaskManager.CreateGenericRobotTaskData(robot, thisTask.currentTaskIndex, thisTask) --[[@as Task_ScanAreasForActionsToComplete_Robot_BespokeData]]
        thisTask.robotsTaskData[robot] = robotTaskData
    end


    -- TEMPLATE: These are often returned from sub tasks Progress() functions, but can also be explicitly defined.
    ---@type uint,ShowRobotState_NewRobotStateDetails
    local ticksToWait, robotStateDetails = 0, { stateText = "Some state text", level = ShowRobotState.StateLevel.normal }

    return ticksToWait, robotStateDetails
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
