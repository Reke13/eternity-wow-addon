-- The list window: every player, sorted by name, with a search and a faction filter. Only the rows
-- in view exist, filled again as it scrolls. A click on a row opens the editor.

---@type string, EternityUIBlacklistNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, Widgets = E.Theme, E.Widgets
local L, List, Editor = ns.L, ns.List, ns.Editor

local KEY = addonName .. ".window"
local ROW = 30
local TOOLBAR = 44
local MENU_WIDTH = 170
local FACTIONS = { "all", "Horde", "Alliance", "unknown" }
local FACTION_COLORS = {
    Horde = { 0.9, 0.25, 0.2 },
    Alliance = { 0.3, 0.55, 1 },
}

---@class EternityUIBlacklistWindow
---@field frame table?
---@field view EternityUIBlacklistEntry[]
local Window = {
    rows = {},
    view = {},
    filter = { text = "", faction = "all" },
}
ns.Window = Window

local function factionName(faction)
    if faction == "all" then
        return L.ALL_FACTIONS
    end
    return L[faction] ~= faction and L[faction] or L.UNKNOWN
end

local function nameColor(entry)
    local color = entry.class and C_ClassColor and C_ClassColor.GetClassColor(entry.class)
    if color then
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

local function day(stamp)
    return stamp and date(L.DATE_FORMAT, stamp) or ""
end

