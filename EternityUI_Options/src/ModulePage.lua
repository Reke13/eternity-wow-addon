-- A module's page, built from its schema: the Enabled switch and General, Appearance and module
-- tabs. A group's "tab" field places it; a module tab with `groups` lists them in a picker and
-- shows one at a time, with an optional live preview above (the picker goes on the left, or on
-- top with `picker = "top"`). A tab that draws itself (`build`) may name in `paths` the options
-- it sets, which then leave General and Appearance. Rows only exist for tabs that open.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Theme = E.Theme
local Widgets = E.Widgets

local ModulePage = {}
ns.ModulePage = ModulePage

local ROW = 44
local CAPTION = 30

-- visibleWhen = { [path] = value } or { [path] = { value, value } }: every path must match (one of
-- its values when there is a list).
local function matches(value, wanted)
    if type(wanted) ~= "table" then
        return value == wanted
    end
    for _, candidate in ipairs(wanted) do
        if value == candidate then
            return true
        end
    end
    return false
end

local function isVisible(module, option)
    for path, wanted in pairs(option.visibleWhen or {}) do
        if not matches(E.store:Get(module.name, path), wanted) then
            return false
        end
    end
    return true
end

local function format(option)
    local digits = option.step < 1 and (option.step < 0.1 and 2 or 1) or 0
    return function(value)
        return string.format("%." .. digits .. "f", value)
    end
end

local function newControl(parent, option, onChange)
    if option.type == "toggle" then
        return Widgets.Toggle(parent, onChange)
    elseif option.type == "range" then
        return Widgets.Slider(parent, option.min, option.max, option.step, format(option), onChange)
    elseif option.type == "select" then
        local choices = {}
        for i, entry in ipairs(option.values) do
            choices[i] = { entry.value, E.Localize(entry.label) }
        end
        return Widgets.Dropdown(parent, choices, onChange)
    elseif option.type == "color" then
        return Widgets.Color(parent, onChange)
    end
    local box = Widgets.Input(parent, onChange)
    box:SetWidth(240)
    return box
end

-- The options of a group as { path, option, advanced } entries. `advanced` on an option or on its
-- whole group: V2's Basic level hides it.
local function entriesOf(group)
    local entries = {}
    for _, option in ipairs(group.options) do
        entries[#entries + 1] = {
            path = group.id .. "." .. option.id,
            option = option,
            advanced = (option.advanced or group.advanced) and true or false,
        }
    end
    return entries
end

--- The layout the modules' pages use now: "v1" (rows) or "v2" (cards, ListV2.lua).
---@return string
function ModulePage.Version()
    return E.store:Get("EternityUI", "general.optionsVersion")
end

-- An option's control, already saving to the store.
local function controlFor(parent, page, entry)
    local path, option = entry.path, entry.option
    return newControl(parent, option, function(value)
        E.store:Set(page.module.name, path, value)
        if option.type ~= "range" then
            page.Refresh()
        elseif page.preview and page.picked then
            -- A slider changes on every step: only the live preview follows it.
            page.preview:Refresh(page.picked)
        end
    end)
end
ModulePage.Format = format

-- V1: a caption per section and one row per option.
local function fillRows(list, child, page, sections)
    for _, section in ipairs(sections) do
        local caption = Widgets.Text(child, 13, "muted")
        caption:SetText(E.Localize(section.label):upper())
        table.insert(list.items, { caption = caption })
        for _, entry in ipairs(section.entries) do
            local path, option = entry.path, entry.option
            local control = controlFor(child, page, entry)
            local label = E.Localize(option.label)
            if option.requiresReload then
                label = label .. " (/reload)"
            end
            local row = Widgets.Row(child, label, control)
            row:SetHeight(ROW)
            -- The option's description, in the "i" beside its label.
            local description = option.description and E.Localize(option.description)
            if description and description ~= "" then
                row.info = Widgets.Info(row, E.Localize(option.label), description)
                row.info:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
            end
            table.insert(list.items, { row = row, control = control, option = option, path = path })
        end
    end
