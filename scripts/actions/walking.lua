--- The action to have the robot walk its character in a direction until told to stop.

local Walking = {} ---@class Action_Walking : Action

Walking.OnLoad = function()
    MOD.Interfaces.Actions.walking = Walking.Walk
end

--- A robot's entity will start walking in a given direction.
---@param robotEntity LuaEntity
---@param direction defines.direction|nil # NNil for not walking
Walking.Walk = function(robotEntity, direction)
    robotEntity.walking_state = { walking = (direction ~= nil), direction = direction }
end

return Walking
