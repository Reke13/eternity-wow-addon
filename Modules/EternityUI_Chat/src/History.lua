-- EternityUI_Chat: conversations. Every chat message the messenger or the history cares about is
-- filed under a conversation (a whisper per player, a Battle.net whisper per account, guild,
-- officers, party, raid, instance, nearby and each channel). Conversations whose kind has
-- history on are kept in EternityUIChatDB (per character or for the account); the rest only live
-- this session. On login the last lines can be shown again in Blizzard's chat, dimmed.
-- Messages with secret values (Blizzard's chat restrictions) never get here: Chat.lua drops them.

---@type string, EternityUIChatNamespace
local _, ns = ...
local opt, secret, L = ns.opt, ns.secret, ns.L

local DAY = 86400
local RESTORE_DELAY = 1 -- seconds after login, once the chat windows exist
local DIM = "ff8c8c99"

---@class EternityUIChatMessage
---@field t number time()
---@field f string? sender: "Name-Realm", a Battle.net name or nil for mine
---@field c string? sender class file
---@field m boolean? mine
---@field x string text
---@field e string chat type (WHISPER, GUILD, CHANNEL...), for its color

---@class EternityUIChatConversation
---@field key string
---@field kind string whisper, bnet, guild, officer, party, raid, instance, say, channel
---@field title string
---@field target string? whisper: "Name-Realm"; bnet: BattleTag; channel: its base name
---@field reply string? whisper: the name exactly as the game gave it, to whisper back
---@field class string? whisper: the other player's class
---@field unread integer
---@field updated number
---@field messages EternityUIChatMessage[]

---@class EternityUIChatHistory
---@field session table<string, EternityUIChatConversation> conversations not saved
---@field onMessage fun(conversation: EternityUIChatConversation, message: EternityUIChatMessage)?
---@field restored boolean?
local History = { session = {} }
ns.History = History

-- Each chat type: its conversation kind (and the option groups that name it).
local KINDS = {
    WHISPER = "whisper",
    WHISPER_INFORM = "whisper",
    BN_WHISPER = "bnet",
    BN_WHISPER_INFORM = "bnet",
    GUILD = "guild",
    OFFICER = "officer",
    PARTY = "party",
    PARTY_LEADER = "party",
    RAID = "raid",
    RAID_LEADER = "raid",
    RAID_WARNING = "raid",
    INSTANCE_CHAT = "instance",
    INSTANCE_CHAT_LEADER = "instance",
    SAY = "say",
    YELL = "say",
    EMOTE = "say",
    CHANNEL = "channel",
}
History.KINDS = KINDS
-- Kind -> option id in the "messenger" and "history" groups.
local OPTION = {
    whisper = "whispers",
    bnet = "bnet",
    guild = "guild",
    officer = "guild",
    party = "group",
    raid = "group",
    instance = "group",
    say = "say",
    channel = "channels",
}
History.OPTION = OPTION
local TITLES = {
    guild = "GUILD",
    officer = "OFFICER",
    party = "PARTY",
    raid = "RAID",
    instance = "INSTANCE",
    say = "SAY",
}

--- The chat events the module listens to.
function History.Events()
    local list = {}
    for chatType in pairs(KINDS) do
        list[#list + 1] = "CHAT_MSG_" .. chatType
    end
    table.sort(list)
    return list
end

local function myName()
    local name, realm = UnitFullName("player")
    if not name then
        return nil
    end
    return name .. "-" .. (realm and realm ~= "" and realm or (GetNormalizedRealmName() or ""))
end

-- Storage -----------------------------------------------------------------------------------

--- Saved conversations of the current scope (this character or the account).
function History:Saved()
    local db = ns.DB()
    local scope = opt("history.scope") == "account" and "account" or (myName() or "?")
    db.history[scope] = db.history[scope] or {}
    return db.history[scope]
end

local function keepsHistory(kind)
    return opt("history.enabled") and opt("history." .. OPTION[kind])
end

--- The conversation, created if needed. It lives where its kind says (saved or session).
---@return EternityUIChatConversation
function History:Conversation(key, kind, title, target)
    local saved, session = self:Saved(), self.session
    local conversation = saved[key] or session[key]
    if not conversation then
        conversation =
            { key = key, kind = kind, title = title, target = target, unread = 0, updated = time(), messages = {} }
    end
    -- Move it if its kind's history option changed.
    if keepsHistory(kind) then
        saved[key], session[key] = conversation, nil
    else
        session[key], saved[key] = conversation, nil
    end
    return conversation
end

--- Every conversation (saved and session), most recent first.
---@return EternityUIChatConversation[]
function History:List()
    local list = {}
    for _, store in ipairs({ self:Saved(), self.session }) do
        for _, conversation in pairs(store) do
            list[#list + 1] = conversation
        end
    end
    table.sort(list, function(a, b)
        if a.updated ~= b.updated then
            return a.updated > b.updated
        end
        return a.key < b.key
    end)
    return list
end

function History:Get(key)
    return self:Saved()[key] or self.session[key]
end

function History:Clear(key)
    self:Saved()[key] = nil
    self.session[key] = nil
end

function History:ClearAll()
    local db = ns.DB()
    db.history = {}
    self.session = {}
end

--- Drops the messages older than history.days and over history.lines.
function History:Prune(now)
    now = now or time()
    local oldest = now - opt("history.days") * DAY
    local max = opt("history.lines")
    for _, store in pairs(ns.DB().history) do
        for key, conversation in pairs(store) do
            local messages = type(conversation) == "table" and conversation.messages
            if type(messages) ~= "table" then
                store[key] = nil
            else
                local kept = {}
                for _, message in ipairs(messages) do
                    if (message.t or 0) >= oldest then
                        kept[#kept + 1] = message
                    end
                end
                while #kept > max do
                    table.remove(kept, 1)
                end
                conversation.messages = kept
                if #kept == 0 then
                    store[key] = nil
                end
            end
        end
    end
end

-- Filing messages ---------------------------------------------------------------------------

--- Battle.net account of a whisper: its BattleTag (stable across sessions) and a display name.
local function bnetAccount(bnSenderID)
    if not bnSenderID or secret(bnSenderID) or not C_BattleNet or not C_BattleNet.GetAccountInfoByID then
        return nil
    end
    local info = C_BattleNet.GetAccountInfoByID(bnSenderID)
    local tag = info and info.battleTag
    if not tag or secret(tag) then
        return nil
    end
    return tag, (strsplit("#", tag))
end

--- Conversation key, kind, title and target of a chat event, or nil if it isn't filed.
function History:Classify(chatType, sender, channelBaseName, bnSenderID)
    local kind = KINDS[chatType]
    if not kind then
        return nil
    end
    if kind == "whisper" then
        local full = ns.FullName(sender)
        if not full then
            return nil
        end
        return "W:" .. full, kind, ns.ShortName(full), full
    elseif kind == "bnet" then
        local tag, name = bnetAccount(bnSenderID)
        if not tag then
            return nil
        end
        return "B:" .. tag, kind, name, tag
    elseif kind == "channel" then
        if type(channelBaseName) ~= "string" or channelBaseName == "" then
            return nil
        end
        return "C:" .. channelBaseName, kind, channelBaseName, channelBaseName
    end
    return kind:upper(), kind, L[TITLES[kind]], nil
end

--- The GUID of the character a Battle.net friend is playing, if it can be known.
local function friendGUID(bnSenderID)
    if not bnSenderID or secret(bnSenderID) or not C_BattleNet then
        return nil
    end
    local account = C_BattleNet.GetAccountInfoByID(bnSenderID)
    local game = account and account.gameAccountInfo
    return game and game.playerGuid or nil
end

--- Whether the messenger or the history wants this kind.
function History:Wants(kind)
    local id = OPTION[kind]
    local messenger = opt("mode.style") == "messenger" and opt("messenger." .. id)
    return messenger or keepsHistory(kind)
end

--- Files one chat event (its values are already known not to be secret).
---@return EternityUIChatConversation?, EternityUIChatMessage?
function History:Ingest(event, text, sender, channelBaseName, guid, bnSenderID)
    local chatType = event:sub(10)
    local key, kind, title, target = self:Classify(chatType, sender, channelBaseName, bnSenderID)
    if not key or not self:Wants(kind) then
        return nil
    end
    local mine = chatType:find("_INFORM$") ~= nil
    local from = ns.FullName(sender)
    if kind == "bnet" then
        from = title
    elseif from and from == myName() then
        mine = true
    end
    -- An outgoing whisper names the other player as its sender; a GUID of our own says nothing.
    local own = mine and not secret(guid) and guid == UnitGUID("player")
    local class = not own and ns.Players:FromGUID(kind == "bnet" and friendGUID(bnSenderID) or guid) or nil
    if not class and from then
        local known = ns.Players:Get(from)
        class = known and known.c
    end
    local conversation = self:Conversation(key, kind, title, target)
    -- Whispers go back to the name as the game wrote it, like Blizzard's reply does: the realm
    -- FullName adds (GetNormalizedRealmName, an internal name in Forever) isn't accepted there.
    if kind == "whisper" and type(sender) == "string" and sender ~= "" then
        conversation.reply = sender
    end
    ---@type EternityUIChatMessage
    local message = {
        t = time(),
        f = not mine and from or nil,
        c = not mine and class or nil,
        m = mine or nil,
        x = text,
        e = chatType,
    }
    conversation.messages[#conversation.messages + 1] = message
    conversation.updated = message.t
    if class and (kind == "bnet" or kind == "whisper") then
        conversation.class = class
    end
    local max = opt("history.lines")
    while #conversation.messages > max do
        table.remove(conversation.messages, 1)
    end
    if self.onMessage then
        self.onMessage(conversation, message)
    end
    return conversation, message
end

-- Showing it again in Blizzard's chat -------------------------------------------------------

local function chatColor(chatType)
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
    if info then
        return info.r, info.g, info.b
    end
    return 1, 1, 1
end

function History:FormatLine(message, conversation)
    local who
    if message.m then
        who = L.YOU
    elseif message.f then
        who = conversation.kind == "bnet" and message.f or ns.ShortName(message.f)
        local color = ns.Players:ClassHex(message.c)
        if color then
            who = ("|c%s%s|r"):format(color, who)
        end
        -- A player link, like a live line: a click whispers them (without our own realm, which the
        -- server doesn't take in Forever).
        if conversation.kind ~= "bnet" then
            who = ("|Hplayer:%s|h%s|h"):format(ns.ShortName(message.f), who)
        end
    end
    local where = conversation.kind == "whisper" and ("@" .. conversation.title) or conversation.title
    local stamp = date("%H:%M", message.t)
    return ("|c%s[%s] [%s]|r %s%s"):format(DIM, stamp, where, who and (who .. ": ") or "", message.x)
end

--- Shows the last history.restoreLines saved lines in the chat windows that show their type.
function History:Restore()
    if self.restored or not opt("history.enabled") or not opt("history.restore") then
        return
    end
    self.restored = true
    local lines = {}
    for _, conversation in pairs(self:Saved()) do
        for _, message in ipairs(conversation.messages) do
            lines[#lines + 1] = { message = message, conversation = conversation }
        end
    end
    table.sort(lines, function(a, b)
        return a.message.t < b.message.t
    end)
    local first = math.max(1, #lines - opt("history.restoreLines") + 1)
    local frames = _G.CHAT_FRAMES or {}
    for i = first, #lines do
        local line = lines[i]
        local event = "CHAT_MSG_" .. line.message.e
        local text = self:FormatLine(line.message, line.conversation)
        local r, g, b = chatColor(line.message.e)
        for _, name in ipairs(frames) do
            local frame = _G[name]
            if frame and frame.IsEventRegistered and frame:IsEventRegistered(event) then
                frame:AddMessage(text, r * 0.7, g * 0.7, b * 0.7)
            end
        end
    end
end

function History:Start()
    self:Prune()
    C_Timer.After(RESTORE_DELAY, function()
        if ns.running then
            self:Restore()
        end
    end)
end