end

-- (Re)makes a list's scroll and items in the layout in use. The scroll fills the list's parent and
-- keeps whether it was shown; the old one is hidden. Only the layout changes: values stay stored.
local function fillList(list)
    local shown = not list.scroll or list.scroll:IsShown()
    if list.scroll then
        list.scroll:Hide()
    end
    list.version = ModulePage.Version()
    list.scroll = Widgets.Scroll(list.parent)
    list.scroll:SetAllPoints()
    list.scroll:SetShown(shown)
    list.items = {}
    if list.version == "v2" then
        ns.ListV2.Fill(list, list.scroll.child, list.page, list.sections, controlFor)
    else
        fillRows(list, list.scroll.child, list.page, list.sections)
    end
end

-- One list of sections in a scroll area, filling parent. A section is { label, entries }.
local function newList(parent, page, sections)
    local list = { parent = parent, page = page, sections = sections }
    fillList(list)
    page.lists[#page.lists + 1] = list
    return list
end

local function refreshList(list, module)
    if list.version ~= ModulePage.Version() then
        fillList(list)
    end
    if list.version == "v2" then
        ns.ListV2.Layout(list, module, isVisible)
        return
    end
    local y = 0
    for _, item in ipairs(list.items) do
        if item.caption then
            item.caption:ClearAllPoints()
            item.caption:SetPoint("TOPLEFT", 0, y - 12)
            y = y - CAPTION
        else
            local shown = isVisible(module, item.option)
            item.row:SetShown(shown)
            if shown then
                local value = E.store:Get(module.name, item.path)
                if item.control.SetValue then
                    item.control:SetValue(value)
                elseif not item.control:HasFocus() then
                    item.control:SetText(value)
                end
                item.row:ClearAllPoints()
                item.row:SetPoint("TOPLEFT", 0, y)
                item.row:SetPoint("TOPRIGHT", 0, y)
                item.y = -y
                y = y - ROW
            end
        end
    end
    list.scroll:SetContentHeight(-y + 8)
end

-- A tab with a picker: buttons on the left, the chosen view on the right; or, with
-- tab.picker = "top", a row of choices on top and the view under it, full width. views = { { id,
-- text, sections } }. tab.onPick(id) is told when another view is chosen.
local TOP_PICKER = 30 + 14

-- V2 gives the options more room: a preview that draws itself goes in a window beside the options
-- (a short one, like UnitFrames' strip that opens its own window, stays), and the picker on the left
-- is one column.
local INLINE_PREVIEW_MAX = 60
local PICK_ROW = 36
local PREVIEW_PAD = 12

-- The window that holds a tab's preview in V2, made the first time it opens.
-- onShown(open) is told when it opens or closes.
local function previewWindow(page, tab, frame, onShown)
    if page.previewWindows[tab.key] then
        return page.previewWindows[tab.key]
    end
    local w = Widgets.Window(nil, page.title .. " · " .. L.V2_PREVIEW)
    w:SetFrameStrata("DIALOG")
    w:SetWidth(440)
    -- Looks like the options window: its background image and veil, its scale and no shadow.
    w.wallpaper = Theme.NewWallpaper(w)
    function w.onPaint(self)
        -- No drop shadow around it: the options window has none.
        self.shadow:Hide()
        Theme.PaintWallpaper(self.wallpaper, "window")
        self:SetScale(E.store:Get("EternityUI", "general.optionsScale"))
    end
    w:HookScript("OnShow", function()
        onShown(true)
    end)
    w:HookScript("OnHide", function()
        onShown(false)
    end)
    -- Closes with the tab (another tab, another page, the options window).
    frame:HookScript("OnHide", function()
        w:Hide()
    end)
    page.previewWindows[tab.key] = w
    return w
end

local function buildPicked(tab, frame, page, views)
    local preview = tab.preview and tab.preview(frame)
    page.preview = preview
    page.previewWindows = page.previewWindows or {}
    page.pickButtons = {}
    page.pickLists = {}
    local onTop = tab.picker == "top"
    local holder = CreateFrame("Frame", nil, frame)
    local byView = {}
    for _, view in ipairs(views) do
        byView[view.id] = view
    end

    local segmented
    function page.Pick(id)
        page.picked = id
        for key, button in pairs(page.pickButtons) do
            button:SetActive(key == id)
        end
        if segmented then
            segmented:SetValue(id)
        end
        if not page.pickLists[id] then
            local list = newList(holder, page, byView[id].sections)
            list.scroll:SetAllPoints()
            page.pickLists[id] = list
        end
        for key, list in pairs(page.pickLists) do
            list.scroll:SetShown(key == id)
        end
        page.Refresh()
        if tab.onPick then
            tab.onPick(id)
        end
    end

    if onTop then
        local choices = {}
        for _, view in ipairs(views) do
            choices[#choices + 1] = { view.id, view.text }
        end
        segmented = Widgets.Segmented(frame, choices, page.Pick)
    else
        for _, view in ipairs(views) do
            page.pickButtons[view.id] = Widgets.Button(frame, view.text, "nav", function()
                page.Pick(view.id)
            end)
        end
    end

    -- V2: the preview opens from a button in the options window's header, left of its close button
    -- (Window.SetHeader asks page.HeaderAction). A short strip with a button of its own that opens its
    -- own window (UnitFrames') stays in place, invisible and without the mouse, so it still closes
    -- that window when the tab hides; the header's button clicks it.
    local strip = preview ~= nil and preview.button ~= nil and preview:GetHeight() <= INLINE_PREVIEW_MAX
    page.headerActions = page.headerActions or {}
    local function headerChanged()
        if ns.Window.current == page then
            ns.Window.RefreshHeader()
        end
    end
    local function toggleWindow()
        local w = previewWindow(page, tab, frame, headerChanged)
        if w:IsShown() then
            w:Hide()
            return
        end
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", ns.Window.frame, "TOPRIGHT", 12, 0)
        w:Paint()
        w:Show()
        page.Refresh()
    end
    local function clickStrip()
        preview.button:Click()
        headerChanged()
    end

    -- Lays the tab out for the layout in use; ModulePage calls it again when that changes.
    local function place()
        local v2 = ModulePage.Version() == "v2"
        local windowed = v2 and preview ~= nil and not strip and preview:GetHeight() > INLINE_PREVIEW_MAX
        local folded = v2 and strip
        local top = 0
        page.headerActions[tab.key] = nil
        if preview then
            preview:ClearAllPoints()
            if windowed then
                local w = previewWindow(page, tab, frame, headerChanged)
                preview:SetParent(w.body)
                preview:SetPoint("TOPLEFT", PREVIEW_PAD, -PREVIEW_PAD)
                preview:SetPoint("TOPRIGHT", -PREVIEW_PAD, -PREVIEW_PAD)
                w:SetHeight(40 + preview:GetHeight() + PREVIEW_PAD * 2)
                page.headerActions[tab.key] = {
                    text = function()
                        return w:IsShown() and L.V2_PREVIEW_HIDE or L.V2_PREVIEW_SHOW
                    end,
                    run = toggleWindow,
                }
            else
                if page.previewWindows[tab.key] then
                    page.previewWindows[tab.key]:Hide()
                end
                preview:SetParent(frame)
                preview:SetPoint("TOPLEFT")
                preview:SetPoint("TOPRIGHT")
                if folded then
                    page.headerActions[tab.key] = {
                        text = function()
                            return preview.button.label:GetText()
                        end,
                        run = clickStrip,
                    }
                else
                    top = -preview:GetHeight() - 12
                end
            end
            if strip then
                preview:SetAlpha(folded and 0 or 1)
                preview.button:EnableMouse(not folded)
            end
            preview:Show()
        end
        headerChanged()

        holder:ClearAllPoints()
        holder:SetPoint("BOTTOMRIGHT")
        if onTop then
            segmented:ClearAllPoints()
            segmented:SetPoint("TOPLEFT", 0, top)
            holder:SetPoint("TOPLEFT", 0, top - TOP_PICKER)
            return
        end
        -- V1: two columns of small buttons. V2: one column as wide as its longest name.
        local width = 84
        if v2 then
            width = 110
            for _, button in pairs(page.pickButtons) do
                width = math.max(width, math.ceil(button.label:GetStringWidth()) + 28)
            end
        end
        for i, view in ipairs(views) do
            local button = page.pickButtons[view.id]
            button:SetSize(width, 32)
            button:ClearAllPoints()
            if v2 then
                button:SetPoint("TOPLEFT", 0, top - (i - 1) * PICK_ROW)
            else
                local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
                button:SetPoint("TOPLEFT", column * 90, top - row * 36)
            end
        end
        holder:SetPoint("TOPLEFT", v2 and width + 20 or 186, top)
    end
    page.placePickers = page.placePickers or {}
    page.placePickers[#page.placePickers + 1] = place
    place()
    page.Pick(views[1].id)
end

-- The views of a picker tab. `groups` shows whole schema groups, one per view. `views` gathers
-- options of several groups: { id, text, sections = { { label, paths } or { group } } }. Stored
-- paths don't change. Options used here are marked in `used` and leave General and Appearance.
local function viewsOf(tab, byId, byPath, used)
    local views = {}
    for _, id in ipairs(tab.groups or {}) do
        local group = byId[id]
        views[#views + 1] = {
            id = id,
            text = tab.short and tab.short[id] or E.Localize(group.label),
            sections = { { label = group.label, entries = entriesOf(group) } },
        }
        for _, entry in ipairs(views[#views].sections[1].entries) do
            used[entry.path] = true
        end
    end
    for _, view in ipairs(tab.views or {}) do
        local sections = {}
        for _, section in ipairs(view.sections) do
            local group = section.group and byId[section.group]
            local entries = group and entriesOf(group) or {}
            for _, path in ipairs(section.paths or {}) do
                entries[#entries + 1] = byPath[path]
            end
            for _, entry in ipairs(entries) do
                used[entry.path] = true
            end
            sections[#sections + 1] = { label = section.label or group.label, entries = entries }
        end
        views[#views + 1] = { id = view.id, text = view.text, sections = sections }
    end
    return views
end

-- Where the module's options go: General, Appearance (lists of sections) and the tabs' views.
local function placeOptions(module)
    local byId, byPath, used = {}, {}, {}
    for _, group in ipairs(module.schema.groups) do
        byId[group.id] = group
        for _, entry in ipairs(entriesOf(group)) do
            byPath[entry.path] = entry
        end
    end
    local tabViews = {}
    for _, tab in ipairs(module.tabs or {}) do
        for _, path in ipairs(tab.paths or {}) do
            used[path] = true
        end
        if tab.groups or tab.views then
            tabViews[tab] = viewsOf(tab, byId, byPath, used)
        end
    end
    -- What's left goes to General and Appearance, by group.
    local general, appearance = {}, {}
    for _, group in ipairs(module.schema.groups) do
        local entries = {}
        for _, entry in ipairs(entriesOf(group)) do
            if not used[entry.path] then
                entries[#entries + 1] = entry
            end
        end
        if #entries > 0 then
            local section = { label = group.label, entries = entries }
            table.insert(group.tab == "appearance" and appearance or general, section)
        end
    end
    return general, appearance, tabViews
end

-- Where a tab's content starts under the tab selector, by layout.
local TAB_TOP = { v1 = 42, v2 = 54 }

-- The tab selector of the layout in use: V1's segmented buttons or V2's tabs (ListV2.Tabs).
local function applyLayout(page)
    local v2 = ModulePage.Version() == "v2"
    if page.layout == v2 then
        return
    end
    page.layout = v2
    for _, place in ipairs(page.placePickers or {}) do
        place()
    end
    page.selector:SetShown(not v2)
    page.tabBar:SetShown(v2)
    for _, entry in pairs(page.tabs) do
        entry.frame:SetPoint("TOPLEFT", 0, -TAB_TOP[v2 and "v2" or "v1"])
    end
end

local function build(page, frame)
    local module = page.module
    local general, appearance, tabViews = placeOptions(module)

    page.lists = {}
    page.views = {}
    page.tabs = {}
    local choices = {}
    local function addTab(key, text, fill)
        choices[#choices + 1] = { key, text }
        local tabFrame = CreateFrame("Frame", nil, frame)
        tabFrame:SetPoint("TOPLEFT", 0, -42)
        tabFrame:SetPoint("BOTTOMRIGHT")
        tabFrame:Hide()
        page.tabs[key] = { frame = tabFrame, fill = fill }
    end
    local function addList(groups)
        return function(tabFrame)
            newList(tabFrame, page, groups).scroll:SetAllPoints()
        end
    end
    if #general > 0 then
        addTab("general", L.TAB_GENERAL, addList(general))
    end
    if #appearance > 0 then
        addTab("appearance", L.TAB_APPEARANCE, addList(appearance))
    end
    for _, tab in ipairs(module.tabs or {}) do
        addTab(tab.key, tab.text, function(tabFrame)
            if tab.build then
                -- A tab that draws itself: build(parent, setHeight) returns its view.
                local scroll = Widgets.Scroll(tabFrame)
                scroll:SetAllPoints()
                page.views[#page.views + 1] = tab.build(scroll.child, function(height)
                    scroll:SetContentHeight(height)
                end)
            else
                buildPicked(tab, tabFrame, page, tabViews[tab])
            end
        end)
    end

    function page.ShowTab(key)
        page.current = key
        for name, entry in pairs(page.tabs) do
            if name == key and entry.fill then
                entry.fill(entry.frame)
                entry.fill = nil
            end
            entry.frame:SetShown(name == key)
        end
        page.selector:SetValue(key)
        page.tabBar:SetValue(key)
        page.Refresh()
        if ns.Window.current == page then
            ns.Window.RefreshHeader()
        end
    end

    page.selector = Widgets.Segmented(frame, choices, page.ShowTab)
    page.selector:SetPoint("TOPLEFT")
    page.tabBar = ns.ListV2.Tabs(frame, choices, page.ShowTab)
    page.tabBar:SetPoint("TOPLEFT")
    page.tabBar:SetPoint("TOPRIGHT")

    page.enabled = Widgets.Toggle(frame, function(value)
        E.store:SetModuleEnabled(module.name, value)
    end)
    page.enabled:SetPoint("TOPRIGHT", 0, -5)
    local label = Widgets.Text(frame, 14, "muted")
    label:SetPoint("RIGHT", page.enabled, "LEFT", -10, 0)
    label:SetText(L.ENABLED)

    -- Mover with only this module's elements, while it has some (the usual Mover isn't touched).
    page.mover = Widgets.Button(frame, L.MOVER_THIS, "ghost", function()
        ns.MoverSession.OpenFor(module.name)
    end)
    page.mover:SetPoint("RIGHT", label, "LEFT", -14, 0)
    Widgets.AttachTooltip(page.mover, function(tip)
        tip:SetTitle(L.MOVER_THIS)
        tip:AddLine(L.MOVER_THIS_HINT, "textMuted")
    end)

    -- Buttons the module adds beside the switch: { text, onClick }.
    local anchor = page.mover
    for _, action in ipairs(module.actions or {}) do
        local button = Widgets.Button(frame, action.text, "ghost", action.onClick)
        button:SetPoint("RIGHT", anchor, "LEFT", -14, 0)
        anchor = button
    end

    -- The module's chosen tab first, or the last one.
    local first = choices[#choices][1]
    if module.defaultTab and page.tabs[module.defaultTab] then
        first = module.defaultTab
    end
    page.ShowTab(first)
end

-- What a search should find in an option besides its label.
local function extraText(option, section)
    local parts = { E.Localize(section.label) }
    if option.description then
        parts[#parts + 1] = E.Localize(option.description)
    end
    for _, entry in ipairs(option.values or {}) do
        parts[#parts + 1] = E.Localize(entry.label)
    end
    return table.concat(parts, " ")
end

-- The search entries of a module's page: every option, and the tabs that draw themselves.
local function entriesOfPage(page)
    local module = page.module
    local general, appearance, tabViews = placeOptions(module)
    local entries = {}
    local function addSections(sections, tab, where, view)
        for _, section in ipairs(sections) do
            for _, entry in ipairs(section.entries) do
                entries[#entries + 1] = {
                    label = E.Localize(entry.option.label),
                    extra = extraText(entry.option, section),
                    path = entry.path,
                    tab = tab,
                    view = view,
                    where = where,
                }
            end
        end
    end
    addSections(general, "general", L.TAB_GENERAL)
    addSections(appearance, "appearance", L.TAB_APPEARANCE)
    for _, tab in ipairs(module.tabs or {}) do
        if tab.build then
            entries[#entries + 1] = { label = tab.text, tab = tab.key }
        end
        for _, view in ipairs(tabViews[tab] or {}) do
            addSections(view.sections, tab.key, tab.text .. " > " .. view.text, view.id)
        end
    end
    return entries
end

--- Adds a page per registered module with options, once.
function ModulePage.AddAll()
    for _, module in ipairs(E:ListModules()) do
        if module.schema then
            local page = {
                key = module.name,
                module = module,
                title = E.Localize(module.schema.title),
                note = E.Localize(module.schema.description),
            }
            function page.Build(frame)
                build(page, frame)
            end
            function page.Refresh()
                if not page.lists then
                    return
                end
                applyLayout(page)
                page.enabled:SetValue(E.store:IsModuleEnabled(module.name))
                page.mover:SetShown(ns.MoverSession.HasElements(module.name))
                for _, list in ipairs(page.lists) do
                    refreshList(list, module)
                end
                if page.preview and page.picked then
                    page.preview:Refresh(page.picked)
                end
                for _, view in ipairs(page.views) do
                    if view:IsVisible() then
                        view:Refresh()
                    end
                end
            end
            -- The open tab's description (a tab that draws itself may have one, or a function
            -- that returns it), under the module's own in the "i" beside the title.
            function page.Sections()
                for _, tab in ipairs(module.tabs or {}) do
                    if tab.key == page.current and tab.description then
                        local text = tab.description
                        if type(text) == "function" then
                            text = text()
                        end
                        return { { tab.text, text } }
                    end
                end
            end
            --- The button the open tab puts in the window's header (V2's preview), or nil.
            function page.HeaderAction()
                local action = page.headerActions and page.headerActions[page.current]
                return action and { text = action.text(), run = action.run }
            end
            function page.Select(tab, group)
                if tab and page.tabs[tab] then
                    page.ShowTab(tab)
                end
                if group and page.Pick then
                    page.Pick(group)
                end
            end
            function page.Entries()
                return entriesOfPage(page)
            end
            -- An option hidden by visibleWhen has no row to show: its tab stays open.
            function page.Reveal(path)
                -- An advanced option the Basic level hides: show the advanced ones first.
                if ns.ListV2.HiddenByLevel(page, path) then
                    E.store:Set("EternityUI", "general.optionsLevel", "advanced")
                    page.Refresh()
                end
                -- In a folded card: unfold it.
                if ns.ListV2.Unfold(page, path) then
                    page.Refresh()
                end
                for _, list in ipairs(page.lists) do
                    for _, item in ipairs(list.items) do
                        if item.path == path and item.row:IsVisible() then
                            list.scroll:ScrollTo(item.y - ROW)
                            ns.Search.Flash(item.row)
                            return
                        end
                    end
                end
            end
            ns.Window.AddPage(page)
        end
    end
end
