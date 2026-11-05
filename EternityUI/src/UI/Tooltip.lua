-- The suite's tooltip: one shared themed frame, filled by a build function each time it shows.
-- Colors are any spec Theme.RGBA takes.
---@type string, EternityUINamespace
local _, ns = ...
local Shape = ns.Shape
local Theme = ns.Theme
local Widgets = ns.Widgets

local PADDING = 10
local LINE = 18
local GAP = 24

local tip
local rows = {}
local used = 0

local function color(text, spec)
    local c = Theme.RGBA(spec)
    text:SetTextColor(c[1], c[2], c[3], c[4])
end

local function row()
    used = used + 1
    local entry = rows[used]
    if not entry then
        entry = { left = Widgets.Text(tip, 14, "text"), right = Widgets.Text(tip, 14, "text") }
        entry.left:SetPoint("TOPLEFT", PADDING, -PADDING - (used - 1) * LINE)
        entry.right:SetPoint("TOPRIGHT", -PADDING, -PADDING - (used - 1) * LINE)
        rows[used] = entry
    end
    entry.left:Show()
    entry.right:Show()
    entry.right:SetText("")
    return entry
end

local function create()
    tip = CreateFrame("Frame", nil, UIParent)
    tip:SetFrameStrata("TOOLTIP")
    tip:SetClampedToScreen(true)
    tip:Hide()
    tip.shape = Shape.New(tip)
    function tip:Paint()
        Theme.PaintWindow(self.shape)
    end
    Widgets.Track(tip)

    function tip:SetTitle(text)
        local entry = row()
        Widgets.SetTextSize(entry.left, 16)
        color(entry.left, "text")
        entry.left:SetText(text)
    end

    function tip:AddLine(text, spec)
        local entry = row()
        Widgets.SetTextSize(entry.left, 14)
        color(entry.left, spec or "text")
        entry.left:SetText(text)
    end

    function tip:AddDoubleLine(left, right, leftSpec, rightSpec)
        local entry = row()
        Widgets.SetTextSize(entry.left, 14)
        color(entry.left, leftSpec or "textMuted")
        color(entry.right, rightSpec or "text")
        entry.left:SetText(left)
        entry.right:SetText(right)
    end

    function tip:AddHint(text)
        self:AddLine(text, "textMuted")
    end
end

local function show(owner, build, anchor)
    if not tip then
        create()
    end
    used = 0
    for _, entry in ipairs(rows) do
        entry.left:Hide()
        entry.right:Hide()
    end
    build(tip, owner)
    if used == 0 then
        tip:Hide()
        return
    end
    local width = 0
    for i = 1, used do
        local right = rows[i].right:GetStringWidth()
        width = math.max(width, rows[i].left:GetStringWidth() + (right > 0 and right + GAP or 0))
    end
    tip:SetSize(width + PADDING * 2, used * LINE + PADDING * 2)
    tip:ClearAllPoints()
    if type(anchor) == "function" then
        anchor = anchor()
    end
    if anchor == "CURSOR" then
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale + 12)
    elseif anchor == "RIGHT" then
        tip:SetPoint("LEFT", owner, "RIGHT", 6, 0)
    elseif anchor == "BOTTOM" then
        tip:SetPoint("TOP", owner, "BOTTOM", 0, -6)
    elseif anchor == "LEFT" then
        tip:SetPoint("RIGHT", owner, "LEFT", -6, 0)
    else
        tip:SetPoint("BOTTOM", owner, "TOP", 0, 6)
    end
    tip:Show()
end

--- Shows a tooltip while the mouse is over a frame. build(tip, frame) fills it: SetTitle, AddLine,
--- AddDoubleLine and AddHint. A build that adds nothing shows nothing.
---@param frame table
---@param build fun(tip: table, frame: table)
---@param anchor string|fun(): string|nil "TOP" (default), "BOTTOM", "LEFT", "RIGHT" or "CURSOR"
function Widgets.AttachTooltip(frame, build, anchor)
    frame:HookScript("OnEnter", function(self)
        show(self, build, anchor)
    end)
    frame:HookScript("OnLeave", Widgets.HideTooltip)
end

--- Hides the tooltip, for instance when a drag starts.
function Widgets.HideTooltip()
    if tip then
        tip:Hide()
    end
end
