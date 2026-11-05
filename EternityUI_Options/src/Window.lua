-- The options window: a sidebar of pages and one page at a time. Pages build on first view.
-- A page is { key, title, note, Build(frame), Refresh() }. Esc closes through keyboard input
-- instead of UISpecialFrames, which taints.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Shape = E.Shape
local Theme = E.Theme
local Widgets = E.Widgets

local WIDTH, HEIGHT = 1100, 700
local SIDEBAR = 232

local Window = { pages = {} }
ns.Window = Window
E.OptionsWindow = Window

--- Adds a page to the sidebar, in call order.
---@param page table
function Window.AddPage(page)
    Window.pages[#Window.pages + 1] = page
end

--- Shows a page, building it the first time.
---@param page table
function Window.Show(page)
    local chrome = Window.chrome
    if not page.frame then
        page.frame = CreateFrame("Frame", nil, chrome.body)
        page.frame:SetAllPoints()
        page.Build(page.frame)
    end
    for _, other in ipairs(Window.pages) do
        if other.frame then
            other.frame:SetShown(other == page)
        end
        other.nav:SetActive(other == page)
    end
    Window.RevealNav(page)
    chrome.title:SetText(page.title)
    chrome.note:SetText(page.note)
    Window.current = page
    Window.Refresh()
end

--- Scrolls the page list so the page's entry is in view (it may be opened from elsewhere).
---@param page table
function Window.RevealNav(page)
    local nav = Window.chrome.nav
    local height = nav and nav:GetHeight() or 0
    if not page.navTop or height <= 0 then
        return
    end
    local top, bottom = page.navTop, page.navTop + page.nav:GetHeight()
    local offset = nav:GetVerticalScroll()
    if top < offset then
        offset = top
    elseif bottom > offset + height then
        offset = bottom - height
    else
        return
    end
    nav:SetVerticalScroll(offset)
    nav:SetContentHeight(nav.child:GetHeight()) -- clamps the offset and moves the thumb
end

--- Updates what the window shows from the current state.
function Window.Refresh()
    local page = Window.current
    if page and page.Refresh then
        page.Refresh()
    end
    Window.chrome.profile:SetText(L.PROFILE_LINE:format(E.store:GetProfileName()))
end

local function buildSidebar(frame)
    local chrome = Window.chrome
    local logo = Widgets.Text(frame, 23, "text")
    logo:SetPoint("TOPLEFT", 22, -20)
    logo:SetText("Eternity")
    local version = Widgets.Text(frame, 12, "muted")
    version:SetPoint("BOTTOMLEFT", logo, "BOTTOMRIGHT", 8, 3)
    version:SetText(E.version)

    -- The page list scrolls when it doesn't fit above the profile line (many modules, or a
    -- small options scale).
    local nav = Widgets.Scroll(frame)
    nav:SetPoint("TOPLEFT", 0, -60)
    nav:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", SIDEBAR - 4, 44)
    chrome.nav = nav

    local y = 0
    for _, page in ipairs(Window.pages) do
        if page.module and not chrome.section then
            chrome.section = Widgets.Text(nav.child, 13, "muted")
            chrome.section:SetPoint("TOPLEFT", 22, y - 12)
            chrome.section:SetText(L.MODULES:upper())
            y = y - 34
        end
        page.nav = Widgets.Button(nav.child, page.title, "nav", function()
            Window.Show(page)
        end)
        page.nav:SetPoint("TOPLEFT", 12, y)
        page.nav:SetWidth(SIDEBAR - 24)
        page.navTop = -y
        y = y - 36
    end
    nav:SetContentHeight(-y)

    chrome.profile = Widgets.Text(frame, 13, "muted")
    chrome.profile:SetPoint("BOTTOMLEFT", 22, 18)

    local line = Widgets.Rect(frame, Theme.colors.line)
    line:SetPoint("TOPLEFT", SIDEBAR, 0)
    line:SetPoint("BOTTOMLEFT", SIDEBAR, 0)
    line:SetWidth(E.Pixel.Size(frame))
end

local function buildHeader(frame)
    local chrome = Window.chrome
    chrome.title = Widgets.Text(frame, 25, "text")
    chrome.title:SetPoint("TOPLEFT", SIDEBAR + 26, -20)
    chrome.note = Widgets.Text(frame, 14, "muted")
    chrome.note:SetPoint("TOPLEFT", chrome.title, "BOTTOMLEFT", 0, -5)

    local close = Widgets.Button(frame, "×", "ghost", function()
        frame:Hide()
    end)
    close:SetSize(34, 34)
    close:SetPoint("TOPRIGHT", -18, -18)

    chrome.body = CreateFrame("Frame", nil, frame)
    chrome.body:SetPoint("TOPLEFT", SIDEBAR + 26, -84)
    chrome.body:SetPoint("BOTTOMRIGHT", -26, 22)
end

local function build()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame.shape = Shape.New(frame)
    function frame:Paint()
        Theme.PaintWindow(self.shape)
        self:SetScale(E.store:Get("EternityUI", "general.optionsScale"))
    end
    Widgets.Track(frame)

    -- Keys go on to the game except Esc, which can't be caught in combat.
    frame:EnableKeyboard(true)
    frame:SetScript("OnShow", function(self)
        E.Combat.Run(self, function()
            self:SetPropagateKeyboardInput(true)
        end)
        -- Opened from the Mover (an element's options): it must stay reachable above the Mover.
        ns.MoverScene.SetBehind(true)
    end)
    frame:SetScript("OnHide", function()
        ns.MoverScene.SetBehind(false)
    end)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        end
    end)

    Window.frame = frame
    Window.chrome = {}
    ns.ModulePage.AddAll()
    buildHeader(frame)
    buildSidebar(frame)
    Window.Show(Window.pages[1])
end

--- Opens the window on a module's page, optionally on a tab and a picked group.
---@param module string
---@param tab string?
---@param group string?
function Window.Open(module, tab, group)
    if not Window.frame then
        build()
    end
    Window.frame:Show()
    for _, page in ipairs(Window.pages) do
        if page.key == module then
            Window.Show(page)
            if page.Select then
                page.Select(tab, group)
            end
        end
    end
end

--- Opens or closes the window.
function Window.Toggle()
    if not Window.frame then
        build()
    end
    Window.frame:SetShown(not Window.frame:IsShown())
    if Window.frame:IsShown() then
        Window.Refresh()
    end
end

E.Events.Listen(E.CONFIG_CHANGED, Window, function(_, _, path)
    if path == "general.optionsScale" and Window.frame then
        Window.frame:Paint()
    end
    if Window.frame and Window.frame:IsShown() and path and path:sub(1, 1) == "@" then
        Window.Refresh()
    end
end)
