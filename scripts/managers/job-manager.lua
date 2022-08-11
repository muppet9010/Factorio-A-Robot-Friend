--[[
    Jobs are the visual front end that the player interacts with. They link to a single primary task that the manages all the details.

    All Jobs are required to implement Job_Interface and Job_Details within their bespoke classes.

    All Jobs are required to have entries in the locale file for the below entries:
    TBC:
        - [gui-caption]    a_robot_friend-jobTitle-[JobName]   =   a_robot_friend-jobTitle-MoveToLocation
        - [gui-tooltip]    a_robot_friend-jobTitle-[JobName]   =   a_robot_friend-jobTitle-MoveToLocation
]]

local MoveToLocation = require("scripts.jobs.move-to-location")
local CompleteArea = require("scripts.jobs.complete-area")

--- The generic characteristics of a Job Interface that all specific Job types must implement. Stored in MOD.Interfaces.Jobs.
---@class Job_Interface
---@field jobName string # The internal name of the job. Recorded in here to avoid having to hard code it all over the code.
---@field Create fun(playerIndex:uint, ...): Job_Details # Called to create the job when it's initially added. Can take extra arguments after these default ones per specific Job type.
---@field ActivateJob fun(job:Job_Details): Task_Details # Called when the job is first started by a robot. This triggers the job to make the first task and returns this task. The activation will change the job's state to "active" from "pending".
---@field Remove fun(job:Job_Details) # Called to remove the job when it's no longer wanted.
---@field Pause fun(job:Job_Details) # Called to pause the job and all of its activity. This will mean all robots sit idle on this job as this is intended as a temporary player action. NOT IMPLEMENTED.
---@field Resume fun(job:Job_Details) # Called to resume a previously paused job. NOT IMPLEMENTED.

--- The generic characteristics of a Job Global that all specific Job types must implement. Stored in global jobs list by player.
---@class Job_Details
---@field playerIndex uint
---@field id uint
---@field jobName string  # The name registered under global.Jobs and MOD.Interfaces.Jobs.
---@field jobData? table # Any data that the job needs to store about itself goes in here. Each job will have its own BespokeData class for this.
---@field state "pending"|"active"|"completed"
---@field primaryTaskName string # The Interface name of the primary task.
---@field primaryTask? Task_Details # The primary task for this job.
---@field description? string # A text description for the Job.
---@field robotsOnJob table<uint, Robot> @ Keyed by robot Id.

local JobManager = {} ---@class JobManager

JobManager._CreateGlobals = function()
    global.JobManager = global.JobManager or {} ---@class Global_JobManager # Used by the JobManager for its own global data.
    global.JobManager.playersJobs = global.JobManager.playersJobs or {} ---@type table<uint, table<uint, Job_Details>> # Keyed by player_index to a Jobs table.Jobs table is keyed to the Job Id to the Job_Details object.
    global.JobManager.nextJobId = global.JobManager.nextJobId or 1 ---@type uint # Global job id across all players.

    global.Jobs = global.Jobs or {} ---@class Global_Jobs # All Jobs can put their own global tables under this keyed by their Job Name.
    -- Call any job types that need globals making.
end

JobManager._OnLoad = function()
    MOD.Interfaces.JobManager = JobManager

    MOD.Interfaces.Jobs = MOD.Interfaces.Jobs or {} ---@class MOD_InternalInterfaces_Jobs # Used by all Jobs to register their public functions on by name (save/load safe).
    -- Call all jobs types.
    MoveToLocation._OnLoad()
    CompleteArea._OnLoad()
end

--- Called by the specific Job to make a generic Job object and register it in global for persistence. It's then returned to the specific Job to add it's bespoke elements. The return should be casted to the bespoke Job specific class.
---@param jobName string # The name registered under global.Jobs and MOD.Interfaces.Jobs.
---@param playerIndex uint # The player whom the job will be created under.
---@param primaryTaskName string # The Interface name of the primary Task.
---@return Job_Details
JobManager.CreateGenericJob = function(jobName, playerIndex, primaryTaskName)
    global.JobManager.playersJobs[playerIndex] = global.JobManager.playersJobs[playerIndex] or {}
    ---@type Job_Details
    local job = { playerIndex = playerIndex, id = global.JobManager.nextJobId, jobName = jobName, jobData = {}, state = "pending", primaryTaskName = primaryTaskName, robotsOnJob = {} }
    global.JobManager.playersJobs[playerIndex][job.id] = job
    global.JobManager.nextJobId = global.JobManager.nextJobId + 1
    return job
end

--- Called by the specific Job when it is first activated to handle generic state and GUI updates.
---@param job Job_Details
---@param primaryTask Task_Details
JobManager.ActivateGenericJob = function(job, primaryTask)
    if job.state == "pending" then
        job.state = "active"
    end
    job.primaryTask = primaryTask
end

--- Progress the robot for the job. This may include the jobs initial activation or another cycle in progressing the job's tasks.
---@param job Job_Details
---@param robot Robot
---@return uint ticksToWait
---@return ShowRobotState_NewRobotStateDetails|nil robotStateDetails # nil if there is no state being set by this Task
JobManager.ProgressJobForRobot = function(job, robot)
    -- Record that the robot is working on the job.
    if job.robotsOnJob[robot.id] == nil then
        job.robotsOnJob[robot.id] = robot
    end

    local primaryTask = job.primaryTask
    if primaryTask == nil then
        -- As first running of the Job, Activate the job to generate the primary task for the job.
        primaryTask = MOD.Interfaces.Jobs[job.jobName]--[[@as Job_Interface]] .ActivateJob(job)
    end

    local waitTime, robotStateDetails = MOD.Interfaces.TaskManager.ProgressPrimaryTask(primaryTask, robot)

    -- Check if the primaryTask has just been completed for all.
    if job.state ~= "completed" and primaryTask.state == "completed" then
        JobManager.JobCompleted(job)
    end

    return waitTime, robotStateDetails
end

--- Called by the progression of a Job when it finds its primary task is completed. So the Task data can be dropped and any publication of the job status is performed.
---@param job Job_Details
JobManager.JobCompleted = function(job)
    job.state = "completed"

    -- Clean out the primary task from the job and clean any persistent or global data.
    MOD.Interfaces.TaskManager.RemovingPrimaryTaskFromJob(job.primaryTask)
    job.primaryTask = nil

    -- Clear all of the robots from being active on this job.
    for _, robot in pairs(job.robotsOnJob) do
        MOD.Interfaces.RobotManager.NotifyRobotJobIsCompleted(robot, job)
    end
    job.robotsOnJob = {}
end

--- Checks if the job is completed for this specific robot.
---@param job Job_Details
---@param robot Robot
---@return boolean jobCompletedForRobot
JobManager.IsJobCompleteForRobot = function(job, robot)
    if job.state == "completed" then return true end
    if MOD.Interfaces.TaskManager.IsPrimaryTaskCompleteForRobot(job.primaryTask, robot) == true then return true end
    return false
end

--- Remove the robot from the job.
---@param robot Robot
---@param job Job_Details
JobManager.RemoveRobotFromJob = function(robot, job)
    MOD.Interfaces.TaskManager.RemovingRobotFromPrimaryTask(job.primaryTask, robot)
    job.robotsOnJob[robot.id] = nil
end

--- The robot has been paused so pause all activities in this job.
---@param robot Robot
---@param job Job_Details
JobManager.PausingRobotForJob = function(robot, job)
    MOD.Interfaces.TaskManager.PausingRobotForPrimaryTask(job.primaryTask, robot)
end

return JobManager
