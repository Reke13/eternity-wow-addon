-- The loot window: replaces Blizzard's while the option is on. LootFrame only stops listening to the
-- two events that open and close it, so giving it back is registering them again. Opens at the mouse
-- or at a holder placed with the Mover: the holder keeps its top left corner while the window changes
-- height with the loot.

---@type string, EternityUILootNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets
local L, opt, Recorder = ns.L, ns.opt, ns.Recorder

local KEY = addonName .. ".window"
local HEADER = 32
local FOOTER = 36
local PADDING = 6
local ROW_GAP = 3
local ICON_INSET = 3
local BUTTON_HEIGHT = 26
local HOLDER_WIDTH, HOLDER_HEIGHT = 260, 160
local BLIZZARD_EVENTS = { "LOOT_OPENED", "LOOT_CLOSED" }
local QUEST_COLOR = { 1, 0.82, 0.2, 0.9 }
local SAMPLE_ICON = 134400 -- the question mark

---@class EternityUILootWindow
---@field frame table?
---@field holder table?
---@field looting boolean? the game has a loot session open
---@field preview boolean? showing the sample rows
---@field taken boolean? Blizzard's window isn't listening
local Window = { rows = {} }
ns.Window = Window

local function plain(name)
    return ((name or ""):gsub("\n", ", "))
end

local function samples()
    return {
        { name = L.SAMPLE_GOLD, icon = 133784, quality = 1, count = 1 },
        { name = L.SAMPLE_COMMON, icon = SAMPLE_ICON, quality = 1, count = 8 },
        { name = L.SAMPLE_RARE, icon = SAMPLE_ICON, quality = 3, count = 1 },
        { name = L.SAMPLE_EPIC, icon = SAMPLE_ICON, quality = 4, count = 1, quest = true },
    }
end

--- What the loot session holds now. Emptied slots are left out.
---@return table[]
function Window.Read()
    local items = {}
    for slot = 1, GetNumLootItems() do
        local slotType = GetLootSlotType(slot)
        if slotType ~= Enum.LootSlotType.None then
            local icon, name, count, currencyID, quality, locked, isQuestItem, questID, isActive = GetLootSlotInfo(slot)
            local currency = _G.CurrencyContainerUtil
            if currencyID and currency then
                name, icon, count, quality = currency.GetCurrencyContainerInfo(currencyID, count, name, icon, quality)
            end
            items[#items + 1] = {
                slot = slot,
                slotType = slotType,
                name = plain(name),
                icon = icon,
                count = count,
                quality = quality or 1,
                locked = locked,
                quest = isQuestItem or questID ~= nil,
                bang = questID ~= nil and not isActive,
            }
        end
    end
    return items
end

local function paintRow(row)
    local item = row.item
    if not item then
        return
    end
    local r, g, b = C_Item.GetItemQualityColor(item.quality)
    local border = Theme.colors.line
    if item.quest then
        border = QUEST_COLOR
    elseif opt("window.qualityBorder") then
        border = { r, g, b, 0.7 }
    end
    local fill = row:IsMouseOver() and Theme.colors.hover or { r, g, b, 0.08 }
    Shape.Paint(row.shape, math.min(Theme.radius, 5), fill, border)
    if item.locked then
        row.name:SetTextColor(0.6, 0.6, 0.6)
        row.icon:SetVertexColor(0.9, 0, 0)
    else
        row.name:SetTextColor(r, g, b)
        row.icon:SetVertexColor(1, 1, 1)
    end
end

local function showTooltip(row)
    local item = row.item
    if not item or not item.slot then
        return
    end
    if item.slotType == Enum.LootSlotType.Item then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetLootItem(item.slot)
        CursorUpdate(row)
    elseif item.slotType == Enum.LootSlotType.Currency then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetLootCurrency(item.slot)
        CursorUpdate(row)
    end
end

-- The same fields Blizzard leaves on its frame: its master loot menu reads them.
local function markSelected(row)
    local item = row.item
    local frame = _G.LootFrame
    if frame then
        frame.selectedLootFrame = row
        frame.selectedSlot = item.slot
        frame.selectedItemLink = GetLootSlotLink(item.slot)
        frame.selectedQuality = item.quality
        frame.selectedItemName = item.name
        frame.selectedTexture = item.icon
    end
    StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION")
end

local function onClick(row)
    local item = row.item
    if not item or not item.slot then
        return
    end
    if IsModifiedClick() then
        HandleModifiedItemClick(GetLootSlotLink(item.slot))
    else
        markSelected(row)
        LootSlot(item.slot)
    end
end

