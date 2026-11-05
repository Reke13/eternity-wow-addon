-- The discs on screen. Everything that has to work in combat is secure:
--  * a header (EternityUIDiscsHeader) holds the snippets that open, close and pick;
--  * each disc (and each sub-disc) is a protected ring frame with one SecureActionButton per slot;
--  * each disc with a key has an opener button bound to that key (SetOverrideBindingClick).
-- Pressing the key opens the ring at the mouse; releasing it picks the slot in the mouse's
-- direction and copies its action onto the opener, which runs it on that same release. Clicking
-- a slot runs it directly. A sub-disc slot opens its ring in the same place; the center goes back.
-- Building rings, keys and slot actions only happens out of combat (queued until the fight ends);
-- the look (highlight, cooldowns, counts) is insecure and works anytime.
--
-- Clicks: every secure button listens to both phases, because the template acts on one or the other
-- by the ActionButtonUseKeyDown CVar. useOnKeyDown = false fixes it on the release, whatever the
-- CVar says, and the mouse snippets ignore the press, or a click would run on both phases.

---@type string, EternityUIDiscsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, W = ns.Ui.Theme, ns.Ui.W
local Skin = W.Skin
local Store, Resolve = ns.Store, ns.Resolve

---@class EternityUIDiscsRing
---@field header table?
---@field keys table? owner of the key bindings
---@field rings table[]
---@field openers table[]
---@field used integer rings in use after the last build
---@field running boolean
local Ring = { rings = {}, openers = {}, used = 0, running = false }
ns.Ring = Ring

-- Invisible pick area of every ring (in ring units): GetMousePosition only answers inside it.
local AREA = 4800
local CIRCLE = Theme.MEDIA .. "circle.tga"
local ACTION_ATTRIBUTES = { "type", "spell", "item", "toy", "macro", "macrotext" }

-- Secure snippets -------------------------------------------------------------------------------

-- header:RunAttribute("Open", index, keep): shows ring `index` (keep = where the current one is).
local OPEN = [[
local index, keep = ...
local ring = self:GetFrameRef("ring" .. index)
if not ring then
    return
end
local current = self:GetAttribute("current")
local old = current and self:GetFrameRef("ring" .. current)
ring:ClearAllPoints()
if keep and old then
    local l, b, w, h = old:GetRect()
    ring:SetPoint("CENTER", "$screen", "BOTTOMLEFT", l + w / 2, b + h / 2)
elseif self:GetAttribute("atCursor") then
    ring:SetPoint("CENTER", "$cursor", "BOTTOMLEFT", 0, 0)
else
    ring:SetPoint("CENTER", "$screen", "CENTER", 0, 0)
end
if old and old ~= ring then
    old:Hide()
end
ring:Show()
self:SetAttribute("current", index)
self:SetBindingClick(true, "ESCAPE", "EternityUIDiscsClose", "LeftButton")
]]

local CLOSE = [[
local current = self:GetAttribute("current")
local ring = current and self:GetFrameRef("ring" .. current)
if ring then
    ring:Hide()
end
self:SetAttribute("current", nil)
self:SetAttribute("state", nil)
self:SetAttribute("opener", nil)
self:ClearBindings()
]]

-- The index of the slot in the mouse's direction (nil inside the dead zone): an index because
-- RunAttribute scrubs what a snippet returns, and that turns a frame handle into nil. Slot i sits
-- at start - (i - 1) * step degrees, counter-clockwise from the right, like atan2.
local PICK = [[
local current = self:GetAttribute("current")
local ring = current and self:GetFrameRef("ring" .. current)
local n = ring and ring:GetAttribute("count") or 0
if n == 0 then
    return
end
local x, y = ring:GetMousePosition()
if not x then
    return
end
local _, _, w, h = ring:GetRect()
local dx, dy = (x - 0.5) * w, (y - 0.5) * h
local dead = self:GetAttribute("deadzone") or 0
if dx * dx + dy * dy < dead * dead then
    return
end
local step = 360 / n
local angle = (ring:GetAttribute("start") - math.deg(math.atan2(dy, dx))) % 360
return floor(angle / step + 0.5) % n + 1
]]

