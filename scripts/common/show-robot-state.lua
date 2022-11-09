local Colors = require("utility.lists.colors")

---@class ShowRobotState_RobotStateRenderedText
---@field robot Robot
---@field stateText? string
---@field renderingId uint64
---@field textColor Color
---@field surface LuaSurface
---@field targetEntity? LuaEntity
---@field targetPosition? MapPosition

---@class ShowRobotState_NewRobotStateDetails
---@field stateText? string
---@field level "normal"|"warning"|"error"

local ShowRobotState = {} ---@class ShowRobotState

--- Shows the text above the robot in a normal color for the duration.
---@param robot Robot
---@param newRobotStateDetails ShowRobotState_NewRobotStateDetails
ShowRobotState.UpdateStateText = function(robot, newRobotStateDetails)
    -- Get the details for the text to be actually made.
    local targetEntity, targetPosition, surface
    if robot.entity ~= nil then
        -- Generally there is an entity set for the robot.
        targetEntity = robot.entity
        surface = robot.surface
    else
        -- As last resort show the state over the player so it goes somewhere and this should make it obvious something minor has gone wrong without throwing error messages everywhere.
        local masterCharacter = robot.master.character
        if masterCharacter ~= nil then
            targetEntity = masterCharacter
            surface = robot.master.surface
        else
            targetPosition = robot.master.position
            surface = robot.master.surface
        end
    end
    local color = (newRobotStateDetails.level == "normal") and Colors.white or (newRobotStateDetails.level == "warning") and Colors.warningMessage or (newRobotStateDetails.level == "error") and Colors.errorMessage or Colors.black

    -- Check if there's already a rendering and if so are we asking for the same thing (no change), or do we need to remove the old one and put the new one in place.
    -- Code Note: as many of our tasks only last 1 tick we can't create a rendering that only lasts 1 tick. So we have to create an indefinite one and check when it needs updating. Rather than having weird state tracking we generate the new ones details every update and then just see if its the same output as we already have ot if we need to replace the old one with the new one.
    local replaceText
    if robot.stateRenderedText ~= nil then
        if newRobotStateDetails.stateText ~= robot.stateRenderedText.stateText or color ~= robot.stateRenderedText.textColor or surface ~= robot.stateRenderedText.surface or targetEntity ~= robot.stateRenderedText.targetEntity or targetPosition ~= robot.stateRenderedText.targetPosition then
            replaceText = true
        else
            replaceText = false
        end
    else
        replaceText = true
    end

    -- Create/replace the text if needed.
    if replaceText then
        if robot.stateRenderedText ~= nil then
            rendering.destroy(robot.stateRenderedText.renderingId)
        end
        local newRenderingId = rendering.draw_text {
            text = newRobotStateDetails.stateText,
            surface = surface,
            target = targetEntity or targetPosition,
            target_offset = { 0.0, -0.5 },
            color = color,
            scale_with_zoom = true,
            alignment = "center",
            vertical_alignment = "middle",
        }
        robot.stateRenderedText = {
            robot = robot,
            stateText = newRobotStateDetails.stateText,
            renderingId = newRenderingId,
            textColor = color,
            surface = surface,
            targetEntity = targetEntity,
            targetPosition = targetPosition
        }
    end
end

return ShowRobotState
