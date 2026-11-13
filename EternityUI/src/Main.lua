-- /et commands. Without arguments it opens the options window, which loads on first use.
---@type string, EternityUINamespace
local _, ns = ...
local L = ns.L

local function status()
    local stats = ns.store.raw.stats
    ns.Print(L.STATUS:format(EternityUI.version, ns.store:GetProfileName(), stats.logins, stats.reloads))
    local modules = EternityUI:ListModules()
    if #modules == 0 then
        print(L.NO_MODULES)
    end
    for _, module in ipairs(modules) do
        local state = module.reloadPending and L.MODULE_RELOAD or (module.active and L.MODULE_ON or L.MODULE_OFF)
        print(L.MODULE_LINE:format(module.name, state))
    end
end

-- Loads the options addon; false if it can't.
local function loadOptions()
    if C_AddOns.IsAddOnLoaded("EternityUI_Options") or C_AddOns.LoadAddOn("EternityUI_Options") then
        return true
    end
    ns.Print(L.OPTIONS_MISSING)
    return false
end

--- Opens or closes the options window.
function EternityUI:ToggleOptions()
    if loadOptions() then
        EternityUI.OptionsWindow.Toggle()
    end
end

--- Opens a module's page, optionally on a tab and on a group picked inside it.
---@param module string
---@param tab string?
---@param group string?
function EternityUI:OpenOptions(module, tab, group)
    if loadOptions() then
        EternityUI.OptionsWindow.Open(module, tab, group)
    end
end

--- Opens or closes the Mover, which lives in the options addon.
function EternityUI:ToggleMover()
    if loadOptions() then
        EternityUI.MoverSession.Toggle()
    end
end

local commands = {
    status = status,
    diag = ns.Diagnostics.Print,
    pixel = ns.Diagnostics.TogglePixelTest,
    move = function()
        EternityUI:ToggleMover()
    end,
    help = function()
        ns.Print(L.HELP)
    end,
    startup = function()
        ns.StartupReport.Toggle()
    end,
    ["startup on"] = function()
        ns.Startup.SetEnabled(true)
        ns.Print(L.STARTUP_ON)
    end,
    ["startup off"] = function()
        ns.Startup.SetEnabled(false)
        ns.Print(L.STARTUP_OFF)
    end,
}

SLASH_ETERNITYUI1 = "/et"
SLASH_ETERNITYUI2 = "/eternity"
SlashCmdList.ETERNITYUI = function(message)
    if not ns.store then
        return
    end
    local text = strtrim(message or ""):lower()
    if text == "" then
        EternityUI:ToggleOptions()
    elseif commands[text] then
        commands[text]()
    else
        ns.Print(L.HELP)
    end
end
