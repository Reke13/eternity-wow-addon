-- EternityUI_Minimal: hides the parts of the interface the player picks (Parts tab) and shows
-- them again with the eye on screen, a key or /etmin. Blizzard only hides the whole interface.
-- What's picked and whether it's hidden live in EternityUIMinimalDB, for the account.
-- Disabling the module shows everything again, without /reload.

---@type string, EternityUIMinimalNamespace
local addonName, ns = ...
local E = EternityUI
local L, Parts, Hiding, Button, PartsTab = ns.L, ns.Parts, ns.Hiding, ns.Button, ns.PartsTab

---@class EternityUIMinimalModule: EternityUIModuleDefinition
---@field running boolean?
---@field typing boolean? a chat edit box has the focus
---@field hidden boolean? the picked parts are hidden now
---@field fighting boolean? combat shows everything for now
local Module = {
    schema = ns.OptionsSchema,
    tabs = { { key = "parts", text = L.TAB, build = PartsTab.Build, description = L.TAB_HINT } },
    defaultTab = "parts",
}
ns.Module = Module

local function opt(path)
    return E.store:Get(addonName, path)
end

local function db()
    if type(_G.EternityUIMinimalDB) ~= "table" then
        _G.EternityUIMinimalDB = {}
    end
    local saved = _G.EternityUIMinimalDB
    saved.parts = type(saved.parts) == "table" and saved.parts or {}
    return saved
end

local function say(text)
    local r, g, b = E.Theme.Color("accent")
    print(("|cff%02x%02x%02xEternity:|r %s"):format(r * 255, g * 255, b * 255, text))
end

--- True if the part is picked to hide.
---@param key string
---@return boolean
function Module:IsPicked(key)
    return db().parts[key] == true
end

--- Picks a part or lets it go; applied at once while hidden.
---@param key string
---@param picked boolean
function Module:SetPart(key, picked)
    db().parts[key] = picked and true or nil
    self:Apply()
end

--- Hides the picked parts (when hidden and not shown for combat) and shows the rest.
function Module:Apply()
    local hide = self.running and self.hidden and not self.fighting
    local keep = {}
    if hide then
        local parts = Parts.All()
        parts[#parts + 1] = Parts.Custom(opt("extra.frames"))
        for _, part in ipairs(parts) do
            -- The chat comes back while typing.
            local peeking = part.typing and self.typing
            if (part.custom or self:IsPicked(part.key)) and not peeking then
                for _, frame in ipairs(part.frames) do
                    keep[frame] = true
                    Hiding.Hide(frame, part.fade and part.fade[frame])
                end
            end
        end
    end
    -- The rest comes back, also frames of parts that are gone (a module disabled meanwhile).
    for _, frame in ipairs(Hiding.Frames()) do
        if not keep[frame] then
            Hiding.Show(frame)
        end
    end
    Button.SetState(self.hidden == true)
end

--- Hides or shows the picked parts.
---@param hidden boolean
---@param quiet boolean? no chat line
function Module:SetHidden(hidden, quiet)
    if hidden and not next(db().parts) and #Parts.Custom(opt("extra.frames")).frames == 0 then
        say(L.NOTHING)
        return
    end
    self.hidden = hidden
    db().hidden = hidden
    self:Apply()
    if not quiet then
        say(hidden and L.HIDDEN or L.SHOWN)
    end
end

function Module:Toggle()
    if self.running then
        self:SetHidden(not self.hidden)
    end
end

-- While a chat edit box has the focus, the chat shows (its window is faded, so the box too).
local typingHooked = false
local function hookTyping(self)
    if typingHooked then
        return
    end
    typingHooked = true
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local box = _G["ChatFrame" .. i .. "EditBox"]
        if box and box.HookScript then
            box:HookScript("OnEditFocusGained", function()
                if self.running and not self.typing then
                    self.typing = true
                    self:Apply()
                end
            end)
            box:HookScript("OnEditFocusLost", function()
                if self.typing then
                    self.typing = false
                    self:Apply()
                end
            end)
        end
    end
end

function Module:OnEnable()
    self.running = true
    self.fighting = false
    self.typing = false
    hookTyping(self)
    Button.Create(function()
        self:Toggle()
    end)
    Button.SetShown(opt("toggle.button"))
    Button.Bind(opt("toggle.key"))
    self.hidden = opt("toggle.remember") and db().hidden == true or false
    db().hidden = self.hidden
    E.Events.On("PLAYER_REGEN_DISABLED", self, function()
        if self.hidden and opt("combat.show") then
            self.fighting = true
            self:Apply()
        end
    end)
    E.Events.On("PLAYER_REGEN_ENABLED", self, function()
        if self.fighting then
            self.fighting = false
            self:Apply()
        end
    end)
    -- Eternity's parts appear as their modules start: hide them once the world is in.
    E.Events.On("PLAYER_ENTERING_WORLD", self, function()
        C_Timer.After(1, function()
            if self.running then
                self:Apply()
            end
        end)
    end)
    E.Events.Listen(E.Theme.CHANGED, self, function()
        Button.SetState(self.hidden == true)
    end)
    self:Apply()
end

function Module:OnDisable()
    self.running = false
    self.fighting = false
    Hiding.ShowAll()
    Button.SetShown(false)
    Button.Bind(nil)
end

function Module:OnConfigChanged()
    if not self.running then
        return
    end
    Button.SetShown(opt("toggle.button"))
    Button.Bind(opt("toggle.key"))
    if self.fighting and not opt("combat.show") then
        self.fighting = false
    end
    self:Apply()
end

_G.SLASH_ETERNITYMINIMAL1 = "/etmin"
SlashCmdList.ETERNITYMINIMAL = function(msg)
    if (msg or ""):lower():match("^%s*options") then
        E:OpenOptions(addonName)
    else
        Module:Toggle()
    end
end

E:RegisterModule(addonName, Module)
