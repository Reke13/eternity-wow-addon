-- EternityUI_Map core: helpers the other files share (options, secret guard, colors, the saved
-- position, the map frame and a reversible way to hide Blizzard's regions).

---@type string, EternityUIMapNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = ns.Ui.Theme

---@class EternityUIMapCore
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

--- Color option ("#RRGGBB[AA]" or a theme color like "@accent") as { r, g, b, a }.
function Core.Hex(hex)
    return Theme.RGBA(hex)
end

--- Blizzard's world map (nil on a client without it).
function Core.Map()
    return _G.WorldMapFrame
end

--- True while the gamepad UI owns the panels: the map has its own gamepad layout then, so the
--- module stands down (no moving, scaling or click-through).
function Core.Gamepad()
    local util = _G.InputUtil
    return util ~= nil and util.IsGamepadUIEnabled ~= nil and util.IsGamepadUIEnabled() == true
end

--- The account-wide saved state: { version, point = { point, x, y }? }.
function Core.DB()
    local db = _G.EternityUIMapDB
    if type(db) ~= "table" or db.version ~= 1 then
        db = { version = 1 }
        _G.EternityUIMapDB = db
    end
    return db
end

--- A chat line from the module, in the theme's accent color.
function Core.Print(text)
    local r, g, b = Theme.Color("accent")
    print(("|cff%02x%02x%02xEternity:|r %s"):format(r * 255, g * 255, b * 255, text))
end

-- Hiding Blizzard's regions ---------------------------------------------------------------------

---@class EternityUIMapStash
---@field saved table<table, number> region -> the alpha it had
local Stash = {}
Stash.__index = Stash

--- A set of hidden Blizzard regions that can all be given back. Alpha and not Hide: Blizzard
--- calls Show() on several of them (SetBorder, the title, the tutorial button).
---@return EternityUIMapStash
function Core.NewStash()
    return setmetatable({ saved = {} }, Stash)
end

--- Sets the region's alpha to 0, remembering the alpha it had the first time.
function Stash:Hide(region)
    if not region or not region.SetAlpha then
        return
    end
    if self.saved[region] == nil then
        self.saved[region] = region:GetAlpha()
    end
    region:SetAlpha(0)
end

--- Gives every hidden region its alpha back.
function Stash:RestoreAll()
    for region, alpha in pairs(self.saved) do
        region:SetAlpha(alpha)
    end
    self.saved = {}
end

--- Whether anything is hidden.
function Stash:IsEmpty()
    return next(self.saved) == nil
end
