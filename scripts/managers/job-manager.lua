--[[
    Jobs are the visual front end that the player interacts with. They link to a single primary task that the manages all the details.

    All Jobs are required to register themselves in the dictionary MOD.Interfaces.Jobs. With a key of their Task.jobName and a value of a dictionary of interface values/functions. At a minimum this must include:
        - jobName   =   The internal name of the job.
        - Create()   =   Called to create the job when it's initially added.
        - Remove()   =   Called to remove the job when it's no longer wanted.
        - Pause()   =   Called to pause the job and all of its activity. This will mean all robots move on to their next active job permanently. Also no new robot will be assignable to the job.
        - Resume()   =   Called to resume a previously paused job. Just means robots can be assigned back to the job.

    All Jobs are required to have entries in the locale file for the below entries:
    TBC:
        - [gui-caption]    a_robot_friend-jobTitle-[JobName]   =   a_robot_friend-jobTitle-MoveToLocation
        - [gui-tooltip]    a_robot_friend-jobTitle-[JobName]   =   a_robot_friend-jobTitle-MoveToLocation
]]

local MoveToLocation = require("scripts.jobs.move-to-location")

local JobManager = {} ---@class JobManager

--- The generic characteristics of a Job that all instances must implement. Stored in global jobs list by player.
---@class Job
---@field playerIndex uint
---@field id uint
---@field jobName string  # The name registered under global.Jobs and MOD.Interfaces.Jobs.
---@field jobData? table # Any data that the job needs to store about itself goes in here.
---@field state "pending"|"active"|"completed"
---@field primaryTask Task
---@field description? string # A text description for the Job.
---@field publiclyVisible boolean # If the job is public to other players on the same force or not.

JobManager.CreateGlobals = function()
    global.JobManager = global.JobManager or {} ---@class Global_JobManager # Used by the JobManager for its own global data.
    global.JobManager.playersJobs = global.JobManager.playersJobs or {} ---@type table<uint, table<uint, Job>> # Keyed by player_index to Jobs by their id.
    global.JobManager.nextJobId = global.JobManager.nextJobId or 1 ---@type uint # Global id across all players.

    global.Jobs = global.Jobs or {} ---@class Global_Jobs # All Jobs can put their own global table under this.
    -- Call any job types that need globals making.
end

JobManager.OnLoad = function()
    MOD.Interfaces.JobManager = MOD.Interfaces.JobManager or {} ---@class MOD_InternalInterfaces_JobManager # Used by the JobManager for its own public function registrations (save/load safe).
    MOD.Interfaces.JobManager.CreateGenericJob = JobManager.CreateGenericJob
    MOD.Interfaces.JobManager.JobCompleted = JobManager.JobCompleted

    MOD.Interfaces.Jobs = MOD.Interfaces.Jobs or {} ---@class MOD_InternalInterfaces_Jobs # Used by all Jobs to register their public functions on by name (save/load safe).
    -- Call all jobs types.
    MoveToLocation.OnLoad()
end

--- Called by the specific Job to make a generic Job object and register it. It's then returned to the specific Job to add it's bespoke elements.
---@param jobName string # The name registered under global.Jobs and MOD.Interfaces.Jobs.
---@param playerIndex uint # The player whom the job will be created under.
---@return Job
JobManager.CreateGenericJob = function(jobName, playerIndex)
    global.JobManager.playersJobs[playerIndex] = global.JobManager.playersJobs[playerIndex] or {}
    ---@type Job
    local job = { playerIndex = playerIndex, id = global.JobManager.nextJobId, jobName = jobName, jobData = {}, state = "pending", publiclyVisible = false }
    global.JobManager.playersJobs[playerIndex][job.id] = job
    global.JobManager.nextJobId = global.JobManager.nextJobId + 1
    return job
end

--- Called by the primaryTask when the the task (and thus job) is completed, so it can update it's status and do any configured alerts, etc.
---@param job Job
JobManager.JobCompleted = function(job)
    job.state = "completed"
end

return JobManager
