-- The experience bar: XP, rested and quest XP as stacked segments, divisions, three texts built
-- from {tokens}, the tooltip and hiding Blizzard's status bars through the core's hider.

---@type string, EternityUIExperienceNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets
local Data, L = ns.Data, ns.L

---@class EternityUIExperienceBar
---@field frame table? created the first time it's enabled
---@field mainHidden boolean? the main status bar is invisible
---@field hovered boolean?
local Bar = {}
ns.Bar = Bar

-- Segments from back to front: each one starts at 0 and the one in front covers it.
local SEGMENTS = { "questsAll", "questsDone", "rested", "xp" }
local TEXT_SIZES = { caption = 11, small = 12, body = 14 }
local TEXT_INSET = 8

local function opt(path)
    return E.store:Get(addonName, path)
end

--- XP per hour window from the options (nil = the session).
function Bar.RateMinutes()
    return tonumber(opt("tracking.rateWindow"))
end

-- Blizzard bars ------------------------------------------------------------------------------------

-- The containers must keep their parent: Blizzard calls a method of the manager through
-- GetParent() when they update, for instance on opening its Edit Mode. So "all" hides the manager
-- itself, and "main" makes the main container invisible and lets the mouse through.
local function setMainHidden(main, hidden)
    main:SetAlpha(hidden and 0 or 1)
    for _, bar in pairs(main.bars or {}) do
        bar:EnableMouse(not hidden)
    end
end

--- Hides the Blizzard bars the option asks for and gives back the rest.
---@param mode string? "keep", "main" or "all" (nil gives them all back)
function Bar:ApplyBlizzard(mode)
    local manager = _G.StatusTrackingBarManager
    if manager then
        if mode == "all" then
            E.Hider.Hide(manager, addonName)
        else
            E.Hider.Restore(manager, addonName)
        end
    end
    local main = _G.MainStatusTrackingBarContainer
    local hideMain = mode == "main"
    if main and hideMain ~= (self.mainHidden or false) then
        setMainHidden(main, hideMain)
    end
    self.mainHidden = hideMain
end

--- Blizzard's fades give the container its alpha back: this keeps it invisible.
function Bar:KeepMainHidden()
    local main = _G.MainStatusTrackingBarContainer
    if self.mainHidden and main and main:GetAlpha() > 0 then
        main:SetAlpha(0)
    end
end

-- Tooltip ------------------------------------------------------------------------------------------

---@param tip table
function Bar.BuildTooltip(tip)
    local s = Data:Snapshot(Bar.RateMinutes())
    tip:SetTitle(s.capped and L.MAX_LEVEL or string.format(L.LEVEL, s.level))
    if not s.capped then
        if opt("tooltip.progress") then
            tip:AddDoubleLine(L.XP, string.format("%s / %s", BreakUpLargeNumbers(s.xp), BreakUpLargeNumbers(s.max)))
            tip:AddDoubleLine(L.PERCENT, Data.Expand("{pct}", s))
            tip:AddDoubleLine(L.REMAINING, Data.Expand("{rem} ({rempct})", s))
        end
        if opt("tooltip.rested") then
            local rested = s.rested > 0 and Data.Expand("{rested} ({restedpct})", s) or L.RESTED_NONE
            tip:AddDoubleLine(
                s.resting and (L.RESTED .. " · " .. L.RESTING) or L.RESTED,
                rested,
                nil,
                opt("colors.rested")
            )
        end
        if opt("tooltip.quests") then
            local done = opt("colors.questsDone")
            local all = Theme.RGBA(opt("colors.questsAll"))
            all[4] = 1
            tip:AddDoubleLine(L.QUESTS_DONE, Data.Short(s.done), nil, done)
            tip:AddDoubleLine(L.PROJECTED_DONE, Data.Level(s.projDone), nil, done)
            tip:AddDoubleLine(L.QUESTS_ALL, Data.Short(s.all), nil, all)
            tip:AddDoubleLine(L.PROJECTED_ALL, Data.Level(s.projAll), nil, all)
        end
        if opt("tooltip.session") then
            tip:AddLine(L.SESSION .. " · " .. Data.Duration(s.sessionSeconds), "textMuted")
            tip:AddDoubleLine(L.GAINED, Data.Short(s.gained))
            tip:AddDoubleLine(L.RATE, s.rate and Data.Short(s.rate) or L.UNKNOWN)
            tip:AddDoubleLine(L.ETA, Data.Duration(s.eta))
        end
        if opt("tooltip.kills") then
            tip:AddDoubleLine(L.KILLS, s.kills and tostring(s.kills) or L.UNKNOWN)
            if s.lastKill then
                tip:AddDoubleLine(L.LAST_KILL, Data.Short(s.lastKill))
            end
        end
    end
    if opt("tooltip.time") then
        if not s.capped then
            tip:AddDoubleLine(L.TIME_LEVEL, Data.Duration(s.levelSeconds))
        end
        if s.played then
            tip:AddDoubleLine(L.PLAYED, Data.Duration(s.played))
        end
    end
    if opt("tooltip.hint") then
        tip:AddHint(L.HINT)
    end