-- Opener (key binding). States: holding (key down after opening), open (waiting for the mouse
-- or another press), picking (second press in "press" mode or on an open disc).
local OPENER = [[
local state = owner:GetAttribute("state")
local mine = self:GetAttribute("ring")
if down then
    if state and owner:GetAttribute("opener") == mine then
        if state == "open" then
            owner:SetAttribute("state", "picking")
        end
    else
        owner:RunAttribute("Close")
        owner:RunAttribute("Open", mine)
        owner:SetAttribute("opener", mine)
        owner:SetAttribute("state", "holding")
    end
    return false
end
if state == "holding" and owner:GetAttribute("mode") == "toggle" then
    owner:SetAttribute("state", "open")
    return false
end
if state ~= "holding" and state ~= "picking" then
    return false
end
local index = owner:RunAttribute("Pick")
if not index then
    if state == "holding" and owner:GetAttribute("sticky") then
        owner:SetAttribute("state", "open")
    else
        owner:RunAttribute("Close")
    end
    return false
end
local ring = owner:GetFrameRef("ring" .. owner:GetAttribute("current"))
local slice = ring:GetFrameRef("slice" .. index)
local kind = slice:GetAttribute("kind")
if kind == "disc" then
    owner:RunAttribute("Open", slice:GetAttribute("child"), true)
    owner:SetAttribute("state", "open")
    return false
end
owner:RunAttribute("Close")
if kind ~= "action" then
    return false
end
self:SetAttribute("type", slice:GetAttribute("type"))
self:SetAttribute("spell", slice:GetAttribute("spell"))
self:SetAttribute("item", slice:GetAttribute("item"))
self:SetAttribute("toy", slice:GetAttribute("toy"))
self:SetAttribute("macro", slice:GetAttribute("macro"))
self:SetAttribute("macrotext", slice:GetAttribute("macrotext"))
]]

-- Mouse click on a slot: a sub-disc opens its ring; an action runs and then the disc closes.
local SLICE = [[
if down then
    return false
end
local kind = self:GetAttribute("kind")
if kind == "disc" then
    owner:RunAttribute("Open", self:GetAttribute("child"), true)
    owner:SetAttribute("state", "open")
    return false
end
if kind ~= "action" then
    return false
end
return nil, true
]]
local SLICE_AFTER = [[
owner:RunAttribute("Close")
]]

-- Center: back to the parent disc, or close the top one.
local BACK = [[
if down then
    return false
end
local current = owner:GetAttribute("current")
local ring = current and owner:GetFrameRef("ring" .. current)
local parent = ring and ring:GetAttribute("parent") or 0
if parent > 0 then
    owner:RunAttribute("Open", parent, true)
    owner:SetAttribute("state", "open")
else
    owner:RunAttribute("Close")
end
return false
]]

-- Helpers ---------------------------------------------------------------------------------------

local function opt(path)
    return E.store:Get(addonName, path)
end

local function isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

-- A secure button that always acts on the release (see the note at the top).
local function secureButton(parent, name)
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    button:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    button:SetAttribute("useOnKeyDown", false)
    return button
end

-- Insecure visuals -------------------------------------------------------------------------------

