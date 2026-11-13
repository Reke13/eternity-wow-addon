-- EternityUI_UnitFrames: group and raid frames, on Blizzard's SecureGroupHeaderTemplate. The header
-- decides who goes in each button and shows or hides them, also in combat; we only style the
-- buttons. A new button is sized by the header's initialConfigFunction (restricted code) and
-- then calls back into Lua (CallMethod) to get its inside. All of a header's buttons are made
-- ahead of time, out of combat (startingIndex below 1), so none has to be made in combat. All
-- 85 at once at login took over a second and more than 100 MB, and one per frame still made
-- five seconds of slow frames (about 20 ms each). So the ones in use now (your group, the raid
-- when you're in one) are made one per frame, and the rest one every SLOW_GAP seconds.
-- Every attribute of a header is protected: they change only out of combat.

---@type string, EternityUIUnitFramesNamespace
local addonName, ns = ...
local Style, Frame = ns.Style, ns.Frame
local U = Style.U

local MAX = { party = 5, raid = 40, grouppets = 40 }
local BUDGET_MS = 6 -- time spent making buttons in one frame (at least one button)
local SLOW_GAP = 0.3 -- seconds between buttons of a header not in use yet

---@class EternityUIUnitFramesGroups
local Groups = { headers = {} }
ns.Groups = Groups

local POINTS = {
    down = { point = "TOP", x = 0, y = -1 },
    up = { point = "BOTTOM", x = 0, y = 1 },
    right = { point = "LEFT", x = 1, y = 0 },
    left = { point = "RIGHT", x = -1, y = 0 },
}

-- The snippet every new button runs: its size from the header, and its clicks.
local INITIAL = [[
    local header = self:GetParent()
    self:SetWidth(header:GetAttribute("etWidth"))
    self:SetHeight(header:GetAttribute("etHeight"))
    self:SetAttribute("*type1", "target")
    self:SetAttribute("*type2", "togglemenu")
    header:CallMethod("etInitialConfig", self:GetName())
]]

--- The header and its holder (what the Mover moves) for "party" or "raid".
---@param def EternityUIUnitFramesUnit
---@return table holder
function Groups.New(def)
    local holder = CreateFrame("Frame", "EternityUIUnitFrames_" .. def.key, UIParent)
    holder:SetSize(10, 10)
    holder:SetPoint("CENTER", def.x, def.y)
    -- The pets' header lists the pets of the group or raid instead of its members.
    local template = def.pets and "SecureGroupPetHeaderTemplate" or "SecureGroupHeaderTemplate"
    local header = CreateFrame("Frame", "EternityUIUnitFrames_" .. def.key .. "Header", holder, template)
    header.def = def
    function header.etInitialConfig(_, name)
        local button = _G[name]
        if button then
            -- Clicks can't be registered from restricted code; buttons are made out of combat.
            if not InCombatLockdown() then
                button:RegisterForClicks("AnyUp")
            end
            -- Timed apart in the startup report (/et startup) when the metrics are on.
            local startup = EternityUI.Startup
            if startup and startup.Measure then
                startup.Measure(addonName, "button: create", Frame.Build, button, def)
                startup.Measure(addonName, "button: style", Frame.Style, button)
            else
                Frame.Build(button, def)
                Frame.Style(button)
            end
        end
    end
    header:SetAttribute("template", "SecureUnitButtonTemplate")
    header:SetAttribute("initialConfigFunction", INITIAL)
    holder.header = header
    Groups.headers[def.key] = holder
    return holder
end

-- The header's attributes from the options.
local function configure(holder)
    local header, def = holder.header, holder.header.def
    local key = def.key
    local width, height = U(key, "", "width"), U(key, "", "height")
    local gap = U(key, "", "gap")
    header:SetAttribute("etWidth", width)
    header:SetAttribute("etHeight", height)
    local grow = POINTS[U(key, "", "growth")] or POINTS.down
    header:SetAttribute("point", grow.point)
    header:SetAttribute("xOffset", grow.x * gap)
    header:SetAttribute("yOffset", grow.y * gap)
    header:ClearAllPoints()
    header:SetPoint(grow.point == "BOTTOM" and "BOTTOMLEFT" or (grow.point == "RIGHT" and "TOPRIGHT" or "TOPLEFT"), holder,
        grow.point == "BOTTOM" and "BOTTOMLEFT" or (grow.point == "RIGHT" and "TOPRIGHT" or "TOPLEFT"))
    local columns, perColumn = 1, MAX[key]
    if def.pets then
        header:SetAttribute("showParty", U(key, "", "inParty"))
        header:SetAttribute("showRaid", U(key, "", "inRaid"))
        header:SetAttribute("showPlayer", U(key, "", "showOwn"))
        header:SetAttribute("showSolo", U(key, "", "showOwn"))
        perColumn = U(key, "", "perColumn")
        columns = U(key, "", "columns")
        header:SetAttribute("unitsPerColumn", perColumn)
        header:SetAttribute("maxColumns", columns)
        header:SetAttribute("columnSpacing", gap)
        header:SetAttribute("columnAnchorPoint", U(key, "", "columnGrowth") == "left" and "RIGHT" or "LEFT")
    elseif key == "party" then
        header:SetAttribute("showParty", true)
        header:SetAttribute("showPlayer", U(key, "", "showPlayer"))
        header:SetAttribute("showRaid", U(key, "", "showInRaid"))
        header:SetAttribute("showSolo", false)
        -- In a raid, at most one column of five.
        header:SetAttribute("unitsPerColumn", 5)
        header:SetAttribute("maxColumns", 1)
    else
        header:SetAttribute("showRaid", true)
        header:SetAttribute("showParty", U(key, "", "showSolo"))
        header:SetAttribute("showSolo", U(key, "", "showSolo"))
        header:SetAttribute("showPlayer", true)
        local by = U(key, "", "groupBy")
        if by == "group" then
            header:SetAttribute("groupBy", "GROUP")
            header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
            header:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
        elseif by == "class" then
            header:SetAttribute("groupBy", "CLASS")
            header:SetAttribute("groupingOrder", "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST,SHAMAN,MAGE,WARLOCK,DRUID,DEATHKNIGHT,MONK,DEMONHUNTER,EVOKER")
            header:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
        else
            header:SetAttribute("groupBy", nil)
            header:SetAttribute("groupingOrder", nil)
            header:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
        end
        perColumn = U(key, "", "perColumn")
        columns = U(key, "", "columns")
        header:SetAttribute("unitsPerColumn", perColumn)
        header:SetAttribute("maxColumns", columns)
        header:SetAttribute("columnSpacing", gap)
        header:SetAttribute("columnAnchorPoint", U(key, "", "columnGrowth") == "left" and "RIGHT" or "LEFT")
    end
    -- The holder covers the whole block, for the Mover.
    local rows = math.min(perColumn, MAX[key])
    local across, down = width, height
    if grow.point == "LEFT" or grow.point == "RIGHT" then
        across = rows * width + (rows - 1) * gap
    else
        down = rows * height + (rows - 1) * gap
        across = columns * width + (columns - 1) * gap
    end
    holder:SetSize(across, down)
    holder:SetScale(U(key, "", "scale"))
end

local queue = {} -- holders whose buttons are still being made, in order
local builder
local nextSlow = 0 -- GetTime() when the next button not in use may be made

-- Makes one more of a header's buttons (out of combat, with the header shown): for a moment it
-- lists that many units ahead of the real ones. True once it has all it can have (the options
-- may allow fewer than MAX).
local function buildOne(holder)
    local header = holder.header
    local count = (holder.made or 0) + 1
    holder.made = count
    header:SetAttribute("startingIndex", -count + 1)
    header:SetAttribute("startingIndex", 1)
    if count >= MAX[header.def.key] or not header:GetAttribute("child" .. count) then
        holder.built = true
    end
    return holder.built
end

-- Drops the holders done or switched off.
local function prune()
    for i = #queue, 1, -1 do
        local holder = queue[i]
        if holder.built or not holder.header:IsShown() then
            holder.queued = nil
            table.remove(queue, i)
        end
    end
end

--- True when a header's buttons may be needed now: your group, or the raid while you're in one.
---@param key string
---@return boolean
function Groups.InUse(key)
    if key == "party" then
        return true
    elseif key == "raid" then
        return IsInRaid() and true or false
    end
    return IsInGroup() and true or false -- the group's pets
end

-- The first holder still making buttons: one in use, or else (urgent false) any.
local function nextHolder(urgent)
    prune()
    for _, holder in ipairs(queue) do
        if Groups.InUse(holder.header.def.key) then
            return holder
        end
    end
    if urgent then
        return nil
    end
    return queue[1]
end

local function work()
    local start = debugprofilestop()
    repeat
        local holder = nextHolder(true)
        if not holder then
            break
        end
        buildOne(holder)
    until debugprofilestop() - start >= BUDGET_MS
    -- Nothing in use is waiting: one button not in use, now and then.
    if not nextHolder(true) and GetTime() >= nextSlow then
        local holder = nextHolder(false)
        if holder then
            buildOne(holder)
            nextSlow = GetTime() + SLOW_GAP
        end
    end
end

local function step()
    if InCombatLockdown() then
        return -- protected: it goes on after combat
    end
    if not nextHolder(false) then
        builder:SetScript("OnUpdate", nil)
        return
    end
    -- Shows in the startup report (/et startup) when the metrics are on.
    local startup = EternityUI.Startup
    if startup and startup.Measure then
        startup.Measure(addonName, "group buttons", work)
    else
        work()
    end
end

-- Queues a header's buttons to be made over the next frames.
local function prebuild(holder)
    if holder.built or holder.queued then
        return
    end
    holder.queued = true
    queue[#queue + 1] = holder
    builder = builder or CreateFrame("Frame")
    builder:SetScript("OnUpdate", step)
end

--- Headers still making their buttons.
---@return integer
function Groups.Pending()
    local count = 0
    for _, holder in ipairs(queue) do
        if not holder.built then
            count = count + 1
        end
    end
    return count
end

--- Makes every queued button now (out of combat). For the tests.
function Groups.FinishBuilding()
    while not InCombatLockdown() do
        local holder = nextHolder(false)
        if not holder then
            break
        end
        buildOne(holder)
    end
end

--- Applies the options to a group header (out of combat): attributes, sizes, shown or not.
function Groups.Apply(holder, enabled)
    local header = holder.header
    configure(holder)
    if enabled then
        header:Show()
        prebuild(holder)
        for i = 1, MAX[header.def.key] do
            local button = header:GetAttribute("child" .. i)
            if button and button.uf then
                Frame.Style(button)
            end
        end
        header:Show()
    else
        header:Hide()
    end
end
