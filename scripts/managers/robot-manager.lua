-- This manages the robot's entities, global objects and jobs.

local RobotManager = {} ---@class RobotManager

--- The global object for the robot.
---@class Robot
---@field id uint
---@field entity? LuaEntity
---@field force LuaForce

RobotManager.CreateGlobals = function()
    global.RobotManager = global.RobotManager or {} ---@class Global_RobotManager
    global.RobotManager.robots = global.RobotManager.robots or {} ---@type table<uint, Robot>
    global.RobotManager.nextRobotId = global.RobotManager.nextRobotId or 1 ---@type uint
end

RobotManager.OnLoad = function()
    MOD.Interfaces.RobotManager = MOD.Interfaces.RobotManager or {} ---@class MOD_InternalInterfaces_RobotManager
    MOD.Interfaces.RobotManager.CreateRobot = RobotManager.CreateRobot
end

--- Create a new robot with its entity starting at the given position.
---@param surface LuaSurface
---@param position MapPosition
RobotManager.CreateRobot = function(surface, position)
    ---@type Robot
    local robot = {
        id = global.RobotManager.nextRobotId
    }

    -- Create the robot's entity.
    local entity = surface.create_entity({ name = "character", position = position, force = "player" })
    if entity == nil then
        error("failed to create robot entity")
    end
    robot.entity = entity

    -- Temp hardcoded bits.
    robot.force = game.forces["player"]

    -- Record the robot tot he globals.
    global.RobotManager.robots[robot.id] = robot
    global.RobotManager.nextRobotId = global.RobotManager.nextRobotId + 1
end

return RobotManager
