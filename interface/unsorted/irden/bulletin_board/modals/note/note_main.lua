require("/scripts/messageutil.lua")
require("/interface/unsorted/irden/bulletin_board/utils.lua")
require("/scripts/polling/mqMessageBroker.lua")
require("/interface/StarboundTextboxInterface/scripts/utf8/utf8.lua")

local WIDGETS = {
    CONTENT = "lyt_content",
    TEXT_RAW = "lyt_text_raw",
    TEXT_PARSED = "lyt_text_parsed",
    REPLY = "lyt_reply",
    CREATE = "lyt_create",
    CREATE_NAME = "lyt_create.img_name_frame.tbx_note_name"
}

-- Ограничения дискорда: имя ветки до 100 символов, сообщение до 2000
local MAX_NAME_LENGTH = 100
local MAX_CONTENT_LENGTH = 2000

---@param text string
---@return integer
local function _length(text)
    return utf8.len(text) or #text
end

---@param text any
---@return string
local function _trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

---Перечитать содержимое ветки. Только для режима view
local function reinit()
    locker:lock()
    locker:setMessage("Загрузка сообщений...")
    request("getNoteContent", { threadId = self.threadId }, initNote, onFail)
end

function init()
    self.mode = config.getParameter("mode", noteMode.VIEW)
    self.forumId = config.getParameter("forumId")
    self.threadId = config.getParameter("threadId")
    self.threadName = config.getParameter("threadName")
    self.ready = false
    self.editMode = {
        enabled = false,
        savedText = nil,
        messageId = nil
    }

    BetterTitle.initialize()
    initBroker()
    initTextbox()
    initPreviewMd()

    if self.mode == noteMode.CREATE then
        initCreateMode()
    else
        initViewMode()
    end
end

function initBroker()
    self.broker = createMqMessageBroker(broker.name)

    -- сообщения в этой ветке поменялись -> перечитываем содержимое
    self.broker:createQueue(broker.message, function ()
        self.broker:subscribe(broker.message, reinit)
    end)

    -- доска закрылась -> закрываемся следом
    self.broker:createQueue(broker.uninit, function ()
        self.broker:subscribe(broker.uninit, function ()
            pane.dismiss()
        end)
    end)

    -- сюда стучимся сами, когда создали объявление
    self.broker:createQueue(broker.notesChanged)
end

---Чтение существующей ветки
function initViewMode()
    if not self.threadId then
        chat.addMessage("No thread ID provided")
        pane.dismiss()
        return
    end

    BetterTitle.setSubtitle("Название: " .. tostring(self.threadName or "без названия"))
    self.tbx:setHint("Нажмите для ввода текста...")

    widget.setVisible(WIDGETS.CREATE, false)
    widget.setVisible(WIDGETS.CONTENT, true)

    initMd()
    reinit()
end

---Создание новой ветки: вместо истории показываем форму с заголовком
function initCreateMode()
    if not self.forumId then
        chat.addMessage("No forum ID provided")
        pane.dismiss()
        return
    end

    BetterTitle.setTitle("Новое объявление")
    BetterTitle.setSubtitle("Заголовок сверху, текст снизу")
    self.tbx:setHint("Текст объявления. Enter - создать, Shift+Enter - перенос строки.")

    widget.setVisible(WIDGETS.CONTENT, false)
    widget.setVisible(WIDGETS.REPLY, false)
    widget.setVisible(WIDGETS.CREATE, true)
    widget.focus(WIDGETS.CREATE_NAME)

    self.ready = true
end

function initMd()
    MarkdownParser.setDebug(true)
    self.md = MarkdownParser:setup(WIDGETS.CONTENT)
    self.md:setupScroll({ scrollWidth = 10 })
    self.md:setBlockGap(16)
    self.md:setBlockSeparatorLine(
        "———————————————————————————————————————————————————————————————————————"
    )
    self.md:registerContextMenu({
        { name = "📋 Копировать", data = "copy" },
        { name = "✏ Редактировать", data = "edit" },
        { name = "🗑 Удалить", data = "delete" }
    }, contextMenuInterract)
end

function initTextbox()
    self.tbx = Textbox:setup(WIDGETS.TEXT_RAW)
    self.tbx:setCaretColor({ 255, 255, 255, 255 })
    self.tbx:setOnEscapeKey(function ()
        self.tbx:blur()
    end)
    self.tbx:setOnEnterKey(function ()
        self.tbx:blur()
        sendText(self.tbx:getText())
    end)
    self.tbx:setupScroll()
end

function initPreviewMd()
    self.pmd = MarkdownParser:setup(WIDGETS.TEXT_PARSED)
    self.pmd:setupScroll({ scrollWidth = 10 })
end

---@class MessageData
---@field id        number
---@field author    string
---@field content   string
---@field createdAt number -- epoch

---@param data MessageData[]
function initNote(data)
    if type(data) ~= "table" then
        onFail(data)
        return
    end

    self.md:clear()
    for _, message in ipairs(data) do
        local content = message.content
        local lines = {}
        table.insert(lines, string.format("%s", os.date("%Y-%m-%d %H:%M:%S", message.createdAt)))
        for line in content:gmatch("[^\n]+") do
            ---@type string
            local trimmedLine = line:match("^%s*(.-)%s*$")
            table.insert(lines, trimmedLine)
        end
        self.md:render(lines, { messageId = message.id })
    end
    self.md:setScroll(self.md:getMaxScroll())
    locker:unlock()
    self.ready = true
