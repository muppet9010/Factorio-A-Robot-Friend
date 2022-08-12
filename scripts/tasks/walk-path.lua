--[[
    Makes a robot move down a provided path. Is an action task and does no issue correcting itself.

    Each robot is processed fully separately to the others as there's no shared elements between robots in this task and no sub tasks.
]]

local ShowRobotState = require("scripts.common.show-robot-state")

---@class Task_WalkPath_Details : Task_Details
---@field taskData Task_WalkPath_TaskData
---@field robotsTaskData table<Robot, Task_WalkPath_Robot_TaskData>

---@class Task_WalkPath_TaskData

---@class Task_WalkPath_Robot_TaskData : TaskData_Robot
---@field pathToWalk PathfinderWaypoint[]
---@field nodeTarget uint
---@field positionLastTick? MapPosition
---@field state "active"|"completed"|"stuck"

local WalkPath = {} ---@class Task_WalkPath_Interface : Task_Interface
WalkPath.taskName = "WalkPath"

WalkPath._OnLoad = function()
    MOD.Interfaces.Tasks.WalkPath = WalkPath
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Details # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Details # The parent Task or nil if this is a primary Task of a Job.
---@return Task_WalkPath_Details
WalkPath.ActivateTask = function(job, parentTask)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(WalkPath.taskName, job, parentTask) ---@cast thisTask Task_WalkPath_Details

    return thisTask
end

--- Called to do work on the task by on_tick by each robot.
---@param thisTask Task_WalkPath_Details
---@param robot Robot
---@param pathToWalk? PathfinderWaypoint[] # Only needed on first Progress() for each robot.
---@return uint ticksToWait
---@return ShowRobotState_NewRobotStateDetails|nil robotStateDetails # nil if there is no state being set by this Task
WalkPath.Progress = function(thisTask, robot, pathToWalk)

    -- Handle if this is the first Progress() for a specific robot.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData == nil then
        ---@cast pathToWalk -nil

        -- Record robot specific details to this task.
        robotTaskData = MOD.Interfaces.TaskManager.CreateGenericRobotTaskData(robot, thisTask.currentTaskIndex, thisTask) --[[@as Task_WalkPath_Robot_TaskData]]
        thisTask.robotsTaskData[robot] = robotTaskData
        robotTaskData.pathToWalk = pathToWalk
        robotTaskData.nodeTarget = 1
    end

    -- Currently this accuracy requires the entity to be very very close to the target which may cause overshooting and the entity to loop back and fourth over it.
    local walkAccuracy = 0.3

    -- Check if we are at our target node yet, if we are move the target on by one. Keeps on checking target nodes until it finds one we aren't at.
    -- Code Note: have to check x and y rather than diagonal distance to avoid mismatch between the 2 checks when moving diagonally.
    local currentPosition = robot.entity.position
    local targetPosition = robotTaskData.pathToWalk[robotTaskData.nodeTarget].position
    local largerDistanceToMove = false -- Just starting value so the while loop is entered. All logic paths within the loop replace this value.
    while (not largerDistanceToMove) do
        if math.abs(currentPosition.x - targetPosition.x) <= walkAccuracy and math.abs(currentPosition.y - targetPosition.y) <= walkAccuracy then
            robotTaskData.nodeTarget = robotTaskData.nodeTarget + 1
            if robotTaskData.nodeTarget > #robotTaskData.pathToWalk then
                -- Reached end of path.
                robotTaskData.state = "completed"

                -- Cancel the last movement input sent to the robot as it will stay persistent otherwise.
                robot.entity.walking_state = { walking = false, direction = defines.direction.north }

                return 0, nil
            end
            targetPosition = robotTaskData.pathToWalk[robotTaskData.nodeTarget].position
            largerDistanceToMove = false
        else
            largerDistanceToMove = true
        end
    end

    -- Check if the robot has got stuck (same position as last tick).
    if robotTaskData.positionLastTick ~= nil and robotTaskData.positionLastTick.x == currentPosition.x and robotTaskData.positionLastTick.y == currentPosition.y then
        -- Robot stuck so tell calling task so it can handle.
        robotTaskData.state = "stuck"

        -- Cancel the last movement input sent to the robot as it will stay persistent otherwise.
        robot.entity.walking_state = { walking = false, direction = defines.direction.north }

        return 0, nil
    end
    robotTaskData.positionLastTick = currentPosition

    -- Get the direction to move towards the target node.
    local walkDirection ---@type defines.direction|nil
    if currentPosition.x > targetPosition.x + walkAccuracy then
        -- Needs to go west.
        if currentPosition.y > targetPosition.y + walkAccuracy then
            -- Needs to go north.
            walkDirection = (7) --[[@as defines.direction]]
        elseif currentPosition.y < targetPosition.y - walkAccuracy then
            -- Needs to go south.
            walkDirection = (5) --[[@as defines.direction]]
        else
            -- North/south is fine.
            walkDirection = (6) --[[@as defines.direction]]
        end
    elseif currentPosition.x < targetPosition.x - walkAccuracy then
        -- Needs to go east.
        if currentPosition.y > targetPosition.y + walkAccuracy then
            -- Needs to go north.
            walkDirection = (1) --[[@as defines.direction]]
        elseif currentPosition.y < targetPosition.y - walkAccuracy then
            -- Needs to go south.
            walkDirection = (3) --[[@as defines.direction]]
        else
            -- North/south is fine.
            walkDirection = (2) --[[@as defines.direction]]
        end
    else
        -- East/west is fine
        if currentPosition.y > targetPosition.y + walkAccuracy then
            -- Needs to go north.
            walkDirection = (0) --[[@as defines.direction]]
        elseif currentPosition.y < targetPosition.y - walkAccuracy then
            -- Needs to go south.
            walkDirection = (4) --[[@as defines.direction]]
        else
            -- North/south is fine.
            error("Trying to calculate a direction to walk to the target node from current position, but we are already near enough.")
            walkDirection = nil -- This shouldn't happen and not sure what to do about it right now. At present it won't walk that tick and then next tick it will move the targetNode on one and continue (or complete).
        end
    end

    -- Move towards the target node if we're not going the right direction all ready. This is a persistent command until the walking_state is overridden.
    robot.entity.walking_state = { walking = true, direction = walkDirection }

    ---@type ShowRobotState_NewRobotStateDetails
    local robotStateDetails = { stateText = "Walking the path", level = ShowRobotState.StateLevel.normal }

    return 1, robotStateDetails
