-- Social automations: accept group invites, decline duels and guild invites, invite on a whisper.
-- Blizzard's popups are only hidden (StaticPopup_Hide), never clicked, to keep them untainted.

---@type string, EternityUIAutomationNamespace
local _, ns = ...
local Core, L = ns.Core, ns.L

local Social = {}
Core.Social = Social

local function isFriend(guid)
    if C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then
        return true
    end
    return C_BattleNet ~= nil
        and C_BattleNet.GetGameAccountInfoByGUID ~= nil
        and C_BattleNet.GetGameAccountInfoByGUID(guid) ~= nil
end

local function isGuildMate(guid)
    return IsInGuild() and IsGuildMember ~= nil and IsGuildMember(guid) == true
end

--- Whether an invite from this GUID is accepted with the given mode. Pure apart from the
--- friend and guild lookups.
function Social.InviterAllowed(mode, guid)
    if mode == "anyone" then
        return true
    end
    if mode ~= "friends" and mode ~= "friendsGuild" then
        return false
    end
    if type(guid) ~= "string" or Core.Secret(guid) or guid == "" then
        return false
    end
    if isFriend(guid) then
        return true
    end
    return mode == "friendsGuild" and isGuildMate(guid)
end

--- Whether a whisper is exactly the keyword (case and surrounding spaces don't matter).
function Social.IsKeyword(text, keyword)
    if type(text) ~= "string" or Core.Secret(text) or type(keyword) ~= "string" then
        return false
    end
    keyword = strtrim(keyword):lower()
    return keyword ~= "" and strtrim(text):lower() == keyword
end

local function queued()
    local button = _G.QueueStatusButton
    return button ~= nil and button:IsShown()
end

local acceptedInvite = false

Core.Add({
    id = "acceptInvites",
    events = { "PARTY_INVITE_REQUEST", "GROUP_ROSTER_UPDATE" },
    Enabled = function()
        return Core.On("social.acceptInvites")
    end,
    OnEvent = function(_, event, name, _, _, _, _, _, inviterGUID)
        if event == "GROUP_ROSTER_UPDATE" then
            -- Blizzard's popup stays up after AcceptGroup: hide it once we're in the group.
            if acceptedInvite and IsInGroup() then
                acceptedInvite = false
                StaticPopup_Hide("PARTY_INVITE")
                if _G.LFGInvitePopup and StaticPopupSpecial_Hide then
                    StaticPopupSpecial_Hide(_G.LFGInvitePopup)
                end
            end
            return
        end
        if IsInGroup() or queued() then
            return
        end
        if Social.InviterAllowed(Core.Opt("social.acceptInvites"), inviterGUID) then
            acceptedInvite = true
            AcceptGroup()
            Core.Report(L.INVITE_ACCEPTED, Core.Name(name))
        end
    end,
})

Core.Add({
    id = "declineDuels",
    events = { "DUEL_REQUESTED" },
    Enabled = function()
        return Core.On("social.declineDuels")
    end,
    OnEvent = function(_, _, name)
        CancelDuel()
        StaticPopup_Hide("DUEL_REQUESTED")
        Core.Report(L.DUEL_DECLINED, Core.Name(name))
    end,
})

Core.Add({
    id = "declinePetDuels",
    events = { "PET_BATTLE_PVP_DUEL_REQUESTED" },
    Enabled = function()
        return Core.On("social.declinePetDuels")
    end,
    OnEvent = function()
        if not (C_PetBattles and C_PetBattles.CancelPVPDuel) then
            return
        end
        C_PetBattles.CancelPVPDuel()
        StaticPopup_Hide("PET_BATTLE_PVP_DUEL_REQUESTED")
        Core.Report(L.PET_DUEL_DECLINED)
    end,
})

Core.Add({
    id = "declineGuildInvites",
    events = { "GUILD_INVITE_REQUEST" },
    Enabled = function()
        return Core.On("social.declineGuildInvites")
    end,
    OnEvent = function(_, _, inviter, guildName)
        DeclineGuild()
        -- Blizzard shows its frame on the same event; hide it right after.
        Core.After(0, function()
            local frame = _G.GuildInviteFrame
            if frame and frame:IsShown() then
                frame:Hide()
            end
        end)
        Core.Report(L.GUILD_DECLINED, Core.Name(guildName), Core.Name(inviter))
    end,
})

local function canInvite()
    if not IsInGroup() then
        return true
    end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

Core.Add({
    id = "inviteOnWhisper",
    events = { "CHAT_MSG_WHISPER" },
    Enabled = function()
        return Core.On("social.inviteOnWhisper")
    end,
    OnEvent = function(_, _, text, sender)
        if type(sender) ~= "string" or Core.Secret(sender) then
            return
        end
        if not Social.IsKeyword(text, Core.Opt("social.inviteKeyword")) or not canInvite() then
            return
        end
        C_PartyInfo.InviteUnit(sender)
        Core.Report(L.INVITED, sender)
    end,
})
