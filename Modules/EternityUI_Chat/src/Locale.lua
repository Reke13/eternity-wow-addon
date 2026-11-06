-- EternityUI_Chat: player-facing texts (enUS and esES), shared by every file of the module.

---The module's private table.
---@class EternityUIChatNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string> texts in the client's language
---@field opt fun(path: string): any the module's option value
---@field Players EternityUIChatPlayers class, race and level of the players seen (Players.lua)
---@field History EternityUIChatHistory saved conversations (History.lua)
---@field Skin EternityUIChatSkin look of Blizzard's chat and the modes (Skin.lua)
---@field Messenger EternityUIChatMessenger messenger window (Messenger.lua)
---@field running boolean? between the module's OnEnable and OnDisable
---@field secret fun(value: any): boolean
---@field DB fun(): table
---@field FullName fun(name: string?): string?
---@field ShortName fun(fullName: string): string

---@type string, EternityUIChatNamespace
local addonName, ns = ...

local strings = {
    enUS = {
        MESSENGER = "Messages",
        SEARCH = "Search",
        WRITE = "Write a message",
        SEND = "Send",
        NO_CONVERSATIONS = "No conversations yet",
        NO_SELECTION = "Pick a conversation",
        LOCKED = "Blizzard is restricting the chat right now: messages show in the normal chat.",
        LOCKED_SEND = "The chat is restricted: the message went to the normal chat box.",
        GUILD = "Guild",
        OFFICER = "Officers",
        PARTY = "Party",
        RAID = "Raid",
        INSTANCE = "Instance",
        SAY = "Nearby",
        TODAY = "Today",
        YESTERDAY = "Yesterday",
        YOU = "You",
        LEVEL = "Level %d",
        CLEAR = "Clear this conversation",
        CLEAR_ALL = "Clear the whole history",
        CLOSE_CONVERSATION = "Close this conversation",
        OPTIONS = "Options",
        HISTORY_CLEARED = "Eternity Chat: history cleared.",
        LAUNCHER_HINT = "Click: messages · Right-click: options",
        UNREAD = "%d unread",
        OFFLINE = "Offline",
    },
    esES = {
        MESSENGER = "Mensajes",
        SEARCH = "Buscar",
        WRITE = "Escribe un mensaje",
        SEND = "Enviar",
        NO_CONVERSATIONS = "Todavía no hay conversaciones",
        NO_SELECTION = "Elige una conversación",
        LOCKED = "Blizzard está restringiendo el chat ahora mismo: los mensajes salen en el chat normal.",
        LOCKED_SEND = "El chat está restringido: el mensaje ha ido a la caja del chat normal.",
        GUILD = "Hermandad",
        OFFICER = "Oficiales",
        PARTY = "Grupo",
        RAID = "Banda",
        INSTANCE = "Instancia",
        SAY = "Alrededor",
        TODAY = "Hoy",
        YESTERDAY = "Ayer",
        YOU = "Tú",
        LEVEL = "Nivel %d",
        CLEAR = "Borrar esta conversación",
        CLEAR_ALL = "Borrar todo el historial",
        CLOSE_CONVERSATION = "Cerrar esta conversación",
        OPTIONS = "Opciones",
        HISTORY_CLEARED = "Eternity Chat: historial borrado.",
        LAUNCHER_HINT = "Clic: mensajes · Clic derecho: opciones",
        UNREAD = "%d sin leer",
        OFFLINE = "Desconectado",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)

function ns.opt(path)
    return EternityUI.store:Get(addonName, path)
end

function ns.secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local SCHEMA_VERSION = 1

--- EternityUIChatDB, bound and with its tables (the client loads it before this addon's ADDON_LOADED).
---@return table
function ns.DB()
    local db = _G.EternityUIChatDB
    if type(db) ~= "table" then
        db = {}
        _G.EternityUIChatDB = db
    end
    db.version = SCHEMA_VERSION
    db.players = type(db.players) == "table" and db.players or {}
    db.history = type(db.history) == "table" and db.history or {}
    return db
end

--- "Name-Realm" for a name that may come without its realm (same realm).
---@param name string?
---@return string?
function ns.FullName(name)
    if type(name) ~= "string" or ns.secret(name) or name == "" then
        return nil
    end
    if name:find("-", 1, true) then
        return name
    end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    return realm and (name .. "-" .. realm) or name
end

--- Who a whisper conversation is sent to: the name as the game gave it, or for conversations
--- saved before that was kept, the name without our own realm.
---@param conversation table
---@return string
function ns.WhisperTarget(conversation)
    return conversation.reply or ns.ShortName(conversation.target)
end

--- "Name" for a player of this realm, "Name-Realm" for the others.
function ns.ShortName(fullName)
    local name, realm = strsplit("-", fullName, 2)
    if not realm or realm == (GetNormalizedRealmName and GetNormalizedRealmName()) then
        return name
    end
    return fullName
end
