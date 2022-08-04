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

--- Called by a robot when it actively starts the job.
---@param robot Robot
---@param job Job_WalkToLocation_Data
---@return uint ticksToWait
MoveToLocation.ActivateRobotOnJob = function(robot, job)
    local primaryTask, ticksToWait = MOD.Interfaces.Tasks.WalkToLocation.Begin(robot, job, nil, job.jobData.targetLocation, job.jobData.surface) -- This will be a MoveToLocation task in future, but for now just hard code it to WalkToLocation to avoid a pointless task level, as robots can only walk at present.

    MOD.Interfaces.JobManager.ActivateGenericJob(job, robot, primaryTask)

    return ticksToWait
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