local function newRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row.shape = Shape.New(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", ICON_INSET, -ICON_INSET)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.quest = row:CreateTexture(nil, "OVERLAY")
    row.quest:SetAllPoints(row.icon)
    row.count = Widgets.Text(row, 12, "text")
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 1)
    row.name = Widgets.Text(row, 14, "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.Paint = paintRow
    row:SetScript("OnClick", onClick)
    row:SetScript("OnEnter", function(self)
        paintRow(self)
        showTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        paintRow(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
        ResetCursor()
    end)
    return Widgets.Track(row)
end

local function fillRow(row, item, height)
    row.item = item
    row:SetHeight(height)
    row.icon:SetSize(height - ICON_INSET * 2, height - ICON_INSET * 2)
    row.icon:SetTexture(item.icon)
    row.name:SetText(item.name)
    Widgets.SetTextSize(row.name, opt("window.textSize"))
    row.count:SetText(item.count and item.count > 1 and item.count or "")
    local mark = item.bang and _G.TEXTURE_ITEM_QUEST_BANG or item.quest and _G.TEXTURE_ITEM_QUEST_BORDER
    row.quest:SetShown(mark and true or false)
    if mark then
        row.quest:SetTexture(mark)
    end
    paintRow(row)
    row:Show()
end

--- Redraws from the current items and fits the window to them.
function Window.Draw()
    local w = Window.frame
    if not w then
        return
    end
    local items = Window.preview and samples() or Window.Read()
    local height = opt("window.rowHeight")
    local width = opt("window.width")
    for i, item in ipairs(items) do
        local row = Window.rows[i]
        if not row then
            row = newRow(w.body)
            Window.rows[i] = row
        end
        row:ClearAllPoints()
        local top = -PADDING - (i - 1) * (height + ROW_GAP)
        row:SetPoint("TOPLEFT", PADDING, top)
        row:SetPoint("TOPRIGHT", -PADDING, top)
        fillRow(row, item, height)
    end
    for i = #items + 1, #Window.rows do
        Window.rows[i]:Hide()
        Window.rows[i].item = nil
    end
    local buttons = opt("window.buttons")
    w.footer:SetShown(buttons)
    w.takeAll:SetEnabled(not Window.preview)
    local body = #items * (height + ROW_GAP) - ROW_GAP + PADDING * 2
    w:SetSize(width, HEADER + math.max(body, PADDING * 2) + (buttons and FOOTER or 0))
    w:SetScale(opt("window.scale"))
    w:Paint()
    return #items
end

local function takeAll()
    -- From the end, so taking a slot doesn't shift the ones still to take.
    for slot = GetNumLootItems(), 1, -1 do
        if GetLootSlotType(slot) ~= Enum.LootSlotType.None then
            LootSlot(slot)
        end
    end
end

local function fixed()
    return opt("window.position") == "fixed"
end

-- Leaves the first row under the cursor.
local function place()
    local w = Window.frame
    w:ClearAllPoints()
    if fixed() then
        w:SetPoint("TOPLEFT", Window.holder, "TOPLEFT")
        return
    end
    local rowHeight = opt("window.rowHeight")
    local scale = w:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local middle = PADDING + rowHeight / 2
    w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - middle, y / scale + HEADER + middle)
end

local function create()
    local w = Widgets.Window("EternityUILootWindow", _G.LOOT or L.LOOT, true)
    Window.frame = w
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w.header:SetHeight(HEADER)
    w.footer:SetHeight(FOOTER)
    w.close:SetSize(22, 22)
    w.close:SetPoint("RIGHT", -5, 0)
    w.title:SetPoint("RIGHT", w.close, "LEFT", -6, 0)
    w.title:SetJustifyH("LEFT")
    w.title:SetWordWrap(false)
    Widgets.SetTextSize(w.title, 14)

    function w.onPaint(frame)
        frame.shape.fill:SetAlpha(opt("window.opacity"))
        frame.shadow:SetShown(opt("window.shadow"))
    end

    w.takeAll = Widgets.Button(w.footer, L.TAKE_ALL, "primary", takeAll)
    w.takeAll:SetHeight(BUTTON_HEIGHT)
    w.takeAll:SetPoint("LEFT", PADDING, 0)
    w.takeAll:SetPoint("RIGHT", w.footer, "CENTER", -2, 0)
    w.history = Widgets.Button(w.footer, L.HISTORY_SHORT, "ghost", function()
        ns.History.Toggle()
    end)
    w.history:SetHeight(BUTTON_HEIGHT)
    w.history:SetPoint("LEFT", w.footer, "CENTER", 2, 0)
    w.history:SetPoint("RIGHT", -PADDING, 0)

    -- In the fixed spot, dragging moves the holder and saves it for the Mover.
    w:SetScript("OnDragStart", function(frame)
        local entry = E.Mover.Entry(KEY)
        if not fixed() then
            frame:StartMoving()
        elseif not (entry and entry.locked) then
            Window.holder:StartMoving()
        end
    end)
    w:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
        if fixed() then
            Window.holder:StopMovingOrSizing()
            Window.holder:SetUserPlaced(false)
            E.Mover.SaveFromFrame(KEY)
        end
    end)
    -- A window opened in combat can't let keys through, and it would take the movement keys:
    -- there it doesn't listen to the keyboard and Esc doesn't close it.
    w:HookScript("OnShow", function(frame)
        frame:EnableKeyboard(not InCombatLockdown())
    end)
    w:HookScript("OnHide", function()
        if Window.preview then
            Window.preview = false
            return
        end
        StaticPopup_Hide("LOOT_BIND")
        StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION")
        if Window.looting then
            Window.looting = false
            CloseLoot()
        end
    end)
    w.onPaint(w)
