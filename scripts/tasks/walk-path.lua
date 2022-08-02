local WalkPath = {} ---@class Task_WalkPath_Interface : Task_Interface

WalkPath._OnLoad = function()
    MOD.Interfaces.Tasks.WalkPath = WalkPath
end

-- TODO ?????
--- Request a robot to walk the given path.
---@param robot Robot
---@param path PathfinderWaypoint[]
WalkPath.Begin = function(robot, path)
    -- TODO: start the cycle of walking the path... Need to get the timing infrastructure setup for this.

    --robotEntity.walking_state = { walking = (direction ~= nil), direction = direction }
end

return WalkPath
