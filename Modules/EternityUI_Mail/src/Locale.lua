-- EternityUI_Mail texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIMailNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field opt fun(path: string): any
---@field History EternityUIMailHistory
---@field List EternityUIMailList
---@field Recipient EternityUIMailRecipient
---@field Classes EternityUIMailClasses

---@type string, EternityUIMailNamespace
local addonName, ns = ...

--- An option of this module.
---@param path string
---@return any
function ns.opt(path)
    return EternityUI.store:Get(addonName, path)
end

local strings = {
    enUS = {
        TAB = "History",
        BUTTON = "History",
        BUTTON_HINT = "Every letter your characters sent and received (/etmail)",
        SEARCH = "Search: name, subject, item",
        EMPTY = "No letters yet. Open the mailbox or send one.",
        NOTHING_SELECTED = "Pick a letter on the left.",
        KIND_all = "Sent and received",
        KIND_sent = "Sent",
        KIND_received = "Received",
        CHARS_all = "Every character",
        CHARS_current = "This character",
        SENT_TO = "To %s",
        RECEIVED_FROM = "From %s",
        SENT_TITLE = "Sent to %s",
        RECEIVED_TITLE = "Received from %s",
        CHARACTER = "Character",
        DATE = "Date",
        SEEN = "Seen in the mailbox",
        SUBJECT = "Subject",
        NO_SUBJECT = "(no subject)",
        MONEY = "Gold",
        COD = "Cash on delivery",
        RETURNED = "Returned to the sender",
        ITEMS = "Items",
        N_ITEMS = "%d items",
        ONE_ITEM = "1 item",
        UNKNOWN = "Unknown",
        ITEM_N = "Item %d",
        GOLD = "g",
        SILVER = "s",
        COPPER = "c",
        SUMMARY = "%d letters: %d sent, %d received",
        DELETE = "Delete",
        CLEAR = "Clear all",
        CLEAR_CONFIRM = "Click again",
        COPY = "Copy",
        COPY_HINT = "Shows the letter as text and selects it: Ctrl+C copies it. Click again to go back.",
        BACK = "Back",
        LINK_HINT = "Shift-click to link it in the chat",
    },
    esES = {
        TAB = "Historial",
        BUTTON = "Historial",
        BUTTON_HINT = "Todas las cartas que han enviado y recibido tus personajes (/etmail)",
        SEARCH = "Buscar: nombre, asunto, objeto",
        EMPTY = "Aún no hay cartas. Abre el buzón o envía una.",
        NOTHING_SELECTED = "Elige una carta a la izquierda.",
        KIND_all = "Enviadas y recibidas",
        KIND_sent = "Enviadas",
        KIND_received = "Recibidas",
        CHARS_all = "Todos los personajes",
        CHARS_current = "Este personaje",
        SENT_TO = "Para %s",
        RECEIVED_FROM = "De %s",
        SENT_TITLE = "Enviada a %s",
        RECEIVED_TITLE = "Recibida de %s",
        CHARACTER = "Personaje",
        DATE = "Fecha",
        SEEN = "Vista en el buzón",
        SUBJECT = "Asunto",
        NO_SUBJECT = "(sin asunto)",
        MONEY = "Oro",
        COD = "Contra reembolso",
        RETURNED = "Devuelta al remitente",
        ITEMS = "Objetos",
        N_ITEMS = "%d objetos",
        ONE_ITEM = "1 objeto",
        UNKNOWN = "Desconocido",
        ITEM_N = "Objeto %d",
        GOLD = "o",
        SILVER = "p",
        COPPER = "c",
        SUMMARY = "%d cartas: %d enviadas, %d recibidas",
        DELETE = "Borrar",
        CLEAR = "Borrar todo",
        CLEAR_CONFIRM = "Pulsa otra vez",
        COPY = "Copiar",
        COPY_HINT = "Muestra la carta como texto y la selecciona: Ctrl+C la copia. Pulsa otra vez para volver.",
        BACK = "Volver",
        LINK_HINT = "Mayús-clic para enlazarlo en el chat",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)
