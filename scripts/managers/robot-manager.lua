--[[
    This manages the robot's entities, global objects and jobs list.
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
---@field activeJobs Job_Data[] # Ordered by priority (top first).
---@field state "active"|"standby" # The standby feature is a future task, see readme.
---@field jobBusyUntilTick uint # The tick the robot is busy until on the current job. 0 is not busy. Effectively sleeping the robot from work until then.
---@field stateRenderedText? ShowRobotState_RobotStateRenderedText
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
    robot.activeJobs[#robot.activeJobs + 1] = job
end

--- Removes a job from a robot's list and tidies up any task state data related to it.
---@param jobIndex int # The order id of the job in the robots active tasks.
---@param robot Robot
---@param job Job_Data
RobotManager.RemoveJobFromRobot = function(jobIndex, robot, job)
    MOD.Interfaces.JobManager.RemoveRobotFromJob(robot, job)
    table.remove(robot.activeJobs, jobIndex)
end

--- Called every tick to manage the robots.
---@param event EventData.on_tick
RobotManager.ManageRobots = function(event)
    -- For each robot check if its not busy waiting check down its active job list for something to do.
    for _, robot in pairs(global.RobotManager.robots) do
        if robot.jobBusyUntilTick <= event.tick then
            ---@type ShowRobotState_NewRobotStateDetails|nil, uint
            local newRobotStateDetails, ticksToWait

            if #robot.activeJobs > 0 then
                -- Code Note: have to manually handle looping the active jobs as we remove entries from it while iterating. Its a priority list so the order matters and thus can't be a table key'd by Id.
                local jobIndex = 1
                while jobIndex <= #robot.activeJobs do
                    local job = robot.activeJobs[jobIndex]
                    if job ~= nil then
                        ticksToWait, newRobotStateDetails = MOD.Interfaces.JobManager.ProgressJobForRobot(job, robot)
                        if ticksToWait > 0 then
                            robot.jobBusyUntilTick = event.tick + ticksToWait
                        end

                        if MOD.Interfaces.JobManager.IsJobCompleteForRobot(job, robot) then
                            -- Job completed for this robot so remove the job from the robot and the robot from the job.
                            RobotManager.RemoveJobFromRobot(jobIndex, robot, job)
                            jobIndex = jobIndex - 1 -- As RobotManager.RemoveJobFromRobot() removed an entry from the list we are iterating.
                        else
                            -- Job isn't complete for robot so don't do any other jobs this tick for this robot.
                            break
                        end
                    end
                    jobIndex = jobIndex + 1
                end
            end

            -- If no jobs for this robot, do its idle activity.
            if global.Settings.showRobotState then
                if newRobotStateDetails == nil then
                    ---@type ShowRobotState_NewRobotStateDetails
                    newRobotStateDetails = { stateText = "Idle", level = ShowRobotState.StateLevel.normal }
                end
                ShowRobotState.UpdateStateText(robot, newRobotStateDetails)
            end
        end
    end
end

--- Removes a job from a robot's list as the job has been completed and the tasks removed.
---@param robot Robot
---@param jobCompleted Job_Data
RobotManager.NotifyRobotJobIsCompleted = function(robot, jobCompleted)
    for key, jobInList in pairs(robot.activeJobs) do
        if jobInList == jobCompleted then
            table.remove(robot.activeJobs, key)
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
