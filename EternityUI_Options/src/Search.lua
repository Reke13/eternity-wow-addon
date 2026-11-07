-- The search box of the options window. Pages build on first view, so it searches what they
-- declare (page.Entries), not their rows: every option's label, description, group and choices.
-- Results take the page's place until a result or another page is picked. Tabs that draw themselves
-- have no schema: only the tab is found, not what's inside it.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Theme = E.Theme
local Widgets = E.Widgets
local Window = ns.Window

local RESULT = 50
local MAX_SHOWN = 40
local FLASH_SECONDS = 1.5

local Search = { rows = {} }
ns.Search = Search
Window.Search = Search

-- string.lower leaves multibyte letters alone, so these are folded by hand.
local FOLD = {}
for plain, letters in pairs({
    a = "áàâäÁÀÂÄ",
    e = "éèêëÉÈÊË",
    i = "íìîïÍÌÎÏ",
    o = "óòôöÓÒÔÖ",
    u = "úùûüÚÙÛÜ",
    n = "ñÑ",
    c = "çÇ",
}) do
    for letter in letters:gmatch("[\192-\255][\128-\191]*") do
        FOLD[letter] = plain
    end
end

--- Lower case, without accents or color codes.
---@param text string
---@return string
function Search.Fold(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower():gsub("\195[\128-\191]", FOLD))
end

local function buildIndex()
    local index = {}
    for _, page in ipairs(Window.pages) do
        index[#index + 1] = {
            page = page,
            label = page.title,
            where = L.SEARCH_PAGE,
            folded = Search.Fold(page.title),
            haystack = Search.Fold(page.title .. " " .. page.note),
        }
        for _, entry in ipairs(page.Entries and page.Entries() or {}) do
            entry.page = page
            entry.where = entry.where and (page.title .. " > " .. entry.where) or page.title
            entry.folded = Search.Fold(entry.label)
            entry.haystack = Search.Fold(entry.label .. " " .. page.title .. " " .. (entry.extra or ""))
            index[#index + 1] = entry
        end
    end
    return index
end

--- What matches a text: every word must appear. Options whose label matches come first.
---@param text string
---@return table[]? results nil for an empty search
function Search.Find(text)
    local query = Search.Fold(text):gsub("^%s+", ""):gsub("%s+$", "")
    local words = {}
    for word in query:gmatch("%S+") do
        words[#words + 1] = word
    end
    if #words == 0 then
        return nil
    end
    Search.index = Search.index or buildIndex()
    local found = {}
    for position, entry in ipairs(Search.index) do
        local matches, inLabel = true, true
        for _, word in ipairs(words) do
            matches = matches and entry.haystack:find(word, 1, true) ~= nil
            inLabel = inLabel and entry.folded:find(word, 1, true) ~= nil
        end
        if matches then
            local rank = entry.folded:find(query, 1, true) == 1 and 1 or (inLabel and 2 or 3)
            found[#found + 1] = { entry = entry, rank = rank, position = position }
        end
    end
    table.sort(found, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.position < b.position
    end)
    for i, item in ipairs(found) do
        found[i] = item.entry
    end
    return found
end

--- Opens a result: its page, tab and picked group, then the option itself.
---@param entry table
function Search.Open(entry)
    local page = entry.page
    Window.Open(page.key, entry.tab, entry.view)
    if entry.path and page.Reveal then
        page.Reveal(entry.path)
    end
end

--- Marks a row for a moment.
---@param row table
function Search.Flash(row)
    if not row.searchFlash then
        row.searchFlash = row:CreateTexture(nil, "BACKGROUND")
        row.searchFlash:SetAllPoints()
    end
    local accent = Theme.accent
    -- Opacity goes in the color: SetAlpha would replace it.
    row.searchFlash:SetColorTexture(accent[1], accent[2], accent[3], 0.25)
    row.searchFlash:Show()
    row.searchFlashes = (row.searchFlashes or 0) + 1
    local flash = row.searchFlashes
    C_Timer.After(FLASH_SECONDS, function()
        if row.searchFlashes == flash then
            row.searchFlash:Hide()
        end
    end)
end

local function resultRow(index)
    local row = Search.rows[index]
    if row then
        return row
    end
    local button
    button = Widgets.Button(Search.frame.child, "", "nav", function()
        Search.Open(button.entry)
    end)
    button:SetHeight(RESULT - 2)
    button:SetPoint("TOPLEFT", 0, -(index - 1) * RESULT)
    button:SetPoint("TOPRIGHT", 0, -(index - 1) * RESULT)
    button.label:ClearAllPoints()
    button.label:SetPoint("TOPLEFT", 10, -8)
    button.label:SetPoint("TOPRIGHT", -10, -8)
    button.label:SetJustifyH("LEFT")
    button.label:SetWordWrap(false)
    button.where = Widgets.Text(button, 12, "muted")
    button.where:SetPoint("TOPLEFT", 10, -28)
    button.where:SetPoint("TOPRIGHT", -10, -28)
    button.where:SetJustifyH("LEFT")
    button.where:SetWordWrap(false)
    Search.rows[index] = button
    return button
end

local function draw(results)
    local shown = math.min(#results, MAX_SHOWN)
    for i = 1, shown do
        local row = resultRow(i)
        row.entry = results[i]
        row.label:SetText(results[i].label)
        row.where:SetText(results[i].where)
        row:Show()
    end
    for i = shown + 1, #Search.rows do
        Search.rows[i]:Hide()
    end
    Search.frame:SetContentHeight(shown * RESULT)
    Search.frame:ScrollTo(0)
end

--- Shows the results for a text, or goes back to the page when it's empty.
---@param text string
function Search.Update(text)
    local results = Search.Find(text)
    if not results then
        if Search.active then
            Window.Show(Window.current)
        end
        return
    end
    Search.active = true
    Search.results = results
    for _, page in ipairs(Window.pages) do
        if page.frame then
            page.frame:Hide()
        end
        page.nav:SetActive(false)
    end
    Search.frame:Show()
    Window.SetHeader(L.SEARCH_TITLE, #results > 0 and L.SEARCH_COUNT:format(#results) or L.SEARCH_NONE:format(text))
    draw(results)
end

--- Leaves the results and empties the box.
function Search.Close()
    Search.active = false
    if Search.box then
        Search.frame:Hide()
        if Search.box:GetText() ~= "" then
            Search.box:SetText("")
        end
    end
end

--- Takes the keyboard back from the box.
function Search.Blur()
    if Search.box then
        Search.box:ClearFocus()
    end
end

--- The box and, inside the window's body, the results.
---@param sidebar table
---@param body table
---@return table box
function Search.Build(sidebar, body)
    Search.frame = Widgets.Scroll(body)
    Search.frame:SetAllPoints()
    Search.frame:Hide()

    local box = Widgets.Input(sidebar, function()
        local first = Search.results and Search.active and Search.results[1]
        if first then
            Search.Open(first)
        end
    end, L.SEARCH)
    box:HookScript("OnTextChanged", function(self)
        Search.Update(self:GetText())
    end)
    -- The first Esc leaves the search; only then does Esc close the window.
    box:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
        end
        self:ClearFocus()
    end)
    Search.box = box
    return box
end
