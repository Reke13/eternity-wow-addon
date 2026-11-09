-- One Mover session: changes live in a draft, applied to the frames at once and only saved to the
-- profile on Save. Discard puts everything back. Combat hides the Mover until it ends.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Mover = E.Mover

local Session = { undo = {}, redo = {} }
ns.MoverSession = Session
E.MoverSession = Session

local samples

-- Without modules there's nothing to move yet: three sample frames, visible only in the session.
local function ensureSamples()
    if #Mover.List() > 0 and not samples then
        return
    end
    if not samples then
        samples = {}
        local definitions = {
            { "sample.player", L.SAMPLE_PLAYER, "BOTTOM", -190, 220, 200, 64 },
            { "sample.target", L.SAMPLE_TARGET, "BOTTOM", 190, 220, 200, 64 },
            { "sample.bar", L.SAMPLE_BAR, "BOTTOM", 0, 60, 440, 48 },
        }
        for _, d in ipairs(definitions) do
            local frame = CreateFrame("Frame", nil, UIParent)
            frame:SetSize(d[6], d[7])
            samples[#samples + 1] = frame
            Mover.Register({ key = d[1], label = d[2], point = d[3], x = d[4], y = d[5], frame = frame })
        end
    end
    for _, frame in ipairs(samples) do
        frame:Show()
    end
end

local function close()
    Session.active = false
    Session.selected = nil
    E.Events.Send(Mover.TOGGLED, false)
    ns.MoverScene.Hide()
    ns.MoverElements.Close()
    for _, frame in ipairs(samples or {}) do
        frame:Hide()
    end
    E.Events.Off("PLAYER_REGEN_DISABLED", Session)
    E.Events.Off("PLAYER_REGEN_ENABLED", Session)
    E.Events.Unlisten(E.CONFIG_CHANGED, Session)
end

--- Redraws everything after a change.
function Session.Refresh()
    Mover.ApplyAll(Session.draft)
    ns.MoverScene.RefreshElements()
end

-- An option can change an element's size. Modules apply their options on the next frame, so the
-- handles are measured a moment later, once for a burst of changes.
local function onConfigChanged()
    if Session.refreshPending then
        return
    end
    Session.refreshPending = true
    C_Timer.After(0.1, function()
        Session.refreshPending = false
        if Session.active then
            Session.Refresh()
        end
    end)
end

--- The draft position of an element.
---@param key string
---@return table
function Session.Entry(key)
    return Mover.Entry(key, Session.draft)
end

--- Marks an undo step: call it before changing the draft.
function Session.Checkpoint()
    Session.undo[#Session.undo + 1] = E.DeepCopy(Session.draft)
    Session.redo = {}
end

--- Replaces an element's position in the draft (nil goes back to the default).
---@param key string
---@param entry table?
function Session.Set(key, entry)
    Session.draft[key] = entry
    Session.Refresh()
end

function Session.Select(key)
    Session.selected = key
    ns.MoverScene.RefreshElements()
end

local function step(from, to)
    local layout = table.remove(from)
    if layout then
        to[#to + 1] = E.DeepCopy(Session.draft)
        Session.draft = layout
        Session.Refresh()
    end
end

function Session.Undo()
    step(Session.undo, Session.redo)
end

function Session.Redo()
    step(Session.redo, Session.undo)
end

--- Throws the session away and goes back to the saved layout.
function Session.Discard()
    close()
    Mover.ApplyAll()
end

--- Saves the session and exits.
function Session.Save()
    close()
    Mover.Save(Session.draft)
end

local function open()
    if InCombatLockdown() then
        print(L.MOVER_COMBAT)
        return
    end
    E.Events.Send(Mover.TOGGLED, true)
    ensureSamples()
    Session.draft = Mover.Layout()
    Session.undo, Session.redo = {}, {}
    Session.active = true
    if ns.Window.frame then
        ns.Window.frame:Hide()
    end
    E.Events.On("PLAYER_REGEN_DISABLED", Session, ns.MoverScene.Hide)
    E.Events.On("PLAYER_REGEN_ENABLED", Session, ns.MoverScene.Show)
    E.Events.Listen(E.CONFIG_CHANGED, Session, onConfigChanged)
    ns.MoverScene.Show()
end

--- Enters Mover mode, or leaves it without saving.
function Session.Toggle()
    if Session.active then
        Session.Discard()
    else
        open()
    end
end
