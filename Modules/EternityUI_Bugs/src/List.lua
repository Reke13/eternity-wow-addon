-- The module's "Errors" tab in the options: errors on the left, newest first, and the chosen
-- one on the right in full (message, stack and locals) in a text box that can be selected and
-- copied. It fills the tab's height and scrolls inside. Every login and /reload is a new session,
-- so the list shows every session unless another is picked; the pick is saved (EternityUIBugsDB),
-- the text search lasts until the /reload.

---@type string, EternityUIBugsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, Widgets = E.Theme, E.Widgets
local L, Recorder, opt = ns.L, ns.Recorder, ns.opt

local TAB = "list"
local ROW = 42
local LIST_WIDTH = 280
local BAR = 28
local GAP = 8
local CONFIRM_SECONDS = 4
local SESSIONS = { "current", "previous", "all" }
local KIND_COLORS = {
    error = { 1, 0.42, 0.42, 1 },
    warning = { 0.98, 0.76, 0.32, 1 },
    blocked = { 0.62, 0.7, 1, 1 },
}

---@class EternityUIBugsList
---@field TAB string the tab's key
---@field frame table? the tab's view, once the options built it
---@field view EternityUIBugsEntry[]
---@field selected EternityUIBugsEntry?
local List = {
    TAB = TAB,
    rows = {},
    view = {},
    filter = { text = "", session = "all" },
}
ns.List = List

--- True if `session` is one of the list's session filters.
---@param session any
local function knownSession(session)
    for _, known in ipairs(SESSIONS) do
        if known == session then
            return true
        end
    end
    return false
end

--- The session filter saved with the log ("all" when none or unknown).
---@return string
function List.SavedSession()
    Recorder.Bind()
    local saved = Recorder.db.listSession
    return knownSession(saved) and saved or "all"
end

--- Picks the session filter and saves it with the log.
---@param session string
function List.SetSession(session)
    if not knownSession(session) then
        return
    end
    Recorder.Bind()
    List.filter.session = session
    Recorder.db.listSession = session
end

local function firstLine(text)
    return (text:match("^[^\n]*") or text)
end

