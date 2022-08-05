local ShowRobotState = require("scripts.common.show-robot-state")

---@class Task_WalkPath_Data : Task_Data
---@field taskData Task_WalkPath_BespokeData
---@field robotsTaskData table<Robot, Task_WalkPath_Robot_BespokeData>

---@class Task_WalkPath_BespokeData

---@class Task_WalkPath_Robot_BespokeData : Task_Data_Robot
---@field pathToWalk PathfinderWaypoint[]
---@field nodeTarget int

local WalkPath = {} ---@class Task_WalkPath_Interface : Task_Interface
WalkPath.taskName = "WalkPath"

WalkPath._OnLoad = function()
    MOD.Interfaces.Tasks.WalkPath = WalkPath
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@return Task_WalkPath_Data
WalkPath.ActivateTask = function(job, parentTask)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(WalkPath.taskName, job, parentTask) ---@cast thisTask Task_WalkPath_Data

    return thisTask
end

--- Called to do work on the task by on_tick by each robot.
---@param thisTask Task_WalkPath_Data
---@param robot Robot
---@param pathToWalk? PathfinderWaypoint[] # Only needed on first Progress() for each robot.
---@return uint ticksToWait
WalkPath.Progress = function(thisTask, robot, pathToWalk)

    -- Handle if this is the first Progress() for a robot.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData == nil then
        ---@cast pathToWalk -nil

        -- Record robot specific details to this task.
        robotTaskData = MOD.Interfaces.TaskManager.CreateGenericRobotTaskData(robot, thisTask.currentTaskIndex, thisTask) --[[@as Task_WalkPath_Robot_BespokeData]]
        thisTask.robotsTaskData[robot] = robotTaskData
        robotTaskData.pathToWalk = pathToWalk
        robotTaskData.nodeTarget = 1
    end


    if global.Settings.showRobotState then
        ShowRobotState.UpdateStateText(robot, "Walking the path", "normal")
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

                return 0
            end
            targetPosition = robotTaskData.pathToWalk[robotTaskData.nodeTarget].position
            largerDistanceToMove = false
        else
            largerDistanceToMove = true
        end
    end

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

    return 1
end

--- Called to remove a task. This will propagates down to all sub tasks to tidy up any non task managed globals and other active effects.
---@param thisTask Task_WalkPath_Data
WalkPath.Remove = function(thisTask)
    error("old code on unused code path")
    -- If this task was active then cancel the last movement input sent to the robot as it will stay persistent otherwise.
    --if thisTask.state == "active" then
    --    thisTask.robot.entity.walking_state = { walking = false, direction = defines.direction.north }
    --end

    -- This task never has children.
end

return WalkPath