end

--- Called when a specific robot is being removed from a task.
---@param thisTask Task_WalkPath_Details
---@param robot Robot
WalkPath.RemovingRobotFromTask = function(thisTask, robot)
    -- If the robot was being actively walked it will need its walking_state reset so they don't continue uncontrolled.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData ~= nil and robotTaskData.state == "active" then
        robot.entity.walking_state = { walking = false, direction = defines.direction.north }
    end

    -- Remove any robot specific task data.
    thisTask.robotsTaskData[robot] = nil

    -- This task never has children.
end

--- Called when a task is being removed and any task globals or ongoing activities need to be stopped.
---@param thisTask Task_WalkPath_Details
WalkPath.RemovingTask = function(thisTask)
    -- Any robots which were being active walked will need their walking_state reset so they don't continue uncontrolled.
    for _, robotTaskData in pairs(thisTask.robotsTaskData) do
        if robotTaskData.state == "active" then
            robotTaskData.robot.entity.walking_state = { walking = false, direction = defines.direction.north }
        end
    end

    -- This task never has children.
end

--- Called when pausing a robot and so all of its activities within the this task and sub tasks need to pause.
---@param thisTask Task_WalkPath_Details
---@param robot Robot
WalkPath.PausingRobotForTask = function(thisTask, robot)
    -- If the robot was being actively walked it will need its walking_state reset so they don't continue uncontrolled.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData ~= nil and robotTaskData.state == "active" then
        robot.entity.walking_state = { walking = false, direction = defines.direction.north }
    end

    -- This task never has children.
end

return WalkPath