-- The face of a slot: everything visible, in a plain (not protected) child so it can change in
-- combat. Layers: border, fill, icon (masked when round), cooldown, count, label, sub-disc mark.
local function createFace(slice)
    local face = CreateFrame("Frame", nil, slice)
    face:SetPoint("CENTER")
    face.masked = false
    face.border = face:CreateTexture(nil, "BACKGROUND", nil, 0)
    face.border:SetPoint("CENTER")
    face.fill = face:CreateTexture(nil, "BACKGROUND", nil, 1)
    face.fill:SetPoint("CENTER")
    face.shape = Skin.Shape(face, "control", "BACKGROUND", 2)
    face.icon = face:CreateTexture(nil, "ARTWORK")
    face.icon:SetPoint("CENTER")
    face.mask = face:CreateMaskTexture()
    face.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    face.mask:SetAllPoints(face.icon)
    face.borderMask = face:CreateMaskTexture()
    face.borderMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    face.borderMask:SetAllPoints(face.border)
    face.fillMask = face:CreateMaskTexture()
    face.fillMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    face.fillMask:SetAllPoints(face.fill)
    face.cooldown = CreateFrame("Cooldown", nil, face, "CooldownFrameTemplate")
    face.cooldown:SetAllPoints(face.icon)
    face.cooldown:SetDrawEdge(false)
    face.count = W.Text(face, "", "small")
    face.count:SetPoint("BOTTOMRIGHT", face.icon, "BOTTOMRIGHT", -1, 2)
    face.label = W.Text(face, "", "small")
    face.label:SetPoint("TOP", face, "BOTTOM", 0, -2)
    face.mark = Skin.Icon(face, "chevronRight", 8)
    face.mark:SetPoint("TOPRIGHT", face, "TOPRIGHT", 0, 0)
    return face
end

-- Masks only for circles (squares and rounded ones crop the icon's edge instead). A mask is added
-- once: this runs again each time the mouse leaves a slot.
local function setMasked(face, round)
    if face.masked == round then
        return
    end
    face.masked = round
    if round then
        face.border:AddMaskTexture(face.borderMask)
        face.fill:AddMaskTexture(face.fillMask)
        face.icon:AddMaskTexture(face.mask)
    else
        face.border:RemoveMaskTexture(face.borderMask)
        face.fill:RemoveMaskTexture(face.fillMask)
        face.icon:RemoveMaskTexture(face.mask)
    end
end

-- Applies the slot look options to a face of `size` units.
local function styleFace(face, size)
    local shape = opt("slots.shape")
    local border = opt("slots.border")
    local round = shape == "circle"
    local inset = border and 2 or 0
    local br, bg, bb, ba = Theme.Color(opt("slots.borderColor"))
    local fr, fg, fb, fa = Theme.Color("surface")
    face:SetSize(size, size)
    face.size = size
    face.round = round
    face.rounded = shape == "rounded"

    if shape == "rounded" then
        face.border:Hide()
        face.fill:Hide()
        face.shape:SetColors("surface", border and { br, bg, bb, ba } or nil)
    else
        face.shape:SetColors(nil, nil)
        face.border:SetShown(border)
        face.border:SetSize(size, size)
        face.border:SetColorTexture(br, bg, bb, ba)
        face.fill:Show()
        face.fill:SetSize(size - 2 * inset, size - 2 * inset)
        face.fill:SetColorTexture(fr, fg, fb, fa or 1)
    end
    setMasked(face, round)
    if round then
        face.icon:SetTexCoord(0, 1, 0, 1)
    else
        face.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local iconSize = size - 2 * inset - (shape == "rounded" and 4 or 2)
    face.icon:SetSize(iconSize, iconSize)
    face.cooldown:SetSwipeTexture(round and CIRCLE or "Interface\\Buttons\\WHITE8X8")
    face.cooldown:SetUseCircularEdge(round)
end

-- A spell's cooldown as a Duration object (secret-safe; no global cooldown), false if not available.
local function spellDuration(spell)
    if not C_Spell.GetSpellCooldownDuration then
        return false
    end
    local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spell, true)
    return ok and duration or false
end

local function updateCooldown(face, node)
    if not opt("slots.cooldowns") then
        face.cooldown:Clear()
        return
    end
    local duration = node.spell and spellDuration(node.spell)
    if duration then
        face.cooldown:SetCooldownFromDurationObject(duration, true)
        return
    end
    local start, length
    if node.spell then
        local info = C_Spell.GetSpellCooldown(node.spell)
        if info then
            start, length = info.startTime, info.duration
        end
    elseif node.item then
        start, length = C_Item.GetItemCooldown(node.item)
    end
    if start and length and not isSecret(start) and not isSecret(length) and length > 1.5 then
        face.cooldown:SetCooldown(start, length)
    else
        face.cooldown:Clear()
    end