--- Fills a tooltip with an entry's details.
---@param tip table
---@param entry EternityUIBlacklistEntry
function Window.Describe(tip, entry)
    tip:AddLine(entry.name, nameColor(entry))
    local info = {}
    if entry.level then
        info[#info + 1] = L.LEVEL:format(entry.level)
    end
    info[#info + 1] = entry.race
    info[#info + 1] = entry.className
    if #info > 0 then
        tip:AddLine(table.concat(info, " "), 1, 1, 1)
    end
    local faction = FACTION_COLORS[entry.faction]
    if faction then
        tip:AddLine(factionName(entry.faction), faction[1], faction[2], faction[3])
    end
    tip:AddLine(entry.guild and ("<" .. entry.guild .. ">") or L.NO_GUILD, 0.6, 0.8, 0.6)
    tip:AddLine(entry.reason ~= "" and entry.reason or L.NO_REASON, 1, 0.82, 0, true)
    tip:AddLine(L.ADDED:format(day(entry.added), entry.addedBy or "?"), 0.6, 0.6, 0.6)
    if entry.seen and entry.seenZone then
        tip:AddLine(L.SEEN_IN:format(day(entry.seen), entry.seenZone), 0.6, 0.6, 0.6)
    elseif entry.seen then
        tip:AddLine(L.SEEN:format(day(entry.seen)), 0.6, 0.6, 0.6)
    end
end

local function onEnter(row)
    row.hover:Show()
    if row.entry then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        Window.Describe(GameTooltip, row.entry)
        GameTooltip:AddLine(L.HINT_EDIT, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end
end

local function onLeave(row)
    row.hover:Hide()
    if GameTooltip:IsOwned(row) then
        GameTooltip:Hide()
    end
end

local function onClick(row)
    if row.entry then
        Editor.Open(row.entry)
    end
end

local function text(row, size, role, width)
    local fs = Widgets.Text(row, size, role)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    if width then
        fs:SetWidth(width)
    end
    return fs
end

local function newRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:Hide()
    function row:Paint()
        local c = Theme.colors.hover
        self.hover:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    row.name = text(row, 14, "text", 140)
    row.name:SetPoint("LEFT", 6, 0)
    row.faction = text(row, 13, "muted", 80)
    row.faction:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.guild = text(row, 13, "muted", 130)
    row.guild:SetPoint("LEFT", row.faction, "RIGHT", 8, 0)
    row.added = Widgets.Text(row, 12, "muted")
    row.added:SetPoint("RIGHT", -6, 0)
    row.reason = text(row, 13, "text")
    row.reason:SetPoint("LEFT", row.guild, "RIGHT", 8, 0)
    row.reason:SetPoint("RIGHT", row.added, "LEFT", -8, 0)
    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    row:SetScript("OnClick", onClick)
    return Widgets.Track(row)
end

local function fill(row, entry)
    row.entry = entry
    row.name:SetText(entry.name)
    row.name:SetTextColor(nameColor(entry))
    row.faction:SetText(factionName(entry.faction or "unknown"))
    local color = FACTION_COLORS[entry.faction]
    if color then
        row.faction:SetTextColor(color[1], color[2], color[3])
    else
        row.faction:SetTextColor(0.6, 0.6, 0.6)
    end
    row.guild:SetText(entry.guild or "")
    row.reason:SetText(entry.reason)
    row.added:SetText(day(entry.added))
end

--- Fills the rows in view.
function Window.DrawRows()
    local scroll = Window.frame.scroll
    local first = math.floor(scroll:GetVerticalScroll() / ROW)
    local needed = math.ceil(scroll:GetHeight() / ROW) + 1
    for i = 1, math.max(needed, #Window.rows) do
        local row = Window.rows[i]
        local index = first + i
        local entry = i <= needed and Window.view[index] or nil
        if entry and not row then
            row = newRow(scroll.child)
            Window.rows[i] = row
        end
        if row then
            row:SetShown(entry ~= nil)
            if entry then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW)
                row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW)
                fill(row, entry)
            end
        end
    end
end

--- Applies the filters and redraws.
function Window.Refresh()
    local w = Window.frame
    if not (w and w:IsShown()) then
        return
    end
    Window.view = List.Filter(List.db.players, Window.filter)
    w.empty:SetShown(#Window.view == 0)
    w.scroll:SetContentHeight(#Window.view * ROW)
    Window.DrawRows()
    w.summary:SetText(L.SUMMARY:format(List.Count()))
    w.faction.label:SetText(factionName(Window.filter.faction))
end

local function pick(field, value)
    Window.filter[field] = value
    Window.frame.scroll:SetVerticalScroll(0)
    Window.Refresh()
end

--- Opens the editor for the target if it's a player, or empty.
function Window.AddTarget()
    local info = List.ReadUnit("target")
    local entry = info and List.Get(info.name)
    Editor.Open(entry, info)
end

local function create()
    local w = Widgets.Window("EternityUIBlacklistWindow", L.TITLE, true)
    Window.frame = w
    w:SetSize(680, 460)
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w:SetScript("OnDragStart", function(frame)
        local entry = E.Mover.Entry(KEY)
        if not (entry and entry.locked) then
            frame:StartMoving()
        end
    end)
    w:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
        E.Mover.SaveFromFrame(KEY)
    end)
    -- See the loot history: keys can't pass through a window opened in combat.
    w:HookScript("OnShow", function(frame)
        frame:EnableKeyboard(not InCombatLockdown())
        Window.Refresh()
    end)
    w:HookScript("OnHide", function()
        Widgets.CloseMenu()
    end)

    local bar = CreateFrame("Frame", nil, w.body)
    bar:SetPoint("TOPLEFT", 10, 0)
    bar:SetPoint("TOPRIGHT", -10, 0)
    bar:SetHeight(TOOLBAR)

    w.faction = Widgets.Button(bar, "", "ghost", function(self)
        local entries = {}
        for i, faction in ipairs(FACTIONS) do
            entries[i] = {
                text = factionName(faction),
                onClick = function()
                    pick("faction", faction)
                end,
            }
        end
        Widgets.Menu(self, entries, MENU_WIDTH)
    end)
    w.faction:SetSize(140, 28)
    w.faction:SetPoint("RIGHT")
    w.search = Widgets.Input(bar, nil, L.SEARCH)
    w.search:SetMaxLetters(60)
    w.search:SetHeight(28)
    w.search:SetPoint("LEFT")
    w.search:SetPoint("RIGHT", w.faction, "LEFT", -6, 0)
    w.search:HookScript("OnTextChanged", function(box, userInput)
        if userInput then
            pick("text", box:GetText())
        end
    end)

    w.scroll = Widgets.Scroll(w.body)
    w.scroll:SetPoint("TOPLEFT", 10, -TOOLBAR)
    w.scroll:SetPoint("BOTTOMRIGHT", -10, 4)
    w.scroll:HookScript("OnVerticalScroll", Window.DrawRows)
    w.scroll:HookScript("OnMouseWheel", Window.DrawRows)
    w.scroll:HookScript("OnSizeChanged", Window.DrawRows)
    w.empty = Widgets.Text(w.body, 14, "muted")
    w.empty:SetPoint("CENTER")
    w.empty:SetText(L.EMPTY)

    w.summary = Widgets.Text(w.footer, 13, "muted")
    w.summary:SetPoint("LEFT", 12, 0)
    w.add = Widgets.Button(w.footer, L.ADD, "primary", Window.AddTarget)
    w.add:SetHeight(28)
    w.add:SetPoint("RIGHT", -10, 0)
end

local function register()
    if not E.Mover.elements[KEY] then
        E.Mover.Register({
            key = KEY,
            owner = addonName,
            label = L.TITLE,
            frame = Window.frame,
            point = "CENTER",
            x = 0,
            y = 40,
            openOptions = function()
                E:OpenOptions(addonName)
            end,
        })
    end
end

--- Opens or closes the window.
function Window.Toggle()
    if not Window.frame then
        create()
    end
    register()
    Window.frame:SetShown(not Window.frame:IsShown())
end

--- The list changed: redrawn at most once per frame.
function Window.Schedule()
    if Window.scheduled or not (Window.frame and Window.frame:IsShown()) then
        return
    end
    Window.scheduled = true
    C_Timer.After(0, function()
        Window.scheduled = false
        Window.Refresh()
    end)
end

function Window.Stop()
    if Window.frame then
        Window.frame:Hide()
    end
end
