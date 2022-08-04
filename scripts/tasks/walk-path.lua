local ShowRobotState = require("scripts.common.show-robot-state")

---@class Task_WalkPath_Data : Task_Data
---@field taskData Task_WalkPath_BespokeData

---@class Task_WalkPath_BespokeData
---@field pathToWalk PathfinderWaypoint[]
---@field nodeTarget int

local WalkPath = {} ---@class Task_WalkPath_Interface : Task_Interface
WalkPath.taskName = "WalkPath"

WalkPath._OnLoad = function()
    MOD.Interfaces.Tasks.WalkPath = WalkPath
end

--- Called to create the task and start the process when an active robot first reaches this task.
---@param robot Robot
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param pathToWalk PathfinderWaypoint[]
---@return Task_WalkPath_Data
---@return uint ticksToWait
WalkPath.Begin = function(robot, job, parentTask, pathToWalk)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(WalkPath.taskName, robot, job, parentTask) ---@cast thisTask Task_WalkPath_Data

    -- Store the request data.
    thisTask.taskData = {
        pathToWalk = pathToWalk,
        nodeTarget = 1
    }

    -- Just do a progression once to start.
    local ticksToWait = WalkPath.Progress(thisTask)
    return thisTask, ticksToWait
end

--- Called to continue progression on the task by on_tick.
---@param thisTask Task_WalkPath_Data
---@return uint ticksToWait
WalkPath.Progress = function(thisTask)
    if global.Settings.showRobotState then
        ShowRobotState.UpdateStateText(thisTask.robot, "Walking the path", "normal")
    end

    -- Currently this accuracy requires the entity to be very very close to the target which may cause overshooting and the entity to loop back and fourth over it.
    local walkAccuracy = 0.3

    -- Check if we are at our target node yet, if we are move the target on by one. Keeps on checking target nodes until it finds one we aren't at.
    -- Code Note: have to check x and y rather than diagonal distance to avoid mismatch between the 2 checks when moving diagonally.
    local currentPosition = thisTask.robot.entity.position
    local targetPosition = thisTask.taskData.pathToWalk[thisTask.taskData.nodeTarget].position
    local largerDistanceToMove = false -- Just starting value so the while loop is entered. All logic paths within the loop replace this value.
    while (not largerDistanceToMove) do
        if math.abs(currentPosition.x - targetPosition.x) <= walkAccuracy and math.abs(currentPosition.y - targetPosition.y) <= walkAccuracy then
            thisTask.taskData.nodeTarget = thisTask.taskData.nodeTarget + 1
            if thisTask.taskData.nodeTarget > #thisTask.taskData.pathToWalk then
                -- Reached end of path.
                MOD.Interfaces.TaskManager.TaskCompleted(thisTask)
                return 0
            end
            targetPosition = thisTask.taskData.pathToWalk[thisTask.taskData.nodeTarget].position
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

    -- Move towards the target node.
    thisTask.robot.entity.walking_state = { walking = (walkDirection ~= nil), direction = walkDirection }

    return 1
end



return WalkPath
