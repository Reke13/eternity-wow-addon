-- The guide to your own background images (General > Appearance > "Show the guide"): a window
-- with the steps, the files each place takes, and a ready-made request to paste into an AI
-- assistant so it prepares the images (format, size, name) and says where they go. The request
-- sits in a text box: click it, Ctrl+A and Ctrl+C copy it.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Theme = E.Theme
local Widgets = E.Widgets

local WIDTH, HEIGHT = 600, 520
local PAD = 16
local FOLDER = "World of Warcraft\\_forever_\\Interface\\AddOns\\EternityUI_Wallpapers"

local Guide = {}
ns.WallpaperGuide = Guide
E.WallpaperGuide = Guide -- for the tests

-- "Options.tga · the options window · 1030 × 655", one line per place, from the core's list.
local function filesText()
    local lines = {}
    local labels = { window = L.GUIDE_WINDOW, chat = L.GUIDE_CHAT, quests = L.GUIDE_QUESTS, bags = L.GUIDE_BAGS }
    local sizes = { window = "1030 × 655", chat = "1024 × 512", quests = "512 × 1024", bags = "1024 × 1024" }
    for _, slot in ipairs({ "window", "chat", "quests", "bags" }) do
        local own = Theme.OWN_WALLPAPERS and Theme.OWN_WALLPAPERS[slot]
        if own then
            lines[#lines + 1] = ("•  %s.tga  —  %s  —  %s"):format(own.file, labels[slot], sizes[slot])
        end
    end
    return table.concat(lines, "\n")
end

--- The request for an AI assistant, with the folder and the files.
---@return string
function Guide.Prompt()
    return L.GUIDE_PROMPT:format(FOLDER)
end

local function build()
    local w = Widgets.Window("EternityUIWallpaperGuide", L.GUIDE_TITLE, false)
    w:SetSize(WIDTH, HEIGHT)
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetToplevel(true)
    w:SetPoint("CENTER")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
    end)

    local steps = Widgets.Text(w.body, 13, "text")
    steps:SetPoint("TOPLEFT", PAD, -PAD)
    steps:SetPoint("TOPRIGHT", -PAD, -PAD)
    steps:SetJustifyH("LEFT")
    steps:SetSpacing(3)
    steps:SetText(L.GUIDE_STEPS:format(FOLDER) .. "\n\n" .. filesText())
    w.steps = steps

    local label = Widgets.Text(w.body, 13, "muted")
    label:SetPoint("TOPLEFT", steps, "BOTTOMLEFT", 0, -14)
    label:SetPoint("RIGHT", -PAD, 0)
    label:SetJustifyH("LEFT")
    label:SetText(L.GUIDE_PROMPT_LABEL)

    -- The request, in a box that selects itself: Ctrl+C copies it.
    local box = CreateFrame("ScrollFrame", nil, w.body)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    box:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    box.shape = E.Shape.New(box)
    local edit = CreateFrame("EditBox", nil, box)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetTextInsets(8, 8, 8, 8)
    edit:SetWidth(WIDTH - PAD * 2)
    box:SetScrollChild(edit)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(edit:GetHeight() - self:GetHeight(), 0)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * 40, range)))
    end)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    -- Read-only: typing puts the request back.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(Guide.Prompt())
            self:HighlightText()
        end
    end)
    box:SetScript("OnMouseDown", function()
        edit:SetFocus()
    end)
    w.prompt = edit

    function w.onPaint(frame)
        edit:SetFont(Theme.font, 13 * Theme.fontScale, "")
        local c = Theme.colors.text
        edit:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        E.Shape.Paint(box.shape, math.min(Theme.radius, 5), Theme.colors.hover, Theme.colors.line)
        frame.steps:SetText(L.GUIDE_STEPS:format(FOLDER) .. "\n\n" .. filesText())
    end
    w:Paint()
    edit:SetText(Guide.Prompt())
    Guide.window = w
    return w
end

--- Opens or closes the guide.
function Guide.Toggle()
    local w = Guide.window or build()
    w:SetShown(not w:IsShown())
end
