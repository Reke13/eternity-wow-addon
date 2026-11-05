-- Game events and internal messages for the core and its modules, on one shared frame.
-- Each owner has at most one handler per event. Handler lists are replaced, never edited, so a
-- handler may subscribe or unsubscribe while its event is being dispatched. A handler's error is
-- reported and doesn't stop the others.
---@type string, EternityUINamespace
local _, ns = ...

---@class EternityEvents
local Events = {}
ns.Events = Events
EternityUI.Events = Events

local frame = CreateFrame("Frame")
local events = {} -- event -> { { owner, fn }, ... }
local messages = {} -- message -> { { owner, fn }, ... }

local function without(list, owner)
    local copy = {}
    for _, entry in ipairs(list or {}) do
        if entry.owner ~= owner then
            copy[#copy + 1] = entry
        end
    end
    return copy
end

local function dispatch(list, ...)
    if not list then
        return
    end
    for i = 1, #list do
        local ok, err = pcall(list[i].fn, ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    dispatch(events[event], event, ...)
end)

--- True if the client knows this event. On Forever, registering an unknown event throws.
---@param event string
---@return boolean
function Events.IsValid(event)
    return C_EventUtils.IsEventValid(event) and true or false
end

--- Subscribes owner to a game event: fn(event, ...). Returns false if the client lacks the event.
---@param event string
---@param owner any
---@param fn function
---@return boolean
function Events.On(event, owner, fn)
    if not Events.IsValid(event) then
        return false
    end
    local list = without(events[event], owner)
    list[#list + 1] = { owner = owner, fn = fn }
    events[event] = list
    frame:RegisterEvent(event)
    return true
end

--- Removes owner's handler for a game event.
---@param event string
---@param owner any
function Events.Off(event, owner)
    if not events[event] then
        return
    end
    local list = without(events[event], owner)
    if #list == 0 then
        events[event] = nil
        frame:UnregisterEvent(event)
    else
        events[event] = list
    end
end

--- Subscribes owner to an internal message: fn(message, ...).
---@param message string
---@param owner any
---@param fn function
function Events.Listen(message, owner, fn)
    local list = without(messages[message], owner)
    list[#list + 1] = { owner = owner, fn = fn }
    messages[message] = list
end

--- Removes owner's handler for an internal message.
---@param message string
---@param owner any
function Events.Unlisten(message, owner)
    if messages[message] then
        messages[message] = without(messages[message], owner)
    end
end

--- Sends an internal message.
---@param message string
function Events.Send(message, ...)
    dispatch(messages[message], message, ...)
end

--- Removes every handler of owner: a module calls it when it's disabled.
---@param owner any
function Events.Release(owner)
    for event in pairs(events) do
        Events.Off(event, owner)
    end
    for message in pairs(messages) do
        Events.Unlisten(message, owner)
    end
end
