-- The list window: errors on the left, newest first, and the chosen one on the right in full
-- (message, stack and locals) in a text box that can be selected and copied. Filters last until
-- the /reload.

---@type string, EternityUIBugsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, Widgets = E.Theme, E.Widgets
local L, Recorder, opt = ns.L, ns.Recorder, ns.opt

local KEY = addonName .. ".window"
local ROW = 42
local LIST_WIDTH = 300
local TOOLBAR = 44
local CONFIRM_SECONDS = 4
local SESSIONS = { "current", "previous", "all" }
local KIND_COLORS = {
    error = { 1, 0.42, 0.42, 1 },
    warning = { 0.98, 0.76, 0.32, 1 },
    blocked = { 0.62, 0.7, 1, 1 },
}

---@class EternityUIBugsWindow
---@field frame table?
---@field view EternityUIBugsEntry[]
---@field selected EternityUIBugsEntry?
local Window = {
    rows = {},
    view = {},
    filter = { text = "", session = "current" },
}
ns.Window = Window

local function firstLine(text)
    return (text:match("^[^\n]*") or text)
end

--- The errors the filter lets through, newest first.
---@param errors EternityUIBugsEntry[] oldest first
---@param filter table
---@param session integer this login's session
---@return EternityUIBugsEntry[]
function Window.Filter(errors, filter, session)
    local view = {}
    local needle = filter.text ~= "" and filter.text:lower() or nil
    for i = #errors, 1, -1 do
        local entry = errors[i]
        local inSession = filter.session == "all"
            or (filter.session == "current" and entry.session == session)
            or (filter.session == "previous" and entry.session == session - 1)
        if inSession and (not needle or (entry.message .. "\n" .. entry.stack):lower():find(needle, 1, true)) then
            view[#view + 1] = entry
        end
    end
    return view
end

--- The full text of an error, as it's shown and copied.
---@param entry EternityUIBugsEntry
---@return string
function Window.Describe(entry)
    local parts = {
        entry.message,
        "",
        ("%s: %s · %s: %d · %s: %d · %s"):format(
            L.DATE,
            date("%Y-%m-%d %H:%M:%S", entry.time),
            L.COUNT,
            entry.count,
            L.SESSION,
            entry.session,
            L["KIND_" .. entry.kind] or entry.kind
        ),
    }
    if entry.stack ~= "" then
        parts[#parts + 1] = ""
        parts[#parts + 1] = L.STACK .. ":"
        parts[#parts + 1] = entry.stack
    end
    if entry.locals and entry.locals ~= "" then
        parts[#parts + 1] = ""
        parts[#parts + 1] = L.LOCALS .. ":"
        parts[#parts + 1] = entry.locals
    end
    return table.concat(parts, "\n")
end

-- The detail box -------------------------------------------------------------------------------

local function showDetail()
    local w = Window.frame
    local entry = Window.selected
    local text = entry and Window.Describe(entry) or ""
    w.detailText = text
    w.detail:SetText(text)
    w.nothing:SetShown(entry == nil)
    w.delete:SetEnabled(entry ~= nil)
    w.copy:SetEnabled(entry ~= nil)
    -- The box grows with its text; a hidden string of the same font and width measures it.
    local width = math.max(w.detailScroll.child:GetWidth(), 100)
    w.measure:SetWidth(width)
    w.measure:SetText(text)
    local height = w.measure:GetStringHeight() + 20
    w.detail:SetSize(width, height)
    w.detailScroll:SetContentHeight(height)
    w.detailScroll:ScrollTo(0)
end

-- The list --------------------------------------------------------------------------------------

local function onEnter(row)
    row.hover:SetShown(row.entry ~= nil)
end

local function onLeave(row)
    row.hover:Hide()
end

local function newRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.mark = row:CreateTexture(nil, "BORDER")
    row.mark:SetPoint("TOPLEFT")
    row.mark:SetPoint("BOTTOMLEFT")
    row.mark:SetWidth(3)
    row.selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.selected:SetAllPoints()
    function row:Paint()
        local c = Theme.colors.hover
        self.hover:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        local a = Theme.accent
        self.selected:SetColorTexture(a[1], a[2], a[3], 0.18)
    end
    row.message = Widgets.Text(row, 13, "text")
    row.message:SetPoint("TOPLEFT", 10, -6)
    row.message:SetPoint("TOPRIGHT", -6, -6)
    row.message:SetJustifyH("LEFT")
    row.message:SetWordWrap(false)
    row.detail = Widgets.Text(row, 11, "muted")
    row.detail:SetPoint("BOTTOMLEFT", 10, 6)
    row.detail:SetPoint("BOTTOMRIGHT", -6, 6)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    row:SetScript("OnClick", function(self)
        Window.selected = self.entry
        Window.DrawRows()
        showDetail()
    end)
    return Widgets.Track(row)
end

local function fill(row, entry)
    row.entry = entry
    local color = KIND_COLORS[entry.kind] or KIND_COLORS.error
    row.mark:SetColorTexture(color[1], color[2], color[3], color[4])
    row.message:SetText(firstLine(entry.message))
    local today = date("%Y-%m-%d") == date("%Y-%m-%d", entry.time)
    local when = date(today and "%H:%M" or "%Y-%m-%d %H:%M", entry.time)
    row.detail:SetText(("x%d · %s · %s"):format(entry.count, when, L["KIND_" .. entry.kind] or entry.kind))
    row.selected:SetShown(entry == Window.selected)
end

--- Fills the rows in view; only those exist.
function Window.DrawRows()
    local scroll = Window.frame.list
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

--- Applies the filters and redraws. The chosen error stays chosen while it's in view.
function Window.Refresh()
    local w = Window.frame
    if not (w and w:IsShown()) then
        return
    end
    Recorder.Bind()
    local session = Recorder.Session()
    local view = Window.Filter(Recorder.db.errors, Window.filter, session)
    Window.view = view
    local stillThere = false
    for _, entry in ipairs(view) do
        if entry == Window.selected then
            stillThere = true
            break
        end
    end
    if not stillThere then
        Window.selected = view[1]
    end
    w.empty:SetShown(#view == 0)
    w.list:SetContentHeight(#view * ROW)
    Window.DrawRows()
    showDetail()
    local current = 0
    for _, entry in ipairs(Recorder.db.errors) do
        if entry.session == session then
            current = current + 1
        end
    end
    w.summary:SetText(L.SUMMARY:format(#Recorder.db.errors, current))
    w.session.label:SetText(L["SESSION_" .. Window.filter.session])
end

-- Footer buttons --------------------------------------------------------------------------------

local function resetClear()
    local w = Window.frame
    w.confirming = false
    w.clear.label:SetText(L.CLEAR)
end

local function clear()
    local w = Window.frame
    if w.confirming then
        Recorder.Clear()
        resetClear()
        Window.selected = nil
        Window.Refresh()
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

local function hint(frame, title, text)
    Widgets.AttachTooltip(frame, function(tip)
        tip:SetTitle(title)
        tip:AddLine(text, "textMuted")
    end)
end

--- Size, scale and opacity from the options.
function Window.Apply()
    local w = Window.frame
    if not w then
        return
    end
    w:SetScale(opt("window.scale"))
    w:Paint()
    local size = opt("window.textSize")
    w.detail:SetFont(Theme.font, size * Theme.fontScale, "")
    w.measure:SetFont(Theme.font, size * Theme.fontScale, "")
    if w:IsShown() then
        Window.Refresh()
    end
end

local function create()
    local w = Widgets.Window("EternityUIBugsWindow", L.TITLE, true)
    Window.frame = w
    w:SetSize(860, 520)
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
    -- Keys can't pass through a window opened in combat (see the core's Window).
    w:HookScript("OnShow", function(frame)
        frame:EnableKeyboard(not InCombatLockdown())
        Window.Refresh()
    end)
    w:HookScript("OnHide", function()
        Widgets.CloseMenu()
        w.detail:ClearFocus()
    end)
    function w.onPaint(frame)
        frame.shape.fill:SetAlpha(opt("window.opacity"))
    end

    local bar = CreateFrame("Frame", nil, w.body)
    bar:SetPoint("TOPLEFT", 10, 0)
    bar:SetPoint("TOPRIGHT", -10, 0)
    bar:SetHeight(TOOLBAR)
    w.session = Widgets.Button(bar, "", "ghost", function(self)
        local entries = {}
        for i, session in ipairs(SESSIONS) do
            entries[i] = {
                text = L["SESSION_" .. session],
                onClick = function()
                    Window.filter.session = session
                    w.list:ScrollTo(0)
                    Window.Refresh()
                end,
            }
        end
        Widgets.Menu(self, entries, 180)
    end)
    w.session:SetSize(150, 28)
    w.session:SetPoint("RIGHT")
    w.search = Widgets.Input(bar, nil, L.SEARCH)
    w.search:SetMaxLetters(60)
    w.search:SetHeight(28)
    w.search:SetPoint("LEFT")
    w.search:SetPoint("RIGHT", w.session, "LEFT", -6, 0)
    w.search:HookScript("OnTextChanged", function(box, userInput)
        if userInput then
            Window.filter.text = box:GetText()
            w.list:ScrollTo(0)
            Window.Refresh()
        end
    end)

    w.list = Widgets.Scroll(w.body)
    w.list:SetPoint("TOPLEFT", 10, -TOOLBAR)
    w.list:SetPoint("BOTTOMLEFT", 10, 4)
    w.list:SetWidth(LIST_WIDTH)
    w.list:HookScript("OnVerticalScroll", Window.DrawRows)
    w.list:HookScript("OnMouseWheel", Window.DrawRows)
    w.list:HookScript("OnSizeChanged", Window.DrawRows)
    w.empty = Widgets.Text(w.body, 14, "muted")
    w.empty:SetPoint("CENTER", w.list, "CENTER")
    w.empty:SetText(L.EMPTY)

    local divider = Widgets.Rect(w.body, Theme.colors.line)
    divider:SetPoint("TOPLEFT", w.list, "TOPRIGHT", 8, 0)
    divider:SetPoint("BOTTOMLEFT", w.list, "BOTTOMRIGHT", 8, 0)
    divider:SetWidth(1)

    w.detailScroll = Widgets.Scroll(w.body)
    w.detailScroll:SetPoint("TOPLEFT", w.list, "TOPRIGHT", 18, 0)
    w.detailScroll:SetPoint("BOTTOMRIGHT", -10, 4)
    w.detail = CreateFrame("EditBox", nil, w.detailScroll.child)
    w.detail:SetMultiLine(true)
    w.detail:SetAutoFocus(false)
    w.detail:SetPoint("TOPLEFT")
    w.detail:SetTextInsets(0, 0, 0, 0)
    w.detail:SetFont(Theme.font, opt("window.textSize") * Theme.fontScale, "")
    w.detail:SetTextColor(0.92, 0.92, 0.94, 1)
    w.detail:SetScript("OnEscapePressed", w.detail.ClearFocus)
    -- Read only: whatever is typed goes back to the error's text.
    w.detail:SetScript("OnTextChanged", function(box, userInput)
        if userInput then
            box:SetText(w.detailText or "")
        end
    end)
    w.measure = w.detailScroll.child:CreateFontString(nil, "OVERLAY")
    w.measure:SetFont(Theme.font, opt("window.textSize") * Theme.fontScale, "")
    w.measure:SetPoint("TOPLEFT")
    w.measure:SetJustifyH("LEFT")
    w.measure:SetAlpha(0)
    w.nothing = Widgets.Text(w.body, 14, "muted")
    w.nothing:SetPoint("CENTER", w.detailScroll, "CENTER")
    w.nothing:SetText(L.NOTHING_SELECTED)

    w.summary = Widgets.Text(w.footer, 13, "muted")
    w.summary:SetPoint("LEFT", 12, 0)
    w.clear = Widgets.Button(w.footer, L.CLEAR, "danger", clear)
    w.clear:SetHeight(28)
    w.clear:SetPoint("RIGHT", -10, 0)
    w.delete = Widgets.Button(w.footer, L.DELETE, "ghost", function()
        if Window.selected then
            Recorder.Remove(Window.selected)
            Window.selected = nil
            Window.Refresh()
        end
    end)
    w.delete:SetHeight(28)
    w.delete:SetPoint("RIGHT", w.clear, "LEFT", -6, 0)
    w.copy = Widgets.Button(w.footer, L.COPY, "primary", function()
        w.detail:SetFocus()
        w.detail:HighlightText()
    end)
    w.copy:SetHeight(28)
    w.copy:SetPoint("RIGHT", w.delete, "LEFT", -6, 0)
    hint(w.copy, L.COPY, L.COPY_HINT)
    Window.Apply()
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

--- Opens the window (on the newest error).
function Window.Open()
    if not Window.frame then
        create()
    end
    register()
    Window.selected = nil
    Window.frame:Show()
    Window.Refresh()
end

--- Opens or closes the window.
function Window.Toggle()
    if Window.frame and Window.frame:IsShown() then
        Window.frame:Hide()
    else
        Window.Open()
    end
end

--- Errors come in bursts: redrawn at most once per frame.
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
        if E.Mover.elements[KEY] then
            E.Mover.Unregister(KEY)
        end
    end
end
