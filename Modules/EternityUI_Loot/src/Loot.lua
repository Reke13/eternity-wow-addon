-- EternityUI_Loot: a loot window of its own (Window), a history of what was looted (Recorder and
-- History) and a spot in the Mover for Blizzard's group rolls (Rolls). This file passes the game's
-- events to them. Disabling the module gives Blizzard back its loot window and rolls at once.

---@type string, EternityUILootNamespace
local addonName, ns = ...
local E = EternityUI
local L, Recorder, Window, History, Rolls = ns.L, ns.Recorder, ns.Window, ns.History, ns.Rolls

local CHAT_EVENTS = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY" }

---@class EternityUILootModule: EternityUIModuleDefinition
local Module = {
    schema = ns.OptionsSchema,
    actions = {
        {
            text = L.OPEN_HISTORY,
            onClick = function()
                History.Toggle()
            end,
        },
        {
            text = L.PREVIEW,
            onClick = function()
                Window.Preview()
            end,
        },
    },
}
-- Internals reachable from the tests.
Module.Recorder, Module.Window, Module.History, Module.Rolls = Recorder, Window, History, Rolls

local HANDLERS = {
    LOOT_READY = function()
        Recorder.Open()
    end,
    LOOT_OPENED = function(_, isAutoLoot, fromItem)
        Recorder.Open()
        Window.Open(isAutoLoot, fromItem)
    end,
    LOOT_SLOT_CLEARED = function(_, slot)
        Recorder.Cleared(slot)
        Window.Update()
    end,
    LOOT_SLOT_CHANGED = function()
        Window.Update()
    end,
    LOOT_CLOSED = function()
        Recorder.Close()
        Window.Close()
    end,
}

function Module:OnEnable()
    Recorder.Bind()
    Recorder.onAdd = History.Schedule
    for event, handler in pairs(HANDLERS) do
        E.Events.On(event, self, handler)
    end
    for _, event in ipairs(CHAT_EVENTS) do
        E.Events.On(event, self, Recorder.OnChat)
    end
    Window.Start()
    Rolls.Apply()
end

function Module:OnDisable()
    Recorder.onAdd = nil
    Recorder.Close()
    Window.Stop()
    Rolls.Stop()
    History.Stop()
end

function Module:OnConfigChanged(path)
    Window.Apply()
    Rolls.Apply()
    if path == nil or path == "history.limit" then
        Recorder.Trim()
    end
end

_G.SLASH_ETERNITYLOOT1 = "/etloot"
SlashCmdList.ETERNITYLOOT = function()
    History.Toggle()
end

E:RegisterModule(addonName, Module)
