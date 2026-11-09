-- EternityUI_UnitFrames: Blizzard's unit frames, hidden per frame ("Hide Blizzard's frame") while
-- ours is shown. The core's Hider moves them to a hidden parent and back, out of combat, without
-- replacing any of their methods. The target of target lives inside Blizzard's target frame, so
-- hiding the target hides it too.

---@type string, EternityUIUnitFramesNamespace
local addonName, ns = ...
local E = EternityUI

-- Forever's frames for each of ours (missing ones are skipped).
local FRAMES = {
    player = { "PlayerFrame" },
    pet = { "PetFrame" },
    target = { "TargetFrame", "ComboFrame" },
    targettarget = { "TargetFrameToT" },
    focus = { "FocusFrame" },
    party = { "PartyFrame", "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" },
    raid = { "CompactRaidFrameContainer", "CompactRaidFrameManager" },
    grouppets = { "PartyMemberFrame1PetFrame", "PartyMemberFrame2PetFrame", "PartyMemberFrame3PetFrame", "PartyMemberFrame4PetFrame" },
}

---@class EternityUIUnitFramesBlizzard
local Blizzard = { FRAMES = FRAMES, hidden = {} }
ns.Blizzard = Blizzard

--- Hides or gives back Blizzard's frames for one of ours.
---@param key string
---@param hide boolean
function Blizzard.Apply(key, hide)
    for _, name in ipairs(FRAMES[key] or {}) do
        local frame = _G[name]
        if frame then
            local id = key .. ":" .. name
            if hide and not Blizzard.hidden[id] then
                if E.Hider.Hide(frame, addonName) then
                    Blizzard.hidden[id] = frame
                end
            elseif not hide and Blizzard.hidden[id] then
                Blizzard.hidden[id] = nil
                E.Hider.Restore(frame, addonName)
            end
        end
    end
end

--- Gives every frame back.
function Blizzard.RestoreAll()
    for id, frame in pairs(Blizzard.hidden) do
        Blizzard.hidden[id] = nil
        E.Hider.Restore(frame, addonName)
    end
end