end

-- Frame --------------------------------------------------------------------------------------------

local function newSegment(frame, level)
    local segment = CreateFrame("Frame", nil, frame)
    segment:SetPoint("TOPLEFT")
    segment:SetPoint("BOTTOMLEFT")
    segment:SetFrameLevel(frame:GetFrameLevel() + level)
    segment.shape = Shape.New(segment)
    return segment
end

local function radius()
    return math.min(Theme.radius, math.floor(opt("layout.height") / 2))
end

local function create(self)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame.shape = Shape.New(frame)
    frame.segments = {}
    for i, key in ipairs(SEGMENTS) do
        frame.segments[key] = newSegment(frame, i)
    end
    -- Divisions and texts above the segments.
    frame.overlay = CreateFrame("Frame", nil, frame)
    frame.overlay:SetAllPoints()
    frame.overlay:SetFrameLevel(frame:GetFrameLevel() + #SEGMENTS + 1)
    frame.ticks = {}
    frame.texts = {}
    for _, point in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
        local text = Widgets.Text(frame.overlay, TEXT_SIZES.caption, "text")
        text:SetShadowOffset(1, -1)
        text:SetShadowColor(0, 0, 0, 0.9)
        text:SetJustifyH(point == "CENTER" and "CENTER" or point)
        text:SetPoint(point, point == "LEFT" and TEXT_INSET or point == "RIGHT" and -TEXT_INSET or 0, 0)
        frame.texts[point] = text
    end

    frame:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            E:OpenOptions(addonName)
        end
    end)
    frame:SetScript("OnEnter", function()
        self.hovered = true
        self:Update()
    end)
    frame:SetScript("OnLeave", function()
        self.hovered = false
        self:Update()
    end)
    Widgets.AttachTooltip(frame, function(tip)
        if opt("tooltip.enabled") then
            Bar.BuildTooltip(tip)
        end
    end, "TOP")

    self.frame = frame
    function frame.Paint()
        self:ApplyLayout()
    end
    Widgets.Track(frame)
    return frame
end

