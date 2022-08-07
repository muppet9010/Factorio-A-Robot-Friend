local Events = require("utility.manager-libraries.events")
local ShowRobotState = require("scripts.common.show-robot-state")

---@class Task_GetWalkingPath_Data : Task_Data
---@field taskData Task_GetWalkingPath_BespokeData
---@field robotsTaskData table<Robot, Task_GetWalkingPath_Robot_BespokeData>

---@class Task_GetWalkingPath_BespokeData
---@field endPosition MapPosition
---@field surface LuaSurface

---@class Task_GetWalkingPath_Robot_BespokeData : Task_Data_Robot
---@field startPosition MapPosition
---@field pathRequestId uint
---@field pathFound? PathfinderWaypoint[]
---@field pathFinderTimeout? boolean

local GetWalkingPath = {} ---@class Task_GetWalkingPath_Interface : Task_Interface
GetWalkingPath.taskName = "GetWalkingPath"

GetWalkingPath._CreateGlobals = function()
    global.Tasks.GetWalkingPath = global.Tasks.GetWalkingPath or {} ---@class Global_Task_GetWalkingPath
    global.Tasks.GetWalkingPath.pathRequests = global.Tasks.GetWalkingPath.pathRequests or {} ---@type table<uint, Task_GetWalkingPath_Robot_BespokeData> # Keyed by the path request id.
end

GetWalkingPath._OnLoad = function()
    MOD.Interfaces.Tasks.GetWalkingPath = GetWalkingPath
    Events.RegisterHandlerEvent(defines.events.on_script_path_request_finished, "GetWalkingPath.OnPathRequestFinished", GetWalkingPath._OnPathRequestFinished)
end

--- Called ONCE per Task to create the task when the first robot first reaches this task in the job.
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param endPosition MapPosition
---@param surface LuaSurface
---@return Task_GetWalkingPath_Data
GetWalkingPath.ActivateTask = function(job, parentTask, endPosition, surface)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(GetWalkingPath.taskName, job, parentTask) ---@cast thisTask Task_GetWalkingPath_Data

    -- Store the task wide data.
    thisTask.taskData = {
        endPosition = endPosition,
        surface = surface
    }

    return thisTask
end

