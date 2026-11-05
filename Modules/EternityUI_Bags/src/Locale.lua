-- EternityUI_Bags: player-facing texts (enUS and esES), shared by Inventory.lua and Bags.lua.

---The module's private table.
---@class EternityUIBagsNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string> texts in the client's language
---@field Inventory EternityUIBagsInventory what every character carries (Inventory.lua)

---@type string, EternityUIBagsNamespace
local _, ns = ...

local strings = {
    enUS = {
        BAGS = "Bags",
        BANK = "Bank",
        CHARACTER_BANK = "Character",
        WARBAND = "Warband bank",
        WARBAND_TAB = "Warband",
        SEARCH = "Search",
        SORT = "Sort",
        SORT_HINT = "Blizzard's sort for these bags",
        DEPOSIT = "Deposit",
        DEPOSIT_HINT = "Blizzard's automatic deposit into this bank",
        BLIZZARD_BANK = "Blizzard's bank",
        BLIZZARD_BANK_HINT = "Switch to Blizzard's bank window until you close it (to buy tabs, for example)",
        FREE = "%d / %d free",
        IN_BAGS = "bags",
        IN_BANK = "bank",
        EQUIPPED = "equipped",
        TOTAL = "Total",
        CHARACTERS = "Characters",
        CHARACTERS_HINT = "Characters whose items are remembered. Click one to forget it",
        FORGET = "Forget %s",
        NO_CHARACTERS = "No other characters remembered",
        OPTIONS = "Options",
        REAGENTS = "Reagents",
        KEYRING = "Keyring",
        BAG_N = "Bag %d",
        TAB_N = "Tab %d",
        NO_TABS = "This bank has no tabs yet",
        HINT_HEADER = "Drag to move · Right-click: options",
        HINT_LOCKED = "Right-click: options",
    },
    esES = {
        BAGS = "Bolsas",
        BANK = "Banco",
        CHARACTER_BANK = "Personaje",
        WARBAND = "Banco de la banda guerrera",
        WARBAND_TAB = "Banda guerrera",
        SEARCH = "Buscar",
        SORT = "Ordenar",
        SORT_HINT = "El orden de Blizzard para estas bolsas",
        DEPOSIT = "Depositar",
        DEPOSIT_HINT = "El depósito automático de Blizzard en este banco",
        BLIZZARD_BANK = "Banco de Blizzard",
        BLIZZARD_BANK_HINT = "Cambia a la ventana del banco de Blizzard hasta cerrarla (para comprar pestañas, por ejemplo)",
        FREE = "%d / %d libres",
        IN_BAGS = "bolsas",
        IN_BANK = "banco",
        EQUIPPED = "equipado",
        TOTAL = "Total",
        CHARACTERS = "Personajes",
        CHARACTERS_HINT = "Personajes cuyos objetos se recuerdan. Pulsa uno para olvidarlo",
        FORGET = "Olvidar a %s",
        NO_CHARACTERS = "No se recuerda ningún otro personaje",
        OPTIONS = "Opciones",
        REAGENTS = "Componentes",
        KEYRING = "Llavero",
        BAG_N = "Bolsa %d",
        TAB_N = "Pestaña %d",
        NO_TABS = "Este banco aún no tiene pestañas",
        HINT_HEADER = "Arrastra para mover · Clic derecho: opciones",
        HINT_LOCKED = "Clic derecho: opciones",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)
