-- The parts that can be hidden: every Eternity element the Mover knows (it changes as modules are
-- enabled) and a fixed list of Blizzard's frames. A part is { key, label, frames }; its key is
-- what EternityUIMinimalDB.parts remembers.

---@type string, EternityUIMinimalNamespace
local addonName, ns = ...
local E = EternityUI
local L = ns.L

local Parts = {}
ns.Parts = Parts

-- The chat windows, their tabs and the dock's buttons. The edit boxes stay out: typing must
-- still work with the chat hidden.
local function chatFrames()
    local names = { "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton" }
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        names[#names + 1] = "ChatFrame" .. i
        names[#names + 1] = "ChatFrame" .. i .. "Tab"
    end
    return names
end

local BLIZZARD = {
    { key = "minimap", label = "B_MINIMAP", names = { "MinimapCluster" } },
    { key = "tracker", label = "B_TRACKER", names = { "ObjectiveTrackerFrame" } },
    { key = "buffs", label = "B_BUFFS", names = { "BuffFrame", "DebuffFrame" } },
    -- The chat windows only fade (their edit box is a child: typing must work) and come back
    -- while typing.
    { key = "chat", label = "B_CHAT", names = chatFrames, fade = "^ChatFrame%d+$", typing = true },
    {
        key = "actionbars",
        label = "B_ACTIONBARS",
        names = {
            "MainActionBar",
            "MultiBarBottomLeft",
            "MultiBarBottomRight",
            "MultiBarRight",
            "MultiBarLeft",
            "MultiBar5",
            "MultiBar6",
            "MultiBar7",
        },
    },
    { key = "petstance", label = "B_PET_STANCE", names = { "PetActionBar", "StanceBar" } },
    { key = "micro", label = "B_MICRO", names = { "MicroMenuContainer" } },
    { key = "bagsbar", label = "B_BAGSBAR", names = { "BagsBar" } },
    { key = "xp", label = "B_XP", names = { "StatusTrackingBarManager" } },
    { key = "player", label = "B_PLAYER", names = { "PlayerFrame" } },
    { key = "target", label = "B_TARGET", names = { "TargetFrame", "FocusFrame" } },
    { key = "group", label = "B_GROUP", names = { "PartyFrame", "CompactRaidFrameContainer" } },
    { key = "castbar", label = "B_CASTBAR", names = { "PlayerCastingBarFrame" } },
}

-- The key of Minimal's own button: it never hides itself.
Parts.OWN_KEY = addonName .. ".button"

--- Blizzard's parts whose frames exist in this client.
---@return table[]
function Parts.Blizzard()
    local list = {}
    for _, part in ipairs(BLIZZARD) do
        local names = type(part.names) == "function" and part.names() or part.names
        local frames, fade = {}, {}
        for _, name in ipairs(names) do
            local frame = _G[name]
            if type(frame) == "table" and frame.SetAlpha then
                frames[#frames + 1] = frame
                if part.fade and name:match(part.fade) then
                    fade[frame] = true
                end
            end
        end
        if #frames > 0 then
            list[#list + 1] = {
                key = "blizzard." .. part.key,
                label = L[part.label],
                frames = frames,
                fade = fade,
                typing = part.typing,
            }
        end
    end
    return list
end

-- Other addons' frames, when the addon is loaded.
local ADDONS = {
    {
        key = "zygor",
        label = "Zygor Guides",
        addons = { "ZygorGuidesViewerForever", "ZygorGuidesViewer", "ZygorGuidesViewerClassic" },
        names = { "ZygorGuidesViewerFrame", "ZygorGuidesViewer_ActionBar" },
    },
    { key = "questie", label = "Questie", addons = { "Questie" }, names = { "Questie_BaseFrame" } },
    { key = "spy", label = "Spy", addons = { "Spy" }, names = { "Spy_MainWindow" } },
}

local function loaded(addons)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    for _, name in ipairs(addons) do
        if isLoaded and isLoaded(name) then
            return true
        end
    end
    return false
end

local function framesOf(names)
    local frames = {}
    for _, name in ipairs(names) do
        local frame = _G[name]
        if type(frame) == "table" and frame.SetAlpha then
            frames[#frames + 1] = frame
        end
    end
    return frames
end

--- Other addons' parts: those of the known addons that are loaded.
---@return table[]
function Parts.Addons()
    local list = {}
    for _, part in ipairs(ADDONS) do
        if loaded(part.addons) then
            local frames = framesOf(part.names)
            if #frames > 0 then
                list[#list + 1] = { key = "addon." .. part.key, label = part.label, frames = frames }
            end
        end
    end
    return list
end

--- The frames named in the "Other frames" option (names by commas or spaces, as /fstack shows
--- them). Picked by being listed.
---@param text string?
---@return table
function Parts.Custom(text)
    local names = {}
    for name in tostring(text or ""):gmatch("[%w_%.]+") do
        names[#names + 1] = name
    end
    return { key = "custom", label = "", frames = framesOf(names), custom = true }
end

--- Eternity's parts: the Mover's elements, sorted by label.
---@return table[]
function Parts.Eternity()
    local list = {}
    for _, element in ipairs(E.Mover.List()) do
        if element.key ~= Parts.OWN_KEY and element.frame then
            list[#list + 1] = { key = "eternity." .. element.key, label = element.label, frames = { element.frame } }
        end
    end
    return list
end

--- Every part: Eternity's, Blizzard's and other addons'.
---@return table[]
function Parts.All()
    local list = Parts.Eternity()
    for _, group in ipairs({ Parts.Blizzard(), Parts.Addons() }) do
        for _, part in ipairs(group) do
            list[#list + 1] = part
        end
    end
    return list
end
