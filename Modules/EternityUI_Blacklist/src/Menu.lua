-- Entries in the right-click menu of a player: add, edit, remove. They go through Menu.ModifyMenu,
-- which Blizzard's menus offer to addons without taint. A modifier can't be removed, so it adds
-- nothing while the module or the option is off.

---@type string, EternityUIBlacklistNamespace
local _, ns = ...
local E = EternityUI
local Secret = E.Secret
local L, List, Editor, opt = ns.L, ns.List, ns.Editor, ns.opt

-- The unit menus that belong to another player (Blizzard_UnitPopup, Forever 70790).
local TAGS = {
    "PLAYER",
    "TARGET",
    "FOCUS",
    "PARTY",
    "RAID",
    "RAID_PLAYER",
    "ENEMY_PLAYER",
    "ARENAENEMY",
    "FRIEND",
    "FRIEND_OFFLINE",
    "CHAT_ROSTER",
    "GUILD",
    "GUILD_OFFLINE",
    "COMMUNITIES_GUILD_MEMBER",
    "COMMUNITIES_WOW_MEMBER",
    "RECENT_ALLY",
    "RECENT_ALLY_OFFLINE",
    "PVP_SCOREBOARD",
    "WORLD_STATE_SCORE",
}

---@class EternityUIBlacklistMenu
---@field running boolean?
---@field installed boolean?
local Menu = {}
ns.Menu = Menu

--- Who a menu is about: what can be read of its unit, or else its name. Nil for yourself.
---@param contextData table?
---@return table? info
function Menu.Target(contextData)
    if type(contextData) ~= "table" then
        return nil
    end
    local info = List.ReadUnit(contextData.unit)
    if info then
        return info
    end
    local name = contextData.name
    if Secret.Is(name) then
        return nil
    end
    name = List.Clean(name)
    if not name or (List.Me() and name:lower() == List.Me():lower()) then
        return nil
    end
    return { name = name }
end

local function modify(_, root, contextData)
    if not Menu.running or not opt("menu.enabled") then
        return
    end
    local info = Menu.Target(contextData)
    if not info then
        return
    end
    local entry = List.Get(info.name)
    root:CreateDivider()
    root:CreateTitle(L.TITLE)
    if entry then
        List.Update(entry, info)
        root:CreateButton(L.MENU_EDIT, function()
            Editor.Open(entry)
        end)
        root:CreateButton(L.MENU_REMOVE, function()
            if List.Remove(entry.name) then
                print(L.REMOVED_MSG:format(entry.name))
            end
        end)
    else
        root:CreateButton(L.MENU_ADD, function()
            Editor.Open(nil, info)
        end)
    end
end

function Menu.Start()
    Menu.running = true
    local menus = _G.Menu
    if Menu.installed or not (menus and menus.ModifyMenu) then
        return
    end
    Menu.installed = true
    for _, tag in ipairs(TAGS) do
        menus.ModifyMenu("MENU_UNIT_" .. tag, modify)
    end
end

function Menu.Stop()
    Menu.running = false
end
