local ShowRobotState = {}

--- Shows the text above the robot in a normal color for the duration.
---@param robot Robot
---@param text string
---@param durationTicks uint
ShowRobotState.ShowNormalState = function(robot, text, durationTicks)
    local targetEntity, targetPosition, surface
    if robot.entity.valid then
        targetEntity = robot.entity
        surface = robot.surface
    else
        -- FUTURE: robot corpse detection would go in here.

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

    if robot.currentStateRenderingId ~= nil and rendering.is_valid(robot.currentStateRenderingId) then
        error("Tried to add new state text over old state text")
    end

    robot.currentStateRenderingId = rendering.draw_text {
        text = text,
        surface = surface,
        target = targetEntity or targetPosition,
        color = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
        scale_with_zoom = true,
        alignment = "center",
        vertical_alignment = "bottom",
        time_to_live = durationTicks + 1 -- Add 1 as the current tick is the first and otherwise it vanishes before it starts. TODO - this needs to be more than 1 tick otherwise it doesn't show, however, it then still exists when we come to update it. So need to keep the text indefinitely and a cache of the message and only replace it if the new message is different. (same logic for color).
    }
end

return ShowRobotState
