-- The "i" beside a title: a small round mark whose tooltip holds the description, so the options
-- window keeps descriptions out of the way. A plain frame, so it answers in combat too.
---@type string, EternityUINamespace
local _, ns = ...
local Theme = ns.Theme
local Widgets = ns.Widgets

local SIZE = 16
-- Characters per tooltip line (the suite's tooltip doesn't wrap).
local WIDTH = 60

--- Lines of at most `width` characters, broken between words.
---@param text string
---@param width integer
---@return string[]
function Widgets.WrapLines(text, width)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        if line ~= "" and #line + 1 + #word > width then
            lines[#lines + 1] = line
            line = word
        else
            line = line == "" and word or (line .. " " .. word)
        end
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

--- An "i" on parent. info:Set(title, text, sections) changes what its tooltip says: the title,
--- the text, then each { title, text } of sections under it. It hides with nothing to say.
---@param parent table
---@param title string?
---@param text string?
---@param sections table[]?
---@return table
function Widgets.Info(parent, title, text)
    local info = CreateFrame("Frame", nil, parent)
    info:SetSize(SIZE, SIZE)
    info:EnableMouse(true)
    -- A soft round disc (a 9-sliced border isn't round this small) with the "i" on it.
    info.disc = info:CreateTexture(nil, "BACKGROUND")
    info.disc:SetAllPoints()
    info.disc:SetTexture(Theme.MEDIA .. "circle.tga")
    info.mark = info:CreateFontString(nil, "OVERLAY")
    info.mark:SetPoint("CENTER", 0, 0)
    info.mark:SetFont(Theme.font, 11 * Theme.fontScale, "")
    info.mark:SetText("i")

    local hovered = false
    function info:Paint()
        local colors = Theme.colors
        local disc = hovered and colors.accent or colors.muted
        self.disc:SetVertexColor(disc[1], disc[2], disc[3], hovered and 0.9 or 0.22)
        local mark = hovered and colors.onAccent or colors.text
        self.mark:SetFont(Theme.font, 11 * Theme.fontScale, "")
        self.mark:SetTextColor(mark[1], mark[2], mark[3], hovered and 1 or 0.85)
    end
    Widgets.Track(info)
    info:SetScript("OnEnter", function(self)
        hovered = true
        self:Paint()
    end)
    info:SetScript("OnLeave", function(self)
        hovered = false
        self:Paint()
    end)

    function info:Set(newTitle, newText, sections)
        self.title, self.text, self.sections = newTitle, newText, sections or {}
        local any = newText ~= nil and newText ~= ""
        for _, section in ipairs(self.sections) do
            any = any or (section[2] ~= nil and section[2] ~= "")
        end
        self:SetShown(any)
    end

    --- Fills the suite's tooltip: the title, then the text wrapped, then the sections.
    function info:FillTooltip(tip)
        if self.title and self.title ~= "" then
            tip:SetTitle(self.title)
        end
        for _, line in ipairs(Widgets.WrapLines(self.text or "", WIDTH)) do
            tip:AddLine(line, "textMuted")
        end
        for _, section in ipairs(self.sections) do
            if section[2] and section[2] ~= "" then
                tip:AddLine(" ")
                tip:AddLine(section[1], "text")
                for _, line in ipairs(Widgets.WrapLines(section[2], WIDTH)) do
                    tip:AddLine(line, "textMuted")
                end
            end
        end
    end
    Widgets.AttachTooltip(info, function(tip)
        info:FillTooltip(tip)
    end, "RIGHT")

    info:Set(title, text)
    return info
end
