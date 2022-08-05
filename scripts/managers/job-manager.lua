--[[
    Jobs are the visual front end that the player interacts with. They link to a single primary task that the manages all the details.

    All Jobs are required to have entries in the locale file for the below entries:
    TBC:
        - [gui-caption]    a_robot_friend-jobTitle-[JobName]   =   a_robot_friend-jobTitle-MoveToLocation
        - [gui-tooltip]    a_robot_friend-jobTitle-[JobName]   =   a_robot_friend-jobTitle-MoveToLocation
]]

local MoveToLocation = require("scripts.jobs.move-to-location")

--- The generic characteristics of a Job Interface that all instances must implement. Stored in MOD.Interfaces.Jobs.
---@class Job_Interface
---@field jobName string # The internal name of the job. Recorded in here to avoid having to hard code it all over the code.
---@field Create fun(playerIndex:uint): Job_Data # Called to create the job when it's initially added. Can take extra arguments after these default ones. FUTURE: these extra parameters will need to be defined in a searchable way for the GUI to find them, so part of the Job Interface.
---@field ActivateJob fun(job:Job_Data) # Called when the job is actively started by a robot. This triggers the job to make the first task. The activation will change the job's state to "active" from "pending".
---@field Remove fun(job:Job_Data) # Called to remove the job when it's no longer wanted.
---@field Pause fun(job:Job_Data) # Called to pause the job and all of its activity. This will mean all robots sit idle on this job as this is intended as a temporary player action. NOT IMPLEMENTED.
---@field Resume fun(job:Job_Data) # Called to resume a previously paused job. NOT IMPLEMENTED.

--- The generic characteristics of a Job Global that all instances must implement. Stored in global jobs list by player.
---@class Job_Data
---@field playerIndex uint
---@field id uint
---@field jobName string  # The name registered under global.Jobs and MOD.Interfaces.Jobs.
---@field jobData? table # Any data that the job needs to store about itself goes in here. Each job will have its own BespokeData class for this.
---@field state "pending"|"active"|"completed"
---@field primaryTaskName string # The Interface name of the primary task.
---@field primaryTask? Task_Data # The primary task for this job.
---@field description? string # A text description for the Job.

local JobManager = {} ---@class JobManager

JobManager._CreateGlobals = function()
    global.JobManager = global.JobManager or {} ---@class Global_JobManager # Used by the JobManager for its own global data.
    global.JobManager.playersJobs = global.JobManager.playersJobs or {} ---@type table<uint, table<uint, Job_Data>> # Keyed by player_index to Jobs by their id.
    global.JobManager.nextJobId = global.JobManager.nextJobId or 1 ---@type uint # Global id across all players.

    global.Jobs = global.Jobs or {} ---@class Global_Jobs # All Jobs can put their own global table under this.
    -- Call any job types that need globals making.
end

JobManager._OnLoad = function()
    MOD.Interfaces.JobManager = JobManager

    MOD.Interfaces.Jobs = MOD.Interfaces.Jobs or {} ---@class MOD_InternalInterfaces_Jobs # Used by all Jobs to register their public functions on by name (save/load safe).
    -- Call all jobs types.
    MoveToLocation._OnLoad()
end

--- Called by the specific Job to make a generic Job object and register it in global for persistence. It's then returned to the specific Job to add it's bespoke elements. The return should be casted to the bespoke Job specific class.
---@param jobName string # The name registered under global.Jobs and MOD.Interfaces.Jobs.
---@param playerIndex uint # The player whom the job will be created under.
---@param primaryTaskName string # The Interface name of the primary Task.
---@return Job_Data
JobManager.CreateGenericJob = function(jobName, playerIndex, primaryTaskName)
    global.JobManager.playersJobs[playerIndex] = global.JobManager.playersJobs[playerIndex] or {}
    ---@type Job_Data
    local job = { playerIndex = playerIndex, id = global.JobManager.nextJobId, jobName = jobName, jobData = {}, state = "pending", primaryTaskName = primaryTaskName }
    global.JobManager.playersJobs[playerIndex][job.id] = job
    global.JobManager.nextJobId = global.JobManager.nextJobId + 1
    return job
end

--- Called by the specific Job when it is first activated to handle generic state and GUI updates.
---@param job Job_Data
---@param primaryTask Task_Data
JobManager.ActivateGenericJob = function(job, primaryTask)
    if job.state == "pending" then
        job.state = "active"
    end
    job.primaryTask = primaryTask
end

--- Called by the primaryTask when it (and thus job) is completed, so it can update it's status and do any configured alerts, etc.
---@param job Job_Data
JobManager.JobCompleted = function(job)
    job.state = "completed"
end

--- Progress the robot for the job. This may include the jobs initial activation or another cycle in progressing the job's tasks.
---@param robot Robot
---@param job Job_Data
---@return uint ticksToWait
JobManager.ProgressRobotForJob = function(robot, job)
    local primaryTask = job.primaryTask
    if primaryTask == nil then
        -- As first running of the Job, Activate the job to generate the primary task for the job.
        MOD.Interfaces.Jobs[job.jobName]--[[@as Job_Interface]] .ActivateJob(job)
        primaryTask = job.primaryTask ---@cast primaryTask Task_Data # We always populate it as part of Job.ActivateJob().
    end

    local waitTime = MOD.Interfaces.TaskManager.ProgressPrimaryTask(primaryTask, robot)

    -- Check if the primaryTask completed.
    -- FUTURE: in jobs with multiple robots the job will never be completed when only robot completes its. As the robots could be acting independently (move to location) or the other robots may be finishing up other parts of the shared work (completing a ghost). Will need a task specific function to decide what to do with the robots. Do we send them on to the next job or have them hang around until the job is finished. Maybe helping speed it up if they can.
    if primaryTask.state == "completed" then
        JobManager.JobCompleted(job)
    end

    return waitTime
end

--- Remove the robot from the job.
---@param robot Robot
---@param job Job_Data
JobManager.RemoveRobotFromJob = function(robot, job)
    --TODO: all needs re-doing.
    local primaryTask = job.robotsPrimaryTask[robot]
    MOD.Interfaces.TaskManager.RemovePrimaryTask(primaryTask)
    job.robotsPrimaryTask[robot] = nil
end

return JobManager
