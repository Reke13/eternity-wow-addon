-- EternityUI_UnitFrames: the options' preview. Over the frame picker sits a strip with a "Show
-- preview" button; it opens a window beside the options with the picked frame as your options
-- draw it, filled with your own character (your target's, for the target frames, when you have
-- one). The group and the raid show sample frames laid out with their growth, gap and columns.
-- Every option changed redraws it at once (ModulePage calls the strip's Refresh). The preview's
-- frames are plain frames, not secure buttons: they can't be clicked and never take part in the
-- real frames' events.

---@type string, EternityUIUnitFramesNamespace
local addonName, ns = ...
local E = EternityUI
local Widgets = E.Widgets
local L, Style, Elements = ns.L, ns.Style, ns.Elements
local U = Style.U

local STRIP = 34
local PAD = 16
local MAX_W, MAX_H = 760, 560
local TICK = 0.5
local SAMPLES = { party = 4, raid = 10, grouppets = 4 }
local CAST_ICON = 135812
local ICONS = "Interface\\Icons\\"

-- A made-up group: name, class, health and power (0-1), and what's going on with each.
local PEOPLE = {
    { name = "Aldric", class = "WARRIOR", hp = 0.92, pp = 0.35, level = 60, leader = true, raid = 8, ready = "ready" },
    { name = "Brenna", class = "PRIEST", hp = 0.64, pp = 0.81, level = 60, ready = "ready", target = true },
    { name = "Corvin", class = "ROGUE", hp = 0.38, pp = 0.6, level = 59, raid = 1, ready = "waiting" },
    { name = "Dalia", class = "MAGE", hp = 0, pp = 0, level = 60, dead = true, ready = "notready" },
    { name = "Eryndor", class = "DRUID", hp = 1, pp = 0.55, level = 58, ready = "ready" },
    { name = "Fenna", class = "HUNTER", hp = 0.77, pp = 0.9, level = 60, ready = "ready" },
    { name = "Garrick", class = "PALADIN", hp = 0.51, pp = 0.4, level = 60, raid = 4, ready = "waiting" },
    { name = "Hilde", class = "WARLOCK", hp = 0.86, pp = 0.7, level = 57, offline = true },
    { name = "Ivo", class = "SHAMAN", hp = 0.23, pp = 0.3, level = 60, ready = "ready" },
    { name = "Jessa", class = "PRIEST", hp = 0.98, pp = 0.95, level = 60, ready = "ready" },
}
-- Made-up pets, for the group pets' preview.
local PETS = {
    { name = "Garra", class = "HUNTER", hp = 0.88, pp = 0.7, level = 59 },
    { name = "Ascua", class = "WARLOCK", hp = 0.55, pp = 0.4, level = 60, raid = 2 },
    { name = "Sombra", class = "HUNTER", hp = 0.31, pp = 0.9, level = 58 },
    { name = "Fango", class = "WARLOCK", hp = 1, pp = 0.6, level = 60 },
}
local BUFFS = { "Spell_Holy_WordFortitude", "Spell_Nature_Regeneration", "Spell_Holy_MagicalSentry", "Spell_Nature_Rejuvenation" }
local DEBUFFS = {
    { icon = "Spell_Shadow_ShadowWordPain", kind = "Magic" },
    { icon = "Spell_Shadow_CurseOfSargeras", kind = "Curse" },
    { icon = "Spell_Nature_NullifyDisease", kind = "Disease" },
    { icon = "Ability_Poisons", kind = "Poison" },
    { icon = "Ability_Gouge", kind = "none" },
}
local MAX_HEALTH, MAX_POWER = 4200, 3000

---@class EternityUIUnitFramesPreview
---@field window table?
---@field frames table[] pooled preview frames
---@field key string the frame shown
local Preview = { frames = {}, key = "player" }
ns.Preview = Preview

-- The unit a preview frame shows: the real one when it's there, yourself otherwise.
local function unitFor(def)
    local unit = def.group and "player" or def.unit
    if unit ~= "player" and not UnitExists(unit) then
        return "player"
    end
    return unit
end

local function sample(index)
    local f = Preview.frames[index]
    if not f then
        f = CreateFrame("Button", nil, Preview.window.content)
        f.previewOnly = true
        Elements.Create(f)
        Preview.frames[index] = f
    end
    return f
end

-- A pretend cast, so its bar can be seen.
local function fakeCast(f)
    local cast = f.cast
    if not cast.enabled then
        return
    end
    cast:SetScript("OnUpdate", nil)
    cast:SetMinMaxValues(0, 1)
    cast:SetValue(0.6)
    cast.name:SetText(L.PREVIEW_CAST)
    cast.time:SetText("1.2")
    cast.icon:SetTexture(CAST_ICON)
    local c = Style.Color("cast")
    cast:GetStatusBarTexture():SetVertexColor(c[1], c[2], c[3], 1)
    cast:Show()
end

-- Sample auras -------------------------------------------------------------------------------------

local function sampleIcon(f, index)
    f.sampleAuras = f.sampleAuras or {}
    local b = f.sampleAuras[index]
    if not b then
        b = CreateFrame("Frame", nil, f.auras)
        b.border = b:CreateTexture(nil, "BACKGROUND")
        b.border:SetAllPoints()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cooldown:SetDrawEdge(false)
        b.cooldown:SetReverse(true)
        b.cooldown:SetHideCountdownNumbers(true)
        b.count = b:CreateFontString(nil, "OVERLAY")
        b.count:SetPoint("BOTTOMRIGHT", 1, 0)
        f.sampleAuras[index] = b
    end
    return b
end

-- Forever has no DebuffTypeColor global: the made-up debuffs use the usual dispel colors.
local TYPE_COLORS = {
    Magic = { 0.2, 0.6, 1 },
    Curse = { 0.6, 0, 1 },
    Disease = { 0.6, 0.4, 0 },
    Poison = { 0, 0.6, 0 },
}

local function typeColor(kind)
    local c = TYPE_COLORS[kind] or { 0.8, 0, 0 }
    return c[1], c[2], c[3]
end

-- Made-up buffs and debuffs where the real ones would be, with the frame's options.
local function sampleAuras(f, seed)
    local AuraBox = ns.AuraBox
    local key = f.uf.key
    for _, container in pairs(f.auraContainers or {}) do
        container:Hide()
    end
    local size, perRow = U(key, "Auras", "size"), math.max(U(key, "Auras", "perRow"), 1)
    local gap = AuraBox.GAP
    local swipe, border = U(key, "Auras", "swipe"), U(key, "Auras", "dispelBorder")
    local used = 0
    local kinds = {
        { key = "debuffs", on = U(key, "Debuffs", "enabled"), max = U(key, "Debuffs", "max"), count = 1 + seed % 3 },
        { key = "buffs", on = U(key, "Buffs", "enabled"), max = U(key, "Buffs", "max"), count = 2 + seed % 3 },
    }
    for _, kind in ipairs(kinds) do
        local box = f.auraBoxes and f.auraBoxes[kind.key]
        local position = U(key, "Auras", kind.key == "buffs" and "buffPosition" or "debuffPosition")
        local place = AuraBox.PLACES[position] or AuraBox.PLACES.below
        local count = kind.on and math.min(kind.count, kind.max) or 0
        for i = 1, count do
            used = used + 1
            local b = sampleIcon(f, used)
            local inset = (kind.key == "debuffs" and border) and 2 or 1
            b:SetSize(size, size)
            b.icon:ClearAllPoints()
            b.icon:SetPoint("TOPLEFT", inset, -inset)
            b.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
            b.cooldown:SetAllPoints(b.icon)
            if kind.key == "debuffs" then
                local debuff = DEBUFFS[(seed + i - 1) % #DEBUFFS + 1]
                b.icon:SetTexture(ICONS .. debuff.icon)
                if border then
                    b.border:SetColorTexture(typeColor(debuff.kind))
                else
                    b.border:SetColorTexture(0, 0, 0, 0.8)
                end
            else
                b.icon:SetTexture(ICONS .. BUFFS[(seed + i - 1) % #BUFFS + 1])
                b.border:SetColorTexture(0, 0, 0, 0.8)
            end
            b.cooldown:SetDrawSwipe(swipe and true or false)
            b.cooldown:SetCooldown(GetTime() - 10 * i, 30)
            Style.Font(b.count, math.max(8, math.floor(size * 0.5)))
            b.count:SetText(i == 1 and kind.key == "buffs" and "3" or "")
            local column, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            local dx = (place.across == "Left" and -1 or 1) * column * (size + gap)
            local dy = (place.down == "Up" and 1 or -1) * row * (size + gap)
            b:ClearAllPoints()
            if box then
                b:SetPoint(place.point, box, place.point, dx, dy)
            end
            b:Show()
        end
    end
    for i = used + 1, #(f.sampleAuras or {}) do
        f.sampleAuras[i]:Hide()
    end
end

-- A made-up person on a preview frame: name, class color, health, power and the icons.
local function samplePerson(f, person, index)
    local key = f.uf.key
    local function on(id)
        return U(key, "Indicators", id)
    end
    -- Health.
    f.health:SetMinMaxValues(0, MAX_HEALTH)
    f.health:SetValue(MAX_HEALTH * person.hp)
    local color
    if person.dead or person.offline then
        color = Style.Color("offline")
    else
        color = (Style.Opt("colors.classHealth") and Style.ClassColor(person.class)) or Style.Color("health")
    end
    Style.BarColor(f.health, color[1], color[2], color[3])
    local left = U(key, "Text", "healthLeft")
    if left == "none" then
        f.healthLeft:SetText("")
    elseif left == "level" then
        f.healthLeft:SetText(tostring(person.level))
    elseif left == "nameLevel" then
        f.healthLeft:SetText(person.level .. " " .. person.name)
    else
        f.healthLeft:SetText(person.name)
    end
    local right = Style.TextMode(key, "healthRight")
    local current = math.floor(MAX_HEALTH * person.hp)
    f.healthRight:SetAlpha(1)
    if on("status") and (person.dead or person.offline) then
        f.healthRight:SetText(person.dead and L.DEAD or L.OFFLINE)
    elseif right == "none" or Style.NumberStyle(key) == "none" then
        f.healthRight:SetText("")
    elseif right == "percent" then
        f.healthRight:SetFormattedText("%d%%", math.floor(person.hp * 100 + 0.5))
    elseif right == "currentMax" then
        Style.SetNumbersAs(Style.NumberStyle(key), f.healthRight, "# / #", current, MAX_HEALTH)
    elseif right == "currentPercent" then
        Style.SetNumbersAs(Style.NumberStyle(key), f.healthRight, "#  %d%%", current, math.floor(person.hp * 100 + 0.5))
    elseif right == "missing" then
        if current < MAX_HEALTH then
            Style.SetNumbersAs(Style.NumberStyle(key), f.healthRight, "-#", MAX_HEALTH - current)
        else
            f.healthRight:SetText("")
        end
    else
        Style.SetNumbersAs(Style.NumberStyle(key), f.healthRight, "#", current)
    end
    -- Heals on their way and shields, on some of them.
    f.heals:SetMinMaxValues(0, MAX_HEALTH)
    -- Nearly full ones get one too, to show a heal going past full health.
    local healed = not person.dead and not person.offline and (person.hp < 0.8 or person.hp >= 0.9)
    f.heals:SetValue(healed and MAX_HEALTH * 0.15 or 0)
    f.absorbs:SetMinMaxValues(0, MAX_HEALTH)
    f.absorbs:SetValue((index % 2 == 0 and not person.dead) and MAX_HEALTH * 0.1 or 0)
    -- Power.
    if f.power:IsShown() then
        local mana = person.class ~= "WARRIOR" and person.class ~= "ROGUE"
        f.power:SetMinMaxValues(0, MAX_POWER)
        f.power:SetValue(MAX_POWER * person.pp)
        local pc = Style.PowerColor(mana and 0 or (person.class == "WARRIOR" and 1 or 3), mana and "MANA" or (person.class == "WARRIOR" and "RAGE" or "ENERGY"))
        Style.BarColor(f.power, pc[1], pc[2], pc[3])
        local mode = Style.TextMode(key, "powerText")
        if mode == "none" or Style.NumberStyle(key) == "none" then
            f.powerText:SetText("")
        elseif mode == "percent" then
            f.powerText:SetFormattedText("%d%%", math.floor(person.pp * 100 + 0.5))
        elseif mode == "currentMax" then
            Style.SetNumbersAs(Style.NumberStyle(key), f.powerText, "# / #", math.floor(MAX_POWER * person.pp), MAX_POWER)
        else
            Style.SetNumbersAs(Style.NumberStyle(key), f.powerText, "#", math.floor(MAX_POWER * person.pp))
        end
    end
    -- Portrait: the class icon (a made-up person has no model).
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[person.class]
    if f.portrait:IsShown() and coords then
        f.portrait.model:Hide()
        f.portrait.texture:Show()
        f.portrait.texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        f.portrait.texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
    -- Icons.
    f.leaderIcon:SetAlpha(1)
    f.leaderIcon:SetShown(on("leader") and person.leader or false)
    if on("raidTarget") and person.raid and SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(f.raidIcon, person.raid)
        f.raidIcon:Show()
    else
        f.raidIcon:Hide()
    end
    if f.uf.group and on("readyCheck") and person.ready then
        local textures = {
            ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
            notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
            waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
        }
        f.readyIcon:SetTexture(textures[person.ready])
        f.readyIcon:Show()
    else
        f.readyIcon:Hide()
    end
    f.targeted.border:SetAlpha((f.uf.group and on("targetHighlight") and person.target) and 1 or 0)
    local rangeAlpha = on("rangeAlpha")
    f:SetAlpha((rangeAlpha and index == 3) and rangeAlpha or 1)
end

-- Where sample n goes (0-based) in a group or raid layout, in frame steps.
local function slot(def, n, count)
    local key = def.key
    local growth = U(key, "", "growth")
    if key == "raid" or ns.ByKey[key].pets then
        local perColumn = math.max(U(key, "", "perColumn"), 1)
        local column, row = math.floor(n / perColumn), n % perColumn
        local columns = math.min(math.ceil(count / perColumn), U(key, "", "columns"))
        if column >= columns then
            return nil
        end
        local dx = U(key, "", "columnGrowth") == "left" and -column or column
        return dx, growth == "up" and row or -row
    end
    if growth == "up" then
        return 0, n
    elseif growth == "right" then
        return n, 0
    elseif growth == "left" then
        return -n, 0
    end
    return 0, -n
end

--- Redraws the window for the frame shown.
function Preview.Draw()
    local w = Preview.window
    if not (w and w:IsShown()) then
        return
    end
    local def = ns.ByKey[Preview.key] or ns.ByKey.player
    local key = def.key
    local width, height = U(key, "", "width"), U(key, "", "height")
    local gap = def.group and U(key, "", "gap") or 0
    local count = def.group and SAMPLES[key] or 1
    w.title:SetText(L.PREVIEW_TITLE:format(def.label))
    local minX, maxX, maxY, minY = 0, 0, 0, 0
    local used = 0
    for n = 0, count - 1 do
        local sx, sy = 0, 0
        if def.group then
            sx, sy = slot(def, n, count)
        end
        if sx then
            used = used + 1
            local f = sample(used)
            f.uf = def
            f.unit = unitFor(def)
            f:SetSize(width, height)
            Elements.Layout(f, width, height)
            f:ClearAllPoints()
            local x, y = sx * (width + gap), sy * (height + gap)
            f:SetPoint("TOPLEFT", w.content, "TOPLEFT", x, y)
            f:Show()
            Elements.UpdateAll(f)
            if def.group then
                local list = def.pets and PETS or PEOPLE
                samplePerson(f, list[(n % #list) + 1], n + 1)
            else
                -- The real unit, with the icons a fight would show.
                if U(key, "Indicators", "combat") and f.uf.player then
                    f.combatIcon:Show()
                end
                if U(key, "Indicators", "raidTarget") and SetRaidTargetIconTexture then
                    SetRaidTargetIconTexture(f.raidIcon, 8)
                    f.raidIcon:Show()
                end
            end
            sampleAuras(f, n)
            fakeCast(f)
            minX, maxX = math.min(minX, x), math.max(maxX, x + width)
            maxY, minY = math.max(maxY, y), math.min(minY, y - height)
        end
    end
    for i = used + 1, #Preview.frames do
        Preview.frames[i]:Hide()
    end
    -- Room around for texts, cast bars and auras outside the frames.
    local margin = math.max(U(key, "Auras", "size") * 2 + 24, 60)
    local spanW, spanH = (maxX - minX) + margin * 2, (maxY - minY) + margin * 2
    local scale = math.min(1, (MAX_W - PAD * 2) / spanW, (MAX_H - 60) / spanH) * U(key, "", "scale")
    w.content:SetScale(scale)
    w:SetSize(math.max(260, spanW * scale + PAD * 2), math.max(160, spanH * scale + 60))
    -- Offsets inside content are scaled with it: put its corner where the scaled block fits.
    w.content:ClearAllPoints()
    w.content:SetPoint("TOPLEFT", w.body, "TOPLEFT", (PAD + (margin - minX) * scale) / scale, -(PAD + (margin + maxY) * scale) / scale)
end

local function build()
    local w = Widgets.Window("EternityUIUnitFramesPreview", L.PREVIEW_TITLE:format(""), false)
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
    end)
    w.content = CreateFrame("Frame", nil, w.body)
    w.content:SetSize(1, 1)
    w.note = Widgets.Text(w.body, 12, "muted")
    w.note:SetPoint("BOTTOMLEFT", PAD, 10)
    w.note:SetPoint("BOTTOMRIGHT", -PAD, 10)
    w.note:SetJustifyH("LEFT")
    w.note:SetText(L.PREVIEW_NOTE)
    local elapsed = 0
    w:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= TICK then
            elapsed = 0
            -- Only the real units move: the made-up group stays as it is.
            local def = ns.ByKey[Preview.key]
            if def and not def.group then
                for _, f in ipairs(Preview.frames) do
                    if f:IsShown() and f.unit then
                        Elements.UpdateHealth(f)
                        Elements.UpdatePower(f)
                    end
                end
            end
        end
    end)
    w:SetScript("OnShow", Preview.Draw)
    w:HookScript("OnHide", function()
        if Preview.strip then
            Preview.strip.Refresh()
        end
    end)
    Preview.window = w
    return w
end

--- Opens or closes the window, beside the options.
function Preview.Toggle()
    local w = Preview.window or build()
    if w:IsShown() then
        w:Hide()
        return
    end
    w:ClearAllPoints()
    local options = E.OptionsWindow and E.OptionsWindow.frame
    if options and options:IsShown() then
        w:SetPoint("TOPLEFT", options, "TOPRIGHT", 12, 0)
    else
        w:SetPoint("CENTER", 300, 0)
    end
    w:Show()
    if Preview.strip then
        Preview.strip.Refresh()
    end
end

--- Shows another frame (the options' picker).
---@param id string a frame key, or "general"
function Preview.Pick(id)
    Preview.key = ns.ByKey[id] and id or Preview.key
    Preview.Draw()
end

--- The strip over the frame picker (see definition.tabs: tab.preview).
---@param parent table
---@return table
function Preview.Strip(parent)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(STRIP)
    strip.button = Widgets.Button(strip, L.PREVIEW_SHOW, "ghost", Preview.Toggle)
    strip.button:SetHeight(30)
    strip.button:SetPoint("LEFT")
    strip.hint = Widgets.Text(strip, 12, "muted")
    strip.hint:SetPoint("LEFT", strip.button, "RIGHT", 12, 0)
    strip.hint:SetPoint("RIGHT")
    strip.hint:SetJustifyH("LEFT")
    strip.hint:SetText(L.PREVIEW_HINT)
    function strip.Refresh(_, id)
        if type(id) == "string" then
            Preview.Pick(id)
        else
            Preview.Draw()
        end
        local open = Preview.window and Preview.window:IsShown()
        strip.button.label:SetText(open and L.PREVIEW_HIDE or L.PREVIEW_SHOW)
        strip.button:SetWidth(strip.button.label:GetStringWidth() + 28)
    end
    -- ModulePage calls it with ":" (self, picked id).
    local refresh = strip.Refresh
    strip.Refresh = function(self, id)
        if self ~= strip then
            id = self
        end
        refresh(strip, id)
    end
    strip:HookScript("OnHide", function()
        if Preview.window then
            Preview.window:Hide()
        end
    end)
    Preview.strip = strip
    strip.Refresh(strip)
    return strip
end
