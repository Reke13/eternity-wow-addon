-- The history window: the log, newest first, with a header per day. The log can hold thousands of
-- entries, so only the rows in view exist, and they're filled again as it scrolls. Filters last
-- until the /reload.

---@type string, EternityUILootNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, Widgets = E.Theme, E.Widgets
local L, Recorder = ns.L, ns.Recorder

local KEY = addonName .. ".history"
local ROW = 30
local ICON = 22
local TOOLBAR = 44
local MENU_WIDTH = 190
local DAY = 86400
local CONFIRM_SECONDS = 4
local PERIODS = { "all", "today", "week", "month" }
local KINDS = { "all", "item", "money", "currency" }
local QUALITIES = { 0, 1, 2, 3, 4, 5 }

---@class EternityUILootHistory
---@field frame table?
---@field view table[] what the filters let through, with day headers
local History = {
    rows = {},
    view = {},
    filter = { text = "", kind = "all", quality = 0, character = "all", period = "all" },
}
ns.History = History

--- The first second a period covers.
---@param period string
---@param now integer
---@return integer
function History.Since(period, now)
    if period == "today" then
        local today = date("*t", now)
        today.hour, today.min, today.sec = 0, 0, 0
        return time(today)
    elseif period == "week" then
        return now - 7 * DAY
    elseif period == "month" then
        return now - 30 * DAY
    end
    return 0
end

local function contains(value, needle)
    return value ~= nil and value:lower():find(needle, 1, true) ~= nil
end

local function matches(entry, filter, needle)
    if filter.kind ~= "all" and entry.kind ~= filter.kind then
        return false
    elseif filter.character ~= "all" and entry.character ~= filter.character then
        return false
    elseif entry.kind == "item" and (entry.quality or 1) < filter.quality then
        return false
    elseif filter.quality > 0 and entry.kind ~= "item" then
        return false
    elseif needle then
        return contains(entry.name, needle)
            or contains(entry.source, needle)
            or contains(entry.zone, needle)
            or contains(entry.looter, needle)
    end
    return true
end

