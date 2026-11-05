-- EternityUI_Chat: the module. It wires the pieces together and owns the chat events:
--   * Players.lua decorates sender names (icon, level, class) in Blizzard's chat;
--   * History.lua files messages into conversations and saves them;
--   * Skin.lua restyles Blizzard's chat windows and applies the mode;
--   * Messenger.lua shows the conversations as a messaging app.
-- Chat events whose values are secret (Blizzard's chat restrictions) are ignored: Blizzard shows
-- them in its chat as usual and they're neither filed nor saved. Removing messages from the
-- normal chat uses Blizzard's message event filters, which are removed when disabled.

---@type string, EternityUIChatNamespace
local addonName, ns = ...
local E = EternityUI
local opt, secret, L = ns.opt, ns.secret, ns.L
local History, Messenger = ns.History, ns.Messenger

---@class EternityUIChatModule: EternityUIModuleDefinition
---@field hooked boolean?
---@field filtering boolean?
local Module = {
    schema = ns.OptionsSchema,
    ns = ns, -- for the tests
}

local function locked()
    return C_ChatInfo ~= nil and C_ChatInfo.InChatMessagingLockdown ~= nil and C_ChatInfo.InChatMessagingLockdown()
end

--- Chat event: filed if none of its values is secret.
function Module:OnChatEvent(event, text, sender, _, _, _, _, _, _, channelBaseName, _, _, guid, bnSenderID)
    if not ns.running or locked() then
        return
    end
    if secret(text) or secret(sender) or secret(guid) or secret(channelBaseName) or secret(bnSenderID) then
        return
    end
    if type(text) ~= "string" then
        return
    end
    History:Ingest(event, text, sender, channelBaseName, guid, bnSenderID)
end

--- Message event filter: true removes the message from Blizzard's chat window.
function Module:HideInChat(event, text, sender)
    if not ns.running or opt("mode.style") ~= "messenger" or secret(text) or secret(sender) then
        return false
    end
    local hide = opt("messenger.hideInChat")
    if hide == "none" then
        return false
    end
    local kind = History.KINDS[event:sub(10)]
    if not kind or not opt("messenger." .. History.OPTION[kind]) then
        return false
    end
    if hide == "whispers" and kind ~= "whisper" and kind ~= "bnet" then
        return false
    end
    return true
end

function Module:SetFilters(on)
    local util = _G.ChatFrameUtil
    if not util or not util.AddMessageEventFilter or on == (self.filtering or false) then
        return
    end
    for _, event in ipairs(History.Events()) do
        if on then
            util.AddMessageEventFilter(event, self.filter)
        else
            util.RemoveMessageEventFilter(event, self.filter)
        end
    end
    self.filtering = on
end

function Module:Slash(input)
    local command = strtrim(input or ""):lower()
    if command == "clear" then
        History:ClearAll()
        Messenger:Apply()
        print(L.HISTORY_CLEARED)
    elseif opt("mode.style") == "messenger" then
        Messenger:Toggle()
    else
        E:OpenOptions(addonName, "general")
    end
end

function Module:InstallHooks()
    self.hooked = true
    self.filter = function(_, event, text, sender)
        return self:HideInChat(event, text, sender)
    end
    local events = CreateFrame("Frame")
    for _, event in ipairs(History.Events()) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, ...)
        self:OnChatEvent(event, ...)
    end)
    History.onMessage = function(conversation, message)
        Messenger:OnMessage(conversation, message)
    end
    _G.SLASH_ETERNITYCHAT1 = "/etchat"
    SlashCmdList.ETERNITYCHAT = function(input)
        self:Slash(input)
    end
end

function Module:OnEnable()
    ns.running = true
    if not self.hooked then
        self:InstallHooks()
    end
    ns.Players:Start()
    History:Start()
    ns.Skin:Start()
    Messenger:Start()
    self:SetFilters(true)
end

function Module:OnDisable()
    ns.running = false
    self:SetFilters(false)
    Messenger:Stop()
    ns.Skin:Stop()
    ns.Players:Stop()
end

function Module:OnConfigChanged(path)
    if path == nil or path:find("^history%.") then
        History:Prune()
    end
    ns.Skin:ApplyAll()
    Messenger:Apply()
end

E:RegisterModule(addonName, Module)
