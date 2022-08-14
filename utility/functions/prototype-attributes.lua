-- Returns and caches prototype attributes (direct children only) as requested to save future API calls. Values stored in Lua global variable and populated as requested, as doesn't need persisting. Gets auto refreshed on game load and thus accounts for any change of attributes from mods.
local PrototypeAttributes = {} ---@class Utility_PrototypeAttributes

MOD = MOD or {} ---@class MOD
MOD.UTILITYPrototypeAttributes = MOD.UTILITYPrototypeAttributes or {} ---@type UtilityPrototypeAttributes_CachedTypes

--- Returns the request attribute of a prototype.
---
--- Obtains from the Lua global variable caches if present, otherwise obtains the result and caches it before returning it.
---@param prototypeType UtilityPrototypeAttributes_PrototypeType
---@param prototypeName string
---@param attributeName string
---@return any # attribute value, can include nil.
PrototypeAttributes.GetAttribute = function(prototypeType, prototypeName, attributeName)
    local utilityPrototypeAttributes = MOD.UTILITYPrototypeAttributes

    local typeCache = utilityPrototypeAttributes[prototypeType]
    if typeCache == nil then
        utilityPrototypeAttributes[prototypeType] = {}
        typeCache = utilityPrototypeAttributes[prototypeType]
    end

    local prototypeCache = typeCache[prototypeName]
    if prototypeCache == nil then
        typeCache[prototypeName] = {}
        prototypeCache = typeCache[prototypeName]
    end

    local attributeCache = prototypeCache[attributeName]
    if attributeCache ~= nil then
        return attributeCache.value
    else
        local resultPrototype
        if prototypeType == "entity" then
            resultPrototype = game.entity_prototypes[prototypeName]
        elseif prototypeType == "item" then
            resultPrototype = game.item_prototypes[prototypeName]
        elseif prototypeType == "fluid" then
            resultPrototype = game.fluid_prototypes[prototypeName]
        elseif prototypeType == "tile" then
            resultPrototype = game.tile_prototypes[prototypeName]
        elseif prototypeType == "equipment" then
            resultPrototype = game.equipment_prototypes[prototypeName]
        elseif prototypeType == "recipe" then
            resultPrototype = game.recipe_prototypes[prototypeName]
        elseif prototypeType == "technology" then
            resultPrototype = game.technology_prototypes[prototypeName]
        end
        local resultValue = resultPrototype[attributeName] ---@type any
        prototypeCache[attributeName] = { value = resultValue }
        return resultValue
    end
end

---@alias UtilityPrototypeAttributes_PrototypeType "entity"|"item"|"fluid"|"tile"|"equipment"|"recipe"|"technology" # not all prototype types are supported at present as not needed before.

---@alias UtilityPrototypeAttributes_CachedTypes table<string, UtilityPrototypeAttributes_CachedPrototypes> # a table of each prototype type name (key) and the prototypes it has of that type.
---@alias UtilityPrototypeAttributes_CachedPrototypes table<string, UtilityPrototypeAttributes_CachedAttributes> # a table of each prototype name (key) and the attributes if has of that prototype.
---@alias UtilityPrototypeAttributes_CachedAttributes table<string, UtilityPrototypeAttributes_CachedAttribute> # a table of each attribute name (key) and their cached values stored in the container.
---@class UtilityPrototypeAttributes_CachedAttribute # Container for the cached value. If it exists the value is cached. An empty table signifies that the cached value is nil.
---@field value any # the value of the attribute. May be nil if that's the attributes real value.

return PrototypeAttributes
