-- unresolved
require("/scripts/util.lua")
require("/scripts/vec2.lua")
require("/scripts/messageutil.lua")

-- resolved
require("/interface/unsorted/irden/bulletin_board/utils.lua")
require("/scripts/polling/mqMessageBroker.lua")

local WIDGETS = {
    LIST_NOTES = "sa_notes.list_notes",
    LIST_NOTES_BACKGROUND_FRAME = "background_frame",
    LIST_NOTES_NAME_LABEL = "lyt_name.lbl_name",
    LIST_NOTES_MESSAGE_LABEL = "lyt_message.lbl_message",
    CHK_ARCHIVED = "chk_archived"
}

function init()
    self.forumId = config.getParameter("forumId")
    if not self.forumId then
        chat.addMessage("Доска объявлений: в конфиге пейна не задан forumId")
        pane.dismiss()
        return
    end

    BetterTitle.initialize()
    interface.bindCanvas("tooltipCanvas", true)

    self.broker = createMqMessageBroker(broker.name)
    -- доска закрывается - за ней дочерки
    self.broker:createQueue(broker.uninit)
    -- объявление создали в другом
    self.broker:createQueue(broker.notesChanged, function ()
        self.broker:subscribe(broker.notesChanged, loadNotes)
    end)

    loadNotes()
end

---Перечитывает список объявлений с сервера с учётом архивных
function loadNotes()
    locker:lock(true)
    locker:setMessage("Загрузка объявлений...")
    request(
        "getNotes",
        { forumId = self.forumId, archived = widget.getChecked(WIDGETS.CHK_ARCHIVED) },
        initNotes,
        function (error)
            chat.addMessage("Failed to get notes: " .. sb.printJson(error))
            locker:unlock()
        end
    )
end

---@class ForumThread
---@field id           string
---@field name         string
---@field archived     boolean
---@field locked       boolean
---@field createdAt    number           -- epoch
---@field messageCount number
---@field starterRef   ThreadMessageRef

---@class ThreadMessageRef
---@field channelId number
---@field messageId number

---@param response [string, ForumThread[]] имя канала и список веток
function initNotes(response)
    widget.clearListItems(WIDGETS.LIST_NOTES)
    widget.registerMemberCallback(WIDGETS.LIST_NOTES, "openNote", openNote)

    if type(response) ~= "table" then
        chat.addMessage("Invalid response received: " .. sb.printJson(response))
        locker:unlock()
        return
    end

    local name, data = table.unpack(response)
    if type(data) ~= "table" then
        chat.addMessage("Invalid data received: " .. sb.printJson(data))
        locker:unlock()
        return
    end

    BetterTitle.setSubtitle("Название: " .. tostring(name))

    for _, thread in ipairs(data) do
        local item = widget.addListItem(WIDGETS.LIST_NOTES)
        local path = string.format("%s.%s", WIDGETS.LIST_NOTES, item)
        local framePath = ("%s.%s"):format(path, WIDGETS.LIST_NOTES_BACKGROUND_FRAME)
        widget.setData(framePath, { threadId = thread.id, name = thread.name, itemPath = path })
        updateItemTooltip(framePath, thread.name)

        -- name
        local nameLabelPath = string.format(
            "%s.%s.%s", path, WIDGETS.LIST_NOTES_BACKGROUND_FRAME, WIDGETS.LIST_NOTES_NAME_LABEL
        )
        widget.setText(nameLabelPath, thread.name)

        -- message
        local messageLabelPath = string.format(
            "%s.%s.%s", path, WIDGETS.LIST_NOTES_BACKGROUND_FRAME, WIDGETS.LIST_NOTES_MESSAGE_LABEL
        )
        widget.setText(messageLabelPath, "Загрузка...")
        request(
            "firstMessage", thread.starterRef,
            function (firstMessage)
                widget.setText(messageLabelPath, firstMessage)
            end,
            function (error)
                widget.setText(messageLabelPath, error)
            end
        )
    end

    locker:lock(false)
end

function updateItemTooltip(path, text)
    local tooltipData = widget.getData(path) or {}
    tooltipData.defaultTooltip = text
    widget.setData(path, tooltipData)
end

function createTooltip(screenPosition)
    local w = widget.getChildAt(screenPosition)
    sb.setLogMap("BOARDS PATH: ", "%s", w)
    if w then
        w = w:sub(2)
        local wData = widget.getData(w)
        if wData and type(wData) == "table" and wData.defaultTooltip then
            return wData.defaultTooltip
        end
    end
end

---@class NoteData
---@field itemPath       string
---@field threadId       string
---@field name           string
---@field defaultTooltip string

---Клик по карточке объявления: открываем его на чтение
---@param _    string
---@param data NoteData
function openNote(_, data)
    openNotePane({
        mode = noteMode.VIEW,
        threadId = data.threadId,
        threadName = data.name
    })
end

---Кнопка добавить открываем тот же пейн объявления, но в режиме создания
function createNote()
    openNotePane({
        mode = noteMode.CREATE,
        forumId = self.forumId
    })
end

---Галка архивные
function archived()
    loadNotes()
end

function update(_)
    promises:update()
    self.broker:update()
end

function uninit()
    self.broker:publish(broker.uninit)
    widget.clearListItems(WIDGETS.LIST_NOTES)
end