end

local function register()
    if E.Mover.elements[KEY] then
        return
    end
    E.Mover.Register({
        key = KEY,
        owner = addonName,
        label = L.WINDOW,
        frame = Window.holder,
        point = "TOPLEFT",
        x = 40,
        y = -220,
        scalable = false,
        openOptions = function()
            E:OpenOptions(addonName)
        end,
    })
end

-- Makes Blizzard's window listen or not.
local function take(on)
    local blizzard = _G.LootFrame
    if not blizzard or Window.taken == on then
        return
    end
    Window.taken = on
    for _, event in ipairs(BLIZZARD_EVENTS) do
        if on then
            blizzard:UnregisterEvent(event)
        else
            blizzard:RegisterEvent(event)
        end
    end
    if on and blizzard:IsShown() then
        blizzard:Hide()
    end
end

--- True while this window handles the loot.
---@return boolean
function Window.Active()
    return Window.taken == true
end

--- Brings everything in line with the options.
function Window.Apply()
    local replace = opt("window.replace")
    take(replace)
    if replace and fixed() then
        register()
    else
        E.Mover.Unregister(KEY)
    end
    if Window.frame then
        if replace and Window.frame:IsShown() then
            Window.Draw()
            place()
        elseif not replace then
            Window.frame:Hide()
        end
    end
end

function Window.Start()
    if not Window.holder then
        local holder = CreateFrame("Frame", "EternityUILootAnchor", UIParent)
        holder:SetSize(HOLDER_WIDTH, HOLDER_HEIGHT)
        holder:SetMovable(true)
        holder:SetClampedToScreen(true)
        Window.holder = holder
    end
    if not Window.frame then
        create()
    end
    Window.Apply()
end

function Window.Stop()
    if Window.frame then
        Window.frame:Hide()
    end
    take(false)
    E.Mover.Unregister(KEY)
end

local function play(name)
    local kit = SOUNDKIT[name]
    if kit then
        PlaySound(kit)
    end
end

local function show(isAutoLoot, fromItem)
    local w = Window.frame
    Window.preview = false
    local count = Window.Draw()
    if count == 0 then
        -- Auto loot may have emptied it already: that is not an empty corpse.
        if not isAutoLoot then
            play("LOOT_WINDOW_OPEN_EMPTY")
        end
        Window.looting = false
        CloseLoot()
        return
    end
    w.title:SetText(Recorder.SourceOf(1) or _G.LOOT or L.LOOT)
    place()
    w:Show()
    w:Raise()
    if fromItem then
        play("UI_CONTAINER_ITEM_OPEN")
    elseif IsFishingLoot() then
        play("FISHING_REEL_IN")
    end
end

--- LOOT_OPENED.
---@param isAutoLoot boolean?
---@param fromItem boolean?
function Window.Open(isAutoLoot, fromItem)
    if not Window.taken then
        return
    end
    Window.looting = true
    show(isAutoLoot, fromItem)
end

--- LOOT_SLOT_CLEARED and LOOT_SLOT_CHANGED.
function Window.Update()
    local w = Window.frame
    if not (w and w:IsShown() and Window.looting) then
        return
    end
    if Window.Draw() == 0 then
        CloseLoot()
    end
end

--- LOOT_CLOSED.
function Window.Close()
    Window.looting = false
    if Window.frame and not Window.preview then
        Window.frame:Hide()
    end
end

--- Shows sample rows, to judge the options. Ends when the window closes.
function Window.Preview()
    local w = Window.frame
    if not w or Window.looting then
        return
    end
    Window.preview = true
    Window.Draw()
    w.title:SetText(_G.LOOT or L.LOOT)
    place()
    w:Show()
end
