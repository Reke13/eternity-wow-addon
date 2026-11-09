-- The bars: one header per bar with its buttons, laid out in a grid from the options. Bars 1-8 use
-- LibActionButton buttons on Blizzard's action slots. The other bars borrow Blizzard's own frames
-- (Sources): the stance, pet, micro menu and bags bars take its buttons, the totem and extra bars
-- hold whole Blizzard frames; Blizzard keeps driving them and gets them back on Stop or when the
-- bar is switched off. Bar 1 follows the action page (Paging); every bar has a visibility driver.
-- Action, stance, pet, totem and extra bars are secure headers: Build waits for the end of combat
-- (Bars.pending) when called in combat. The micro menu and bags bars hold plain buttons, so they
-- are plain frames that can re-flow at any time (Arrange).

---@type string, EternityUIActionBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Style, Paging, Icons = ns.Style, ns.Paging, ns.Icons
local LAB = LibStub("LibActionButton-1.0")

---@class EternityUIActionBarsBar
---@field id string option group id ("bar1".."bar8", "stance", "pet", "micro", "bags", "totem", "extra")
---@field first integer? first action slot (action bars)
---@field binding string? binding prefix of its buttons (ACTIONBUTTON...)
---@field command string? binding prefix of borrowed buttons (SHAPESHIFTBUTTON...)
---@field kind string? borrowed frames: "stance", "pet", "micro", "bags" (buttons) or "totem", "extra" (holders)
---@field holder boolean? holds whole Blizzard frames, stacked
---@field plain boolean? plain frame (no protected buttons)
---@field paged boolean? follows the action page (bar 1)
---@field petBattle boolean? stays shown in pet battles
---@field noVehicle boolean? has no hideVehicle option
---@field taken boolean? its Blizzard frames are ours now
---@field installed boolean? its source hooks are in
---@field arranging boolean? Arrange is running
---@field frame table? the header
---@field buttons table[]

---@class EternityUIActionBarsBars
---@field pending boolean? a Build waits for the end of combat
---@field running boolean?
---@field unlocked boolean? move mode (Mover)
---@field binding boolean? key binding mode: bars and empty slots show, so any button can be bound
---@field borrowed table<table, table> borrowed Blizzard frame -> { bar, parent, points, width, height }
local Bars = { borrowed = {} }
ns.Bars = Bars

---@type EternityUIActionBarsBar[]
Bars.LIST = {
    { id = "bar1", first = 1, binding = "ACTIONBUTTON", paged = true, buttons = {} },
    { id = "bar2", first = 61, binding = "MULTIACTIONBAR1BUTTON", buttons = {} },
    { id = "bar3", first = 49, binding = "MULTIACTIONBAR2BUTTON", buttons = {} },
    { id = "bar4", first = 25, binding = "MULTIACTIONBAR3BUTTON", buttons = {} },
    { id = "bar5", first = 37, binding = "MULTIACTIONBAR4BUTTON", buttons = {} },
    { id = "bar6", first = 145, binding = "MULTIACTIONBAR5BUTTON", buttons = {} },
    { id = "bar7", first = 157, binding = "MULTIACTIONBAR6BUTTON", buttons = {} },
    { id = "bar8", first = 169, binding = "MULTIACTIONBAR7BUTTON", buttons = {} },
    { id = "stance", kind = "stance", command = "SHAPESHIFTBUTTON", buttons = {} },
    { id = "pet", kind = "pet", command = "BONUSACTIONBUTTON", buttons = {} },
    { id = "micro", kind = "micro", plain = true, petBattle = true, buttons = {} },
    { id = "bags", kind = "bags", plain = true, petBattle = true, buttons = {} },
    { id = "totem", kind = "totem", holder = true, buttons = {} },
    { id = "extra", kind = "extra", holder = true, noVehicle = true, buttons = {} },
}
Bars.byId = {}
for _, bar in ipairs(Bars.LIST) do
    Bars.byId[bar.id] = bar
end

-- Action pages bar 1 can show: 1-6 Blizzard's pages, 7-10 forms and stances, 11 the flying
-- mount, the rest vehicle, possess, override and temporary shapeshift bars.
local PAGES = 18
-- Size of an empty holder, so Edit Mode can still place it.
local EMPTY_HOLDER = 40

local hidden = CreateFrame("Frame")
hidden:Hide()
Bars.hidden = hidden

local function opt(path)
    return E.store:Get(addonName, path)
end

--- Page driver of bar 1, from its options (Paging.Driver).
function Bars.PageDriver()
    return Paging.Driver()
end

