-- Personalization: the General and Appearance tabs of the core, with a live preview beside them.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Shape = E.Shape
local Theme = E.Theme
local Widgets = E.Widgets

local CORE = "EternityUI"
local THEMES =
    { "midnight", "obsidian", "azeroth", "horde", "alliance", "holo", "frost", "neon", "nightcity", "void", "graphite" }
local ROW = 44

local controls = {} -- option path -> control
local tabs = {}
local stacks = {}

local function setter(path)
    return function(value)
        E.store:Set(CORE, path, value)
    end
end

local function percent(value)
    return string.format("%d%%", math.floor(value * 100 + 0.5))
end

local function factor(value)
    return string.format("%.2f", value)
end

-- A row in a tab. visible (optional) decides from the options whether it shows.
local function addRow(tab, path, label, control, visible)
    controls[path] = control
    local row = Widgets.Row(tab, label, control)
    row:SetHeight(ROW)
    stacks[tab] = stacks[tab] or {}
    table.insert(stacks[tab], { row = row, visible = visible })
end

local function buildGeneral(tab)
    addRow(
        tab,
        "general.themeAccent",
        L.THEME_ACCENT,
        Widgets.Toggle(tab, function(value)
            E.store:Set(CORE, "general.themeAccent", value)
            ns.Window.Refresh()
        end)
    )
    addRow(tab, "general.accentColor", L.ACCENT_COLOR, Widgets.Color(tab, setter("general.accentColor")), function()
        return not E.store:Get(CORE, "general.themeAccent")
    end)
    addRow(
        tab,
        "general.optionsScale",
        L.OPTIONS_SCALE,
        Widgets.Slider(tab, 0.7, 1.5, 0.05, factor, setter("general.optionsScale"))
    )
    addRow(tab, "general.minimapEntry", L.MINIMAP_ENTRY, Widgets.Toggle(tab, setter("general.minimapEntry")))
    addRow(tab, "general.loadMessage", L.LOAD_MESSAGE, Widgets.Toggle(tab, setter("general.loadMessage")))
    local note = Widgets.Input(tab, setter("general.profileNote"))
    note:SetWidth(240)
    note:SetMaxBytes(80)
    addRow(tab, "general.profileNote", L.PROFILE_NOTE, note)
end

local function buildAppearance(tab)
    local themes = {}
    for i, key in ipairs(THEMES) do
        themes[i] = { key, L["THEME_" .. key] }
    end
    addRow(tab, "appearance.theme", L.THEME_LABEL, Widgets.Dropdown(tab, themes, setter("appearance.theme")))
    addRow(
        tab,
        "appearance.corners",
        L.CORNERS,
        Widgets.Dropdown(tab, {
            { "preset", L.PRESET },
            { "round", L.ROUND },
            { "soft", L.SOFT },
            { "sharp", L.SHARP },
        }, setter("appearance.corners"))
    )
    addRow(
        tab,
        "appearance.style",
        L.SURFACE,
        Widgets.Dropdown(tab, {
            { "preset", L.PRESET },
            { "glass", L.GLASS },
            { "flat", L.FLAT },
            { "neon", L.NEON },
        }, setter("appearance.style"))
    )
    addRow(
        tab,
        "appearance.font",
        L.FONT,
        Widgets.Dropdown(tab, {
            { "preset", L.PRESET },
            { "arialn", "Arial Narrow" },
            { "friz", "Friz Quadrata" },
            { "morpheus", "Morpheus" },
            { "skurri", "Skurri" },
        }, setter("appearance.font"))
    )
    addRow(
        tab,
        "appearance.fontScale",
        L.TEXT_SIZE,
        Widgets.Slider(tab, 0.8, 1.3, 0.05, factor, setter("appearance.fontScale"))
    )
    addRow(
        tab,
        "appearance.opacity",
        L.OPACITY,
        Widgets.Slider(tab, 0.6, 1, 0.02, percent, setter("appearance.opacity"))
    )
    addRow(tab, "appearance.pixelPerfect", L.PIXEL_PERFECT, Widgets.Toggle(tab, setter("appearance.pixelPerfect")))
    local note = Widgets.Text(tab, 13, "muted")
    note:SetPoint("TOPLEFT", 0, -ROW * 7 - 6)
    note:SetText(L.PIXEL_PERFECT_NOTE:format(E.Pixel.PerfectScale()))
