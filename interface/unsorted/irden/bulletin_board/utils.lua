require("/scripts/messageutil.lua")

local REQUEST_PREFIX = "irden:bulletin_board:"

---@param requestName string имя без префикса, например "getNotes"
---@param data        any    полезная нагрузка
---@param onSucc      fun(result:any)?
---@param onFail      fun(error:any)?
function request(requestName, data, onSucc, onFail)
    local formatedRequestName = REQUEST_PREFIX .. requestName
    promises:add(world.sendEntityMessage("server", formatedRequestName, data), onSucc, onFail)
end

---@param params table<string, any>
function openNotePane(params)
    local noteConfig = root.assetJson(panes.note)
    for key, value in pairs(params or {}) do
        noteConfig[key] = value
    end
    player.interact("ScriptPane", noteConfig, pane.sourceEntity())
end
