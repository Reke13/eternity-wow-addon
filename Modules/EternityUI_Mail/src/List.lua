-- The module's "History" tab in the options: letters on the left, newest first, and the chosen
-- one on the right: who (names in their class color), when, subject, gold with its coins, and one
-- row per item (icon, name in its quality color, the item's tooltip on hover, Shift-click links
-- it). Copy turns the detail into a text box that can be selected and copied. Hovering a letter
-- in the list shows it in a tooltip. Filters: sent or received, every character or this one, and
-- a search over names, subject and items. The tab fills the options' height; the list and the
-- detail scroll.

---@type string, EternityUIMailNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, Widgets = E.Theme, E.Widgets
local L, History, Classes = ns.L, ns.History, ns.Classes

local TAB = "history"
local ROW = 42
local LIST_WIDTH = 300
local BAR = 28
local GAP = 8
local CONFIRM_SECONDS = 4
local TEXT_SIZE = 13
local ITEM_ROW = 26
local ITEM_ICON = 22
local KINDS = { "all", "sent", "received" }
local CHARS = { "all", "current" }
local KIND_COLORS = {
    sent = { 0.45, 0.7, 1, 1 },
    received = { 0.4, 0.85, 0.5, 1 },
}

---@class EternityUIMailList
---@field TAB string the tab's key
---@field frame table? the tab's view, once the options built it
---@field view EternityUIMailEntry[]
---@field selected EternityUIMailEntry?
---@field copying boolean? the detail shows the letter as text to copy
local List = {
    TAB = TAB,
    rows = {},
    itemRows = {},
    view = {},
    filter = { text = "", kind = "all", chars = "all" },
}
ns.List = List

-- Texts ----------------------------------------------------------------------------------------

--- Copper as "12g 3s 40c" (only the parts there are): the copied text.
---@param copper integer
---@return string
function List.Money(copper)
    copper = math.floor(copper or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest = copper % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. L.GOLD
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. L.SILVER
    end
    if rest > 0 or #parts == 0 then
        parts[#parts + 1] = rest .. L.COPPER
    end
    return table.concat(parts, " ")
end

--- Copper with the coin icons, as the game shows it.
---@param copper integer
---@return string
function List.Coins(copper)
    if GetCoinTextureString then
        local ok, coins = pcall(GetCoinTextureString, math.floor(copper or 0))
        if ok and type(coins) == "string" then
            return coins
        end
    end
    return List.Money(copper)
end

local function itemName(item)
    if item.name and item.name ~= "" then
        return item.name
    end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item.id)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return L.ITEM_N:format(item.id)
end

local function itemQuality(item)
    if type(item.quality) == "number" then
        return item.quality
    end
    local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(item.id)
    return type(quality) == "number" and quality or nil
end

--- An item's name in its quality color.
---@param item EternityUIMailItem
---@return string
function List.ItemText(item)
    local name = itemName(item)
    local quality = itemQuality(item)
    local hex
    if quality and C_Item and C_Item.GetItemQualityColor then
        hex = select(4, C_Item.GetItemQualityColor(quality))
    end
    if type(hex) ~= "string" and quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality] then
        local color = _G.ITEM_QUALITY_COLORS[quality]
        hex = color.hex and color.hex:gsub("^|c", "")
    end
    if type(hex) == "string" and hex ~= "" then
        return "|c" .. hex .. name .. "|r"
    end
    return name
end

local function itemIcon(item)
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.id)
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function itemCount(entry)
    local total = 0
    for _, item in ipairs(entry.items) do
        total = total + item.count
    end
    return total
end

local function when(entry)
    return date("%Y-%m-%d %H:%M", entry.time)
end

--- The other person and the character, each in its class color.
---@param entry EternityUIMailEntry
---@return string other
---@return string char
function List.Names(entry)
    return Classes.Color(entry.other, entry.otherClass), Classes.Color(entry.char, entry.charClass)
end

--- The heading of a letter: "Sent to X" / "Received from X", X in its class color.
---@param entry EternityUIMailEntry
---@return string
function List.Heading(entry)
    local other = List.Names(entry)
    return (entry.kind == "sent" and L.SENT_TITLE or L.RECEIVED_TITLE):format(other)
end

