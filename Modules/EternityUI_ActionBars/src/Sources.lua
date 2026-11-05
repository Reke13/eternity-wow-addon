-- Where each borrowed bar takes its Blizzard frames from, and how Blizzard's side is quieted while
-- we have them and put back afterwards:
--  * stance and pet: Blizzard's own action buttons (their bars are hidden by Blizzard.lua);
--  * micro: the micro menu buttons. MicroMenuContainer stays where it is (Forever anchors the main
--    bar and the bags bar to it); only its art goes transparent. Plain buttons: no combat limits;
--  * bags: the backpack, bag slots, reagent bag and key ring; BagsBar itself goes to the hidden
--    frame (it only holds plain ItemButtons);
--  * totem: the shaman's MultiCastActionBarFrame, whole (it slides and lays out its own buttons);
--  * extra: ExtraActionBarFrame (Forever disables it) and ZoneAbilityFrame, which Blizzard's
--    ExtraAbilityContainer adds and removes; they're kept out of its layout (ignoreInLayout).
-- Blizzard re-parents and re-anchors these frames on its own; the hooks put them back in our bars,
-- at once for plain frames and after combat for the protected ones (Bars.pending).

---@type string, EternityUIActionBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Bars = ns.Bars

---@class EternityUIActionBarsSource
---@field List fun(): table[] Blizzard's frames, in bar order
---@field Take fun(bar: table)? quiets Blizzard's side once the frames are ours
---@field Return fun(bar: table)? undoes Take after the frames went back
---@field Install fun(bar: table)? hooks, installed the first time the bar borrows
---@field Arrange fun(bar: table)? runs after every layout of the bar

---@type table<string, EternityUIActionBarsSource>
local Sources = {}
ns.Sources = Sources

local function opt(path)
    return E.store:Get(addonName, path)
end

-- Runs fn while a bar re-anchors its own frames, so the anchor hooks ignore it.
local quiet = false
function Sources.Quietly(fn, ...)
    local outer = quiet
    quiet = true
    local ok, err = pcall(fn, ...)
    quiet = outer
    if not ok then
        error(err, 2)
    end
end

--- True while a frame is in one of our bars and Blizzard just moved it (not us).
---@param frame table
local function stolenBack(frame)
    return not quiet and Bars.running and Bars.borrowed[frame] ~= nil
end

--- A frame we hold changed parent or anchor on Blizzard's side: lay its bar out again (plain
--- frames at once, protected ones after combat).
---@param frame table
local function reclaim(frame)
    local record = Bars.borrowed[frame]
    local bar = record and Bars.byId[record.bar]
    if not bar then
        return
    end
    if InCombatLockdown() and frame:IsProtected() then
        Bars.pending = true
        return
    end
    Bars:Arrange(bar)
end

--- Hooks SetParent and SetPoint of a frame we borrow (once).
---@param frame table
function Sources.Guard(frame)
    if frame.eternityGuarded then
        return
    end
    frame.eternityGuarded = true
    hooksecurefunc(frame, "SetParent", function(self)
        if stolenBack(self) then
            reclaim(self)
        end
    end)
    hooksecurefunc(frame, "SetPoint", function(self)
        if stolenBack(self) then
            reclaim(self)
        end
    end)
end

-- Plain buttons that Blizzard shows and hides (game rules, the reagent bag): their bar re-flows.
local function followShown(button, bar)
    if button.eternityFollow then
        return
    end
    button.eternityFollow = true
    local function changed()
        if Bars.running and Bars.borrowed[button] and bar.taken then
            Bars:Arrange(bar)
        end
    end
    button:HookScript("OnShow", changed)
    button:HookScript("OnHide", changed)
end

-- Stance and pet ---------------------------------------------------------------------------------

Sources.stance = {
    List = function()
        return _G.StanceBar and StanceBar.actionButtons or {}
    end,
}

Sources.pet = {
    List = function()
        return _G.PetActionBar and PetActionBar.actionButtons or {}
    end,
}

-- Micro menu -------------------------------------------------------------------------------------

local microList
local microArt = {}

