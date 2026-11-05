-- EternityUI_Objectives skin: restyles Blizzard's tracker in place. Blizzard keeps building and
-- laying it out; the module only repaints what Blizzard made.
--
-- No taint (Forever's quest item buttons read an attribute written during layout, so a layout
-- driven by addon code would block them in combat):
-- * no Blizzard method is replaced and no tracker function is called; only hooksecurefunc on the
--   section, block and header instances (mixins are copied into each frame) and HookScript;
-- * nothing is stored on Blizzard's frames: our state lives in weak tables keyed by them;
-- * widget calls only (textures hidden with Hide, colors, fonts, our own regions and frames).
-- Scenario and zone widget sections get their header restyled only: their contents share the
-- UIWidget pools and touching them breaks Blizzard's tooltips with secret values (EllesmereUI).
-- Hooks are installed once and do nothing while Core.running is false; Restore gives every
-- touched piece back its saved look.

---@type string, EternityUIObjectivesNamespace
local _, ns = ...
local Theme, W = ns.Ui.Theme, ns.Ui.W
local Core = ns.Core
local opt = Core.Opt

local OUTLINES = { none = "", shadow = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
-- Sections whose contents are left alone (see the header).
local HEADER_ONLY = { ScenarioObjectiveTracker = true, UIWidgetObjectiveTracker = true }

local function weak()
    return setmetatable({}, { __mode = "k" })
end

---@class EternityUIObjectivesSkin
---@field hooked table<table, boolean> instances already hooked (sections, blocks, lines, headers)
---@field headers table<table, table> Blizzard header -> { shape, line, icon, background shown, text color, button alphas }
---@field bars table<table, table> Blizzard StatusBar -> { hidden textures, texture, color, track, label font }
---@field items table<table, table> quest item button -> { border, texCoord, normal and pushed alpha }
---@field stripped table<table, string> header FontString -> the text Blizzard set (with the level)
---@field fonts table<string, table>? saved Blizzard fonts: font object -> { parent, shadow }
---@field background table? our backdrop behind the tracker
---@field scale number? the tracker's scale before the module changed it
---@field pendingScale boolean? scale waits for the end of combat
local Skin = {
    hooked = weak(),
    headers = weak(),
    bars = weak(),
    items = weak(),
    stripped = weak(),
}
ns.Skin = Skin

local function rgba(path)
    return { Core.Color(path) }
end

-- Text colors ---------------------------------------------------------------------------------

local function colorMode()
    return Core.running and opt("colors.mode") or "blizzard"
end

--- Questions about a block's quest: id and whether it's ready to turn in.
local function questReady(block)
    local questID = block.poiQuestID
    if type(questID) ~= "number" or Core.Secret(questID) then
        return false
    end
    local ok, complete = pcall(C_QuestLog.IsComplete, questID)
    return ok and complete == true
end

--- Repaints a block's title: theme colors, or the ready color over Blizzard's difficulty.
function Skin:ColorTitle(block)
    local fs = block.HeaderText
    if not fs then
        return
    end
    local mode = colorMode()
    if mode == "blizzard" then
        local style = fs.colorStyle
        if style then
            fs:SetTextColor(style.r, style.g, style.b)
        end
        return
    end
    if questReady(block) then
        fs:SetTextColor(Core.Color("colors.ready"))
    elseif mode == "theme" then
        fs:SetTextColor(Core.Color(block.isHighlighted and "colors.titleHover" or "colors.title"))
    else
        local style = fs.colorStyle
        if style then
            fs:SetTextColor(style.r, style.g, style.b)
        end
    end
end

--- The option color for one of Blizzard's OBJECTIVE_TRACKER_COLOR styles (nil = keep it).
local function lineColor(style)
    local C = OBJECTIVE_TRACKER_COLOR
    if not C or not style then
        return nil
    end
    if style == C.Normal then
        return "colors.objective"
    elseif style == C.NormalHighlight then
        return "colors.objectiveHover"
    elseif style == C.Complete then
        return "colors.complete"
    elseif style == C.Failed or style == C.FailedHighlight or style == C.TimeLeft or style == C.TimeLeftHighlight then
        return "colors.failed"
    end
    return nil
end

--- Repaints one of a block's strings after Blizzard set it (title or objective line).
function Skin:ColorString(block, fs)
    if fs == block.HeaderText then
        self:ColorTitle(block)
        return
    end
    local style = fs.colorStyle
    local path = colorMode() ~= "blizzard" and lineColor(style)
    if path then
        fs:SetTextColor(Core.Color(path))
    elseif style then
        fs:SetTextColor(style.r, style.g, style.b)
    end
end

function Skin:ColorLine(block, line)
    if line.Text then
        self:ColorString(block, line.Text)
    end
    if line.Dash then
        if colorMode() ~= "blizzard" then
            line.Dash:SetTextColor(Core.Color("colors.dash"))
        else
            local C = OBJECTIVE_TRACKER_COLOR
            local dash = C and (block.isHighlighted and C.NormalHighlight or C.Normal)
            if dash then
                line.Dash:SetTextColor(dash.r, dash.g, dash.b)
            end
        end
    end
end

function Skin:ColorBlock(block)
    self:ColorTitle(block)
    if type(block.usedLines) == "table" then
        for _, line in pairs(block.usedLines) do
            self:ColorLine(block, line)
        end
    end
end

-- Quest level -----------------------------------------------------------------------------------

-- "[12] Title", "[12+] Title" or with a color code first ("|cffRRGGBB[12] Title|r").
local function withoutLevel(text)
    local stripped, count = text:gsub("^(|c%x%x%x%x%x%x%x%x)%[[^%]]*%]%s*", "%1", 1)
    if count == 0 then
        stripped, count = text:gsub("^%[[^%]]*%]%s*", "", 1)
    end
    return count > 0 and stripped or nil
end
Skin.WithoutLevel = withoutLevel

--- Removes or gives back the "[level]" Forever puts before quest titles. Blizzard measured the
--- block with the level, so a shorter title only leaves the same height.
function Skin:UpdateLevel(block)
    local fs = block.HeaderText
    if not fs then
        return
    end
    local text = fs:GetText()
    if type(text) ~= "string" or Core.Secret(text) then
        return
    end
    local strip = Core.running and not opt("info.level")
    local original = self.stripped[fs]
    if strip then
        if original and text ~= withoutLevel(original) then
            original = nil -- Blizzard wrote a new title
        end
        original = original or text
        local stripped = withoutLevel(original)
        if stripped then
            self.stripped[fs] = original
            if text ~= stripped then
                fs:SetText(stripped)
            end
        end
    elseif original then
        self.stripped[fs] = nil
        if text == withoutLevel(original) then
            fs:SetText(original)
        end
    end
end

-- Headers (the tracker's and each section's) -------------------------------------------------------

local function headerCollapsed(header)
    local owner = header:GetParent()
    local ok, collapsed = pcall(function()
        return owner and owner.IsCollapsed and owner:IsCollapsed()
    end)
    return ok and collapsed == true
end

function Skin:UpdateHeaderIcon(header)
    local record = self.headers[header]
    if record and record.icon then
        record.icon:SetIcon(headerCollapsed(header) and "chevronRight" or "chevronDown")
    end
end

--- Our look on a header: the shape and line are textures of the header itself (BACKGROUND, under
--- Blizzard's text), the chevron sits on the minimize button.
function Skin:SkinHeader(header, main)
    local record = self.headers[header]
    if not record then
        local button = header.MinimizeButton
        record = {
            main = main,
            shape = W.Skin.Shape(header, "control", "BACKGROUND", -8),
            line = header:CreateTexture(nil, "BACKGROUND", nil, -7),
            text = header.Text and { header.Text:GetTextColor() },
            background = header.Background and header.Background:IsShown(),
        }
        record.line:SetHeight(1)
        record.line:SetPoint("BOTTOMLEFT", 4, 0)
        record.line:SetPoint("BOTTOMRIGHT", -4, 0)
        if button then
            record.normal = button:GetNormalTexture()
            record.pushed = button:GetPushedTexture()
            record.highlight = button:GetHighlightTexture()
            record.icon = W.Skin.Icon(button, "chevronDown", 10)
            record.icon:SetPoint("CENTER")
        end
        self.headers[header] = record
        if not self.hooked[header] and header.SetCollapsed then
            self.hooked[header] = true
            hooksecurefunc(header, "SetCollapsed", function(h)
                if Core.running and self.headers[h] and self.headers[h].skinned then
                    self:UpdateHeaderIcon(h)
                end
            end)
        end
    end
    record.skinned = true
    record.shape:SetColors(main and "surfaceHover" or "surface", nil)
    record.line:SetColorTexture(Core.Color("colors.section"))
    record.line:SetAlpha(main and 0.9 or 0.5)
    record.line:Show()
    if header.Background then
        header.Background:Hide()
    end
    if header.Text then
        header.Text:SetTextColor(Core.Color(main and "colors.section" or "colors.title"))
    end
    for _, key in ipairs({ "normal", "pushed", "highlight" }) do
        if record[key] then
            record[key]:SetAlpha(0)
        end
    end
    if record.icon then
        record.icon:SetColor("textMuted")
        record.icon:Show()
        self:UpdateHeaderIcon(header)
    end
end

function Skin:UnskinHeader(header)
    local record = self.headers[header]
    if not record or not record.skinned then
        return
    end
    record.skinned = false
    record.shape:SetColors(nil, nil)
    record.line:Hide()
    if header.Background and record.background then
        header.Background:Show()
    end
    if header.Text and record.text then
        header.Text:SetTextColor(unpack(record.text))
    end
    for _, key in ipairs({ "normal", "pushed", "highlight" }) do
        if record[key] then
            record[key]:SetAlpha(1)
        end
    end
    if record.icon then
        record.icon:Hide()
    end
end

-- Progress and timer bars -------------------------------------------------------------------------

function Skin:SkinBar(holder)
    local bar = holder and holder.Bar
    if not (bar and bar.GetStatusBarTexture) then
        return
    end
    local fill = bar:GetStatusBarTexture()
    local record = self.bars[bar]
    if not record then
        local r, g, b, a = bar:GetStatusBarColor()
        record = {
            hidden = {},
            texture = fill and fill:GetTexture(),
            color = { r, g, b, a },
            label = holder.Label or bar.Label,
        }
        record.labelFont = record.label and record.label:GetFontObject()
        -- Our track goes behind the bar (a frame of the holder, one level below).
        record.track = W.Panel(holder, { role = "control", fill = "track", border = "border" })
        record.track:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
        record.track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
        self.bars[bar] = record
    end
    record.skinned = true
    record.track:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
    record.track:Show()
    -- Blizzard's frame, borders and glows: every texture of the bar except the fill and the icon.
    -- Hidden ones are remembered to show them again; Blizzard may show one later (next pass).
    for _, region in ipairs({ bar:GetRegions() }) do
        if region:IsObjectType("Texture") and region ~= fill and region ~= bar.Icon and region:IsShown() then
            region:Hide()
            record.hidden[region] = true
        end
    end
    if fill then
        fill:SetColorTexture(1, 1, 1, 1)
        bar:SetStatusBarColor(Core.Color("colors.bar"))
    end
    if record.label then
        record.label:SetFontObject(Theme.Font("small"))
    end
end

function Skin:UnskinBar(bar, record)
    if not record.skinned then
        return
    end
    record.skinned = false
    record.track:Hide()
    for region in pairs(record.hidden) do
        region:Show()
    end
    record.hidden = {}
    local fill = bar:GetStatusBarTexture()
    if fill and record.texture then
        fill:SetTexture(record.texture)
    end
    if record.color[1] then
        bar:SetStatusBarColor(unpack(record.color))
    end
    if record.label and record.labelFont then
        record.label:SetFontObject(record.labelFont)
    end
end

-- Quest item buttons --------------------------------------------------------------------------------

function Skin:SkinItem(button)
    if not (button.icon and button.Cooldown) then
        return -- another right edge frame (find group button)
    end
    local record = self.items[button]
    if not record then
        local normal, pushed = button:GetNormalTexture(), button:GetPushedTexture()
        record = {
            normal = normal,
            pushed = pushed,
            normalAlpha = normal and normal:GetAlpha() or 1,
            pushedAlpha = pushed and pushed:GetAlpha() or 1,
            texCoord = { button.icon:GetTexCoord() },
            border = CreateFrame("Frame", nil, button),
        }
        record.border:SetAllPoints()
        record.border.shape = W.Skin.Shape(record.border, "small", "OVERLAY")
        self.items[button] = record
    end
    record.skinned = true
    if record.normal then
        record.normal:SetAlpha(0)
    end
    if record.pushed then
        record.pushed:SetAlpha(0)
    end
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    record.border.shape:SetColors(nil, rgba("colors.dash"))
    record.border:Show()
end

function Skin:UnskinItem(button, record)
    if not record.skinned then
        return
    end
    record.skinned = false
    if record.normal then
        record.normal:SetAlpha(record.normalAlpha)
    end
    if record.pushed then
        record.pushed:SetAlpha(record.pushedAlpha)
    end
    button.icon:SetTexCoord(unpack(record.texCoord))
    record.border:Hide()
end

-- Walking a section ---------------------------------------------------------------------------------

function Skin:HookBlock(block)
    if self.hooked[block] then
        return
    end
    self.hooked[block] = true
    if block.SetStringText then
        hooksecurefunc(block, "SetStringText", function(b, fs)
            if Core.running and fs then
                self:ColorString(b, fs)
            end
        end)
    end
    if block.UpdateHighlight then
        hooksecurefunc(block, "UpdateHighlight", function(b)
            if Core.running then
                self:ColorBlock(b)
            end
        end)
    end
    if block.SetHeader then
        hooksecurefunc(block, "SetHeader", function(b)
            if Core.running then
                self:UpdateLevel(b)
                self:ColorTitle(b)
            end
        end)
    end
end

local function eachIn(map, fn)
    if type(map) == "table" then
        for _, frame in pairs(map) do
            fn(frame)
        end
    end
end

--- Restyles everything a section shows now (runs after each of its layouts).
function Skin:Walk(section)
    if not Core.running then
        return
    end
    local headerOnly = HEADER_ONLY[section:GetName() or ""]
    if opt("look.headers") then
        self:SkinHeader(section.Header, false)
    end
    if headerOnly then
        return
    end
    if type(section.usedBlocks) == "table" then
        for _, blocks in pairs(section.usedBlocks) do
            for _, block in pairs(blocks) do
                self:HookBlock(block)
                self:UpdateLevel(block)
                self:ColorBlock(block)
                if type(block.usedLines) == "table" then
                    for _, line in pairs(block.usedLines) do
                        ns.Feedback:HookLine(line)
                    end
                end
            end
        end
    end
    if opt("look.bars") then
        eachIn(section.usedProgressBars, function(holder)
            self:SkinBar(holder)
        end)
        eachIn(section.usedTimerBars, function(holder)
            self:SkinBar(holder)
        end)
    end
    if opt("look.items") then
        eachIn(section.usedRightEdgeFrames, function(button)
            self:SkinItem(button)
        end)
    end
end

-- Fonts ------------------------------------------------------------------------------------------

local FONTS = { ObjectiveTrackerLineFont = "body", ObjectiveTrackerHeaderFont = "heading" }

--- The theme's typeface on Blizzard's two tracker fonts, at the size Blizzard's Edit Mode chose
--- (Text Size); with the option off or the module off, Blizzard's fonts again.
function Skin:ApplyFonts()
    local themed = Core.running and opt("look.font")
    local edge = Core.running and opt("look.outline") or "none"
    for name, style in pairs(FONTS) do
        local font = _G[name]
        if font then
            self.fonts = self.fonts or {}
            local saved = self.fonts[name]
            if themed or (Core.running and edge ~= "none") then
                if not saved then
                    local x, y = font:GetShadowOffset()
                    saved =
                        { parent = font:GetFontObject(), shadow = { x, y }, shadowColor = { font:GetShadowColor() } }
                    self.fonts[name] = saved
                end
                local path, size = font:GetFont()
                if themed then
                    path = Theme.Font(style):GetFont()
                end
                font:SetFont(path, size, OUTLINES[edge] or "")
                if edge == "shadow" then
                    font:SetShadowOffset(1, -1)
                    font:SetShadowColor(0, 0, 0, 0.9)
                else
                    font:SetShadowOffset(0, 0)
                end
            elseif saved then
                self.fonts[name] = nil
                if saved.parent then
                    font:SetFontObject(saved.parent)
                end
                font:SetShadowOffset(unpack(saved.shadow))
                font:SetShadowColor(unpack(saved.shadowColor))
            end
        end
    end
end

-- Background and scale -------------------------------------------------------------------------------

--- Our backdrop: a frame of the tracker covering Blizzard's NineSlice, which Blizzard already
--- stretches to the last section shown. Blizzard's own background is left to its Edit Mode opacity.
function Skin:UpdateBackground(tracker)
    local shown = Core.running and opt("look.background")
    if shown and not self.background then
        self.background = W.Panel(tracker, { role = "window", fill = "window", border = "border" })
        self.background:SetAllPoints(tracker.NineSlice or tracker)
    end
    if self.background then
        self.background:SetFrameLevel(tracker:GetFrameLevel())
        self.background.shape:SetAlpha(opt("look.backgroundOpacity") or 0.75)
        self.background:SetShown(shown and true or false)
    end
end

--- The tracker's scale, out of combat only (it lives in Blizzard's managed right column).
function Skin:ApplyScale(tracker)
    if InCombatLockdown() then
        self.pendingScale = true
        return
    end
    self.pendingScale = false
    local wanted = Core.running and opt("size.scale") or 1
    if self.scale == nil then
        if wanted == 1 then
            return -- never touched: leave Blizzard's alone
        end
        self.scale = tracker:GetScale()
    end
    local target = Core.running and wanted * self.scale or self.scale
    if math.abs(tracker:GetScale() - target) > 0.001 then
        tracker:SetScale(target)
    end
    if not Core.running or wanted == 1 then
        self.scale = nil
    end
end

-- Whole tracker ---------------------------------------------------------------------------------------

--- Hooks installed once, when the tracker exists.
function Skin:Install(tracker)
    if self.hooked[tracker] then
        return
    end
    self.hooked[tracker] = true
    Core.EachSection(function(section)
        if not self.hooked[section] then
            self.hooked[section] = true
            hooksecurefunc(section, "EndLayout", function(s)
                self:Walk(s)
            end)
        end
    end)
    -- Edit Mode's Text Size swaps the fonts' parents: the theme face goes back on top.
    if ObjectiveTrackerManager and ObjectiveTrackerManager.SetTextSize then
        hooksecurefunc(ObjectiveTrackerManager, "SetTextSize", function()
            if Core.running and self.fonts then
                for name, saved in pairs(self.fonts) do
                    saved.parent = _G[name] and _G[name]:GetFontObject() or saved.parent
                end
                self:ApplyFonts()
            end
        end)
    end
end

--- Restyles the whole tracker as it is now (enable, option or theme change).
function Skin:Apply(tracker)
    self:Install(tracker)
    self:ApplyFonts()
    self:UpdateBackground(tracker)
    self:ApplyScale(tracker)
    if opt("look.headers") then
        if tracker.Header then
            self:SkinHeader(tracker.Header, true)
        end
    else
        for header in pairs(self.headers) do
            self:UnskinHeader(header)
        end
    end
    if not opt("look.bars") then
        for bar, record in pairs(self.bars) do
            self:UnskinBar(bar, record)
        end
    end
    if not opt("look.items") then
        for button, record in pairs(self.items) do
            self:UnskinItem(button, record)
        end
    end
    Core.EachSection(function(section)
        self:Walk(section)
    end)
end

--- Gives everything back as Blizzard drew it (Core.running is already false).
function Skin:Restore(tracker)
    for header in pairs(self.headers) do
        self:UnskinHeader(header)
    end
    for bar, record in pairs(self.bars) do
        self:UnskinBar(bar, record)
    end
    for button, record in pairs(self.items) do
        self:UnskinItem(button, record)
    end
    for block in pairs(self.hooked) do
        if type(block) == "table" and block.HeaderText and block.usedLines then
            self:UpdateLevel(block)
            self:ColorBlock(block)
        end
    end
    self:ApplyFonts()
    if tracker then
        self:UpdateBackground(tracker)
        self:ApplyScale(tracker)
    end
end