end

-- Cooldown and count of a slot (insecure; secret values are left out).
local function updateState(face, node)
    if not node then
        return
    end
    local count = ""
    local usable = not node.missing
    if node.item and node.attrs and node.attrs.type == "item" then
        local n = C_Item.GetItemCount(node.item, false, true)
        if not isSecret(n) then
            usable = usable and n > 0
            if opt("slots.counts") and n > 1 then
                count = tostring(n)
            end
        end
    end
    face.count:SetText(count)
    face.icon:SetDesaturated(not usable)
    -- In the color: a texture's SetAlpha replaces the alpha of its vertex color.
    face.icon:SetVertexColor(1, 1, 1, usable and 1 or 0.6)
    updateCooldown(face, node)
end

-- The ring's decoration (backdrop, pointer, center text) and its per-frame logic: which slot the
-- mouse points at, the opening animation and refreshing the slot states.
local function createVisual(ring)
    local visual = CreateFrame("Frame", nil, ring)
    visual:SetPoint("CENTER")
    visual.backdrop = visual:CreateTexture(nil, "BACKGROUND", nil, -2)
    visual.backdrop:SetAllPoints()
    visual.backdrop:SetTexture(CIRCLE)
    visual.pointer = visual:CreateTexture(nil, "BACKGROUND", nil, -1)
    visual.pointer:SetTexture(CIRCLE)
    visual.pointer:SetSize(10, 10)
    visual.title = W.Text(visual, "", "body")
    visual.title:SetPoint("CENTER")
    visual.title:SetWidth(120)
    visual.title:SetJustifyH("CENTER")
    visual.title:SetWordWrap(true)

    visual:SetScript("OnShow", function(self)
        -- The last slot pointed at when it closed goes back to normal.
        local last = self.hovered and ring.slices[self.hovered]
        if last then
            styleFace(last.face, last.face.size)
        end
        self.elapsed, self.tick, self.hovered = 0, 0, nil
        self.title:SetText(opt("disc.centerLabel") and ring.node.label or "")
        for _, slice in ipairs(ring.slices) do
            updateState(slice.face, slice.node)
        end
    end)
    visual:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        self.tick = self.tick + elapsed
        Ring:Track(ring)
        if self.tick > 0.25 then
            self.tick = 0
            for _, slice in ipairs(ring.slices) do
                if slice:IsShown() then
                    updateState(slice.face, slice.node)
                end
            end
        end
    end)
    return visual
end

--- Hover, highlight, pointer and animation of an open ring (insecure, every frame).
function Ring:Track(ring)
    local visual = ring.visual
    local n = ring.count or 0
    local scale = ring:GetEffectiveScale()
    local cx, cy = ring:GetCenter()
    local x, y = GetCursorPosition()
    local dx, dy = x / scale - (cx or 0), y / scale - (cy or 0)
    local hovered
    if n > 0 and dx * dx + dy * dy >= (opt("behavior.deadzone") ^ 2) then
        local step = 360 / n
        local angle = (ring.start - math.deg(math.atan2(dy, dx))) % 360
        hovered = math.floor(angle / step + 0.5) % n + 1
    end

    -- Opening animation: faces fade and grow in 0.12 s.
    local t = opt("disc.animation") and math.min(1, visual.elapsed / 0.12) or 1
    local grow = opt("highlight.scale")
    local dim = opt("highlight.dim") and hovered ~= nil
    local hr, hg, hb = Theme.Color(opt("highlight.color"))
    for i = 1, n do
        local face = ring.slices[i].face
        local on = i == hovered
        face:SetScale((0.6 + 0.4 * t) * (on and grow or 1))
        face:SetAlpha(t * ((dim and not on) and 0.55 or 1))
        if on and visual.hovered ~= i then
            if face.rounded then
                face.shape:SetColors("surface", { hr, hg, hb, 1 })
            else
                face.border:Show()
                face.border:SetColorTexture(hr, hg, hb, 1)
            end
        end
    end
    if visual.hovered ~= hovered then
        if visual.hovered and ring.slices[visual.hovered] then
            styleFace(ring.slices[visual.hovered].face, ring.slices[visual.hovered].face.size)
        end
        visual.hovered = hovered
        local node = hovered and ring.slices[hovered].node
        visual.title:SetText(opt("disc.centerLabel") and (node and node.label or ring.node.label) or "")
    end

    local showPointer = opt("highlight.pointer") and opt("disc.backdrop") and hovered ~= nil
    visual.pointer:SetShown(showPointer)
    local length = math.sqrt(dx * dx + dy * dy)
    if showPointer and length > 0 then
        local radius = visual:GetWidth() / 2 - 6
        visual.pointer:SetVertexColor(hr, hg, hb, 1)
        visual.pointer:ClearAllPoints()
        visual.pointer:SetPoint("CENTER", visual, "CENTER", dx / length * radius, dy / length * radius)
    end
