local Events = require("utility.manager-libraries.events")

local GetWalkingPath = {} ---@class GetWalkingPath : Task

---@class GetWalkingPath_PathRequester
---@field pathRequestId uint
---@field requestDetails GetWalkingPath_RequestDetails
---@field callbackTaskInterfaceName string
---@field callbackData table<any, any>

---@class GetWalkingPath_RequestDetails
---@field robot Robot
---@field surface LuaSurface
---@field startPosition MapPosition
---@field endPosition MapPosition
---@field endPositionEntity? LuaEntity

---@alias GetWalkingPath_FindPath_ResultInterface fun(event: EventData.on_script_path_request_finished, requestDetails: GetWalkingPath_RequestDetails, callbackData:table<any, any>) --- The function that's called back by GetWalkingPath.FindPath() must confirm to this interface.

GetWalkingPath.CreateGlobals = function()
    global.Tasks.GetWalkingPath = global.Tasks.GetWalkingPath or {} ---@class Global_Task_GetWalkingPath
    global.Tasks.GetWalkingPath.pathRequests = global.Tasks.GetWalkingPath.pathRequests or {} ---@type table<uint, GetWalkingPath_PathRequester> # Keyed by the path request id.
end

GetWalkingPath.OnLoad = function()
    MOD.Interfaces.Tasks.GetWalkingPath = GetWalkingPath._FindPath
    Events.RegisterHandlerEvent(defines.events.on_script_path_request_finished, "GetWalkingPath.OnPathRequestFinished", GetWalkingPath._OnPathRequestFinished)
end

--- Request to find a walking path between 2 points for the robot.
---
--- The function referenced by callbackTaskInterfaceName must conform to GetWalkingPath_FindPath_ResultInterface.
---@param robot Robot
---@param surface LuaSurface
---@param startPosition MapPosition
---@param endPosition MapPosition
---@param endPositionEntity? LuaEntity # An entity at the endPosition that the pathfinder should ignore when trying to get to the position.
---@param callbackTaskInterfaceName string # The task interface name to be called when the path request completes. Function must confirm to GetWalkingPath_FindPath_ResultInterface.
---@param callbackData table<any, any> # The data that should be passed back to the callback task when the path request completes.
GetWalkingPath._FindPath = function(robot, surface, startPosition, endPosition, endPositionEntity, callbackTaskInterfaceName, callbackData)
    local pathRequestId = surface.request_path({
        bounding_box = robot.entity.prototype.collision_box, -- Future: should be cached as there may be no entity if the robot is dead at request time and we don't want to error.
        collision_mask = robot.entity.prototype.collision_mask, -- Future: should be cached as there may be no entity if the robot is dead at request time and we don't want to error.
        start = startPosition,
        goal = endPosition,
        force = robot.force,
        radius = 1.0,
        can_open_gates = true,
        entity_to_ignore = endPositionEntity,
        pathfind_flags = { cache = false, prefer_straight_paths = true, no_break = true } -- Is done as a higher priority pathing request even over long distances with these settings. We don't cache as we want the best path for this robot and not just something in the vague vicinity.
    })
    global.Tasks.GetWalkingPath.pathRequests[pathRequestId] = {
        pathRequestId = pathRequestId,
        requestDetails = { robot = robot, surface = surface, startPosition = startPosition, endPosition = endPosition, endPositionEntity = endPositionEntity },
        callbackTaskInterfaceName = callbackTaskInterfaceName,
        callbackData = callbackData
    }
end

--- React to a path request being completed. Its up to the caller to handle the too busy response as it may want to try again or try some alternative task instead.
---@param event EventData.on_script_path_request_finished
GetWalkingPath._OnPathRequestFinished = function(event)
    local pathRequester = global.Tasks.GetWalkingPath.pathRequests[event.id]
    if pathRequester == nil then return end

    -- Call back to requesters task handler with the response and details.
    MOD.Interfaces.Tasks[pathRequester.callbackTaskInterfaceName](event, pathRequester.requestDetails, pathRequester.callbackData)
end

return GetWalkingPath