--- Size, scale, background, font and divisions. The position belongs to the Mover.
function Bar:ApplyLayout()
    local frame = self.frame
    if not frame then
        return
    end
    local width = opt("layout.width")
    frame:SetScale(opt("layout.scale"))
    frame:SetSize(width, opt("layout.height"))
    for _, text in pairs(frame.texts) do
        Widgets.SetTextSize(text, TEXT_SIZES[opt("layout.font")] or TEXT_SIZES.caption)
    end

    local count = opt("bar.ticks")
    for i = 1, math.max(count - 1, #frame.ticks) do
        local tick = frame.ticks[i]
        if not tick then
            tick = frame.overlay:CreateTexture(nil, "ARTWORK")
            frame.ticks[i] = tick
        end
        tick:SetColorTexture(Theme.Color("borderStrong"))
        tick:SetWidth(E.Pixel.Size(frame))
        tick:ClearAllPoints()
        tick:SetPoint("TOP", frame, "TOPLEFT", width * i / math.max(count, 1), -2)
        tick:SetPoint("BOTTOM", frame, "BOTTOMLEFT", width * i / math.max(count, 1), 2)
        tick:SetShown(i < count)
    end
    self:Update()
end

local function setSegment(segment, fraction, width, spec)
    local w = math.max(0, math.min(1, fraction)) * width
    segment:SetWidth(math.max(w, 1))
    segment:SetShown(w >= 1)
    Shape.Paint(segment.shape, radius(), Theme.RGBA(spec), nil)
end

--- Redraws the segments and texts from a fresh snapshot.
function Bar:Update()
    local frame = self.frame
    if not frame then
        return
    end
    self:KeepMainHidden()
    local s = Data:Snapshot(Bar.RateMinutes())
    local hide = not self.running or (s.capped and opt("bar.maxLevel") == "hide")
    frame:SetShown(not hide)
    if hide then
        return
    end
    if opt("layout.background") then
        local track = Theme.RGBA("track")
        track[4] = track[4] * Theme.opacity
        Shape.Paint(frame.shape, radius(), track, Theme.colors.border)
    else
        Shape.Paint(frame.shape, radius(), nil, nil)
    end

    local width, max = opt("layout.width"), s.max > 0 and s.max or 1
    local segments = frame.segments
    if s.capped then
        setSegment(segments.xp, 1, width, opt("colors.xp"))
        segments.rested:Hide()
        segments.questsDone:Hide()
        segments.questsAll:Hide()
    else
        setSegment(segments.xp, s.xp / max, width, opt("colors.xp"))
        setSegment(segments.rested, (s.xp + s.rested) / max, width, opt("colors.rested"))
        setSegment(segments.questsDone, (s.xp + s.done) / max, width, opt("colors.questsDone"))
        setSegment(segments.questsAll, (s.xp + s.all) / max, width, opt("colors.questsAll"))
        segments.rested:SetShown(segments.rested:IsShown() and opt("bar.rested") and s.rested > 0)
        segments.questsDone:SetShown(segments.questsDone:IsShown() and opt("bar.questsDone") and s.done > 0)
        segments.questsAll:SetShown(segments.questsAll:IsShown() and opt("bar.questsAll") and s.all > 0)
    end

    local show = opt("bar.textShow")
    local visible = show == "always" or (show == "hover" and self.hovered)
    local texts = frame.texts
    if s.capped then
        texts.LEFT:SetText("")
        texts.CENTER:SetText(L.MAX_LEVEL)
        texts.RIGHT:SetText("")
    else
        texts.LEFT:SetText(Data.Expand(opt("bar.textLeft"), s))
        texts.CENTER:SetText(Data.Expand(opt("bar.textCenter"), s))
        texts.RIGHT:SetText(Data.Expand(opt("bar.textRight"), s))
    end
    for _, text in pairs(texts) do
        text:SetShown(visible)
    end
end

function Bar:Start()
    self.running = true
    if not self.frame then
        create(self)
    end
    self:ApplyBlizzard(opt("bar.hideBlizzard"))
    self:ApplyLayout()
    -- The Mover owns the position: at the bottom center by default.
    E.Mover.Register({
        key = addonName,
        owner = addonName,
        label = E.Localize(ns.OptionsSchema.title),
        frame = self.frame,
        point = "BOTTOM",
        x = 0,
        y = 4,
        openOptions = function()
            E:OpenOptions(addonName)
        end,
    })
end

function Bar:Stop()
    self.running = false
    E.Mover.Unregister(addonName)
    self:ApplyBlizzard(nil)
    if self.frame then
        self.frame:Hide()
    end
end