end

-- Frames -----------------------------------------------------------------------------------------

function Ring:Init()
    if self.header then
        return
    end
    local header = CreateFrame("Frame", "EternityUIDiscsHeader", UIParent, "SecureHandlerBaseTemplate")
    header:SetAttribute("Open", OPEN)
    header:SetAttribute("Close", CLOSE)
    header:SetAttribute("Pick", PICK)
    self.header = header
    self.keys = CreateFrame("Frame")

    -- Escape (bound only while a disc is open) clicks this one.
    local close = secureButton(UIParent, "EternityUIDiscsClose")
    SecureHandlerWrapScript(
        close,
        "OnClick",
        header,
        [[
        owner:RunAttribute("Close")
        return false
    ]]
    )
end

local function createSlice(ring)
    local slice = secureButton(ring)
    slice.face = createFace(slice)
    SecureHandlerWrapScript(slice, "OnClick", Ring.header, SLICE, SLICE_AFTER)
    return slice
end

local function createRing(index)
    local ring = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    ring:SetSize(AREA, AREA)
    ring:SetFrameStrata("DIALOG")
    ring:Hide()
    ring.slices = {}
    ring.visual = createVisual(ring)
    ring.center = secureButton(ring)
    ring.center:SetPoint("CENTER")
    SecureHandlerWrapScript(ring.center, "OnClick", Ring.header, BACK)
    SecureHandlerSetFrameRef(Ring.header, "ring" .. index, ring)
    Ring.rings[index] = ring
    return ring
end

local function opener(index)
    local button = Ring.openers[index]
    if not button then
        button = secureButton(UIParent, "EternityUIDiscsOpen" .. index)
        SecureHandlerWrapScript(button, "OnClick", Ring.header, OPENER)
        Ring.openers[index] = button
    end
    return button
end