--- Called to do work on the task by on_tick by each robot.
---@param thisTask Task_GetWalkingPath_Data
---@param robot Robot
---@param startPosition? MapPosition # Only needed on first Progress() for each robot.
---@return uint ticksToWait
---@return ShowRobotState_NewRobotStateDetails|nil robotStateDetails # nil if there is no state being set by this Task
GetWalkingPath.Progress = function(thisTask, robot, startPosition)
    local taskData = thisTask.taskData

    -- Handle if this is the first Progress() for a robot.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData == nil then
        ---@cast startPosition -nil

        -- Record robot specific details to this task.
        robotTaskData = MOD.Interfaces.TaskManager.CreateGenericRobotTaskData(robot, thisTask.currentTaskIndex, thisTask) --[[@as Task_GetWalkingPath_Robot_BespokeData]]
        thisTask.robotsTaskData[robot] = robotTaskData
        robotTaskData.startPosition = startPosition

        --[[
        FUTURE: should play around with these values and see what impact they have.
        Need to check pathfinder going through dense and difficult areas, not just simple open and blocky areas.

        path_resolution_modifier values:
            - -1 and below is bad as it can sometimes get stuck on things as it would path in 2-3 tile jumps, so I think 0 is a better start.
            - 0 is right for simple areas as this seems to be whole tiles, but it fails on close buildings (like biters do).
            - 2 can't do furnace staggered walls, as can't find the gaps in them, so not much better over 0 really.
            - 3 gets between close buildings (staggered furnace wall), but is very jagged, so would need either the path or movement control smoothing to try and remove the jittery-ness.

        with `prefer_straight_paths` enabled it removes the jitter in the path, but tends to have odd detours even if the distance covered is the same (looks odd).

        The highest path_resolution_modifier gives best results, but takes ages to calculate. So ideally want something quick initially and then detect any big detours and re-do that bit of the path with a detailed one (with possible smoothing still).

        This really needs a whole series of test setups and recording the different routes through.
    ]]
        -- Left as detailed with jittery movement, but able to find tight paths for now.
        local pathRequestId = taskData.surface.request_path({
            bounding_box = robot.entity.prototype.collision_box, -- Could be cached, but actually called very rarely, so no real benefit.
            collision_mask = robot.entity.prototype.collision_mask, -- Could be cached, but actually called very rarely, so no real benefit. FUTURE: May be some of these options we want as non default?
            start = startPosition,
            goal = taskData.endPosition,
            force = robot.force,
            radius = 0.0, -- FUTURE: this probably wants to be higher to allow us just getting close enough for what we want to do. Maybe it should be specified as part of when the parent task calls in. With a default of close like this. When it was at a value of 1.0 the pathfinder would sometimes suggest pathing in to a blocking entity right next to the target location and mining it. At 0 while it requires the target position to be reachable, it does avoid this oddity.
            can_open_gates = true,
            entity_to_ignore = robot.entity, -- has to be the entity itself as otherwise it blocks its own path request.
            pathfind_flags = {
                cache = false, -- We don't cache as we want the best path for this robot and not just something in the vague vicinity.
                prefer_straight_paths = false, -- Oddly straight paths lead to some odd paths the it tries to square off things and doesn't do it very well.
                no_break = true -- Is done as a higher priority pathing request even over long distances with these settings.
            },
            path_resolution_modifier = 3 --[[
            Xorimuth said: path_resolution_modifier determines the resolution of the path. When the number is lower (e.g. -3), it will finish quicker and the waypoints will be further apart. I use it for my spidertron pathfinder, where I start with -3, if it fails, I then try -1, 1, and 3, which are more likely to succeed (e.g. if the valid path is very intricate), but take progressively more time to complete.
            supported range is -8 to +8.
        ]]
        })
        global.Tasks.GetWalkingPath.pathRequests[pathRequestId] = robotTaskData
        robotTaskData.pathRequestId = pathRequestId
    end

    -- There's nothing active to be done and when the pathfinder returns the event will record the data and mark the task as complete for that robot.
    ---@type ShowRobotState_NewRobotStateDetails
    local robotStateDetails = { stateText = "Looking for walking path", level = ShowRobotState.StateLevel.normal }
    return 1, robotStateDetails
end

--- React to a path request being completed. Its up to the caller to handle the too busy response as it may want to try again or try some alternative task instead.
---@param event EventData.on_script_path_request_finished
GetWalkingPath._OnPathRequestFinished = function(event)
    local thisRobotTaskData = global.Tasks.GetWalkingPath.pathRequests[event.id]
    if thisRobotTaskData == nil then return end

    -- This task has completed in all situations, so record the result. The parent task can obtain it when it polls.
    thisRobotTaskData.state = "completed"
    thisRobotTaskData.pathFinderTimeout = event.try_again_later
    thisRobotTaskData.pathFound = event.path

    -- Remove the global waiting for the path finder request to complete.
    global.Tasks.GetWalkingPath.pathRequests[event.id] = nil
end

--- Called when a specific robot is being removed from a task.
---@param thisTask Task_GetWalkingPath_Data
---@param robot Robot
GetWalkingPath.RemovingRobotFromTask = function(thisTask, robot)
    -- Remove any pending path request object in the global for this robot.
    local robotTaskData = thisTask.robotsTaskData[robot]
    if robotTaskData ~= nil and robotTaskData.state == "active" then
        global.Tasks.GetWalkingPath.pathRequests[robotTaskData.pathRequestId] = nil
    end

    -- Remove any robot specific task data.
    thisTask.robotsTaskData[robot] = nil

    -- This task never has children.
end

--- Called when a task is being removed and any task globals or ongoing activities need to be stopped.
---@param thisTask Task_GetWalkingPath_Data
GetWalkingPath.RemovingTask = function(thisTask)
    -- Remove any pending path request objects in the global for all robots in this task.
    for _, robotTaskData in pairs(thisTask.robotsTaskData) do
        if robotTaskData.state == "active" then
            global.Tasks.GetWalkingPath.pathRequests[robotTaskData.pathRequestId] = nil
        end
    end

    -- This task never has children.
end

return GetWalkingPath