--- The errors the filter lets through, newest first.
---@param errors EternityUIBugsEntry[] oldest first
---@param filter table
---@param session integer this login's session
---@return EternityUIBugsEntry[]
function List.Filter(errors, filter, session)
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
function List.Describe(entry)
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
    local v = List.frame
    local entry = List.selected
    local text = entry and List.Describe(entry) or ""
    v.detailText = text
    v.detail:SetText(text)
    v.nothing:SetShown(entry == nil and #List.view > 0)
    v.delete:SetEnabled(entry ~= nil)
    v.copy:SetEnabled(entry ~= nil)
    -- The box grows with its text; a hidden string of the same font and width measures it.
    local width = math.max(v.detailScroll.child:GetWidth(), 100)
    v.measure:SetWidth(width)
    v.measure:SetText(text)
    local height = v.measure:GetStringHeight() + 20
    v.detail:SetSize(width, height)
    v.detailScroll:SetContentHeight(height)
    v.detailScroll:ScrollTo(0)
end

-- The list --------------------------------------------------------------------------------------

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
    row:SetScript("OnEnter", function(self)
        self.hover:SetShown(self.entry ~= nil)
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
    end)
    row:SetScript("OnClick", function(self)
        List.selected = self.entry
        List.DrawRows()
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
    row.selected:SetShown(entry == List.selected)
end

--- Fills the rows in view; only those exist.
function List.DrawRows()
    local scroll = List.frame.list
    local first = math.floor(scroll:GetVerticalScroll() / ROW)
    local needed = math.ceil(scroll:GetHeight() / ROW) + 1
    for i = 1, math.max(needed, #List.rows) do
        local row = List.rows[i]
        local index = first + i
        local entry = i <= needed and List.view[index] or nil
        if entry and not row then
            row = newRow(scroll.child)
            List.rows[i] = row
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
function List.Refresh()
    local v = List.frame
    if not (v and v:IsVisible()) then
        return
    end
    local session = Recorder.Session()
    local view = List.Filter(Recorder.db.errors, List.filter, session)
    List.view = view
    local stillThere = false
    for _, entry in ipairs(view) do
        if entry == List.selected then
            stillThere = true
            break
        end
    end
    if not stillThere then
        List.selected = view[1]
    end
    v.empty:SetShown(#view == 0)
    v.list:SetContentHeight(#view * ROW)
    List.DrawRows()
    showDetail()
    local current = 0
    for _, entry in ipairs(Recorder.db.errors) do
        if entry.session == session then
            current = current + 1
        end
    end
    v.summary:SetText(L.SUMMARY:format(#Recorder.db.errors, current))
    v.session.label:SetText(L["SESSION_" .. List.filter.session])
end

--- The detail's text size from the options.
function List.Apply()
    local v = List.frame
    if not v then
        return
    end
    local size = opt("list.textSize") * Theme.fontScale
    v.detail:SetFont(Theme.font, size, "")
    v.measure:SetFont(Theme.font, size, "")
    List.Refresh()
end

-- Building the tab -----------------------------------------------------------------------------

local function hint(frame, title, text)
    Widgets.AttachTooltip(frame, function(tip)
        tip:SetTitle(title)
        tip:AddLine(text, "textMuted")
    end)
end

local function clearButton(v)
    local button
    local armed = false
    button = Widgets.Button(v, L.CLEAR, "danger", function()
        if not armed then
            armed = true
            button.label:SetText(L.CLEAR_CONFIRM)
            C_Timer.After(CONFIRM_SECONDS, function()
                armed = false
                button.label:SetText(L.CLEAR)
            end)
            return
        end
        armed = false
        button.label:SetText(L.CLEAR)
        Recorder.Clear()
        List.selected = nil
        List.Refresh()
    end)
    return button
end

--- The tab's view (ModulePage's build(parent, setHeight)). It takes the height of the area the
--- options give it, so the page itself doesn't scroll: the list and the detail do.
---@param parent table
---@param setHeight fun(height: number)
---@return table view with Refresh
function List.Build(parent, setHeight)
    local v = CreateFrame("Frame", nil, parent)
    v:SetPoint("TOPLEFT")
    v:SetPoint("TOPRIGHT")
    List.frame = v
    List.filter.session = List.SavedSession()
    local area = parent:GetParent()
    local function fit()
        local height = math.max(area:GetHeight() - 4, 200)
        v:SetHeight(height)
        setHeight(height)
        if v:IsVisible() then
            List.DrawRows()
        end
    end
    area:HookScript("OnSizeChanged", fit)
    v:SetScript("OnShow", List.Refresh)

    -- Top: search and session.
    v.session = Widgets.Button(v, "", "ghost", function(self)
        local entries = {}
        for i, session in ipairs(SESSIONS) do
            entries[i] = {
                text = L["SESSION_" .. session],
                onClick = function()
                    List.SetSession(session)
                    v.list:ScrollTo(0)
                    List.Refresh()
                end,
            }
        end
        Widgets.Menu(self, entries, 180)
    end)
    v.session:SetSize(150, BAR)
    v.session:SetPoint("TOPRIGHT", 0, -GAP)
    v.search = Widgets.Input(v, nil, L.SEARCH)
    v.search:SetMaxLetters(60)
    v.search:SetHeight(BAR)
    v.search:SetPoint("TOPLEFT", 0, -GAP)
    v.search:SetPoint("RIGHT", v.session, "LEFT", -6, 0)
    v.search:HookScript("OnTextChanged", function(box, userInput)
        if userInput then
            List.filter.text = box:GetText()
            v.list:ScrollTo(0)
            List.Refresh()
        end
    end)

    -- Bottom: summary and buttons.
    v.clear = clearButton(v)
    v.clear:SetHeight(BAR)
    v.clear:SetPoint("BOTTOMRIGHT")
    v.delete = Widgets.Button(v, L.DELETE, "ghost", function()
        if List.selected then
            Recorder.Remove(List.selected)
            List.selected = nil
            List.Refresh()
        end
    end)
    v.delete:SetHeight(BAR)
    v.delete:SetPoint("RIGHT", v.clear, "LEFT", -6, 0)
    v.copy = Widgets.Button(v, L.COPY, "primary", function()
        v.detail:SetFocus()
        v.detail:HighlightText()
    end)
    v.copy:SetHeight(BAR)
    v.copy:SetPoint("RIGHT", v.delete, "LEFT", -6, 0)
    hint(v.copy, L.COPY, L.COPY_HINT)
    v.summary = Widgets.Text(v, 13, "muted")
    v.summary:SetPoint("BOTTOMLEFT", 0, 8)

    -- Middle: the list and the chosen error.
    local top, bottom = -(GAP + BAR + GAP), BAR + GAP
    v.list = Widgets.Scroll(v)
    v.list:SetPoint("TOPLEFT", 0, top)
    v.list:SetPoint("BOTTOMLEFT", 0, bottom)
    v.list:SetWidth(LIST_WIDTH)
    v.list:HookScript("OnVerticalScroll", List.DrawRows)
    v.list:HookScript("OnMouseWheel", List.DrawRows)
    v.list:HookScript("OnSizeChanged", List.DrawRows)
    v.empty = Widgets.Text(v, 14, "muted")
    v.empty:SetPoint("CENTER")
    v.empty:SetText(L.EMPTY)

    local divider = Widgets.Rect(v, Theme.colors.line)
    divider:SetPoint("TOPLEFT", v.list, "TOPRIGHT", 8, 0)
    divider:SetPoint("BOTTOMLEFT", v.list, "BOTTOMRIGHT", 8, 0)
    divider:SetWidth(1)

    v.detailScroll = Widgets.Scroll(v)
    v.detailScroll:SetPoint("TOPLEFT", v.list, "TOPRIGHT", 18, 0)
    v.detailScroll:SetPoint("BOTTOMRIGHT", 0, bottom)
    v.detailScroll:HookScript("OnSizeChanged", function()
        if v:IsVisible() then
            showDetail()
        end
    end)
    v.detail = CreateFrame("EditBox", nil, v.detailScroll.child)
    v.detail:SetMultiLine(true)
    v.detail:SetAutoFocus(false)
    v.detail:SetPoint("TOPLEFT")
    v.detail:SetTextInsets(0, 0, 0, 0)
    v.detail:SetFont(Theme.font, opt("list.textSize") * Theme.fontScale, "")
    v.detail:SetTextColor(0.92, 0.92, 0.94, 1)
    v.detail:SetScript("OnEscapePressed", v.detail.ClearFocus)
    -- Read only: whatever is typed goes back to the error's text.
    v.detail:SetScript("OnTextChanged", function(box, userInput)
        if userInput then
            box:SetText(v.detailText or "")
        end
    end)
    v:HookScript("OnHide", function()
        v.detail:ClearFocus()
    end)
    v.measure = v.detailScroll.child:CreateFontString(nil, "OVERLAY")
    v.measure:SetFont(Theme.font, opt("list.textSize") * Theme.fontScale, "")
    v.measure:SetPoint("TOPLEFT")
    v.measure:SetJustifyH("LEFT")
    v.measure:SetAlpha(0)
    v.nothing = Widgets.Text(v, 14, "muted")
    v.nothing:SetPoint("CENTER", v.detailScroll, "CENTER")
    v.nothing:SetText(L.NOTHING_SELECTED)

    fit()
    v.Refresh = List.Refresh
    return v
end

--- Opens the options on this tab, on the newest error.
function List.Open()
    List.selected = nil
    E:OpenOptions(addonName, TAB)
end

--- Whether the tab is on screen.
---@return boolean
function List.IsShown()
    return List.frame ~= nil and List.frame:IsVisible()
end

--- Errors come in bursts: redrawn at most once per frame, and only while the tab is open.
function List.Schedule()
    if List.scheduled or not List.IsShown() then
        return
    end
    List.scheduled = true
    C_Timer.After(0, function()
        List.scheduled = false
        List.Refresh()
    end)
end