-- Lays out ring `index` for `node` (and, recursively, a ring per sub-disc). Out of combat only.
function Ring:Allocate(node, parent)
    self.used = self.used + 1
    local index = self.used
    local ring = self.rings[index] or createRing(index)
    local children = node.children or {}
    local n = math.min(#children, Store.MAX_SLOTS)
    local size = opt("slots.size")
    -- The radius grows when the slots wouldn't fit around it.
    local radius = math.max(opt("disc.radius"), n * (size + 6) / (2 * math.pi))
    local start = 90 - opt("disc.startAngle")
    local step = n > 0 and 360 / n or 0

    ring.node, ring.count, ring.start = node, n, start
    ring:SetScale(opt("disc.scale"))
    ring:SetAlpha(opt("disc.alpha"))
    ring:SetAttribute("count", n)
    ring:SetAttribute("start", start)
    ring:SetAttribute("parent", parent)

    local outer = 2 * radius + size + 24
    ring.visual:SetSize(outer, outer)
    ring.visual.backdrop:SetShown(opt("disc.backdrop"))
    ring.visual.backdrop:SetVertexColor(Theme.Color(opt("disc.backdropColor")))
    ring.visual.title:SetWidth(math.max(60, 2 * radius - size - 8))
    ring.visual.title:SetText(opt("disc.centerLabel") and node.label or "")
    local inner = math.max(24, 2 * radius - size - 12)
    ring.center:SetSize(inner, inner)

    for i = 1, n do
        local child = children[i]
        local slice = ring.slices[i] or createSlice(ring)
        ring.slices[i] = slice
        local angle = math.rad(start - (i - 1) * step)
        slice:ClearAllPoints()
        slice:SetPoint("CENTER", ring, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
        slice:SetSize(size, size)
        slice.node = child
        for _, key in ipairs(ACTION_ATTRIBUTES) do
            slice:SetAttribute(key, child.attrs and child.attrs[key] or nil)
        end
        SecureHandlerSetFrameRef(ring, "slice" .. i, slice)

        local face = slice.face
        styleFace(face, size)
        face.icon:SetTexture(child.icon)
        face.label:SetText(child.label)
        face.label:SetShown(opt("slots.labels"))
        face.mark:SetShown(child.children ~= nil and opt("slots.subdiscMark"))
        if child.children then
            slice:SetAttribute("kind", "disc")
            slice:SetAttribute("child", self:Allocate(child, index))
        else
            slice:SetAttribute("kind", child.attrs and "action" or "empty")
            slice:SetAttribute("child", nil)
        end
        slice:Show()
    end
    for i = n + 1, #ring.slices do
        ring.slices[i]:Hide()
        ring.slices[i].node = nil
    end
    return index
end

-- Rings and keys from the store and the options. Out of combat only.
function Ring:Apply()
    self:Init()
    SecureHandlerExecute(self.header, [[ self:RunAttribute("Close") ]])
    ClearOverrideBindings(self.keys)
    self.used = 0
    for _, button in ipairs(self.openers) do
        button:SetAttribute("ring", nil)
    end
    if not self.running then
        return
    end

    local header = self.header
    header:SetAttribute("mode", opt("behavior.activation"))
    header:SetAttribute("sticky", opt("behavior.sticky"))
    header:SetAttribute("atCursor", opt("behavior.position") == "cursor")
    header:SetAttribute("deadzone", opt("behavior.deadzone"))

    local keys = Store:Keys()
    local count = 0
    for _, disc in ipairs(Store:List()) do
        local key = keys[disc.id]
        if key then
            count = count + 1
            local button = opener(count)
            button:SetAttribute("ring", self:Allocate(Resolve.Disc(disc), 0))
            SetOverrideBindingClick(self.keys, true, key, button:GetName(), "LeftButton")
        end
    end
end

--- Rebuilds every ring and key. In combat it waits for the end.
function Ring:Build()
    E.Combat.Run(self, function()
        self:Apply()
    end)
end

function Ring:Start()
    self.running = true
    self:Build()
end

--- Closes the discs and frees the keys (in combat, when it ends).
function Ring:Stop()
    self.running = false
    self:Build()
end

--- true if a disc is open.
function Ring:IsOpen()
    return self.header ~= nil and self.header:GetAttribute("current") ~= nil
end

--- Opens a disc by its index among the keyed ones, out of combat (tests and previews).
function Ring:Open(index)
    if self.header and not InCombatLockdown() and self.openers[index] then
        local ring = self.openers[index]:GetAttribute("ring")
        if ring then
            SecureHandlerExecute(self.header, ([[ self:RunAttribute("Open", %d) ]]):format(ring))
            self.header:SetAttribute("state", "open")
            self.header:SetAttribute("opener", ring)
            return self.rings[ring]
        end
    end
end

function Ring:Close()
    if self.header and not InCombatLockdown() then
        SecureHandlerExecute(self.header, [[ self:RunAttribute("Close") ]])
    end
end
