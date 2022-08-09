--[[
    Manages a collection of robots analysing the actions and materials needed for a given group of areas to "complete" it. Then they collect the required materials and go to the area to carry out the actions, repeating as required. Actions can include, building, mining, upgrading, rotating.
    Takes in an array of areas to be completed. These can overlap and will be deduped. Is to allow flexibility in selecting multiple smaller areas to be done while avoiding others, thus an odd overall shape to be completed.

    All robots are processed within this task as individuals as some sub tasks are looped over per robot until the total is done. This is a multi stage mix of combined and individual robot sub tasks.

    Notes:
        - By default players and robots have no trash slots.
        - Activities are done 1 robot per chunk until all chunks are completed for that activity. Then the next activity is started by all robots.
        - Order of activities:
            - Deconstruct everything. Clears the way for everything else.
            - Upgrade everything. Makes use of items for doing rotations as these require 1 item to do, but are item neutral.
            - Build everything. Should empty the inventories out.
]]

local ShowRobotState = require("scripts.common.show-robot-state")

---@class Task_CompleteArea_Data : Task_Data
---@field taskData Task_CompleteArea_BespokeData
---@field robotsTaskData table<Robot, Task_CompleteArea_Robot_BespokeData>

---@class Task_CompleteArea_BespokeData
---@field surface LuaSurface
---@field areasToComplete BoundingBox[]
---@field force LuaForce
---@field scannedAreaData? Task_ScanAreasForActionsToComplete_BespokeData

---@class Task_CompleteArea_Robot_BespokeData : Task_Data_Robot
---@field state "active"|"completed"

local CompleteArea = {} ---@class Task_CompleteArea_Interface : Task_Interface
CompleteArea.taskName = "CompleteArea"

CompleteArea._OnLoad = function()
    MOD.Interfaces.Tasks.CompleteArea = CompleteArea
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param surface LuaSurface
---@param areasToComplete BoundingBox[]
---@param force LuaForce
---@return Task_CompleteArea_Data
CompleteArea.ActivateTask = function(job, parentTask, surface, areasToComplete, force)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(CompleteArea.taskName, job, parentTask) ---@cast thisTask Task_CompleteArea_Data

    -- Store the task wide data.
    thisTask.taskData = {
        surface = surface,
        areasToComplete = areasToComplete,
        force = force
    }

    return thisTask
end

--- Called to do work on the task by on_tick by each robot.
---@param thisTask Task_CompleteArea_Data
---@param robot Robot
---@return uint ticksToWait
---@return ShowRobotState_NewRobotStateDetails|nil robotStateDetails # nil if there is no state being set by this Task
CompleteArea.Progress = function(thisTask, robot)
    local taskData = thisTask.taskData

    -- Handle if this is the very first robot to Progress() this Task.
    if thisTask.currentTaskIndex == 0 then
        -- Just activate the scanning task initially as until this is completed we don't know if any resources need taking.
        thisTask.plannedTasks[#thisTask.plannedTasks + 1] = MOD.Interfaces.Tasks.ScanAreasForActionsToComplete.ActivateTask(thisTask.job, thisTask, taskData.surface, taskData.areasToComplete, taskData.force)
        thisTask.currentTaskIndex = 1
    end

    -- TEMPLATE: If there's robot specific data or child tasks.
    -- Handle if this is the first Progress() for a specific robot.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData == nil then
        -- Record robot specific details to this task.
        robotTaskData = MOD.Interfaces.TaskManager.CreateGenericRobotTaskData(robot, thisTask.currentTaskIndex, thisTask) --[[@as Task_CompleteArea_Robot_BespokeData]]
        thisTask.robotsTaskData[robot] = robotTaskData
    end

    -- Do the scanning task if we have no scanned data yet. All robots do this, but none store any personal data or state during it.
    if taskData.scannedAreaData == nil then
        local task_ScanAreasForActionsToComplete_Data = thisTask.plannedTasks[robotTaskData.currentTaskIndex] --[[@as Task_ScanAreasForActionsToComplete_Data]]
        local ticksToWait, robotStateDetails = MOD.Interfaces.Tasks.ScanAreasForActionsToComplete.Progress(task_ScanAreasForActionsToComplete_Data, robot)
        if task_ScanAreasForActionsToComplete_Data.state == "completed" then
            taskData.scannedAreaData = task_ScanAreasForActionsToComplete_Data.taskData
        end

        --We always return on the robot that did some progression on this. The next robot cycle will the next step fresh.
        return ticksToWait, robotStateDetails
    end

    --TODO: head off to deconstruct anything in the way first (if needed). Then review scanned results and items the robots have and decide if we need to collect anything extra for any building.


    -- TEMPLATE: These are often returned from sub tasks Progress() functions, but can also be explicitly defined.
    ---@type uint,ShowRobotState_NewRobotStateDetails
    local ticksToWait, robotStateDetails = 0, { stateText = "Some state text", level = ShowRobotState.StateLevel.normal }

    return ticksToWait, robotStateDetails
end

--- Called when a specific robot is being removed from a task.
---@param thisTask Task_CompleteArea_Data
---@param robot Robot
CompleteArea.RemovingRobotFromTask = function(thisTask, robot)
    -- Tidy up any robot specific stuff.
    local robotTaskData = thisTask.robotsTaskData[robot]

    -- Remove any robot specific task data.
    thisTask.robotsTaskData[robot] = nil

    MOD.Interfaces.TaskManager.GenericTaskPropagateRemoveRobot(thisTask, robot)
end

--- Called when a task is being removed and any task globals or ongoing activities need to be stopped.
---@param thisTask Task_CompleteArea_Data
CompleteArea.RemovingTask = function(thisTask)
    -- Remove any per robot bits if the robot is still active.
    for _, robotTaskData in pairs(thisTask.robotsTaskData) do
        if robotTaskData.state == "active" then
        end
    end

    MOD.Interfaces.TaskManager.GenericTaskPropagateRemove(thisTask)
end

--- Called when pausing a robot and so all of its activities within the this task and sub tasks need to pause.
---@param thisTask Task_CompleteArea_Data
---@param robot Robot
CompleteArea.PausingRobotForTask = function(thisTask, robot)
    -- If the robot was being actively used in some way stop it.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData ~= nil and robotTaskData.state == "active" then
    end

    MOD.Interfaces.TaskManager.GenericTaskPropagatePausingRobot(thisTask, robot)
end

return CompleteArea
