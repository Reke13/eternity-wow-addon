-- Eternity's entries in Blizzard's UI: the addon compartment (the minimap's addon button) and a
-- page in Options > AddOns with a button that opens Eternity's own window. A failure here leaves
-- the rest of the addon working.
---@type string, EternityUINamespace
local _, ns = ...
local Events = ns.Events
local L = ns.L

local Integration = {}

local function registerCompartment()
    if not ns.store:Get("EternityUI", "general.minimapEntry") then
        return
    end
    AddonCompartmentFrame:RegisterAddon({
        text = "Eternity",
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
        notCheckable = true,
        func = function()
            EternityUI:ToggleOptions()
        end,
    })
end

-- Shows Eternity's window over Blizzard's options, without closing it if it's already open.
-- Blizzard's options stay open: closing them from here would run their OnHide (bindings, micro
-- buttons) tainted by this click.
local function openFromSettings()
    local window = EternityUI.OptionsWindow
    if not (window and window.frame and window.frame:IsShown()) then
        EternityUI:ToggleOptions()
    end
    window = EternityUI.OptionsWindow
    if window and window.frame then
        window.frame:Raise()
    end
end

local function buildSettingsPage()
    local frame = CreateFrame("Frame")

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Eternity |cff808080" .. EternityUI.version .. "|r")

    local notes = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    notes:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    notes:SetPoint("RIGHT", -16, 0)
    notes:SetJustifyH("LEFT")
    notes:SetText(L.SETTINGS_NOTES)

    local open = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    open:SetSize(220, 26)
    open:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -16)
    open:SetText(L.SETTINGS_OPEN)
    open:SetScript("OnClick", openFromSettings)

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -8)
    hint:SetText(L.SETTINGS_HINT)

    return frame
end

local function registerSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end
    local category = Settings.RegisterCanvasLayoutCategory(buildSettingsPage(), "Eternity")
    Settings.RegisterAddOnCategory(category)
    Integration.settingsCategory = category
end

local function safely(fn)
    local ok, err = pcall(fn)
    if not ok then
        geterrorhandler()(err)
    end
end

Events.Listen(EternityUI.READY, Integration, function()
    safely(registerCompartment)
    safely(registerSettings)
end)
