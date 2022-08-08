---@class Job_CompleteArea_Data : Job_Data
---@field jobData Job_CompleteArea_BespokeData

---@class Job_CompleteArea_BespokeData
---@field surface LuaSurface
---@field areasToComplete BoundingBox[]
---@field force LuaForce

local CompleteArea = {} ---@class Job_CompleteArea_Interface : Job_Interface
CompleteArea.jobName = "CompleteArea"

CompleteArea._OnLoad = function()
    MOD.Interfaces.Jobs.CompleteArea = CompleteArea
end

--- Called to create the job when it's initially added.
---@param playerIndex uint
---@param surface LuaSurface
---@param areasToComplete BoundingBox[]
---@param force LuaForce
---@return Job_CompleteArea_Data
CompleteArea.Create = function(playerIndex, surface, areasToComplete, force)
    local job = MOD.Interfaces.JobManager.CreateGenericJob(CompleteArea.jobName, playerIndex, "CompleteArea") ---@cast job Job_CompleteArea_Data

    -- Store the target data.
    job.jobData = {
        surface = surface,
        areasToComplete = areasToComplete,
        force = force
    }

    return job
end

--- Called when the job is actively started by a robot.
---@param job Job_CompleteArea_Data
---@return Task_CompleteArea_Data
CompleteArea.ActivateJob = function(job)
    local primaryTask = MOD.Interfaces.Tasks.CompleteArea.ActivateTask(job, nil, job.jobData.surface, job.jobData.areasToComplete, job.jobData.force)

    MOD.Interfaces.JobManager.ActivateGenericJob(job, primaryTask)

    return primaryTask
end

--- Called to remove the job when it's no longer wanted.
---@param job Job_CompleteArea_Data
CompleteArea.Remove = function(job)
    error("Not implemented")

    -- Clean out the primary task from the job and cleans any persistent or global data in the Task hierarchy.
    MOD.Interfaces.TaskManager.RemovingPrimaryTaskFromJob(job.primaryTask)
end

--- Called to pause the job and all of its activity.
---@param job Job_CompleteArea_Data
CompleteArea.Pause = function(job)
    error("Not implemented")
end

--- Called to resume a previously paused job.
---@param job Job_CompleteArea_Data
CompleteArea.Resume = function(job)
    error("Not implemented")
end

return CompleteArea
