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
---@field jobName string # The internal name of the job.
---@field Create fun(playerIndex:uint): Job_Data # Called to create the job when it's initially added. Can take extra arguments after these default ones. FUTURE: these extra parameters will need to be defined in a searchable way for the GUI to find them, so part of the Job Interface.
---@field Activate fun(robot:Robot, job:Job_Data) # Called by a robot when it actively starts the job. This triggers the job to make the first task and start the process for actual work to be done. Changes state to "active" from "pending".
---@field Remove fun(job:Job_Data) # Called to remove the job when it's no longer wanted.
---@field Pause fun(job:Job_Data) # Called to pause the job and all of its activity. This will mean all robots move on to their next active job permanently. Also no new robot will be assignable to the job.
---@field Resume fun(job:Job_Data) # Called to resume a previously paused job. Just means robots can be assigned back to the job.

--- The generic characteristics of a Job Global that all instances must implement. Stored in global jobs list by player.
---@class Job_Data
---@field playerIndex uint
---@field id uint
---@field jobName string  # The name registered under global.Jobs and MOD.Interfaces.Jobs.
---@field jobData? table # Any data that the job needs to store about itself goes in here. Each job will have its own BespokeData class for this.
---@field state "pending"|"active"|"completed"
---@field primaryTask Task_Data
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
    MOD.Interfaces.JobManager = MOD.Interfaces.JobManager or {} ---@class MOD_InternalInterfaces_JobManager # Used by the JobManager for its own public function registrations (save/load safe).
    MOD.Interfaces.JobManager.CreateGenericJob = JobManager.CreateGenericJob
    MOD.Interfaces.JobManager.JobCompleted = JobManager.JobCompleted
    MOD.Interfaces.JobManager.ActivateGenericJob = JobManager.ActivateGenericJob

    MOD.Interfaces.Jobs = MOD.Interfaces.Jobs or {} ---@class MOD_InternalInterfaces_Jobs # Used by all Jobs to register their public functions on by name (save/load safe).
    -- Call all jobs types.
    MoveToLocation._OnLoad()
end

--- Called by the specific Job to make a generic Job object and register it in global for persistence. It's then returned to the specific Job to add it's bespoke elements. The return should be casted to the bespoke Job specific class.
---@param jobName string # The name registered under global.Jobs and MOD.Interfaces.Jobs.
---@param playerIndex uint # The player whom the job will be created under.
---@return Job_Data
JobManager.CreateGenericJob = function(jobName, playerIndex)
    global.JobManager.playersJobs[playerIndex] = global.JobManager.playersJobs[playerIndex] or {}
    ---@type Job_Data
    local job = { playerIndex = playerIndex, id = global.JobManager.nextJobId, jobName = jobName, jobData = {}, state = "pending" }
    global.JobManager.playersJobs[playerIndex][job.id] = job
    global.JobManager.nextJobId = global.JobManager.nextJobId + 1
    return job
end

--- Called by the specific Job when it is first activated to handle generic state and GUI updates.
---@param job Job_Data
JobManager.ActivateGenericJob = function(job)
    job.state = "active"
end

--- Called by the primaryTask when the the task (and thus job) is completed, so it can update it's status and do any configured alerts, etc.
---@param job Job_Data
JobManager.JobCompleted = function(job)
    job.state = "completed"
end

return JobManager