--- Frames a bar uses. Action bars: the option, limited to its buttons; stance: also the forms the
--- character has (Blizzard never hides the stance buttons of a class without forms); the other
--- borrowed bars: every Blizzard frame they hold.
---@param bar EternityUIActionBarsBar
---@return integer
function Bars.Count(bar)
    if bar.plain or bar.holder then
        return #bar.buttons
    end
    local count = math.min(opt(bar.id .. ".buttons"), #bar.buttons)
    if bar.kind == "stance" then
        count = math.min(count, GetNumShapeshiftForms() or 0)
    end
    return count
end

--- Visibility driver of a bar, from its options (and move mode).
---@param bar EternityUIActionBarsBar
function Bars.VisibilityDriver(bar)
    local id = bar.id
    if not opt(id .. ".enabled") or Bars.Count(bar) == 0 then
        return "hide"
    end
    if Bars.unlocked or Bars.binding then
        return "show"
    end
    local prefix = bar.petBattle and "" or "[petbattle] hide; "
    if bar.kind == "pet" then
        prefix = prefix .. "[nopet] hide; "
    end
    if id ~= "bar1" and not bar.noVehicle and opt(id .. ".hideVehicle") then
        prefix = prefix .. "[vehicleui][overridebar][possessbar] hide; "
    end
    local mode = opt(id .. ".visibility")
    if mode == "combat" then
        return prefix .. "[combat] show; hide"
    elseif mode == "nocombat" then
        return prefix .. "[nocombat] show; hide"
    elseif mode == "target" then
        return prefix .. "[@target,exists] show; hide"
    elseif mode == "custom" then
        local conditions = strtrim(opt(id .. ".conditions"))
        return prefix .. (conditions ~= "" and conditions or "show")
    end
    return prefix .. "show"
end

-- Creation --------------------------------------------------------------------------------------

local function createFrame(bar)
    local name = "EternityActionBar_" .. bar.id
    local frame = bar.plain and CreateFrame("Frame", name, UIParent)
        or CreateFrame("Frame", name, UIParent, "SecureHandlerStateTemplate")
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame.bar = bar
    if bar.paged then
        frame:SetAttribute("_onstate-page", Paging.ON_PAGE)
    end
    bar.frame = frame
    return frame
end

local function createActionButtons(bar)
    for i = 1, 12 do
        local name = string.format("EternityActionBar_%sButton%d", bar.id, i)
        local button = LAB:CreateButton(i, name, bar.frame, Style.ButtonConfig(bar, i))
        Style.ShortenHotkeys(button)
        Icons.Hook(button)
        button.eternityCommand = bar.binding .. i
        if bar.paged then
            for page = 1, PAGES do
                button:SetState(page, "action", (page - 1) * 12 + i)
            end
        else
            button:SetState(0, "action", bar.first + i - 1)
        end
        bar.buttons[i] = button
    end
end

--- Whether a borrowed bar should hold Blizzard's frames now. Stance and pet always do (their
--- Blizzard bars are hidden by Blizzard.lua); the others only while switched on.
---@param bar EternityUIActionBarsBar
function Bars.Wanted(bar)
    if bar.kind == "stance" or bar.kind == "pet" then
        return true
    end
    return opt(bar.id .. ".enabled") and true or false
end

--- Moves Blizzard's frames for a borrowed bar into it (saving where they were).
---@param bar EternityUIActionBarsBar
function Bars:Borrow(bar)
    local source = ns.Sources[bar.kind]
    wipe(bar.buttons)
    for i, frame in ipairs(source.List()) do
        if not self.borrowed[frame] then
            local width, height = frame:GetSize()
            local points = {}
            for p = 1, frame:GetNumPoints() do
                points[p] = { frame:GetPoint(p) }
            end
            self.borrowed[frame] = {
                bar = bar.id,
                parent = frame:GetParent(),
                points = points,
                width = width,
                height = height,
            }
        end
        if bar.command then
            frame.eternityCommand = bar.command .. i
        end
        bar.buttons[i] = frame
    end
    if not bar.taken then
        bar.taken = true
        if source.Take then
            source.Take(bar)
        end
    end
    if not bar.installed then
        bar.installed = true
        if source.Install then
            source.Install(bar)
        end
    end
end

