local Events = require("utility.manager-libraries.events")
local ShowRobotState = require("scripts.common.show-robot-state")

---@class Task_GetWalkingPath_Data : Task_Data
---@field taskData Task_GetWalkingPath_BespokeData

---@class Task_GetWalkingPath_BespokeData
---@field startPosition MapPosition
---@field endPosition MapPosition
---@field surface LuaSurface
---@field pathFound? PathfinderWaypoint[]
---@field pathFinderTimeout? boolean

local GetWalkingPath = {} ---@class Task_GetWalkingPath_Interface : Task_Interface
GetWalkingPath.taskName = "GetWalkingPath"

GetWalkingPath._CreateGlobals = function()
    global.Tasks.GetWalkingPath = global.Tasks.GetWalkingPath or {} ---@class Global_Task_GetWalkingPath
    global.Tasks.GetWalkingPath.pathRequests = global.Tasks.GetWalkingPath.pathRequests or {} ---@type table<uint, Task_GetWalkingPath_Data> # Keyed by the path request id.
end

GetWalkingPath._OnLoad = function()
    MOD.Interfaces.Tasks.GetWalkingPath = GetWalkingPath
    Events.RegisterHandlerEvent(defines.events.on_script_path_request_finished, "GetWalkingPath.OnPathRequestFinished", GetWalkingPath._OnPathRequestFinished)
end

--- Called to create the task and start the process when an active robot first reaches this task.
---@param robot Robot
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param startPosition MapPosition
---@param endPosition MapPosition
---@param surface LuaSurface
---@return Task_GetWalkingPath_Data
---@return uint ticksToWait
GetWalkingPath.Begin = function(robot, job, parentTask, startPosition, endPosition, surface)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(GetWalkingPath.taskName, robot, job, parentTask) ---@cast thisTask Task_GetWalkingPath_Data

    -- Store the request data.
    thisTask.taskData = {
        startPosition = startPosition,
        endPosition = endPosition,
        surface = surface
    }

    local pathRequestId = surface.request_path({
        bounding_box = robot.entity.prototype.collision_box, -- Future: should be cached as there may be no entity if the robot is dead at request time and we don't want to error.
        collision_mask = robot.entity.prototype.collision_mask, -- Future: should be cached as there may be no entity if the robot is dead at request time and we don't want to error. Also may be some of these options we want as non default?
        start = startPosition,
        goal = endPosition,
        force = robot.force,
        radius = 1.0, -- FUTURE: this probably wants to be higher to allow us just getting close enough.
        can_open_gates = true,
        entity_to_ignore = robot.entity, -- has to be the entity itself as otherwise it blocks its own path request.
        pathfind_flags = {
            cache = false, -- We don't cache as we want the best path for this robot and not just something in the vague vicinity.
            prefer_straight_paths = false, -- Oddly straight paths lead to some odd paths the it tries to square off things and doesn't do it very well.
            no_break = true -- Is done as a higher priority pathing request even over long distances with these settings.
        },
        path_resolution_modifier = 0 --[[
            FUTURE: should play around with these values and see what impact they have. Need to check pathfinder going through dense and difficult areas, not just simple open and blocky areas.
            Xorimuth said: path_resolution_modifier determines the resolution of the path. When the number is lower (e.g. -3), it will finish quicker and the waypoints will be further apart. I use it for my spidertron pathfinder, where I start with -3, if it fails, I then try -1, 1, and 3, which are more likely to succeed (e.g. if the valid path is very intricate), but take progressively more time to complete.
            value of 10 crashes the game, bugged: https://forums.factorio.com/viewtopic.php?f=7&t=103056
        ]]
    })
    global.Tasks.GetWalkingPath.pathRequests[pathRequestId] = thisTask

    if global.Settings.showRobotState then
        ShowRobotState.UpdateStateText(thisTask.robot, "Looking for walking path", "normal")
    end

    return thisTask, 1
end

--- React to a path request being completed. Its up to the caller to handle the too busy response as it may want to try again or try some alternative task instead.
---@param event EventData.on_script_path_request_finished
GetWalkingPath._OnPathRequestFinished = function(event)
    local thisTask = global.Tasks.GetWalkingPath.pathRequests[event.id]
    if thisTask == nil then return end

    -- This task has completed in all situations, so record the result. The parent task can obtain it when it polls.
    thisTask.state = "completed"
    thisTask.taskData.pathFinderTimeout = event.try_again_later
    thisTask.taskData.pathFound = event.path
end

--- Called to continue progression on the task by on_tick.
---@param thisTask Task_GetWalkingPath_Data
---@return uint ticksToWait
GetWalkingPath.Progress = function(thisTask)
    if global.Settings.showRobotState then
        ShowRobotState.UpdateStateText(thisTask.robot, "Looking for walking path", "normal")
    end
    return 1
end

return GetWalkingPath
