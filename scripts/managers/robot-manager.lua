--[[
    This manages the robot's entities, global objects and jobs.
]]

local Events = require("utility.manager-libraries.events")
local ShowRobotState = require("scripts.show-robot-state")
local Colors = require("utility.lists.colors")

--- The global object for the robot.
---@class Robot
---@field id uint
---@field entity? LuaEntity
---@field surface LuaSurface
---@field force LuaForce
---@field master LuaPlayer
---@field activeJobs Job_Data[]
---@field state "active"|"standby" # FUTURE: standby is what players can do to their own or other players robots. They can't change their orders, but they can order the robot to stop and it goes in to standby until re-activated by its master or the order issuer.
---@field jobBusyUntilTick uint # The tick the robot is busy until on the current job. 0 is not busy.
---@field currentStateRenderingId uint64

local RobotManager = {} ---@class RobotManager

RobotManager._CreateGlobals = function()
    global.RobotManager = global.RobotManager or {} ---@class Global_RobotManager
    global.RobotManager.robots = global.RobotManager.robots or {} ---@type table<uint, Robot> # Keyed by Robot.id
    global.RobotManager.nextRobotId = global.RobotManager.nextRobotId or 1 ---@type uint
end

RobotManager._OnLoad = function()
    MOD.Interfaces.RobotManager = RobotManager

    Events.RegisterHandlerEvent(defines.events.on_tick, "RobotManager.ManageRobots", RobotManager.ManageRobots)
end

--- Create a new robot with its entity starting at the given position.
---@param surface LuaSurface
---@param position MapPosition
---@param master LuaPlayer
---@return Robot
RobotManager.CreateRobot = function(surface, position, master)
    ---@type Robot
    local robot = {
        id = global.RobotManager.nextRobotId,
        surface = surface,
        force = master.force --[[@as LuaForce]] ,
        master = master,
        activeJobs = {},
        state = "active",
        jobBusyUntilTick = 0
    }

    -- Create the robot's entity.
    local entity = surface.create_entity({ name = "character", position = position, force = "player" })
    if entity == nil then
        error("failed to create robot entity")
    end
    robot.entity = entity
    robot.entity.color = Colors.PrimaryLocomotiveColors[math.random(1, #Colors.PrimaryLocomotiveColors)]

    -- Record the robot to the globals.
    global.RobotManager.robots[robot.id] = robot
    global.RobotManager.nextRobotId = global.RobotManager.nextRobotId + 1

    return robot
end

--- Assigns a job to a robot at the end of its active job list. Doesn't activate any tasks until the robot starts wanting to do the job.
---@param robot Robot
---@param job Job_Data
RobotManager.AssignRobotToJob = function(robot, job)
    robot.activeJobs[#robot.activeJobs + 1] = job
end

--- Removes a job from a robot's list and tidies up any task state data related to it.
---@param robot Robot
---@param robotsJobIndex int
RobotManager.RemoveRobotFromJob = function(robot, robotsJobIndex)
    local job = robot.activeJobs[robotsJobIndex]
    MOD.Interfaces.JobManager.RemoveRobotFromJob(robot, job)
    table.remove(robot.activeJobs, robotsJobIndex)
end

--- Called every tick to manage the robots.
---@param event EventData.on_tick
RobotManager.ManageRobots = function(event)
    -- For each robot check if its not busy waiting check down its active job list for something to do.
    for _, robot in pairs(global.RobotManager.robots) do
        if robot.jobBusyUntilTick <= event.tick then
            if #robot.activeJobs > 0 then
                -- There are jobs for this robot to try and do.
                for robotsJobIndex, job in pairs(robot.activeJobs) do
                    local ticksToWait = MOD.Interfaces.JobManager.ProgressRobotForJob(robot, job)
                    if ticksToWait > 0 then
                        robot.jobBusyUntilTick = event.tick + ticksToWait
                    else
                        -- 0 ticksToWait means job completed.
                        RobotManager.RemoveRobotFromJob(robot, robotsJobIndex)
                        robot.jobBusyUntilTick = 0
                    end
                end
            else
                -- No jobs for this robot.
                if global.Settings.showRobotState then
                    ShowRobotState.ShowNormalState(robot, "Idle", 1)
                end
            end
        end
    end
end

return RobotManager
