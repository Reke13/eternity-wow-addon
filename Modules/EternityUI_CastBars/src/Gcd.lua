-- The global cooldown bar: under or over the player's cast bar (anchored to it) or free in Edit
-- Mode. Forever has no global cooldown spell (61304 is Retail's), so the cooldown of a baseline
-- spell of the player's class that has no cooldown of its own is read instead (the idea comes
-- from NaowhForever). It runs on C_Spell.GetSpellCooldownDuration (a Duration object, secret-safe);
-- plain start and duration are only a fallback. SpellCooldownInfo.isOnGCD is never secret.

---@type string, EternityUICastBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = E.Theme
local Cast, Timer, L = ns.Cast, ns.Timer, ns.L

local FALLBACK = 61304
-- A filler without a cooldown per class (Forever classes; the rest use 61304).
local CLASS_SPELLS = {
    WARRIOR = 6673, -- Battle Shout
    PALADIN = 635, -- Holy Light
    HUNTER = 1978, -- Serpent Sting
    ROGUE = 1752, -- Sinister Strike
    PRIEST = 585, -- Smite
    SHAMAN = 403, -- Lightning Bolt
    MAGE = 133, -- Fireball
    WARLOCK = 686, -- Shadow Bolt
    DRUID = 5176, -- Wrath
}
local PREVIEW = 0.6

---@class EternityUICastBarsGcd
---@field frame table Timer bar
---@field spell number spell whose cooldown is read
---@field player EternityUICastBar? the player's bar it hangs from
---@field registered boolean? it's an Mover element (free)
---@field enabled boolean?
---@field previewing boolean?
---@field running boolean?
local Gcd = { CLASS_SPELLS = CLASS_SPELLS, FALLBACK = FALLBACK }
Gcd.__index = Gcd
ns.Gcd = Gcd

local function opt(path)
    return E.store:Get(addonName, path)
end

local function try(fn, ...)
    if not fn then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function known(spell)
    if IsPlayerSpell then
        return try(IsPlayerSpell, spell) == true
    end
    return C_SpellBook ~= nil and try(C_SpellBook.IsSpellKnown, spell) == true
end

--- The spell whose cooldown is the GCD for this character.
---@return number
function Gcd.FindSpell()
    local _, class = UnitClass("player")
    local spell = CLASS_SPELLS[class]
    if spell and known(spell) then
        return spell
    end
    return FALLBACK
end

---@return EternityUICastBarsGcd
function Gcd.New()
    local self = setmetatable({ key = addonName .. ".gcd", spell = FALLBACK }, Gcd)
    local frame = Timer.Create(UIParent, "EternityUICastBarGCD")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame.onDone = function()
        self:Stop()
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "SPELLS_CHANGED" then
            self.spell = Gcd.FindSpell()
        end
        self:Update()
    end)
    self.frame = frame
    return self
end

local function unregister(self)
    if self.registered then
        self.registered = false
        E.Mover.Unregister(self.key)
    end
end

--- Size, color and place: hanging from the player's bar (when it's on) or an Mover element.
---@param player EternityUICastBar
function Gcd:ApplyLayout(player)
    local frame = self.frame
    local attach = opt("gcd.attach")
    local anchor = attach ~= "free" and player.enabled and player.frame.background
    local height = opt("layout.gcdHeight")
    frame:SetScale(opt("layout.scale"))
    Timer.Layout(frame, anchor and nil or opt("layout.gcdWidth"), height, Theme.RGBA(opt("colors.gcd")))
    frame.label:SetText(self.previewing and not self.running and L.GCD or "")
    if anchor then
        unregister(self)
        local gap = opt("gcd.gap")
        frame:ClearAllPoints()
        if attach == "above" then
            frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, gap)
            frame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, gap)
        else
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
            frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -gap)
        end
    elseif not self.registered then
        self.registered = true
        E.Mover.Register({
            key = self.key,
            owner = addonName,
            label = L.GCD,
            frame = frame,
            point = "BOTTOM",
            x = 0,
            y = 196,
        })
    end
end

--- Reads the GCD and shows or hides the bar (called on SPELL_UPDATE_COOLDOWN).
function Gcd:Update()
    if not self.enabled then
        return
    end
    local frame = self.frame
    local info = C_Spell and try(C_Spell.GetSpellCooldown, self.spell)
    if type(info) ~= "table" then
        self:Stop()
        return
    end
    local onGCD = Cast.Plain(info.isOnGCD)
    if self.spell == FALLBACK then
        -- 61304 is the GCD itself: any active cooldown on it is the GCD.
        onGCD = onGCD or Cast.Plain(info.isActive)
    end
    local start, total = Cast.Plain(info.startTime), Cast.Plain(info.duration)
    if onGCD == nil and start and total then
        -- Clients without isOnGCD: a short cooldown on a spell that has none is the GCD.
        onGCD = total > 0 and total <= 2
    end
    if onGCD ~= true then
        self:Stop()
        return
    end
    self.running = true
    frame.label:SetText("")
    local duration = C_Spell.GetSpellCooldownDuration and try(C_Spell.GetSpellCooldownDuration, self.spell)
    if duration and Timer.Run(frame, duration) then
        return
    end
    if start and total and total > 0 then
        Timer.RunPlain(frame, start, total)
    else
        self:Stop()
    end
end

--- Ends the GCD on screen (back to the preview while Mover is open).
function Gcd:Stop()
    self.running = false
    if self.previewing then
        Timer.SetStatic(self.frame, PREVIEW)
        self.frame.label:SetText(L.GCD)
        self.frame:Show()
    else
        Timer.Stop(self.frame)
    end
end

---@param on boolean
function Gcd:SetPreview(on)
    self.previewing = on and true or false
    if not self.running then
        self:Stop()
    end
end

---@param player EternityUICastBar
function Gcd:Enable(player)
    if not self.enabled then
        self.enabled = true
        self.spell = Gcd.FindSpell()
        for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED" }) do
            pcall(self.frame.RegisterEvent, self.frame, event)
        end
    end
    self:ApplyLayout(player)
end

function Gcd:Disable()
    if not self.enabled then
        return
    end
    self.enabled = false
    self.frame:UnregisterAllEvents()
    unregister(self)
    self.previewing, self.running = false, false
    Timer.Stop(self.frame)
end
