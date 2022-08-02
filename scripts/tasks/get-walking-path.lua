local Events = require("utility.manager-libraries.events")

---@class Task_GetWalkingPath_Data : Task_Data
---@field taskData Task_GetWalkingPath_BespokeData

---@class Task_GetWalkingPath_BespokeData
---@field startPosition MapPosition
---@field endPosition MapPosition
---@field surface LuaSurface
---@field robot Robot

---@alias GetWalkingPath_Begin_ResponseInterface fun(getWalkingPathTask: Task_GetWalkingPath_Data, event: EventData.on_script_path_request_finished, requestData: Task_GetWalkingPath_BespokeData) --- The function that's called back by GetWalkingPath.Begin() must confirm to this interface.

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
---@param job Job_Data # The job related to the lead task in this hierarchy.
---@param parentTask? Task_Data # The parent Task or nil if this is a primary Task of a Job.
---@param parentCallbackFunctionName? string # The name this task calls when it wants to give its parent a status update of some sort. This named function must conform to GetWalkingPath_Begin_ResponseInterface.
---@param robot Robot
---@param startPosition MapPosition
---@param endPosition MapPosition
---@param surface LuaSurface
---@return Task_GetWalkingPath_Data
GetWalkingPath.Begin = function(job, parentTask, parentCallbackFunctionName, robot, startPosition, endPosition, surface)
    local thisTask = MOD.Interfaces.TaskManager.CreateGenericTask(GetWalkingPath.taskName, job, parentTask, parentCallbackFunctionName) ---@cast thisTask Task_GetWalkingPath_Data

    -- Store the request data.
    thisTask.taskData = {
        startPosition = startPosition,
        endPosition = endPosition,
        surface = surface,
        robot = robot
    }

    local pathRequestId = surface.request_path({
        bounding_box = robot.entity.prototype.collision_box, -- Future: should be cached as there may be no entity if the robot is dead at request time and we don't want to error.
        collision_mask = robot.entity.prototype.collision_mask, -- Future: should be cached as there may be no entity if the robot is dead at request time and we don't want to error.
        start = startPosition,
        goal = endPosition,
        force = robot.force,
        radius = 1.0,
        can_open_gates = true,
        entity_to_ignore = nil, -- FUTURE: get whatever is at the position right now, but may be multiple entities and so we need to select the correct one to ignore (one with a collision box that affects our robot?)
        pathfind_flags = { cache = false, prefer_straight_paths = true, no_break = true }, -- Is done as a higher priority pathing request even over long distances with these settings. We don't cache as we want the best path for this robot and not just something in the vague vicinity.
        path_resolution_modifier = 0 -- FUTURE: should play around with these values and see what impact they have. Need to check pathfinder going through dense and difficult areas, not just simple open and blocky areas.
    })
    global.Tasks.GetWalkingPath.pathRequests[pathRequestId] = thisTask

    return thisTask
end

--- React to a path request being completed. Its up to the caller to handle the too busy response as it may want to try again or try some alternative task instead.
---@param event EventData.on_script_path_request_finished
GetWalkingPath._OnPathRequestFinished = function(event)
    local thisTask = global.Tasks.GetWalkingPath.pathRequests[event.id]
    if thisTask == nil then return end

    -- This task has completed in all situations.
    thisTask.state = "completed"

    -- Call back to requesters task handler with the response and details.
    MOD.Interfaces.Tasks[thisTask.parentTask.taskName][thisTask.parentCallbackFunctionName](thisTask, event, thisTask.taskData)
end

return GetWalkingPath
