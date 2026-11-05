-- EternityUI_Stats core: helpers the other files share (options, secret guard, colors, the
-- per-character saved state).

---@type string, EternityUIStatsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = ns.Ui.Theme

---@class EternityUIStatsCore
---@field running boolean? between the module's OnEnable and OnDisable
local Core = {}
ns.Core = Core

--- An option of this module ("group.option").
function Core.Opt(path)
    return E.store:Get(addonName, path)
end

--- True for a secret value (always false on clients without secrets).
function Core.Secret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

--- Color option ("#RRGGBB[AA]" or a theme color like "@accent") as { r, g, b, a }; white if
--- it isn't valid.
function Core.Hex(hex)
    return Theme.RGBA(hex)
end

--- The player's class token ("WARRIOR"...), nil when the client doesn't say.
function Core.Class()
    local ok, _, class = pcall(UnitClass, "player")
    if ok and type(class) == "string" then
        return class
    end
    return nil
end

local function characterKey()
    local name = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or "?"
    return name .. "-" .. realm
end

--- This character's saved state: { shown = bool, collapsed = { [category] = true } }.
function Core.Char()
    local db = _G.EternityUIStatsDB
    if type(db) ~= "table" or db.version ~= 1 then
        db = { version = 1, chars = {} }
        _G.EternityUIStatsDB = db
    end
    local key = characterKey()
    local char = db.chars[key]
    if type(char) ~= "table" then
        char = { shown = Core.Opt("panel.startShown") ~= false, collapsed = {} }
        db.chars[key] = char
    end
    char.collapsed = type(char.collapsed) == "table" and char.collapsed or {}
    return char
end

--- A chat line from the module, in the theme's accent color.
function Core.Print(text)
    local r, g, b = Theme.Color("accent")
    print(("|cff%02x%02x%02xEternity:|r %s"):format(r * 255, g * 255, b * 255, text))
end
