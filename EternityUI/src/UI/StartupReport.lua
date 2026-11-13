-- /et startup: the saved startup reports (Core/Startup.lua) in a window, as text to read and
-- copy. Built on first use. It looks like the options window: the theme's surface, opacity and
-- edge, the "window" background image and the options' scale, and no shadow.
---@type string, EternityUINamespace
local _, ns = ...
local L = ns.L
local Startup = ns.Startup
local Theme = ns.Theme
local Widgets = ns.Widgets

local TEXT_SIZE = 12
local PAD = 12

local StartupReport = { shown = 1 } -- shown: index of the report on screen, 1 is the newest
ns.StartupReport = StartupReport

local window

local function currentText()
    local reports = Startup.Reports()
    local report = reports[StartupReport.shown]
    if not report then
        return L.STARTUP_EMPTY:format(Startup.WINDOW)
    end
    return Startup.Text(report)
end

-- Fits the text box to its text, so the scroll covers all of it.
local function layout()
    local scroll = window.scroll
    local width = math.max(scroll:GetWidth() - 16, 100)
    window.box:SetWidth(width)
    window.measure:SetWidth(width)
    window.measure:SetText(window.text)
    local height = math.ceil(window.measure:GetStringHeight()) + TEXT_SIZE
    window.box:SetHeight(height)
    scroll:SetContentHeight(height)
end

local function show()
    local count = #Startup.Reports()
    StartupReport.shown = math.max(1, math.min(StartupReport.shown, math.max(count, 1)))
    window.text = currentText()
    window.box:SetText(window.text)
    window.box:SetCursorPosition(0)
    window.older:SetShown(StartupReport.shown < count)
    window.newer:SetShown(StartupReport.shown > 1)
    window.clear:SetShown(count > 0)
    layout()
    window.scroll:ScrollTo(0)
end

local function build()
    window = Widgets.Window("EternityUIStartupReport", L.STARTUP_TITLE, true)
    window:SetSize(860, 560)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
    end)
    -- The options window's background image (General > Appearance), over the theme's surface.
    window.wallpaper = Theme.NewWallpaper(window)
    window:HookScript("OnSizeChanged", function(frame)
        Theme.PaintWallpaper(frame.wallpaper, "window")
    end)

    -- The text sits on a box in the theme's colors, like the chat's copy window.
    local panel = CreateFrame("Frame", nil, window.body)
    panel:SetPoint("TOPLEFT", PAD, -PAD)
    panel:SetPoint("BOTTOMRIGHT", -PAD, 0)
    panel.shape = ns.Shape.New(panel)
    window.panel = panel
    window.scroll = Widgets.Scroll(panel)
    window.scroll:SetPoint("TOPLEFT", 8, -8)
    window.scroll:SetPoint("BOTTOMRIGHT", -4, 8)
    window.scroll:HookScript("OnSizeChanged", function()
        if window:IsShown() then
            layout()
        end
    end)

    local box = CreateFrame("EditBox", nil, window.scroll.child)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetPoint("TOPLEFT")
    box:SetTextInsets(0, 0, 0, 0)
    box:SetFont(Theme.font, TEXT_SIZE * Theme.fontScale, "")
    box:SetScript("OnEscapePressed", box.ClearFocus)
    -- Read only: whatever is typed goes back to the report.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(window.text or "")
        end
    end)
    window.box = box
    window.measure = window.scroll.child:CreateFontString(nil, "OVERLAY")
    window.measure:SetFont(Theme.font, TEXT_SIZE * Theme.fontScale, "")
    window.measure:SetPoint("TOPLEFT")
    window.measure:SetJustifyH("LEFT")
    window.measure:SetAlpha(0)

    local select = Widgets.Button(window.footer, L.STARTUP_SELECT, "primary", function()
        box:SetFocus()
        box:HighlightText()
    end)
    select:SetSize(150, 28)
    select:SetPoint("LEFT", PAD, 0)
    window.older = Widgets.Button(window.footer, L.STARTUP_OLDER, "ghost", function()
        StartupReport.shown = StartupReport.shown + 1
        show()
    end)
    window.older:SetSize(100, 28)
    window.older:SetPoint("LEFT", select, "RIGHT", 8, 0)
    window.newer = Widgets.Button(window.footer, L.STARTUP_NEWER, "ghost", function()
        StartupReport.shown = StartupReport.shown - 1
        show()
    end)
    window.newer:SetSize(100, 28)
    window.newer:SetPoint("LEFT", window.older, "RIGHT", 8, 0)
    window.clear = Widgets.Button(window.footer, L.STARTUP_CLEAR, "danger", function()
        Startup.Clear()
        StartupReport.shown = 1
        show()
    end)
    window.clear:SetSize(100, 28)
    window.clear:SetPoint("RIGHT", -PAD, 0)
    local hint = Widgets.Text(window.footer, 11, "muted")
    hint:SetPoint("LEFT", window.newer, "RIGHT", 12, 0)
    hint:SetPoint("RIGHT", window.clear, "LEFT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.STARTUP_COPY_HINT)

    window:HookScript("OnHide", function()
        box:ClearFocus()
    end)

    -- Every theme change (Widgets.Track) and the options' scale repaint it.
    function window.onPaint(frame)
        frame.shadow:Hide()
        Theme.PaintWallpaper(frame.wallpaper, "window")
        frame:SetScale(ns.store and ns.store:Get("EternityUI", "general.optionsScale") or 1)
        local size = TEXT_SIZE * Theme.fontScale
        box:SetFont(Theme.font, size, "")
        window.measure:SetFont(Theme.font, size, "")
        local c = Theme.colors.text
        box:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        ns.Shape.Paint(panel.shape, math.min(Theme.radius, 5), Theme.colors.hover, Theme.colors.line)
        if frame:IsShown() and frame.text then
            layout()
        end
    end
    window:Paint()
    ns.Events.Listen(ns.CONFIG_CHANGED, StartupReport, function(_, module, path)
        if module == "EternityUI" and path == "general.optionsScale" then
            window:Paint()
        end
    end)
end

--- Opens the window on the newest report.
function StartupReport.Open()
    if not window then
        build()
    end
    StartupReport.shown = 1
    window:Show()
    window:Raise()
    show()
end

--- Opens or closes the window.
function StartupReport.Toggle()
    if window and window:IsShown() then
        window:Hide()
    else
        StartupReport.Open()
    end
end

--- The window, once built (for the tests).
---@return table?
function StartupReport.Frame()
    return window
end

EternityUI.StartupReport = StartupReport
