-- Experience data: a snapshot of the current level (XP, rested, quests, projection), the session
-- (gains, XP per hour, time to level, kills to level) and each character's level history in
-- EternityUIExperienceDB (time online and XP by source per level), which feeds the charts.

---@type string, EternityUIExperienceNamespace
local _, ns = ...
local L = ns.L

local SCHEMA_VERSION = 1
-- A gain is put down to a quest turn-in or a kill seen this close to it (seconds).
local MATCH_WINDOW = 1
-- Gains wait this long before being classified, so the quest or kill event can arrive.
local RESOLVE_DELAY = 0.5

---One level of a character's history.
---@class EternityUIExperienceLevel
---@field seconds number time online at this level
---@field kill number XP from kills
---@field quest number XP from quests
---@field other number XP from anything else
---@field kills number number of kills that gave XP

---@class EternityUIExperienceGain
---@field t number GetTime() of the gain
---@field xp number
---@field level number level the XP was earned at
---@field source string? "kill", "quest" or "other" once classified

---@class EternityUIExperienceSnapshot
---@field level number
---@field maxLevel number
---@field capped boolean
---@field xp number
---@field max number
---@field rested number
---@field resting boolean
---@field done number XP of the quests ready to turn in
---@field all number XP of the whole quest log
---@field projDone number level (with fraction) after turning in the completed quests
---@field projAll number level (with fraction) after the whole log
---@field rate number? XP per hour (nil until there's enough data)
---@field eta number? seconds to level
---@field kills number? kills to level
---@field lastKill number? XP of the last kill
---@field gained number XP this session
---@field sessionSeconds number
---@field levelSeconds number? time at this level (/played if known, else tracked)
---@field played number? total /played, if the client sent it

---@class EternityUIExperienceData
---@field db table?
---@field char table? this character's record
---@field session table
---@field quests { done: number, all: number }
---@field markers { quest: number?, questXP: number?, kill: number? }
local Data = { quests = { done = 0, all = 0 }, markers = {} }
ns.Data = Data

-- Helpers ------------------------------------------------------------------------------------------

-- Values that may arrive as secrets (12.x clients) are treated as missing.
local function number(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return type(value) == "number" and value or nil
end

-- Characters are keyed by GUID: UnitName is not unique on Forever.
local function charKey()
    return EternityUI.store.character or "?"
end

local function maxLevel()
    local max = GetMaxLevelForPlayerExpansion and number(GetMaxLevelForPlayerExpansion())
    return max or 80
end

--- Short number: 950, 12.3k, 1.25M.
---@param n number?
---@return string
function Data.Short(n)
    if not n then
        return L.UNKNOWN
    end
    if n >= 1e6 then
        return string.format("%.2fM", n / 1e6)
    elseif n >= 1e4 then
        return string.format("%.1fk", n / 1e3)
    end
    return tostring(math.floor(n + 0.5))
end

--- Duration: 1h 05m, 12m 30s, 45s.
---@param seconds number?
---@return string
function Data.Duration(seconds)
    if not seconds or seconds ~= seconds or seconds == math.huge then
        return L.UNKNOWN
    end
    seconds = math.floor(seconds + 0.5)
    local d, h, m, s =
        math.floor(seconds / 86400), math.floor(seconds / 3600) % 24, math.floor(seconds / 60) % 60, seconds % 60
    if d > 0 then
        return string.format("%dd %02dh", d, h)
    elseif h > 0 then
        return string.format("%dh %02dm", h, m)
    elseif m > 0 then
        return string.format("%dm %02ds", m, s)
    end
    return s .. "s"
end

--- Level with fraction as "24 (35%)".
---@param level number
---@return string
function Data.Level(level)
    local whole = math.floor(level)
    return string.format("%d (%d%%)", whole, math.floor((level - whole) * 100))
end

-- Storage ------------------------------------------------------------------------------------------

--- Binds EternityUIExperienceDB (loaded before ADDON_LOADED) and this character's record.
function Data:Bind()
    if self.char then
        return self.char
    end
    local db = _G.EternityUIExperienceDB
    if type(db) ~= "table" or db.version ~= SCHEMA_VERSION or type(db.chars) ~= "table" then
        db = { version = SCHEMA_VERSION, chars = {} }
        _G.EternityUIExperienceDB = db
    end
    self.db = db
    local key = charKey()
    local char = db.chars[key]
    if type(char) ~= "table" or type(char.levels) ~= "table" then
        char = { levels = {} }
        db.chars[key] = char
    end
    self.char = char
    return char
end

--- History record of a level (created empty if missing).
---@param level number
---@return EternityUIExperienceLevel
function Data:LevelRecord(level)
    local levels = self:Bind().levels
    local record = levels[level]
    if type(record) ~= "table" then
        record = { seconds = 0, kill = 0, quest = 0, other = 0, kills = 0 }
        levels[level] = record
    end
    return record
end

--- Clears this character's history.
function Data:ResetHistory()
    self:Bind().levels = {}
end

-- Session ------------------------------------------------------------------------------------------

--- Starts the session (also on /reload: the session is the time since the module started).
function Data:Start()
    local now = GetTime()
    self:Bind()
    self.session = { start = now, last = now, gained = 0, gains = {}, pending = {}, kills = 0, killXP = 0 }
    self.played = nil
    self:Resync()
    self:ScanQuests()
end

--- Takes the current XP as the starting point (on start, and when the module is enabled again:
--- what was gained while it was disabled doesn't count).
function Data:Resync()
    self.last =
        { level = UnitLevel("player"), xp = number(UnitXP("player")) or 0, max = number(UnitXPMax("player")) or 0 }
    if self.session then
        self.session.last = GetTime()
    end
end

--- Adds the time since the last tick to the current level's history.
function Data:Tick()
    local session = self.session
    if not session then
        return
    end
    local now = GetTime()
    local level = UnitLevel("player")
    if level < maxLevel() then
        local record = self:LevelRecord(level)
        record.seconds = record.seconds + (now - session.last)
    end
    session.last = now
end

--- PLAYER_XP_UPDATE: works out the gain (also across a level up) and queues it to classify.
function Data:OnXP()
    local session, last = self.session, self.last
    if not session then
        return
    end
    local level = UnitLevel("player")
    local xp, max = number(UnitXP("player")), number(UnitXPMax("player"))
    if not xp or not max then
        return
    end
    local delta
    if level > last.level then
        delta = (last.max - last.xp) + xp
        local finished = self:LevelRecord(last.level)
        finished.finished = time()
    else
        delta = xp - last.xp
    end
    self.last = { level = level, xp = xp, max = max }
    if delta > 0 then
        self:AddGain(delta, last.level)
    end
end

---@param xp number
---@param level number
function Data:AddGain(xp, level)
    local gain = { t = GetTime(), xp = xp, level = level }
    local session = self.session
    session.gained = session.gained + xp
    session.gains[#session.gains + 1] = gain
    session.pending[#session.pending + 1] = gain
    C_Timer.After(RESOLVE_DELAY, function()
        self:Resolve()
    end)
end

--- QUEST_TURNED_IN and CHAT_MSG_COMBAT_XP_GAIN leave a mark the next gain is matched with.
---@param kind string "quest" or "kill"
function Data:Mark(kind)
    self.markers[kind] = GetTime()
end

local function near(marker, t)
    return marker and math.abs(marker - t) <= MATCH_WINDOW
end

--- Classifies the pending gains: quest, kill or other. force classifies them all now.
---@param force boolean?
function Data:Resolve(force)
    local session = self.session
    if not session then
        return
    end
    local now, keep = GetTime(), {}
    for _, gain in ipairs(session.pending) do
        if force or now - gain.t >= RESOLVE_DELAY - 0.05 then
            if near(self.markers.quest, gain.t) then
                gain.source = "quest"
                self.markers.quest = nil
            elseif near(self.markers.kill, gain.t) then
                gain.source = "kill"
                self.markers.kill = nil
                session.kills = session.kills + 1
                session.killXP = session.killXP + gain.xp
                session.lastKill = gain.xp
            else
                gain.source = "other"
            end
            local record = self:LevelRecord(gain.level)
            record[gain.source] = record[gain.source] + gain.xp
            if gain.source == "kill" then
                record.kills = record.kills + 1
            end
        else
            keep[#keep + 1] = gain
        end
    end
    session.pending = keep
end

--- TIME_PLAYED_MSG: total and this level's /played (seconds).
function Data:OnPlayed(total, level)
    total, level = number(total), number(level)
    if total then
        self.played = { total = total, level = level, at = GetTime() }
    end
end

--- XP per hour over `minutes` (nil = the whole session). nil until there's a minute of data.
---@param minutes number?
---@return number?
function Data:Rate(minutes)
    local session = self.session
    if not session then
        return nil
    end
    local now = GetTime()
    local elapsed = now - session.start
    if elapsed < 60 then
        return nil
    end
    if not minutes then
        return session.gained / elapsed * 3600
    end
    local window = math.min(minutes * 60, elapsed)
    local sum = 0
    for i = #session.gains, 1, -1 do
        local gain = session.gains[i]
        if now - gain.t > window then
            break
        end
        sum = sum + gain.xp
    end
    return sum / window * 3600
end

--- XP gained in buckets of `minutes` from the start of the session (oldest first).
---@param minutes number
---@return number[]
function Data:Buckets(minutes)
    local session = self.session
    if not session then
        return {}
    end
    local size = minutes * 60
    local count = math.max(1, math.ceil((GetTime() - session.start) / size))
    local buckets = {}
    for i = 1, count do
        buckets[i] = 0
    end
    for _, gain in ipairs(session.gains) do
        local i = math.min(count, math.floor((gain.t - session.start) / size) + 1)
        buckets[i] = buckets[i] + gain.xp
    end
    return buckets
end

-- Quests -------------------------------------------------------------------------------------------

--- Sums the XP of the quest log: the quests ready to turn in and all of them.
function Data:ScanQuests()
    local done, all = 0, 0
    local count = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, count do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID then
            local xp = number(GetQuestLogRewardXP(info.questID)) or 0
            all = all + xp
            if C_QuestLog.ReadyForTurnIn(info.questID) then
                done = done + xp
            end
        end
    end
    self.quests = { done = done, all = all }
end

-- Snapshot -----------------------------------------------------------------------------------------

-- Level (with fraction) after adding `add` XP. Levels past this one are assumed to need as much
-- XP as this one (the client only gives this level's total), so it's an estimate.
local function project(level, xp, max, add, cap)
    if max <= 0 then
        return level
    end
    return math.min(cap, level + (xp + add) / max)
end

--- Everything the bar, tooltip and texts show, read now.
---@param rateMinutes number? XP per hour window (nil = session)
---@return EternityUIExperienceSnapshot
function Data:Snapshot(rateMinutes)
    local level, cap = UnitLevel("player"), maxLevel()
    local xp, max = number(UnitXP("player")) or 0, number(UnitXPMax("player")) or 0
    local capped = level >= cap or (IsXPUserDisabled and IsXPUserDisabled()) or false
    local session = self.session
    local s = {
        level = level,
        maxLevel = cap,
        capped = capped,
        xp = xp,
        max = max,
        rested = number(GetXPExhaustion()) or 0,
        resting = IsResting() and true or false,
        done = self.quests.done,
        all = self.quests.all,
        gained = session and session.gained or 0,
        sessionSeconds = session and (GetTime() - session.start) or 0,
        lastKill = session and session.lastKill,
    }
    s.projDone = project(level, xp, max, s.done, cap)
    s.projAll = project(level, xp, max, s.all, cap)
    s.rate = self:Rate(rateMinutes)
    local remaining = max - xp
    if s.rate and s.rate > 0 and not capped then
        s.eta = remaining / s.rate * 3600
    end
    if session and session.kills > 0 and not capped then
        s.kills = math.ceil(remaining / (session.killXP / session.kills))
    end
    if self.played then
        local since = GetTime() - self.played.at
        s.played = self.played.total + since
        if self.played.level then
            s.levelSeconds = self.played.level + since
        end
    end
    if not s.levelSeconds and self.char and self.char.levels[level] then
        s.levelSeconds = self.char.levels[level].seconds
    end
    return s
end

-- Texts --------------------------------------------------------------------------------------------

local function percent(part, whole)
    return whole > 0 and string.format("%.1f%%", part / whole * 100) or "0%"
end

-- Token values of a snapshot ({level}, {cur}...).
local TOKENS = {
    level = function(s)
        return tostring(s.level)
    end,
    next = function(s)
        return tostring(math.min(s.level + 1, s.maxLevel))
    end,
    cur = function(s)
        return Data.Short(s.xp)
    end,
    max = function(s)
        return Data.Short(s.max)
    end,
    pct = function(s)
        return percent(s.xp, s.max)
    end,
    rem = function(s)
        return Data.Short(s.max - s.xp)
    end,
    rempct = function(s)
        return percent(s.max - s.xp, s.max)
    end,
    rested = function(s)
        return Data.Short(s.rested)
    end,
    restedpct = function(s)
        return percent(s.rested, s.max)
    end,
    done = function(s)
        return Data.Short(s.done)
    end,
    quests = function(s)
        return Data.Short(s.all)
    end,
    proj = function(s)
        return "→ " .. Data.Level(s.projDone)
    end,
    rate = function(s)
        return s.rate and (Data.Short(s.rate) .. "/h") or L.UNKNOWN
    end,
    eta = function(s)
        return Data.Duration(s.eta)
    end,
    kills = function(s)
        return s.kills and tostring(s.kills) or L.UNKNOWN
    end,
    gained = function(s)
        return Data.Short(s.gained)
    end,
    session = function(s)
        return Data.Duration(s.sessionSeconds)
    end,
}

--- Replaces the {tokens} of a user text. Unknown tokens are left as they are and "|" is escaped.
---@param template string
---@param s EternityUIExperienceSnapshot
---@return string
function Data.Expand(template, s)
    template = template:gsub("|", "||")
    return (
        template:gsub("{(%a+)}", function(token)
            local fn = TOKENS[token]
            return fn and fn(s) or nil
        end)
    )
end
