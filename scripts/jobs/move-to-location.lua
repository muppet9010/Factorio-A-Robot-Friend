---@class Job_MoveToLocation_Details : Job_Details
---@field jobData Job_MoveToLocation_JobData

---@class Job_MoveToLocation_JobData
---@field targetLocation MapPosition
---@field surface LuaSurface

local MoveToLocation = {} ---@class Job_MoveToLocation_Interface : Job_Interface
MoveToLocation.jobName = "MoveToLocation"

MoveToLocation._OnLoad = function()
    MOD.Interfaces.Jobs.MoveToLocation = MoveToLocation
end

--- Called to create the job when it's initially added.
---@param playerIndex uint
---@param targetLocation MapPosition
---@param surface LuaSurface
---@return Job_MoveToLocation_Details
MoveToLocation.Create = function(playerIndex, targetLocation, surface)
    local job = MOD.Interfaces.JobManager.CreateGenericJob(MoveToLocation.jobName, playerIndex, "MoveToLocation") ---@cast job Job_MoveToLocation_Details

    -- Store the target data.
    job.jobData = {
        targetLocation = targetLocation,
        surface = surface
    }

    return job
end

--- Called when the job is actively started by a robot.
---@param job Job_MoveToLocation_Details
---@return Task_WalkToLocation_Details
MoveToLocation.ActivateJob = function(job)
    local primaryTask = MOD.Interfaces.Tasks.WalkToLocation.ActivateTask(job, nil, job.jobData.targetLocation, job.jobData.surface, 1) -- This will be a MoveToLocation task in future, but for now just hard code it to WalkToLocation to avoid a pointless task level, as robots can only walk at present.

    MOD.Interfaces.JobManager.ActivateGenericJob(job, primaryTask)

    return primaryTask
end

--- Called to remove the job when it's no longer wanted.
---@param job Job_MoveToLocation_Details
MoveToLocation.Remove = function(job)
    error("Not implemented")
    -- Not done anything for this jobs specific global or its own data. Should a deleted job not keep some of its details and be moved to a deleted list in case of mistake?

    -- Clean out the primary task from the job and cleans any persistent or global data in the Task hierarchy.
    MOD.Interfaces.TaskManager.RemovingPrimaryTaskFromJob(job.primaryTask)
end

--- Called to pause the job and all of its activity.
---@param job Job_MoveToLocation_Details
MoveToLocation.Pause = function(job)
    error("Not implemented")
end

--- Called to resume a previously paused job.
---@param job Job_MoveToLocation_Details
MoveToLocation.Resume = function(job)
    error("Not implemented")
end

return MoveToLocation
