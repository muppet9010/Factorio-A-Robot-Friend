local LoggingUtils = require("utility.helper-utils.logging-utils")

local MoveToLocation = {} ---@class MoveToLocation : Job
MoveToLocation.jobName = "MoveToLocation"

MoveToLocation.OnLoad = function()
    MOD.Interfaces.Jobs.MoveToLocation = MoveToLocation
end

--- Called to create the job when it's initially added.
---@param playerIndex uint
---@param targetLocation? MapPosition
---@param targetEntity? LuaEntity
MoveToLocation.Create = function(playerIndex, targetLocation, targetEntity)
    targetLocation = targetLocation or (targetEntity and targetEntity.position)
    if targetLocation == nil then
        error("no location provided")
    end

    local job = MOD.Interfaces.JobManager.CreateGenericJob(MoveToLocation.jobName, playerIndex)
    job.primaryTask = MOD.Interfaces.Tasks.WalkToLocation.Create(targetLocation, targetEntity, job, nil, nil) -- This will be the MoveToLocation task in future, but for now just hard code it to WalkToLocation to avoid a pointless task level, as robots can only walk.
end

--- Called to remove the job when it's no longer wanted.
---@param playerIndex uint
---@param jobId uint
MoveToLocation.Remove = function(playerIndex, jobId)
end

--- Called to pause the job and all of its activity. This will mean all robots move on to their next active job permanently. Also no new robot will be assignable to the job.
---@param playerIndex uint
---@param jobId uint
MoveToLocation.Pause = function(playerIndex, jobId)
end

--- Called to resume a previously paused job. Just means robots can be assigned back to the job.
---@param playerIndex uint
---@param jobId uint
MoveToLocation.Resume = function(playerIndex, jobId)
end

return MoveToLocation