Sources.micro = {
    -- The buttons MicroMenu holds (the ones its game rules allow), by layout index. Read once:
    -- after that they're ours.
    List = function()
        if not microList then
            local menu = _G.MicroMenu
            if not menu then
                return {}
            end
            microList = {}
            for _, child in ipairs({ menu:GetChildren() }) do
                if child.layoutIndex and child:IsObjectType("Button") then
                    microList[#microList + 1] = child
                end
            end
            table.sort(microList, function(a, b)
                return a.layoutIndex < b.layoutIndex
            end)
        end
        return microList
    end,
    Take = function()
        local menu = _G.MicroMenu
        for _, key in ipairs({ "BorderArt", "BackgroundArt" }) do
            local art = menu and menu[key]
            if art then
                microArt[art] = microArt[art] or art:GetAlpha()
                art:SetAlpha(0)
            end
        end
    end,
    Return = function()
        for art, alpha in pairs(microArt) do
            art:SetAlpha(alpha)
        end
        wipe(microArt)
        local menu = _G.MicroMenu
        if menu and menu.Layout then
            menu:Layout()
        end
        if UpdateMicroButtons then
            UpdateMicroButtons()
        end
    end,
    Install = function(bar)
        for _, button in ipairs(microList or {}) do
            followShown(button, bar)
            Sources.Guard(button)
        end
        -- UpdateMicroButtons refreshes states (and on some clients anchors); MicroMenu's help
        -- ticket button follows the menu's edge button, which is ours now.
        if UpdateMicroButtons then
            hooksecurefunc("UpdateMicroButtons", function()
                if Bars.running and bar.taken then
                    Bars:Arrange(bar)
                end
            end)
        end
        local menu = _G.MicroMenu
        if menu and menu.UpdateHelpTicketButtonAnchor then
            hooksecurefunc(menu, "UpdateHelpTicketButtonAnchor", function()
                local ticket, first = _G.HelpOpenWebTicketButton, bar.buttons[1]
                if Bars.running and bar.taken and ticket and first then
                    ticket:ClearAllPoints()
                    ticket:SetPoint("CENTER", first, "TOP", 0, 6)
                end
            end)
        end
    end,
}

-- Bags -------------------------------------------------------------------------------------------

local BAG_BUTTONS = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot",
    "CharacterBag1Slot",
    "CharacterBag2Slot",
    "CharacterBag3Slot",
    "CharacterReagentBag0Slot",
    "KeyRingButton",
}

Sources.bags = {
    List = function()
        local list = {}
        for _, name in ipairs(BAG_BUTTONS) do
            local button = _G[name]
            if button then
                list[#list + 1] = button
            end
        end
        return list
    end,
    Take = function()
        local bagsBar = _G.BagsBar
        if bagsBar and not Sources.bagsParent then
            Sources.bagsParent = bagsBar:GetParent()
            bagsBar:SetParent(Bars.hidden)
        end
    end,
    Return = function()
        local bagsBar = _G.BagsBar
        if bagsBar and Sources.bagsParent then
            bagsBar:SetParent(Sources.bagsParent)
            Sources.bagsParent = nil
            if bagsBar.Layout then
                bagsBar:Layout()
            end
        end
    end,
    Install = function(bar)
        for _, button in ipairs(Sources.bags.List()) do
            followShown(button, bar)
            -- Blizzard anchors these back to BagsBar from more places than its Layout.
            Sources.Guard(button)
        end
        -- BagsBar:Layout re-anchors every bag button (expand toggle, Edit Mode settings).
        local bagsBar = _G.BagsBar
        if bagsBar and bagsBar.Layout then
            hooksecurefunc(bagsBar, "Layout", function()
                if Bars.running and bar.taken then
                    Bars:Arrange(bar)
                end
            end)
        end
    end,
}

-- Totems -----------------------------------------------------------------------------------------

Sources.totem = {
    -- Only shamans get a totem bar (the frame exists for every class on Classic-style clients).
    List = function()
        local frame = _G.MultiCastActionBarFrame
        if frame and select(2, UnitClass("player")) == "SHAMAN" then
            return { frame }
        end
        return {}
    end,
    Install = function(bar)
        for _, frame in ipairs(Sources.totem.List()) do
            Sources.Guard(frame)
        end
    end,
}

-- Extra and zone abilities -----------------------------------------------------------------------

local extraArt = {}

-- Art drawn around the extra button and the zone ability buttons.
local function artOf(frame)
    if frame == _G.ExtraActionBarFrame then
        local button = _G.ExtraActionButton1
        return button and button.style
    end
    return frame.Style
end

Sources.extra = {
    List = function()
        local list = {}
        local extra = _G.ExtraActionBarFrame
        local util = _G.ActionButtonUtil
        local disabled = util and util.IsExtraActionButtonDisabled and util.IsExtraActionButtonDisabled()
        if extra and not disabled then
            list[#list + 1] = extra
        end
        if _G.ZoneAbilityFrame then
            list[#list + 1] = _G.ZoneAbilityFrame
        end
        return list
    end,
    Take = function(bar)
        for _, frame in ipairs(bar.buttons) do
            frame.ignoreInLayout = true
        end
    end,
    -- After every layout: the art follows the option.
    Arrange = function(bar)
        for _, frame in ipairs(bar.buttons) do
            local art = artOf(frame)
            if art then
                extraArt[art] = extraArt[art] or art:GetAlpha()
                art:SetAlpha(opt("extra.hideArt") and 0 or extraArt[art])
            end
        end
    end,
    -- Back into ExtraAbilityContainer if Blizzard still lists the frame there (it shows it).
    Return = function(bar)
        local container = _G.ExtraAbilityContainer
        for art, alpha in pairs(extraArt) do
            art:SetAlpha(alpha)
        end
        wipe(extraArt)
        for _, frame in ipairs(Sources.extra.List()) do
            frame.ignoreInLayout = nil
            if container and container.frames then
                for _, pair in ipairs(container.frames) do
                    if pair.frame == frame then
                        frame:SetParent(container)
                    end
                end
            end
        end
        if container and container.Layout then
            container:Layout()
        end
    end,
    Install = function(bar)
        for _, frame in ipairs(Sources.extra.List()) do
            Sources.Guard(frame)
        end
    end,
}
