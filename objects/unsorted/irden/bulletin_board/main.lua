function init()
    object.setInteractive(true)
    self.forumId = config.getParameter("forumId")
    if not self.forumId then
        object.smash()
    end
end

---@class InteractionArgs
---@field sourceId         number
---@field sourcePosition   Vec2F
---@field targetId         number
---@field interactPosition Vec2F
function onInteraction(args)
    if not args or not args.sourceId then
        return nil
    end
    local boardPane = root.assetJson("/interface/unsorted/irden/bulletin_board/config.json")
    boardPane.forumId = self.forumId
    return { "ScriptPane", boardPane }
end