--- The entries the filter lets through, newest first, with a { header } before each day.
---@param entries table[] oldest first
---@param filter table
---@param now integer
---@return table[] view
---@return integer count
---@return integer copper
function History.Filter(entries, filter, now)
    local view, count, copper = {}, 0, 0
    local since = History.Since(filter.period, now)
    local needle = filter.text ~= "" and filter.text:lower() or nil
    local day
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry.time < since then
            break
        end
        if matches(entry, filter, needle) then
            local thisDay = date("%Y-%m-%d", entry.time)
            if thisDay ~= day then
                day = thisDay
                view[#view + 1] = { header = date(L.DATE_FORMAT, entry.time) }
            end
            view[#view + 1] = entry
            count = count + 1
            if entry.kind == "money" then
                copper = copper + entry.count
            end
        end
    end
    return view, count, copper
end

local function nameOf(entry)
    if entry.kind == "money" then
        return GetMoneyString(entry.count)
    elseif entry.count and entry.count > 1 then
        return (entry.name or "") .. " x" .. entry.count
    end
    return entry.name or ""
end

local function detailOf(entry)
    local parts = {}
    if entry.looter then
        parts[#parts + 1] = L.LOOTED_BY:format(entry.looter)
    end
    parts[#parts + 1] = entry.source
    parts[#parts + 1] = entry.zone
    return table.concat(parts, " · ")
end

local function onEnter(row)
    local entry = row.entry
    row.hover:SetShown(entry ~= nil)
    if entry and entry.link then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(entry.link)
        GameTooltip:AddLine(L.HINT_LINK, 0.6, 0.6, 0.6)
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
    local entry = row.entry
    if entry and entry.link and IsModifiedClick() then
        HandleModifiedItemClick(entry.link)
    end
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
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.time = Widgets.Text(row, 12, "muted")
    row.time:SetPoint("RIGHT", -6, 0)
    row.name = Widgets.Text(row, 14, "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "CENTER", 20, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.detail = Widgets.Text(row, 12, "muted")
    row.detail:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.detail:SetPoint("RIGHT", row.time, "LEFT", -8, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row.day = Widgets.Text(row, 13, "muted")
    row.day:SetPoint("LEFT", 4, -4)
    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    row:SetScript("OnClick", onClick)
    return Widgets.Track(row)
end

local function fill(row, item)
    local isHeader = item.header ~= nil
    row.entry = not isHeader and item or nil
    row.day:SetShown(isHeader)
    row.icon:SetShown(not isHeader)
    row.name:SetShown(not isHeader)
    row.detail:SetShown(not isHeader)
    row.time:SetShown(not isHeader)
    if isHeader then
        row.day:SetText(item.header)
        return
    end
    row.icon:SetTexture(item.kind == "money" and 133784 or item.icon or 134400)
    row.name:SetText(nameOf(item))
    if item.kind == "money" then
        row.name:SetTextColor(1, 1, 1)
    else
        row.name:SetTextColor(C_Item.GetItemQualityColor(item.quality or 1))
    end
    row.detail:SetText(detailOf(item))
    row.time:SetText(date("%H:%M", item.time))
end

--- Fills the rows in view.
function History.DrawRows()
    local w = History.frame
    local scroll = w.scroll
    local first = math.floor(scroll:GetVerticalScroll() / ROW)
    local needed = math.ceil(scroll:GetHeight() / ROW) + 1
    for i = 1, math.max(needed, #History.rows) do
        local row = History.rows[i]
        local index = first + i
        local item = i <= needed and History.view[index] or nil
        if item and not row then
            row = newRow(scroll.child)
            History.rows[i] = row
        end
        if row then
            row:SetShown(item ~= nil)
            if item then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW)
                row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW)
                fill(row, item)
            end
        end
    end
end

--- Applies the filters and redraws.
function History.Refresh()
    local w = History.frame
    if not (w and w:IsShown()) then
        return
    end
    local view, count, copper = History.Filter(Recorder.db.entries, History.filter, time())
    History.view = view
    w.empty:SetShown(count == 0)
    w.scroll:SetContentHeight(#view * ROW)
    History.DrawRows()
    if copper > 0 then
        w.summary:SetText(L.SUMMARY_GOLD:format(count, GetMoneyString(copper)))
    else
        w.summary:SetText(L.SUMMARY:format(count))
    end
end

local function qualityName(quality)
    return quality == 0 and L.ANY_QUALITY or _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality)
end

local function kindName(kind)
    return kind == "all" and L.ALL_KINDS or L["KIND_" .. kind]
end

local function characterName(character)
    return character == "all" and L.ALL_CHARACTERS or character
end

-- Button texts follow the filter.
local function label()
    local w = History.frame
    local filter = History.filter
    w.kind.label:SetText(kindName(filter.kind))
    w.quality.label:SetText(qualityName(filter.quality))
    w.character.label:SetText(characterName(filter.character))
    w.period.label:SetText(L["PERIOD_" .. filter.period])
end

local function pick(field, value)
    History.filter[field] = value
    label()
    History.frame.scroll:SetVerticalScroll(0)
    History.Refresh()
end

local function menu(owner, field, values, name)
    local entries = {}
    for i, value in ipairs(values) do
        entries[i] = {
            text = name(value),
            onClick = function()
                pick(field, value)
            end,
        }
    end
    Widgets.Menu(owner, entries, MENU_WIDTH)
end

local function filterButton(parent, onPress)
    local button = Widgets.Button(parent, "", "ghost", onPress)
    button:SetHeight(28)
    return button
end

local function resetClear()
    local w = History.frame
    w.confirming = false
    w.clear.label:SetText(L.CLEAR)
end

local function clear()
    local w = History.frame
    if w.confirming then
        Recorder.Clear()
        resetClear()
        History.Refresh()
        return
    end
    w.confirming = true
    w.clear.label:SetText(L.CLEAR_CONFIRM)
    C_Timer.After(CONFIRM_SECONDS, function()
        if w.confirming then
            resetClear()
        end
    end)
end

local function create()
    local w = Widgets.Window("EternityUILootHistory", L.HISTORY, true)
    History.frame = w
    w:SetSize(640, 520)
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
    -- See the loot window: keys can't pass through a window opened in combat.
    w:HookScript("OnShow", function(frame)
        frame:EnableKeyboard(not InCombatLockdown())
        History.Refresh()
    end)
    w:HookScript("OnHide", function()
        Widgets.CloseMenu()
    end)

    local bar = CreateFrame("Frame", nil, w.body)
    bar:SetPoint("TOPLEFT", 10, 0)
    bar:SetPoint("TOPRIGHT", -10, 0)
    bar:SetHeight(TOOLBAR)

    w.period = filterButton(bar, function(self)
        menu(self, "period", PERIODS, function(period)
            return L["PERIOD_" .. period]
        end)
    end)
    w.period:SetWidth(100)
    w.period:SetPoint("RIGHT")
    w.character = filterButton(bar, function(self)
        local values = { "all" }
        for _, character in ipairs(Recorder.Characters()) do
            values[#values + 1] = character
        end
        menu(self, "character", values, characterName)
    end)
    w.character:SetWidth(130)
    w.character:SetPoint("RIGHT", w.period, "LEFT", -6, 0)
    w.character.label:SetWidth(118)
    w.character.label:SetWordWrap(false)
    w.quality = filterButton(bar, function(self)
        menu(self, "quality", QUALITIES, qualityName)
    end)
    w.quality:SetWidth(120)
    w.quality:SetPoint("RIGHT", w.character, "LEFT", -6, 0)
    w.kind = filterButton(bar, function(self)
        menu(self, "kind", KINDS, kindName)
    end)
    w.kind:SetWidth(90)
    w.kind:SetPoint("RIGHT", w.quality, "LEFT", -6, 0)
    w.search = Widgets.Input(bar, nil, L.SEARCH)
    w.search:SetMaxLetters(60)
    w.search:SetHeight(28)
    w.search:SetPoint("LEFT")
    w.search:SetPoint("RIGHT", w.kind, "LEFT", -6, 0)
    w.search:HookScript("OnTextChanged", function(box, userInput)
        if userInput then
            pick("text", box:GetText())
        end
    end)

    w.scroll = Widgets.Scroll(w.body)
    w.scroll:SetPoint("TOPLEFT", 10, -TOOLBAR)
    w.scroll:SetPoint("BOTTOMRIGHT", -10, 4)
    w.scroll:HookScript("OnVerticalScroll", History.DrawRows)
    w.scroll:HookScript("OnMouseWheel", History.DrawRows)
    w.scroll:HookScript("OnSizeChanged", History.DrawRows)
    w.empty = Widgets.Text(w.body, 14, "muted")
    w.empty:SetPoint("CENTER")
    w.empty:SetText(L.EMPTY)

    w.summary = Widgets.Text(w.footer, 13, "muted")
    w.summary:SetPoint("LEFT", 12, 0)
    w.clear = Widgets.Button(w.footer, L.CLEAR, "danger", clear)
    w.clear:SetHeight(28)
    w.clear:SetPoint("RIGHT", -10, 0)
    label()
end

local function register()
    if not E.Mover.elements[KEY] then
        E.Mover.Register({
            key = KEY,
            owner = addonName,
            label = L.HISTORY,
            frame = History.frame,
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
function History.Toggle()
    Recorder.Bind()
    if not History.frame then
        create()
    end
    register()
    History.frame:SetShown(not History.frame:IsShown())
end

--- A new entry came in: redrawn at most once per frame, because loot comes in bursts.
function History.Schedule()
    if History.scheduled or not (History.frame and History.frame:IsShown()) then
        return
    end
    History.scheduled = true
    C_Timer.After(0, function()
        History.scheduled = false
        History.Refresh()
    end)
end

function History.Stop()
    if History.frame then
        History.frame:Hide()
    end
end
