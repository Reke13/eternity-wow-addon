-- Bar 1 paging: the state driver that picks the action page bar 1 shows. Vehicle, possess and
-- override actions first, then the flying mount's bar, Blizzard's pages 2-6 (Shift+number), the
-- forms and stances of the class (or the player's own conditions) and page 1 last. The class pages
-- follow ElvUI's defaults for Classic-style clients (Forever has the nine Classic classes).

---@type string, EternityUIActionBarsNamespace
local addonName, ns = ...
local E = EternityUI

---@class EternityUIActionBarsPaging
local Paging = {}
ns.Paging = Paging

-- Pages the client gives each class's forms and stances (bonus bars 1-4 are pages 7-10).
Paging.CLASS = {
    DRUID = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10;",
    ROGUE = "[bonusbar:1] 7;",
    WARRIOR = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9;",
    PRIEST = "[form:1] 7;",
}
-- Druids in stealth: cat form while prowling gets page 8, so bonus bar 2 shares page 10 (ElvUI's).
Paging.DRUID_STEALTH =
    "[bonusbar:1,nostealth] 7; [bonusbar:1,stealth] 8; [bonusbar:2] 10; [bonusbar:3] 9; [bonusbar:4] 10;"
-- Any other class: whatever bonus bar the client gives.
Paging.DEFAULT = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10;"

-- Resolves the special page states to the bar the client has active.
Paging.ON_PAGE = [[
    if newstate == "special" then
        if HasVehicleActionBar() then
            newstate = GetVehicleBarIndex()
        elseif HasOverrideActionBar() then
            newstate = GetOverrideBarIndex()
        elseif HasTempShapeshiftActionBar() then
            newstate = GetTempShapeshiftBarIndex()
        elseif HasBonusActionBar() then
            newstate = GetBonusBarIndex()
        else
            newstate = 1
        end
    end
    newstate = tonumber(newstate) or 1
    self:SetAttribute("state", newstate)
    control:ChildUpdate("state", newstate)
]]

local function opt(path)
    return E.store:Get(addonName, path)
end

--- Form and stance pages of a class.
---@param class string? class file name ("DRUID"); the player's when nil
---@param stealth boolean? druids: own page while prowling
---@return string
function Paging.ForClass(class, stealth)
    class = class or select(2, UnitClass("player"))
    if class == "DRUID" and stealth then
        return Paging.DRUID_STEALTH
    end
    return Paging.CLASS[class] or Paging.DEFAULT
end

-- Conditions ending in ";" so the next part can follow them.
local function clause(text)
    text = strtrim(text or "")
    if text == "" then
        return nil
    end
    if text:sub(-1) ~= ";" then
        text = text .. ";"
    end
    return text
end

--- Page driver of bar 1, from its options.
---@param class string? for the tests; the player's class when nil
---@return string
function Paging.Driver(class)
    local parts = {}
    if opt("bar1.vehicle") then
        parts[#parts + 1] = "[overridebar][vehicleui][possessbar][shapeshift] special;"
    end
    if opt("bar1.pagingMount") then
        parts[#parts + 1] = "[bonusbar:5] 11;"
    end
    parts[#parts + 1] = "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6;"
    local mode = opt("bar1.pagingMode")
    if mode == "class" then
        parts[#parts + 1] = Paging.ForClass(class, opt("bar1.pagingStealth"))
    elseif mode == "custom" then
        parts[#parts + 1] = clause(opt("bar1.pagingCustom"))
    end
    parts[#parts + 1] = "1"
    return table.concat(parts, " ")
end
