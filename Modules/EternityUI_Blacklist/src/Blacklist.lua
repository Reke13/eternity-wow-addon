-- EternityUI_Blacklist: your own list of players, Horde or Alliance, with the reason for each.
-- Shared by every character of the account (EternityUIBlacklistDB). Entries are added from a
-- player's right-click menu (Menu), the list window (Window, /bl) or the slash command, and edited
-- in the Editor. Warnings tells you when a listed player turns up. Disabling the module stops the
-- warnings and the menu entries and closes its windows; Blizzard's UI is left as it was.

---@type string, EternityUIBlacklistNamespace
local addonName, ns = ...
local E = EternityUI
local L, List, Editor, Window, Warnings, Menu = ns.L, ns.List, ns.Editor, ns.Window, ns.Warnings, ns.Menu

---@class EternityUIBlacklistModule: EternityUIModuleDefinition
local Module = {
    schema = ns.OptionsSchema,
    actions = {
        {
            text = L.OPEN,
            onClick = function()
                Window.Toggle()
            end,
        },
    },
}
-- Internals reachable from the tests.
Module.List, Module.Editor, Module.Window, Module.Warnings, Module.Menu = List, Editor, Window, Warnings, Menu

function Module:OnEnable()
    List.Bind()
    List.onChange = Window.Schedule
    Warnings.Start(self)
    Menu.Start()
end

function Module:OnDisable()
    List.onChange = nil
    Warnings.Stop()
    Menu.Stop()
    Editor.Stop()
    Window.Stop()
end

local function say(text)
    print(("|cffff4040%s:|r %s"):format(L.TITLE, text))
end

--- /bl add name [reason] adds or updates a player; the target's details are kept when it's them.
--- /bl add alone opens the editor on the target, to write the reason there.
---@param rest string
---@return EternityUIBlacklistEntry?
function Module.SlashAdd(rest)
    local name, reason = rest:match("^(%S+)%s*(.-)$")
    local target = List.ReadUnit("target")
    if not name then
        if not target then
            say(L.NEED_NAME)
            return nil
        end
        Editor.Open(List.Get(target.name), target)
        return nil
    end
    local info = target and List.Key(name) == List.Key(target.name) and target or { name = name }
    if reason ~= "" then
        info.reason = reason
    end
    local entry = List.Add(info)
    if entry then
        say(L.ADDED_MSG:format(entry.name))
    end
    return entry
end

function Module.Slash(message)
    if not Module.active then
        return
    end
    List.Bind()
    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" then
        Window.Toggle()
    elseif command == "add" then
        Module.SlashAdd(rest)
    elseif command == "remove" or command == "del" then
        local entry = List.Remove(rest)
        say((entry and L.REMOVED_MSG or L.NOT_FOUND):format(entry and entry.name or rest))
    else
        say(L.HELP)
    end
end

_G.SLASH_ETERNITYBLACKLIST1 = "/bl"
_G.SLASH_ETERNITYBLACKLIST2 = "/blacklist"
SlashCmdList.ETERNITYBLACKLIST = Module.Slash

E:RegisterModule(addonName, Module)
