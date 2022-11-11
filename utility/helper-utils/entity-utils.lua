--[[
    All Factorio LuaEntity related utils functions.
]]
--

local EntityUtils = {} ---@class Utility_EntityUtils
local PositionUtils = require("utility.helper-utils.position-utils")

---@param surface LuaSurface
---@param positionedBoundingBox BoundingBox
---@param collisionBoxOnlyEntities boolean
---@param onlyForceAffected? LuaForce
---@param onlyDestructible boolean
---@param onlyKillable boolean
---@param entitiesExcluded? LuaEntity[]
---@return table<int, LuaEntity>
EntityUtils.ReturnAllObjectsInArea = function(surface, positionedBoundingBox, collisionBoxOnlyEntities, onlyForceAffected, onlyDestructible, onlyKillable, entitiesExcluded)
    local entitiesFound = surface.find_entities(positionedBoundingBox)
    local filteredEntitiesFound = {} ---@type table<int, LuaEntity>
    for _, entity in pairs(entitiesFound) do
        local entityExcluded = false
        if entitiesExcluded ~= nil and #entitiesExcluded > 0 then
            for _, excludedEntity in pairs(entitiesExcluded) do
                if entity == excludedEntity then
                    entityExcluded = true
                    break
                end
            end
        end
        if not entityExcluded then
            if (onlyForceAffected == nil) or (entity.force == onlyForceAffected) then
                if (not onlyDestructible) or (entity.destructible) then
                    if (not onlyKillable) or (entity.health ~= nil) then
                        if (not collisionBoxOnlyEntities) or (PositionUtils.IsBoundingBoxPopulated(entity.prototype.collision_box)) then
                            filteredEntitiesFound[#filteredEntitiesFound + 1] = entity
                        end
                    end
                end
            end
        end
    end
    return filteredEntitiesFound
end

---@param surface LuaSurface
---@param positionedBoundingBox BoundingBox
---@param killerEntity? LuaEntity
---@param collisionBoxOnlyEntities boolean
---@param onlyForceAffected? LuaForce
---@param entitiesExcluded? LuaEntity[]
---@param killerForce? ForceIdentification
EntityUtils.KillAllKillableObjectsInArea = function(surface, positionedBoundingBox, killerEntity, collisionBoxOnlyEntities, onlyForceAffected, entitiesExcluded, killerForce)
    if killerForce == nil then
        killerForce = "neutral"
    end
    for _, entity in pairs(EntityUtils.ReturnAllObjectsInArea(surface, positionedBoundingBox, collisionBoxOnlyEntities, onlyForceAffected, true, true, entitiesExcluded)) do
        if killerEntity ~= nil then
            entity.die(killerForce, killerEntity)
        else
            entity.die(killerForce)
        end
    end
end

---@param surface LuaSurface
---@param positionedBoundingBox BoundingBox
---@param killerEntity? LuaEntity
---@param onlyForceAffected LuaForce
---@param entitiesExcluded? LuaEntity[]
---@param killerForce? ForceIdentification
EntityUtils.KillAllObjectsInArea = function(surface, positionedBoundingBox, killerEntity, onlyForceAffected, entitiesExcluded, killerForce)
    if killerForce == nil then
        killerForce = "neutral"
    end
    for k, entity in pairs(EntityUtils.ReturnAllObjectsInArea(surface, positionedBoundingBox, false, onlyForceAffected, false, false, entitiesExcluded)) do
        if entity.destructible then
            if killerEntity ~= nil then
                entity.die(killerForce, killerEntity)
            else
                entity.die(killerForce)
            end
        else
            entity.destroy { do_cliff_correction = true, raise_destroy = true }
        end
    end
end

---@param surface LuaSurface
---@param positionedBoundingBox BoundingBox
---@param collisionBoxOnlyEntities boolean
---@param onlyForceAffected? LuaForce
---@param entitiesExcluded? LuaEntity[]
EntityUtils.DestroyAllKillableObjectsInArea = function(surface, positionedBoundingBox, collisionBoxOnlyEntities, onlyForceAffected, entitiesExcluded)
    for k, entity in pairs(EntityUtils.ReturnAllObjectsInArea(surface, positionedBoundingBox, collisionBoxOnlyEntities, onlyForceAffected, true, true, entitiesExcluded)) do
        entity.destroy { do_cliff_correction = true, raise_destroy = true }
    end
end

---@param surface LuaSurface
---@param positionedBoundingBox BoundingBox
---@param onlyForceAffected? LuaForce
---@param entitiesExcluded? LuaEntity[]
EntityUtils.DestroyAllObjectsInArea = function(surface, positionedBoundingBox, onlyForceAffected, entitiesExcluded)
    for k, entity in pairs(EntityUtils.ReturnAllObjectsInArea(surface, positionedBoundingBox, false, onlyForceAffected, false, false, entitiesExcluded)) do
        entity.destroy { do_cliff_correction = true, raise_destroy = true }
    end
end

-- Kills an entity and handles the optional arguments as Factorio API doesn't accept nil arguments.
---@param entity LuaEntity
---@param killerForce LuaForce
---@param killerCauseEntity? LuaEntity
EntityUtils.EntityDie = function(entity, killerForce, killerCauseEntity)
    if killerCauseEntity ~= nil then
        entity.die(killerForce, killerCauseEntity)
    else
        entity.die(killerForce)
    end
end

return EntityUtils
