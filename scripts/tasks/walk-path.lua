local WalkPath = {} ---@class WalkPath : Task

WalkPath.OnLoad = function()
    MOD.Interfaces.Tasks.WalkPath = WalkPath._RequestWalk
end

--- Request a robot to walk the given path.
---@param robot Robot
---@param path PathfinderWaypoint[]
WalkPath._RequestWalk = function(robot, path)
    -- TODO: start the cycle of walking the path... Need to get the timing infrastructure setup for this.

    --robotEntity.walking_state = { walking = (direction ~= nil), direction = direction }
end

return WalkPath
