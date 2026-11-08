-- The error log. Nothing replaces the game's error handler: Blizzard's own error window
-- (ScriptErrorsFrame) gets every Lua error and warning whether it shows or not, so a
-- hooksecurefunc on the method it receives them with sees them all, untainted and without
-- touching Blizzard's code. The ones that came before this addon loaded are read from that
-- window's list when the module starts. Blocked and forbidden actions come as events.
-- Errors are kept in EternityUIBugsDB, the same error once with a count, newest last.

---@type string, EternityUIBugsNamespace
local addonName, ns = ...
local E = EternityUI
local L, opt = ns.L, ns.opt

local isSecret = issecretvalue or function()
    return false
end

---@class EternityUIBugsEntry
---@field kind string error, warning or blocked
---@field message string
---@field stack string
---@field locals string?
---@field count integer
---@field time integer last time it happened
---@field first integer first time it happened
---@field session integer session it last happened in

---@class EternityUIBugsRecorder
---@field db table? EternityUIBugsDB
---@field running boolean
---@field onAdd fun(entry: EternityUIBugsEntry, isNew: boolean)? runs after an error is saved
local Recorder = { running = false }
ns.Recorder = Recorder

local byKey = {} -- message and stack -> entry, for the current log
local busy = false -- an error raised while saving one isn't saved again (no loop)
local imported = 0 -- how many of Blizzard's earlier errors were read already

--- A text the game may hand over as a secret: those can't be read, compared or saved.
---@param value any
---@return string?
local function readable(value)
    if value == nil then
        return nil
    elseif isSecret(value) then
        return L.SECRET
    end
    return tostring(value)
end

local function keyOf(entry)
    return entry.kind .. "\n" .. entry.message .. "\n" .. (entry.stack or "")
end

local function reindex()
    byKey = {}
    for _, entry in ipairs(Recorder.db.errors) do
        byKey[keyOf(entry)] = entry
    end
end

--- The saved log. Every login is a new session.
function Recorder.Bind()
    if Recorder.db then
        return
    end
    local db = _G.EternityUIBugsDB
    if type(db) ~= "table" then
        db = {}
        _G.EternityUIBugsDB = db
    end
    db.version = 1
    db.errors = db.errors or {}
    db.session = (db.session or 0) + 1
    Recorder.db = db
    reindex()
end

--- The session this login is.
---@return integer
function Recorder.Session()
    Recorder.Bind()
    return Recorder.db.session
end

--- Drops the oldest errors over the limit.
function Recorder.Trim()
    local db = Recorder.db
    if not db then
        return
    end
    local limit = opt("capture.limit")
    local extra = #db.errors - limit
    if extra > 0 then
        for _ = 1, extra do
            table.remove(db.errors, 1)
        end
        reindex()
    end
end

--- Saves an error, or counts it again if it's already there (it moves to the end).
---@param kind string error, warning or blocked
---@param message any
---@param stack any
---@param locals any
---@param when integer?
---@return EternityUIBugsEntry?
function Recorder.Add(kind, message, stack, locals, when)
    if busy then
        return nil
    end
    busy = true
    local ok, entry, isNew = pcall(function()
        Recorder.Bind()
        local db = Recorder.db
        local now = when or time()
        local fresh = {
            kind = kind,
            message = readable(message) or "?",
            stack = readable(stack) or "",
            locals = opt("capture.locals") and readable(locals) or nil,
        }
        local key = keyOf(fresh)
        local found = byKey[key]
        if found then
            found.count = found.count + 1
            found.time = now
            local isNewThisSession = found.session ~= db.session
            found.session = db.session
            if fresh.locals then
                found.locals = fresh.locals
            end
            for i, item in ipairs(db.errors) do
                if item == found then
                    table.remove(db.errors, i)
                    break
                end
            end
            db.errors[#db.errors + 1] = found
            return found, isNewThisSession
        end
        fresh.count = 1
        fresh.time = now
        fresh.first = now
        fresh.session = db.session
        db.errors[#db.errors + 1] = fresh
        byKey[key] = fresh
        Recorder.Trim()
        return fresh, true
    end)
    busy = false
    if ok and entry and Recorder.onAdd then
        pcall(Recorder.onAdd, entry, isNew)
    end
    return ok and entry or nil
end

--- Removes one error.
---@param entry EternityUIBugsEntry
function Recorder.Remove(entry)
    local db = Recorder.db
    for i, item in ipairs(db and db.errors or {}) do
        if item == entry then
            table.remove(db.errors, i)
            byKey[keyOf(entry)] = nil
            return
        end
    end
end

--- Forgets every error.
function Recorder.Clear()
    Recorder.Bind()
    wipe(Recorder.db.errors)
    byKey = {}
end

-- Blizzard's error window ------------------------------------------------------------------

local WARNING = 1 -- WarningMessageType in Blizzard_ScriptErrorsFrame

local function wanted(kind)
    if kind == "warning" then
        return opt("capture.warnings")
    elseif kind == "blocked" then
        return opt("capture.blocked")
    end
    return true
end

local function fromBlizzard(_, message, messageType, stack, locals)
    if not Recorder.running then
        return
    end
    local kind = messageType == WARNING and "warning" or "error"
    if wanted(kind) then
        Recorder.Add(kind, message, stack, locals)
    end
end

-- Errors Blizzard's window got before this addon loaded (or while the module was off). Its
-- list is only read; the time it keeps is a text, so they get the moment they're read.
local function importEarlier()
    local frame = _G.ScriptErrorsFrame
    local list = frame and frame.errorData
    if type(list) ~= "table" then
        return
    end
    for i = imported + 1, #list do
        local data = list[i]
        if type(data) == "table" then
            local kind = data.messageType == WARNING and "warning" or "error"
            if wanted(kind) then
                Recorder.Add(kind, data.message, data.stack, data.locals)
            end
        end
    end
    imported = #list
end

--- Starts collecting. The hook is installed once; while the module is off it does nothing.
function Recorder.Start()
    Recorder.Bind()
    local frame = _G.ScriptErrorsFrame
    if not Recorder.hooked and frame and frame.DisplayMessageInternal then
        hooksecurefunc(frame, "DisplayMessageInternal", fromBlizzard)
        Recorder.hooked = true
    end
    Recorder.running = true
    importEarlier()
end

function Recorder.Stop()
    Recorder.running = false
    local frame = _G.ScriptErrorsFrame
    imported = frame and type(frame.errorData) == "table" and #frame.errorData or imported
end

--- A blocked or forbidden action: the game names the addon and the function.
---@param event string
---@param addon any
---@param fn any
function Recorder.OnBlocked(event, addon, fn)
    if not (Recorder.running and opt("capture.blocked")) then
        return
    end
    local macro = event:find("^MACRO") ~= nil
    if macro then
        addon, fn = "Macro", addon
    end
    local who = readable(addon)
    if who == nil or who == "" then
        who = L.UNKNOWN_ADDON
    end
    local format = event:find("FORBIDDEN") and L.BLOCKED_FORBIDDEN or L.BLOCKED
    Recorder.Add("blocked", format:format(who, readable(fn) or "?"), "", nil)
end

Recorder.EVENTS = { "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "MACRO_ACTION_BLOCKED", "MACRO_ACTION_FORBIDDEN" }