end

function onFail(error)
    chat.addMessage("Failed to get note: " .. sb.printJson(error))
    locker:unlock()
end

---@param _ number Delta time per frame = 1/60th from second
function update(_)
    promises:update()
    if self.broker then
        self.broker:update()
    end
end

function createTooltip(screenPosition)
    local w = widget.getChildAt(screenPosition)
    sb.setLogMap("NOTES PATH: ", "%s", w)
    if w then
        w = w:sub(2)
        local wData = widget.getData(w)
        if wData and type(wData) == "table" and wData.defaultTooltip then
            return wData.defaultTooltip
        end
    end
end

function enablePreview(name, data)
    local enabled = widget.getChecked(name)
    if enabled then
        widget.setVisible(WIDGETS.TEXT_PARSED, true)
        widget.setVisible(WIDGETS.TEXT_RAW, false)
        self.pmd:render(self.tbx:getText())
    else
        self.pmd:clear()
        widget.setVisible(WIDGETS.TEXT_PARSED, false)
        widget.setVisible(WIDGETS.TEXT_RAW, true)
    end
end

function contextMenuInterract(blockId, name, data)
    if data == "copy" then
        clipboard.setText(self.md:getText(blockId))
        interface.queueMessage("Текст скопирован.")
    elseif data == "edit" then
        turnOnEditMode(blockId)
    elseif data == "delete" then
        promises:add(player.confirm({
            message = "Вы уверены, что хотите удалить это сообщение?"
        }), function (confirmed)
            if confirmed then
                -- TODO: потом перекинуть на сервер, сейчас удаление только локальное
                self.md:remove(blockId)
            end
        end)
    end
end

function turnOnEditMode(blockId)
    self.editMode.enabled = true
    if not self.editMode.savedText then
        self.editMode.savedText = self.tbx:getText()
    end
    self.tbx:clear()
    local text = self.md:getText(blockId)
    local messageId = self.md:getMetadata(blockId).messageId
    self.editMode.messageId = messageId
    local result = text:gsub("^.-\n", "")
    self.tbx:setText(result)
    widget.setVisible(WIDGETS.REPLY, true)
end

function turnOffEditMode()
    self.editMode.enabled = false
    self.tbx:clear()
    self.tbx:setText(self.editMode.savedText or "")
    self.editMode.savedText = nil
    widget.setVisible(WIDGETS.REPLY, false)
end

function closeReplyCallback(name, data)
    if self.editMode.enabled then
        turnOffEditMode()
    end
end

---Enter в поле заголовка - отправляем ровно то же, что и Enter в поле текста
function submitNote()
    sendText(self.tbx:getText())
end

---Единая точка отправки: в режиме создания заводим ветку, иначе пишем в существующую
---@param content string
function sendText(content)
    if self.mode == noteMode.CREATE then
        createNote(content)
    else
        replyText(content)
    end
end

---Создание новой ветки на форуме
---@param content string
function createNote(content)
    local name = _trim(widget.getText(WIDGETS.CREATE_NAME))
    content = _trim(content)

    if name == "" then
        interface.queueMessage("Введите заголовок объявления.")
        widget.focus(WIDGETS.CREATE_NAME)
        return
    end
    if _length(name) > MAX_NAME_LENGTH then
        interface.queueMessage(string.format("Заголовок длиннее %d символов.", MAX_NAME_LENGTH))
        return
    end
    if content == "" then
        interface.queueMessage("Текст объявления пустой.")
        self.tbx:focus()
        return
    end
    if _length(content) > MAX_CONTENT_LENGTH then
        interface.queueMessage(string.format("Текст длиннее %d символов.", MAX_CONTENT_LENGTH))
        return
    end

    locker:lock()
    locker:setMessage("Создание объявления...")
    request(
            "createNote", { forumId = self.forumId, name = name, content = content },
            function (response)
                interface.queueMessage(tostring(response or "Объявление создано"))
                -- доска перечитает список и увидит новое объявление
                self.broker:publish(broker.notesChanged)
                pane.dismiss()
            end,
            function (error)
                interface.queueMessage(tostring(error))
                locker:unlock()
            end
    )
end

---Ответ в существующую ветку или правка своего сообщения
---@param content string
function replyText(content)
    content = _trim(content)
    if content == "" then
        return
    end

    locker:lock()
    locker:setMessage("Отправка сообщения...")
    local function onSuccess(response)
        interface.queueMessage(response)
        self.tbx:clear()
        closeReplyCallback()
        reinit()
    end
    local function onError(error)
        interface.queueMessage(error)
        locker:unlock()
    end
    if not self.editMode.enabled then
        request(
                "sendText", {forumId = self.forumId, content = content, threadId = self.threadId },
                onSuccess, onError
        )
    else
        request(
                "editText", { forumId = self.forumId, content = content, threadId = self.threadId, messageId = self.editMode.messageId },
                onSuccess, onError
        )
    end
end

function uninit()
    if self.broker then
        self.broker:close()
    end
    if self.md then
        self.md:destroy()
    end
end