end

local function buildPreview(parent)
    local title = Widgets.Text(parent, 13, "muted")
    title:SetPoint("TOPLEFT")
    title:SetText(L.PREVIEW)

    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", 0, -24)
    card:SetPoint("TOPRIGHT", 0, -24)
    card:SetHeight(226)
    card.shape = Shape.New(card)

    local name = Widgets.Text(card, 18, "text")
    name:SetPoint("TOPLEFT", 18, -18)
    name:SetText(L.SAMPLE_NAME)
    local info = Widgets.Text(card, 14, "muted")
    info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    info:SetText(L.SAMPLE_INFO)

    local health = card:CreateTexture(nil, "ARTWORK")
    health:SetPoint("TOPLEFT", 18, -76)
    health:SetSize(190, 16)
    local mana = card:CreateTexture(nil, "ARTWORK")
    mana:SetPoint("TOPLEFT", 18, -98)
    mana:SetSize(120, 8)

    local option = Widgets.Text(card, 15, "text")
    option:SetPoint("TOPLEFT", 18, -128)
    option:SetText(L.SAMPLE_OPTION)
    local toggle = Widgets.Toggle(card, function() end)
    toggle:SetPoint("TOPRIGHT", -18, -126)
    toggle:SetValue(true)

    local button = Widgets.Button(card, L.SAMPLE_BUTTON, "primary", function() end)
    button:SetPoint("BOTTOMLEFT", 18, 18)
    button:SetPoint("BOTTOMRIGHT", -18, 18)

    function card:Paint()
        Theme.PaintWindow(self.shape)
        health:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        local second = Theme.colors.accent2
        mana:SetColorTexture(second[1], second[2], second[3], 1)
    end
    Widgets.Track(card)

    local note = Widgets.Text(parent, 13, "muted")
    note:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -10)
    note:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", 0, -10)
    note:SetJustifyH("LEFT")
    note:SetText(L.PREVIEW_NOTE)
end

local function showTab(key)
    for name, tab in pairs(tabs) do
        tab:SetShown(name == key)
    end
end

local function build(frame)
    local left = CreateFrame("Frame", nil, frame)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", -322, 0)

    local selector = Widgets.Segmented(left, {
        { "general", L.TAB_GENERAL },
        { "appearance", L.TAB_APPEARANCE },
    }, showTab)
    selector:SetPoint("TOPLEFT")

    for key, buildTab in pairs({ general = buildGeneral, appearance = buildAppearance }) do
        local tab = CreateFrame("Frame", nil, left)
        tab:SetPoint("TOPLEFT", 0, -42)
        tab:SetPoint("BOTTOMRIGHT")
        tabs[key] = tab
        buildTab(tab)
    end
    selector:SetValue("appearance")
    showTab("appearance")

    local right = CreateFrame("Frame", nil, frame)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(300)
    buildPreview(right)
end

local function refresh()
    for path, control in pairs(controls) do
        if control.HasFocus and control:HasFocus() then
            control = nil
        end
        if control then
            local value = E.store:Get(CORE, path)
            if control.SetValue then
                control:SetValue(value)
            else
                control:SetText(value)
            end
        end
    end
    for tab, stack in pairs(stacks) do
        local y = 0
        for _, entry in ipairs(stack) do
            local shown = not entry.visible or entry.visible()
            entry.row:SetShown(shown)
            if shown then
                entry.row:ClearAllPoints()
                entry.row:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, y)
                entry.row:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, y)
                y = y - ROW
            end
        end
    end
end

ns.Window.AddPage({ key = "look", title = L.LOOK, note = L.LOOK_NOTE, Build = build, Refresh = refresh })
