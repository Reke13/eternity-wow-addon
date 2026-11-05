-- /et diag and /et pixel: what the real client answers to the questions the base depends on.
-- Only reads. A secret answer is reported as such, never compared.
---@type string, EternityUINamespace
local _, ns = ...
local L = ns.L
local Pixel = ns.Pixel
local Secret = ns.Secret

---@class EternityDiagnostics
local Diagnostics = {}
ns.Diagnostics = Diagnostics

local function yesNo(value)
    return value and L.YES or L.NO
end

-- True if an XML template exists on this client.
local function hasTemplate(name)
    if not C_XMLUtil then
        return false
    end
    local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
    return ok and info ~= nil
end

-- Compresses and restores a short text with the client's encoder.
local function encodingRoundTrip()
    if not C_EncodingUtil then
        return false
    end
    local text = "Eternity"
    local method = Enum.CompressionMethod.Deflate
    local ok, packed = pcall(C_EncodingUtil.CompressString, text, method)
    if not ok then
        return false
    end
    local restored
    ok, restored = pcall(C_EncodingUtil.DecompressString, packed, method)
    return ok and restored == text
end

--- The diagnostic lines, as label/value pairs.
---@return string[][]
function Diagnostics.Collect()
    local version, build, _, interface = GetBuildInfo()
    local physicalWidth, physicalHeight = GetPhysicalScreenSize()
    local stats = ns.store.raw.stats
    return {
        { "Build", string.format("%s.%s · Interface %s", version, build, tostring(interface)) },
        { "WOW_PROJECT_ID", string.format("%s (CAMELOT %s)", tostring(WOW_PROJECT_ID), tostring(WOW_PROJECT_CAMELOT)) },
        { "Logins / reloads", string.format("%d / %d", stats.logins, stats.reloads) },
        { "GUID known", yesNo(ns.store.character) },
        { "Combat lockdown", yesNo(InCombatLockdown()) },
        { "Auras secret", yesNo(Secret.AurasRestricted()) },
        { "Player health secret", yesNo(Secret.Is(UnitHealth("player"))) },
        { "Screen", string.format("%dx%d", physicalWidth, physicalHeight) },
        {
            "Scale",
            string.format("UIParent %.4f · perfect %.4f", UIParent:GetEffectiveScale(), Pixel.PerfectScale()),
        },
        { "1 pixel in UIParent", string.format("%.4f units", Pixel.Size(UIParent)) },
        { "Compression round trip", yesNo(encodingRoundTrip()) },
        { "CustomAuraContainerTemplate", yesNo(hasTemplate("CustomAuraContainerTemplate")) },
    }
end

function Diagnostics.Print()
    ns.Print(L.DIAG_TITLE)
    for _, line in ipairs(Diagnostics.Collect()) do
        print(string.format("  %s: |cffffffff%s|r", line[1], line[2]))
    end
end

local test

local function buildPixelTest()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(320, 96)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    local fill = frame:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.08, 0.07, 0.11, 0.95)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -14)
    title:SetText(L.PIXEL_TITLE)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
    hint:SetWidth(290)
    hint:SetText(L.PIXEL_HINT)

    local size = Pixel.Size(frame)
    local function line(a, b, width, height)
        local edge = frame:CreateTexture(nil, "ARTWORK")
        edge:SetColorTexture(0.55, 0.36, 0.96, 1)
        edge:SetSnapToPixelGrid(false)
        edge:SetTexelSnappingBias(0)
        edge:SetPoint(a)
        edge:SetPoint(b)
        if width then
            edge:SetWidth(width)
        else
            edge:SetHeight(height)
        end
    end
    line("TOPLEFT", "TOPRIGHT", nil, size)
    line("BOTTOMLEFT", "BOTTOMRIGHT", nil, size)
    line("TOPLEFT", "BOTTOMLEFT", size, nil)
    line("TOPRIGHT", "BOTTOMRIGHT", size, nil)
    return frame
end

--- Shows or hides the 1 pixel test.
function Diagnostics.TogglePixelTest()
    test = test or buildPixelTest()
    test:SetShown(not test:IsShown())
end
