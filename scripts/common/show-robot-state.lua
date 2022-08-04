local Colors = require("utility.lists.colors")

---@class RobotStateRenderedText
---@field robot Robot
---@field stateText? string
---@field renderingId uint64
---@field textColor Color
---@field surface LuaSurface
---@field targetEntity? LuaEntity
---@field targetPosition? MapPosition

local ShowRobotState = {} ---@class ShowRobotState

--- Shows the text above the robot in a normal color for the duration.
---@param robot Robot
---@param text string
---@param level "normal"|"warning"|"error"
ShowRobotState.UpdateStateText = function(robot, text, level)
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
    local color = (level == "normal") and Colors.white or (level == "warning") and Colors.warningMessage or (level == "error") and Colors.errorMessage or Colors.black

    -- Check if there's already a rendering and if so are we asking for the same thing (no change), or do we need to remove the old one and put the new one in place.
    local replaceText = false
    if robot.stateRenderedText ~= nil then
        if text ~= robot.stateRenderedText.stateText then replaceText = true; goto ShowRobotState_UpdateStateText_EndOfReplaceTextCheck end
        if color ~= robot.stateRenderedText.textColor then replaceText = true; goto ShowRobotState_UpdateStateText_EndOfReplaceTextCheck end
        if surface ~= robot.stateRenderedText.surface then replaceText = true; goto ShowRobotState_UpdateStateText_EndOfReplaceTextCheck end
        if targetEntity ~= robot.stateRenderedText.targetEntity then replaceText = true; goto ShowRobotState_UpdateStateText_EndOfReplaceTextCheck end
        if targetPosition ~= robot.stateRenderedText.targetPosition then replaceText = true; goto ShowRobotState_UpdateStateText_EndOfReplaceTextCheck end

        ::ShowRobotState_UpdateStateText_EndOfReplaceTextCheck::
    else
        replaceText = true
    end

    -- Create/replace the text if needed.
    if replaceText then
        if robot.stateRenderedText ~= nil then
            rendering.destroy(robot.stateRenderedText.renderingId)
        end
        local newRenderingId = rendering.draw_text {
            text = text,
            surface = surface,
            target = targetEntity or targetPosition,
            target_offset = { 0, -0.5 },
            color = color,
            scale_with_zoom = true,
            alignment = "center",
            vertical_alignment = "middle",
        }
        robot.stateRenderedText = {
            robot = robot,
            stateText = text,
            renderingId = newRenderingId,
            textColor = color,
            surface = surface,
            targetEntity = targetEntity,
            targetPosition = targetPosition
        }
    end
end

return ShowRobotState