--- Gives a bar's borrowed frames back to Blizzard, with their look and place (out of combat for
--- protected frames).
---@param bar EternityUIActionBarsBar
function Bars:Return(bar)
    ns.Sources.Quietly(function()
        -- Size and place every frame first, then give the parents back: a frame shown again in
        -- Blizzard's bar runs its layout (the micro menu reads its buttons' centers), and a
        -- button still placed in our hidden bar has no center yet.
        local returning = {}
        for frame, saved in pairs(self.borrowed) do
            if saved.bar == bar.id then
                returning[frame] = saved
                Style:Remove(frame)
                frame:SetSize(saved.width, saved.height)
                frame:ClearAllPoints()
                for _, p in ipairs(saved.points) do
                    frame:SetPoint(unpack(p))
                end
                -- Taken before Blizzard ever placed it (a hidden micro button): with no point it
                -- has no center either, so put it on its parent until Blizzard lays it out.
                if #saved.points == 0 then
                    frame:SetPoint("CENTER", saved.parent or UIParent, "CENTER")
                end
            end
        end
        for frame, saved in pairs(returning) do
            self.borrowed[frame] = nil
            frame:SetParent(saved.parent)
        end
    end)
    if bar.taken then
        bar.taken = false
        local source = ns.Sources[bar.kind]
        if source and source.Return then
            source.Return(bar)
        end
    end
    wipe(bar.buttons)
end

--- Gives every borrowed frame back to Blizzard.
function Bars:GiveBack()
    for _, bar in ipairs(self.LIST) do
        if bar.kind then
            self:Return(bar)
        end
    end
end

-- Layout ----------------------------------------------------------------------------------------

