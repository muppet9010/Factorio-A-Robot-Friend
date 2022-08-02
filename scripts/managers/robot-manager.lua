--[[
    This manages the robot's entities, global objects and jobs.
]]

local Events = require("utility.manager-libraries.events")

local RobotManager = {} ---@class RobotManager

--- The global object for the robot.
---@class Robot
---@field id uint
---@field entity? LuaEntity
---@field force LuaForce
---@field master LuaPlayer
---@field activeJobs Job[]
---@field state "active"|"standby"

RobotManager.CreateGlobals = function()
    global.RobotManager = global.RobotManager or {} ---@class Global_RobotManager
    global.RobotManager.robots = global.RobotManager.robots or {} ---@type table<uint, Robot> # Keyed by Robot.id
    global.RobotManager.nextRobotId = global.RobotManager.nextRobotId or 1 ---@type uint
end

RobotManager.OnLoad = function()
    MOD.Interfaces.RobotManager = MOD.Interfaces.RobotManager or {} ---@class MOD_InternalInterfaces_RobotManager
    MOD.Interfaces.RobotManager.CreateRobot = RobotManager.CreateRobot

    Events.RegisterHandlerEvent(defines.events.on_tick, "RobotManager.ManageRobots", RobotManager.ManageRobots)
end

--- Create a new robot with its entity starting at the given position.
---@param surface LuaSurface
---@param position MapPosition
RobotManager.CreateRobot = function(surface, position, master)
    ---@type Robot
    local robot = {
        id = global.RobotManager.nextRobotId,
        force = master.force,
        master = master,
        activeJobs = {},
        state = "active"
    }

    -- Create the robot's entity.
    local entity = surface.create_entity({ name = "character", position = position, force = "player" })
    if entity == nil then
        error("failed to create robot entity")
    end
    robot.entity = entity

    -- Record the robot to the globals.
    global.RobotManager.robots[robot.id] = robot
    global.RobotManager.nextRobotId = global.RobotManager.nextRobotId + 1
end

--- Assigns a job to a robot at the end of its list.
---@param robot Robot
---@param job Job
RobotManager.AssignRobotToJob = function(robot, job)
    robot.activeJobs[robot.activeJobs + 1] = job
end

--- Called every tick to manage the robots.
---@param event EventData.on_tick
RobotManager.ManageRobots = function(event)
    --TODO: check each robot and if past the robots "busyUntil" tick call back to the jobs current task to "Progress()".
end

return RobotManager
