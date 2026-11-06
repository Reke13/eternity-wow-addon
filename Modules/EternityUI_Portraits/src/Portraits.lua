-- EternityUI_Portraits: a theme's class portraits over Blizzard's unit frames. Each one is our own
-- frame on top of Blizzard's portrait, which is never touched, so hiding ours gives it back.

---The module's private table.
---@class EternityUIPortraitsNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)

---@type string, EternityUIPortraitsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = E.Theme

local UNITS = { "player", "target", "focus", "party1", "party2", "party3", "party4" }
local FALLBACK_SIZE = 60

local Module = {
    schema = ns.OptionsSchema,
    overlays = {},
}

local function opt(path)
    return E.store:Get(addonName, path)
end

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Blizzard's portrait texture of a unit, if its frame exists. Forever's frame paths.
local function portraitOf(unit)
    if unit == "player" then
        local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
        return container and container.PlayerPortrait
    elseif unit == "target" or unit == "focus" then
        local frame = unit == "target" and _G.TargetFrame or _G.FocusFrame
        local container = frame and frame.TargetFrameContainer
        return container and container.Portrait
    end
    local member = _G.PartyFrame and _G.PartyFrame["MemberFrame" .. unit:sub(-1)]
    return member and member.Portrait
end

-- The class of a player unit, nil for anything else or when it can't be read.
local function classOf(unit)
    local exists = UnitExists(unit)
    if secret(exists) or not exists then
        return nil
    end
    local isPlayer = UnitIsPlayer(unit)
    if secret(isPlayer) or not isPlayer then
        return nil
    end
    local _, class = UnitClass(unit)
    if secret(class) then
        return nil
    end
    return class
end

-- A child of protected frames, so it's only created out of combat. It takes no mouse: clicks reach
-- Blizzard's frame below.
local function overlayOf(unit, portrait)
    local overlay = Module.overlays[unit]
    if overlay or InCombatLockdown() then
        return overlay
    end
    local parent = portrait:GetParent()
    overlay = CreateFrame("Frame", nil, parent)
    overlay:SetFrameLevel(parent:GetFrameLevel() + 10)
    overlay:SetPoint("CENTER", portrait, "CENTER")
    overlay.texture = overlay:CreateTexture(nil, "ARTWORK")
    overlay.texture:SetAllPoints()
    Module.overlays[unit] = overlay
    return overlay
end

function Module:Refresh(unit)
    local portrait = portraitOf(unit)
    local class = self.running and Theme.portraits and classOf(unit)
    local file = class and Theme.portraits[class]
    local overlay = self.overlays[unit]
    if not (portrait and file) then
        if overlay then
            overlay:Hide()
        end
        return
    end
    overlay = overlayOf(unit, portrait)
    if not overlay then
        return
    end
    local width = portrait:GetWidth()
    if secret(width) or width <= 0 then
        width = FALLBACK_SIZE
    end
    overlay:SetSize(width * opt("look.scale"), width * opt("look.scale"))
    overlay.texture:SetTexture(Theme.WALLPAPERS .. file .. ".tga")
    overlay:Show()
end

function Module:RefreshAll()
    for _, unit in ipairs(UNITS) do
        self:Refresh(unit)
    end
end

local function createEvents(self)
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function()
        self:RefreshAll()
    end)
    E.Events.Listen(Theme.CHANGED, self, function()
        self:RefreshAll()
    end)
end

function Module:OnEnable()
    self.running = true
    if not self.events then
        createEvents(self)
    end
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED",
        "PLAYER_FOCUS_CHANGED",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_REGEN_ENABLED",
    }) do
        self.events:RegisterEvent(event)
    end
    self:RefreshAll()
end

function Module:OnDisable()
    self.running = false
    self.events:UnregisterAllEvents()
    self:RefreshAll()
end

function Module:OnConfigChanged()
    self:RefreshAll()
end

E:RegisterModule(addonName, Module)
