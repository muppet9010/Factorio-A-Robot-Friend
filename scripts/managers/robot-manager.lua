--[[
    This manages the robot's entities, global objects and jobs.
]]

local Events = require("utility.manager-libraries.events")
local ShowRobotState = require("scripts.common.show-robot-state")

--- The global object for the robot.
---@class Robot
---@field id uint
---@field entity? LuaEntity
---@field surface LuaSurface
---@field force LuaForce
---@field master LuaPlayer
---@field activeJobs table<uint, Job_Data> # Key'd by the job's id.
---@field state "active"|"standby" # The standby feature is a future task, see readme.
---@field jobBusyUntilTick uint # The tick the robot is busy until on the current job. 0 is not busy.
---@field stateRenderedText? RobotStateRenderedText
---@field name string # The robots' actual name, like Bob or Robot 13
---@field nameRenderId uint64 # The render Id of the robots name tag.
---@field color Color # The color of the robot, affects its entity and things that expect opacity.
---@field fontColor Color # The color of the robot with no opacity, used for fonts.

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
    local entity = robot.surface.create_entity({ name = "character", position = position, force = "player" })
    if entity == nil then
        error("failed to create robot entity")
    end
    robot.entity = entity

    -- Robot personalisation.
    RobotManager.UpdateColor(robot, master.color)
    RobotManager.UpdateName(robot, "Robot " .. robot.id)

    -- Record the robot to the globals.
    global.RobotManager.robots[robot.id] = robot
    global.RobotManager.nextRobotId = global.RobotManager.nextRobotId + 1

    return robot
end

--- Assigns a job to a robot at the end of its active job list. Doesn't activate any tasks until the robot starts wanting to do the job.
---@param robot Robot
---@param job Job_Data
RobotManager.AssignRobotToJob = function(robot, job)
    robot.activeJobs[job.id] = job
end

--- Removes a job from a robot's list and tidies up any task state data related to it.
---@param robot Robot
---@param job Job_Data
RobotManager.RemoveRobotFromJob = function(robot, job)
    MOD.Interfaces.JobManager.RemoveRobotFromJob(robot, job)
    robot.activeJobs[job.id] = nil
end

--- Called every tick to manage the robots.
---@param event EventData.on_tick
RobotManager.ManageRobots = function(event)
    -- For each robot check if its not busy waiting check down its active job list for something to do.
    for _, robot in pairs(global.RobotManager.robots) do
        if robot.jobBusyUntilTick <= event.tick then
            for _, job in pairs(robot.activeJobs) do
                local ticksToWait = MOD.Interfaces.JobManager.ProgressRobotForJob(robot, job)
                if ticksToWait > 0 then
                    robot.jobBusyUntilTick = event.tick + ticksToWait
                end

                if job.state == "completed" then
                    -- Job completed so remove it from the list.
                    RobotManager.RemoveRobotFromJob(robot, job)
                end
                if ticksToWait > 0 then
                    -- Job is waiting to do something so don't do any other jobs this tick for this robot.
                    break
                end
            end

            -- If no jobs for this robot, do its idle activity.
            if next(robot.activeJobs) == nil then
                if global.Settings.showRobotState then
                    ShowRobotState.UpdateStateText(robot, "Idle", "normal")
                end
            end
        end
    end
end

--- Sets a robots color and updates visual elements related to it.
---@param robot Robot
---@param color Color
RobotManager.UpdateColor = function(robot, color)
    robot.color = color
    if robot.entity ~= nil then
        robot.entity.color = color
    end
    robot.fontColor = { r = color.r, g = color.g, b = color.b, 255 }
end

--- Sets a robots name and updates visual elements related to it.
---@param robot Robot
---@param name string
RobotManager.UpdateName = function(robot, name)
    robot.name = name
    if robot.nameRenderId ~= nil then
        rendering.destroy(robot.nameRenderId)
    end
    robot.nameRenderId = rendering.draw_text {
        text = robot.name,
        surface = robot.surface,
        target = robot.entity,
        target_offset = { 0, -2 },
        color = robot.fontColor,
        scale_with_zoom = true,
        alignment = "center",
        vertical_alignment = "middle",
        forces = { robot.force }
    }
end

return RobotManager
