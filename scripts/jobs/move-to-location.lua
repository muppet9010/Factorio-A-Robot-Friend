---@class Job_WalkToLocation_Data : Job_Data
---@field jobData Job_WalkToLocation_BespokeData

---@class Job_WalkToLocation_BespokeData
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
---@return Job_WalkToLocation_Data
MoveToLocation.Create = function(playerIndex, targetLocation, surface)
    local job = MOD.Interfaces.JobManager.CreateGenericJob(MoveToLocation.jobName, playerIndex, "WalkToLocation") ---@cast job Job_WalkToLocation_Data

    -- Store the target data.
    job.jobData = {
        targetLocation = targetLocation,
        surface = surface
    }

    return job
end

--- Called when the job is actively started by a robot.
---@param job Job_WalkToLocation_Data
---@return Task_WalkToLocation_Data
MoveToLocation.ActivateJob = function(job)
    local primaryTask = MOD.Interfaces.Tasks.WalkToLocation.ActivateTask(job, nil, job.jobData.targetLocation, job.jobData.surface) -- This will be a MoveToLocation task in future, but for now just hard code it to WalkToLocation to avoid a pointless task level, as robots can only walk at present.

    MOD.Interfaces.JobManager.ActivateGenericJob(job, primaryTask)

    return primaryTask
end

--- Called to remove the job when it's no longer wanted.
---@param job Job_WalkToLocation_Data
MoveToLocation.Remove = function(job)
    error("Not implemented")
end

--- Called to pause the job and all of its activity.
---@param job Job_WalkToLocation_Data
MoveToLocation.Pause = function(job)
    error("Not implemented")
end

--- Called to resume a previously paused job.
---@param job Job_WalkToLocation_Data
MoveToLocation.Resume = function(job)
    error("Not implemented")
end

return MoveToLocation