--- The letter's lines under the heading, colored: character, date, subject, gold.
---@param entry EternityUIMailEntry
---@return string
function List.Info(entry)
    local _, char = List.Names(entry)
    local label = "|cffa3a3b8%s:|r %s"
    local lines = {
        label:format(L.CHARACTER, char .. " (" .. entry.realm .. ")"),
        label:format(entry.kind == "sent" and L.DATE or L.SEEN, when(entry)),
        label:format(L.SUBJECT, entry.subject ~= "" and entry.subject or L.NO_SUBJECT),
    }
    if (entry.money or 0) > 0 then
        lines[#lines + 1] = label:format(L.MONEY, List.Coins(entry.money))
    end
    if (entry.cod or 0) > 0 then
        lines[#lines + 1] = label:format(L.COD, List.Coins(entry.cod))
    end
    if entry.returned then
        lines[#lines + 1] = "|cffff8080" .. L.RETURNED .. "|r"
    end
    return table.concat(lines, "\n")
end

--- The full text of a letter, without colors, as it's copied.
---@param entry EternityUIMailEntry
---@return string
function List.Describe(entry)
    local sent = entry.kind == "sent"
    local lines = {
        (sent and L.SENT_TITLE or L.RECEIVED_TITLE):format(entry.other),
        "",
        L.CHARACTER .. ": " .. entry.char .. " (" .. entry.realm .. ")",
        (sent and L.DATE or L.SEEN) .. ": " .. when(entry),
        L.SUBJECT .. ": " .. (entry.subject ~= "" and entry.subject or L.NO_SUBJECT),
    }
    if (entry.money or 0) > 0 then
        lines[#lines + 1] = L.MONEY .. ": " .. List.Money(entry.money)
    end
    if (entry.cod or 0) > 0 then
        lines[#lines + 1] = L.COD .. ": " .. List.Money(entry.cod)
    end
    if entry.returned then
        lines[#lines + 1] = L.RETURNED
    end
    if #entry.items > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.ITEMS .. ":"
        for _, item in ipairs(entry.items) do
            lines[#lines + 1] = "  " .. item.count .. " × " .. itemName(item)
        end
    end
    return table.concat(lines, "\n")
end

--- The two lines of a row: who and subject; when, character, items and gold.
---@param entry EternityUIMailEntry
---@return string title
---@return string detail
function List.RowTexts(entry)
    local other, char = List.Names(entry)
    local who = (entry.kind == "sent" and L.SENT_TO or L.RECEIVED_FROM):format(other)
    local title = who .. " · " .. (entry.subject ~= "" and entry.subject or L.NO_SUBJECT)
    local parts = { when(entry), char }
    local count = itemCount(entry)
    if count > 0 then
        parts[#parts + 1] = count == 1 and L.ONE_ITEM or L.N_ITEMS:format(count)
    end
    if (entry.money or 0) > 0 then
        parts[#parts + 1] = List.Coins(entry.money)
    end
    return title, table.concat(parts, " · ")
end

-- Filter ---------------------------------------------------------------------------------------

local function matches(entry, needle)
    if not needle then
        return true
    end
    local haystack = { entry.other, entry.subject, entry.char }
    for _, item in ipairs(entry.items) do
        haystack[#haystack + 1] = itemName(item)
    end
    return table.concat(haystack, "\n"):lower():find(needle, 1, true) ~= nil
end

--- The letters the filter lets through, newest first.
---@param mails EternityUIMailEntry[] oldest first
---@param filter table
---@return EternityUIMailEntry[]
function List.Filter(mails, filter)
    local view = {}
    local needle = filter.text ~= "" and filter.text:lower() or nil
    local realm, char = History.Me()
    for i = #mails, 1, -1 do
        local entry = mails[i]
        local kind = filter.kind == "all" or entry.kind == filter.kind
        local who = filter.chars == "all" or (entry.realm == realm and entry.char == char)
        if kind and who and matches(entry, needle) then
            view[#view + 1] = entry
        end
    end
    return view
end

-- Tooltips -------------------------------------------------------------------------------------

local function hideTooltip()
    GameTooltip:Hide()
end

--- The item's own tooltip, and how to link it.
local function itemTooltip(row)
    local item = row.item
    if not item then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(item.id)
    GameTooltip:AddLine(L.LINK_HINT, 0.64, 0.62, 0.72)
    GameTooltip:Show()
end

--- A letter of the list in a tooltip: who, when, subject, gold and its items.
---@param tip table GameTooltip
---@param entry EternityUIMailEntry
function List.FillTooltip(tip, entry)
    tip:AddLine(List.Heading(entry), 1, 1, 1)
    for line in (List.Info(entry) .. "\n"):gmatch("(.-)\n") do
        tip:AddLine(line, 1, 1, 1)
    end
    if #entry.items > 0 then
        tip:AddLine(" ")
        for _, item in ipairs(entry.items) do
            tip:AddLine("|T" .. itemIcon(item) .. ":0|t " .. item.count .. " × " .. List.ItemText(item), 1, 1, 1)
        end
    end
end

local function letterTooltip(row)
    if not row.entry then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    List.FillTooltip(GameTooltip, row.entry)
    GameTooltip:Show()
end

-- The detail -----------------------------------------------------------------------------------

local function newItemRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ITEM_ROW)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:Hide()
    function row:Paint()
        local c = Theme.colors.hover
        self.hover:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ITEM_ICON, ITEM_ICON)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.text = Widgets.Text(row, TEXT_SIZE, "text")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        itemTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        hideTooltip()
    end)
    row:SetScript("OnClick", function(self)
        if not (self.item and IsModifiedClick and IsModifiedClick("CHATLINK")) then
            return
        end
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local _, link = getInfo(self.item.id)
        if link and ChatEdit_InsertLink then
            ChatEdit_InsertLink(link)
        end
    end)
    return Widgets.Track(row)
end

local function showDetail()
    local v = List.frame
    local entry = List.selected
    local copying = List.copying and entry ~= nil
    v.nothing:SetShown(entry == nil and #List.view > 0)
    v.delete:SetEnabled(entry ~= nil)
    v.copy:SetEnabled(entry ~= nil)
    v.copy.label:SetText(copying and L.BACK or L.COPY)
    local width = math.max(v.detailScroll.child:GetWidth(), 100)
    local height

    -- Copy mode: the plain text in a box that can be selected.
    v.detail:SetShown(copying)
    if copying then
        local text = List.Describe(entry)
        v.detailText = text
        v.detail:SetText(text)
        v.measure:SetWidth(width)
        v.measure:SetText(text)
        height = v.measure:GetStringHeight() + 20
        v.detail:SetSize(width, height)
    end

    -- The letter: heading, lines and a row per item.
    v.heading:SetShown(entry ~= nil and not copying)
    v.info:SetShown(entry ~= nil and not copying)
    v.itemsLabel:SetShown(entry ~= nil and not copying and #entry.items > 0)
    local items = (entry and not copying) and entry.items or {}
    if entry and not copying then
        v.heading:SetWidth(width)
        v.heading:SetText(List.Heading(entry))
        v.info:SetWidth(width)
        v.info:SetText(List.Info(entry))
        local y = v.heading:GetStringHeight() + 10 + v.info:GetStringHeight()
        if #items > 0 then
            v.itemsLabel:ClearAllPoints()
            v.itemsLabel:SetPoint("TOPLEFT", 0, -(y + 16))
            y = y + 16 + v.itemsLabel:GetStringHeight() + 6
        end
        for i, item in ipairs(items) do
            local row = List.itemRows[i]
            if not row then
                row = newItemRow(v.detailScroll.child)
                List.itemRows[i] = row
            end
            row.item = item
            row.icon:SetTexture(itemIcon(item))
            row.text:SetText(item.count .. " × " .. List.ItemText(item))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetWidth(width)
            row:Show()
            y = y + ITEM_ROW
        end
        height = y + 20
    end
    for i = #items + 1, #List.itemRows do
        List.itemRows[i].item = nil
        List.itemRows[i]:Hide()
    end
    v.detailScroll:SetContentHeight(height or 0)
    v.detailScroll:ScrollTo(0)
    if copying then
        v.detail:SetFocus()
        v.detail:HighlightText()
    end
end

-- The list -------------------------------------------------------------------------------------

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
    row.title = Widgets.Text(row, 13, "text")
    row.title:SetPoint("TOPLEFT", 10, -6)
    row.title:SetPoint("TOPRIGHT", -6, -6)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.detail = Widgets.Text(row, 11, "muted")
    row.detail:SetPoint("BOTTOMLEFT", 10, 6)
    row.detail:SetPoint("BOTTOMRIGHT", -6, 6)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        self.hover:SetShown(self.entry ~= nil)
        letterTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        hideTooltip()
    end)
    row:SetScript("OnClick", function(self)
        List.selected = self.entry
        List.copying = false
        List.DrawRows()
        showDetail()
    end)
    return Widgets.Track(row)
end

local function fill(row, entry)
    row.entry = entry
    local color = KIND_COLORS[entry.kind] or KIND_COLORS.received
    row.mark:SetColorTexture(color[1], color[2], color[3], color[4])
    local title, detail = List.RowTexts(entry)
    row.title:SetText(title)
    row.detail:SetText(detail)
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

--- Applies the filters and redraws. The chosen letter stays chosen while it's in view.
function List.Refresh()
    local v = List.frame
    if not (v and v:IsVisible()) then
        return
    end
    local mails = History.Bind().mails
    local view = List.Filter(mails, List.filter)
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
        List.copying = false
    end
    v.empty:SetShown(#view == 0)
    v.list:SetContentHeight(#view * ROW)
    List.DrawRows()
    showDetail()
    local sent = 0
    for _, entry in ipairs(mails) do
        if entry.kind == "sent" then
            sent = sent + 1
        end
    end
    v.summary:SetText(L.SUMMARY:format(#mails, sent, #mails - sent))
    v.kind.label:SetText(L["KIND_" .. List.filter.kind])
    v.chars.label:SetText(L["CHARS_" .. List.filter.chars])
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
        History.Clear()
        List.selected = nil
        List.Refresh()
    end)
    return button
end

-- A filter button with a menu of its choices.
local function choiceButton(v, choices, prefix, key)
    local button = Widgets.Button(v, "", "ghost", function(self)
        local entries = {}
        for i, choice in ipairs(choices) do
            entries[i] = {
                text = L[prefix .. choice],
                onClick = function()
                    List.filter[key] = choice
                    v.list:ScrollTo(0)
                    List.Refresh()
                end,
            }
        end
        Widgets.Menu(self, entries, 190)
    end)
    button:SetSize(170, BAR)
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

    -- Top: search, kind and characters.
    v.chars = choiceButton(v, CHARS, "CHARS_", "chars")
    v.chars:SetPoint("TOPRIGHT", 0, -GAP)
    v.kind = choiceButton(v, KINDS, "KIND_", "kind")
    v.kind:SetPoint("RIGHT", v.chars, "LEFT", -6, 0)
    v.search = Widgets.Input(v, nil, L.SEARCH)
    v.search:SetMaxLetters(60)
    v.search:SetHeight(BAR)
    v.search:SetPoint("TOPLEFT", 0, -GAP)
    v.search:SetPoint("RIGHT", v.kind, "LEFT", -6, 0)
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
            History.Remove(List.selected)
            List.selected = nil
            List.Refresh()
        end
    end)
    v.delete:SetHeight(BAR)
    v.delete:SetPoint("RIGHT", v.clear, "LEFT", -6, 0)
    v.copy = Widgets.Button(v, L.COPY, "primary", function()
        List.copying = not List.copying
        showDetail()
    end)
    v.copy:SetHeight(BAR)
    v.copy:SetPoint("RIGHT", v.delete, "LEFT", -6, 0)
    hint(v.copy, L.COPY, L.COPY_HINT)
    v.summary = Widgets.Text(v, 13, "muted")
    v.summary:SetPoint("BOTTOMLEFT", 0, 8)

    -- Middle: the list and the chosen letter.
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
    local child = v.detailScroll.child

    -- The letter.
    v.heading = Widgets.Text(child, 16, "text")
    v.heading:SetPoint("TOPLEFT")
    v.heading:SetJustifyH("LEFT")
    v.info = Widgets.Text(child, TEXT_SIZE, "text")
    v.info:SetPoint("TOPLEFT", v.heading, "BOTTOMLEFT", 0, -10)
    v.info:SetJustifyH("LEFT")
    v.info:SetSpacing(4)
    v.itemsLabel = Widgets.Text(child, TEXT_SIZE, "muted")
    v.itemsLabel:SetText(L.ITEMS)

    -- Copy mode: the letter as text.
    local size = TEXT_SIZE * Theme.fontScale
    v.detail = CreateFrame("EditBox", nil, child)
    v.detail:SetMultiLine(true)
    v.detail:SetAutoFocus(false)
    v.detail:SetPoint("TOPLEFT")
    v.detail:SetTextInsets(0, 0, 0, 0)
    v.detail:SetFont(Theme.font, size, "")
    v.detail:SetTextColor(0.92, 0.92, 0.94, 1)
    v.detail:SetScript("OnEscapePressed", v.detail.ClearFocus)
    v.detail:Hide()
    -- Read only: whatever is typed goes back to the letter's text.
    v.detail:SetScript("OnTextChanged", function(box, userInput)
        if userInput then
            box:SetText(v.detailText or "")
        end
    end)
    v:HookScript("OnHide", function()
        v.detail:ClearFocus()
        List.copying = false
    end)
    v.measure = child:CreateFontString(nil, "OVERLAY")
    v.measure:SetFont(Theme.font, size, "")
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

--- Opens the options on this tab, on the newest letter.
function List.Open()
    List.selected = nil
    List.copying = false
    E:OpenOptions(addonName, TAB)
end

--- Whether the tab is on screen.
---@return boolean
function List.IsShown()
    return List.frame ~= nil and List.frame:IsVisible()
end

--- Redrawn at most once per frame, and only while the tab is open.
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