-- Grid position of button i: column and row counted from the start corner.
local function place(button, frame, i, perRow, width, height, spacing, start)
    local column, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
    local right, bottom = start:find("right") ~= nil, start:find("bottom") ~= nil
    local point = (bottom and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT")
    local x = column * (width + spacing) * (right and -1 or 1)
    local y = row * (height + spacing) * (bottom and 1 or -1)
    button:ClearAllPoints()
    button:SetPoint(point, frame, point, x, y)
end

local function fitGrid(frame, count, perRow, width, height, spacing)
    local columns, rows = perRow, math.ceil(math.max(count, 1) / perRow)
    frame:SetSize(
        math.max(columns * width + (columns - 1) * spacing, 1),
        math.max(rows * height + (rows - 1) * spacing, 1)
    )
end

-- Action, stance and pet buttons: a grid of square buttons of the bar's size.
local function arrangeButtons(bar)
    local frame, id = bar.frame, bar.id
    local count = Bars.Count(bar)
    local perRow = math.min(opt(id .. ".perRow"), math.max(count, 1))
    local size, spacing = opt(id .. ".size"), opt(id .. ".spacing")
    local start = opt(id .. ".start")
    local keyDown = opt("general.clickOnDown") or C_CVar.GetCVarBool("ActionButtonUseKeyDown")

    for i, button in ipairs(bar.buttons) do
        local used = i <= count
        if bar.kind then
            button:SetParent(used and frame or hidden)
        else
            button:UpdateConfig(Style.ButtonConfig(bar, i))
            button:SetAttribute("useOnKeyDown", keyDown and true or false)
            button:SetShown(used)
        end
        if used then
            Style:Apply(button, size)
            if bar.kind then
                Style:ApplyTexts(button)
            end
            place(button, frame, i, perRow, size, size, spacing, start)
        end
    end
    fitGrid(frame, count, perRow, size, size, spacing)
end

-- Micro menu and bags: the buttons Blizzard shows, in order, with no gaps.
local function arrangeLoose(bar)
    local frame, id = bar.frame, bar.id
    local shown = {}
    for _, button in ipairs(bar.buttons) do
        button:SetParent(frame)
        if button:IsShown() then
            shown[#shown + 1] = button
        end
    end
    local perRow = math.min(opt(id .. ".perRow"), math.max(#shown, 1))
    local spacing, start = opt(id .. ".spacing"), opt(id .. ".start")
    local width, height
    if bar.kind == "bags" then
        width = opt("bags.size")
        height = width
    else
        -- Micro buttons keep Blizzard's size (they aren't square).
        local saved = bar.buttons[1] and Bars.borrowed[bar.buttons[1]]
        width, height = saved and saved.width or 24, saved and saved.height or 32
    end
    for i, button in ipairs(shown) do
        if bar.kind == "bags" then
            if opt("bags.skin") and button.icon then
                Style:Apply(button, width)
            else
                Style:Remove(button)
                button:SetSize(width, height)
            end
        end
        place(button, frame, i, perRow, width, height, spacing, start)
    end
    fitGrid(frame, #shown, perRow, width, height, spacing)
end

-- Totem and extra: Blizzard's frames stacked top to bottom, centered (the extra bar with its
-- Spacing between them).
local function arrangeHolder(bar)
    local frame = bar.frame
    local gap = bar.id == "extra" and opt("extra.spacing") or 0
    local width, height = 0, 0
    for i, held in ipairs(bar.buttons) do
        local w, h = held:GetSize()
        width = math.max(width, w)
        held:SetParent(frame)
        held:ClearAllPoints()
        held:SetPoint("TOP", frame, "TOP", 0, -height)
        height = height + h + (i < #bar.buttons and held:IsShown() and gap or 0)
    end
    frame:SetSize(math.max(width, EMPTY_HOLDER), math.max(height, EMPTY_HOLDER))
end

--- Lays out a bar's buttons and sizes the bar. Plain bars (micro menu, bags) can do it in combat;
--- the others only out of combat (left pending otherwise).
---@param bar EternityUIActionBarsBar
function Bars:Arrange(bar)
    if not bar.frame then
        return
    end
    if not bar.plain and InCombatLockdown() then
        self.pending = true
        return
    end
    -- Re-parenting a button can show it, and OnShow re-flows its bar (Sources): once is enough.
    if bar.arranging then
        return
    end
    bar.arranging = true
    local source = bar.kind and ns.Sources[bar.kind]
    local ok, err = pcall(ns.Sources.Quietly, function()
        -- Prepare: the source's own layout inside its frames, before they're measured.
        if source and source.Prepare then
            source.Prepare(bar)
        end
        if bar.holder then
            arrangeHolder(bar)
        elseif bar.plain then
            arrangeLoose(bar)
        else
            arrangeButtons(bar)
        end
        if source and source.Arrange then
            source.Arrange(bar)
        end
    end)
    bar.arranging = false
    if not ok then
        error(err, 2)
    end
end

--- Lays out, styles and positions one bar (out of combat).
---@param bar EternityUIActionBarsBar
function Bars:LayoutBar(bar)
    local frame, id = bar.frame, bar.id
    self:Arrange(bar)
    -- The position belongs to the core's Mover (Mover.lua).
    frame:SetScale(opt(id .. ".scale"))
    frame.alpha = opt(id .. ".alpha")
    frame.fadedAlpha = opt(id .. ".fadedAlpha")
    frame.mouseover = opt(id .. ".visibility") == "mouseover" and not self.unlocked and not self.binding
    frame:SetAlpha(frame.mouseover and frame.fadedAlpha or frame.alpha)

    if bar.paged then
        RegisterStateDriver(frame, "page", Bars.PageDriver())
    end
    RegisterStateDriver(frame, "visibility", Bars.VisibilityDriver(bar))
end

--- Creates what's missing and applies every option. In combat it waits (Bars.pending).
---@return boolean applied false if it was left for after combat
function Bars:Build()
    if InCombatLockdown() then
        self.pending = true
        return false
    end
    self.pending = false
    Icons:Refresh()
    for _, bar in ipairs(self.LIST) do
        if not bar.frame then
            createFrame(bar)
            if not bar.kind then
                createActionButtons(bar)
            end
        end
        if bar.kind then
            if Bars.Wanted(bar) then
                self:Borrow(bar)
            else
                self:Return(bar)
            end
        end
        self:LayoutBar(bar)
    end
    self:UpdateFader()
    return true
end

--- Hides every bar and gives Blizzard's frames back (out of combat).
---@return boolean applied
function Bars:Stop()
    if InCombatLockdown() then
        self.pending = true
        return false
    end
    self.pending = false
    for _, bar in ipairs(self.LIST) do
        if bar.frame then
            UnregisterStateDriver(bar.frame, "page")
            UnregisterStateDriver(bar.frame, "visibility")
            bar.frame:Hide()
        end
    end
    self:GiveBack()
    self:UpdateFader()
    return true
end

-- Mouseover fade --------------------------------------------------------------------------------

local fader = CreateFrame("Frame")
fader:Hide()

-- Moves each mouseover bar's alpha towards its target (full while hovered or dragging an action).
fader:SetScript("OnUpdate", function(_, elapsed)
    local time = math.max(opt("general.fadeTime"), 0.01)
    local dragging = GetCursorInfo() ~= nil
    for _, bar in ipairs(Bars.LIST) do
        local frame = bar.frame
        if frame and frame.mouseover and frame:IsShown() then
            local target = (dragging or frame:IsMouseOver()) and frame.alpha or frame.fadedAlpha
            local current = frame:GetAlpha()
            local step = math.abs(frame.alpha - frame.fadedAlpha) * elapsed / time
            if math.abs(target - current) <= step then
                frame:SetAlpha(target)
            else
                frame:SetAlpha(current + (target > current and step or -step))
            end
        end
    end
end)

--- Runs the fader only while some bar fades on mouseover.
function Bars:UpdateFader()
    local any = false
    if self.running then
        for _, bar in ipairs(self.LIST) do
            if bar.frame and bar.frame.mouseover then
                any = true
            end
        end
    end
    fader:SetShown(any)
end
