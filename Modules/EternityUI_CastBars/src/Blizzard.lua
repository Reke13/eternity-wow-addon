-- Hiding Blizzard's cast and mirror bars: each one is moved to a hidden frame and given back to the parent
-- it had. Blizzard's Edit Mode re-parents the player's bar ("lock to player frame"), so a SetParent
-- hook keeps it hidden and remembers the new parent to give it back there. Nothing is moved in
-- combat: the change waits for PLAYER_REGEN_ENABLED (CastBars.lua calls Apply again).
-- The target, focus and boss bars stay with their parent, because TargetSpellBarMixin calls its
-- methods through GetParent(): they're hidden each time Blizzard shows them.

---@type string, EternityUICastBarsNamespace
local _, ns = ...

-- Blizzard's bars per unit or kind (seen in Forever FrameXML 1.60.1.70790). Boss bars are made by
-- TargetFrameMixin:CreateSpellbar; arena ones live in Blizzard_Deprecated_ArenaUI (Forever has no
-- CompactArenaFrame). A name the client doesn't have is skipped.
local FRAMES = {
    player = { "PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame" },
    target = { "TargetFrameSpellBar" },
    focus = { "FocusFrameSpellBar" },
    pet = { "PetCastingBarFrame" },
    boss = {},
    arena = {},
    mirror = { "MirrorTimerContainer" },
}
for i = 1, 5 do
    FRAMES.boss[i] = "Boss" .. i .. "TargetFrameSpellBar"
    FRAMES.arena[i] = "ArenaEnemyMatchFrame" .. i .. "CastingBar"
end
-- Bars of a unit frame: they keep their parent.
local KEEP_PARENT = { target = true, focus = true, boss = true }

---@class EternityUICastBarsBlizzard
---@field hidden table<table, table> hidden frame -> { parent }
---@field hooked table<table, boolean>
---@field units table<string, boolean>? units whose bars should be hidden (nil = none)
---@field pending boolean? a change is waiting for the end of combat
local Blizzard = { hidden = {}, hooked = {}, FRAMES = FRAMES }
ns.Blizzard = Blizzard

local hider = CreateFrame("Frame")
hider:Hide()
Blizzard.hider = hider

local function hook(frame)
    if Blizzard.hooked[frame] then
        return
    end
    Blizzard.hooked[frame] = true
    hooksecurefunc(frame, "SetParent", function(self, parent)
        local saved = Blizzard.hidden[self]
        if not saved or parent == hider then
            return
        end
        -- Blizzard moved it while hidden: give it back there later, hide it again now.
        saved.parent = parent
        if InCombatLockdown() then
            Blizzard.pending = true
        else
            self:SetParent(hider)
        end
    end)
end

local function hookShow(frame)
    if Blizzard.hooked[frame] then
        return
    end
    Blizzard.hooked[frame] = true
    frame:HookScript("OnShow", function(self)
        if Blizzard.hidden[self] then
            self:Hide()
        end
    end)
end

--- Hides the bars of these units and gives back the rest.
---@param units table<string, boolean>? nil gives them all back
function Blizzard:Apply(units)
    self.units = units
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = false
    local wanted = {}
    for unit, names in pairs(FRAMES) do
        if units and units[unit] then
            for _, name in ipairs(names) do
                local frame = _G[name]
                if frame then
                    wanted[frame] = true
                    if KEEP_PARENT[unit] then
                        self.hidden[frame] = self.hidden[frame] or {}
                        hookShow(frame)
                        frame:Hide()
                    else
                        if not self.hidden[frame] then
                            self.hidden[frame] = { parent = frame:GetParent() }
                            hook(frame)
                        end
                        if frame:GetParent() ~= hider then
                            frame:SetParent(hider)
                        end
                    end
                end
            end
        end
    end
    for frame, saved in pairs(self.hidden) do
        if not wanted[frame] then
            self.hidden[frame] = nil
            if saved.parent then
                frame:SetParent(saved.parent)
            end
        end
    end
end

--- Whether a Blizzard frame is hidden by the module (for the tests).
function Blizzard:IsHidden(frame)
    local saved = self.hidden[frame]
    return saved ~= nil and (saved.parent == nil or frame:GetParent() == hider)
end
