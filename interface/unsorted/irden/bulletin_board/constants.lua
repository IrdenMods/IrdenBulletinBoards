
broker = {
    name = "irden:bulletin_board",
    -- сообщение в открытом объявлении изменилось -> перечитать содержимое
    message = "message",
    -- доска закрывается -> всем дочерним пейнам закрыться
    uninit = "uninit",
    -- список объявлений изменился -> доске перечитать список
    notesChanged = "notesChanged"
}

---Пути до пейнов доски
panes = {
    note = "/interface/unsorted/irden/bulletin_board/modals/note/note_config.json"
}

---Режимы пейна объявления. Прилетают в note_main.lua через поле "mode" конфига пейна
noteMode = {
    -- чтение существующей ветки: история сообщений + ответ
    VIEW = "view",
    -- создание новой ветки: заголовок + текст
    CREATE = "create"
}
