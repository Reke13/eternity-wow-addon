-- EternityUI_Bugs: collects the game's Lua errors, warnings and blocked actions (Recorder) and
-- lists them (Window). This file starts and stops them and tells the player when one comes in.
-- Nothing of Blizzard's is replaced: its error window keeps working as before (the "Display Lua
-- errors" setting still decides whether it pops up), and disabling the module only stops the
-- collecting.

---@type string, EternityUIBugsNamespace
local addonName, ns = ...
local E = EternityUI
local L, Recorder, Window, opt = ns.L, ns.Recorder, ns.Window, ns.opt

local CHAT_EVERY = 10 -- seconds between chat notices, so a burst gives one line
local MESSAGE_LENGTH = 80

---@class EternityUIBugsModule: EternityUIModuleDefinition
local Module = {
    schema = ns.OptionsSchema,
    actions = {
        {
            text = L.OPEN,
            onClick = function()
                Window.Toggle()
            end,
        },
    },
}
-- Internals reachable from the tests.
Module.Recorder, Module.Window = Recorder, Window

local lastNotice = -math.huge

local function short(text)
    local line = text:match("^[^\n]*") or text
    -- The file path is long and the same for every error of an addon: keep its name and line.
    line = line:gsub("^Interface[/\\]AddOns[/\\]", "")
    if #line > MESSAGE_LENGTH then
        line = line:sub(1, MESSAGE_LENGTH - 3) .. "..."
    end
    return line
end

--- A new error (or a known one again): chat line, sound and the list, as the options say.
---@param entry EternityUIBugsEntry
---@param isNew boolean new this session
function Module.Notify(entry, isNew)
    Window.Schedule()
    local now = GetTime()
    if opt("notify.chat") and now - lastNotice >= CHAT_EVERY then
        lastNotice = now
        if isNew or entry.count == 1 then
            print(L.NEW:format(short(entry.message)))
        else
            print(L.AGAIN:format(entry.count))
        end
    end
    if isNew and opt("notify.sound") and SOUNDKIT then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
    if isNew and opt("notify.open") and not InCombatLockdown() then
        if not (Window.frame and Window.frame:IsShown()) then
            Window.Open()
        end
    end
end

function Module:OnEnable()
    Recorder.onAdd = Module.Notify
    for _, event in ipairs(Recorder.EVENTS) do
        E.Events.On(event, self, Recorder.OnBlocked)
    end
    Recorder.Start()
    Recorder.Trim()
end

function Module:OnDisable()
    Recorder.onAdd = nil
    Recorder.Stop()
    Window.Stop()
end

function Module:OnConfigChanged(path)
    if path == nil or path == "capture.limit" then
        Recorder.Trim()
    end
    Window.Apply()
end

_G.SLASH_ETERNITYBUGS1 = "/etbugs"
SlashCmdList.ETERNITYBUGS = function()
    if E.store:IsModuleEnabled(addonName) then
        Window.Toggle()
    else
        E:OpenOptions(addonName)
    end
end

E:RegisterModule(addonName, Module)
