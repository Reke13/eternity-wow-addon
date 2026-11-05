-- Unexplored areas: the game only gives addons the areas the player has explored
-- (C_MapExplorationInfo.GetExploredMapTextures), so the rest are drawn from src/Data/Overlays.lua
-- (generated from the client's DB2 tables by Tools/Gen-MapOverlays.ps1), tinted with the
-- options' color under Blizzard's explored ones.
--
-- No data provider and no pin: Blizzard runs those through secureexecuterange and an error there
-- would break the map. It's a plain frame over the map's canvas (whose units are the art's
-- pixels), refreshed after OnMapChanged, on MAP_EXPLORATION_UPDATED and on show. Only the base
-- layer is drawn (Forever's zone maps have one); with another layer showing it hides itself.

---@type string, EternityUIMapNamespace
local _, ns = ...
local Core = ns.Core
local opt = Core.Opt

---@class EternityUIMapUnexplored
---@field hooked boolean?
---@field frame table? our frame over the canvas
---@field textures table[] every texture created (reused)
---@field used integer textures drawn now
---@field layer integer? the canvas layer seen on the last scale change
---@field events table?
local Unexplored = { textures = {}, used = 0 }
ns.Unexplored = Unexplored

function Unexplored:Wanted()
    return Core.running == true and opt("unexplored.enabled") == true
end

--- Key of an overlay by size and offset (how explored and unexplored ones are matched).
function Unexplored.Key(width, height, x, y)
    return width .. ":" .. height .. ":" .. x .. ":" .. y
end

--- The keys of the areas explored on this map (empty when the client says nothing or secret).
function Unexplored.Explored(mapID)
    local keys = {}
    local api = C_MapExplorationInfo
    if not (api and api.GetExploredMapTextures) then
        return keys
    end
    local ok, list = pcall(api.GetExploredMapTextures, mapID)
    if not ok or type(list) ~= "table" or Core.Secret(list) then
        return keys
    end
    for _, info in ipairs(list) do
        local w, h, x, y = info.textureWidth, info.textureHeight, info.offsetX, info.offsetY
        if type(w) == "number" and not (Core.Secret(w) or Core.Secret(x)) then
            keys[Unexplored.Key(w, h, x, y)] = true
        end
    end
    return keys
end

--- The overlays of this map nobody explored yet: a list of { w, h, x, y, fileIDs... }.
function Unexplored.Missing(mapID)
    local data = ns.Overlays
    local art = data and data.maps[mapID]
    local list = art and data.art[art]
    if not list then
        return {}
    end
    local explored = Unexplored.Explored(mapID)
    local missing = {}
    for _, overlay in ipairs(list) do
        if not explored[Unexplored.Key(overlay[1], overlay[2], overlay[3], overlay[4])] then
            missing[#missing + 1] = overlay
        end
    end
    return missing
end

-- Drawing ---------------------------------------------------------------------------------------

--- The smallest power of two (from 16) that holds `size`: the file size of a partial tile.
local function fileSize(size)
    local file = 16
    while file < size do
        file = file * 2
    end
    return file
end

function Unexplored:CreateFrame(map)
    if self.frame then
        return self.frame
    end
    local canvas = map:GetCanvas()
    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetAllPoints(canvas)
    frame:EnableMouse(false)
    local ok, level = pcall(function()
        return map:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION")
    end)
    frame:SetFrameLevel(ok and type(level) == "number" and level or canvas:GetFrameLevel() + 1)
    self.frame = frame
    return frame
end

function Unexplored:Texture(map)
    self.used = self.used + 1
    local texture = self.textures[self.used]
    if not texture then
        texture = self.frame:CreateTexture(nil, "ARTWORK", nil, -1)
        self.textures[self.used] = texture
        -- Zone maps with a mask (rare) clip their art: clip ours the same way.
        if map.GetMaskTexture and map:GetMaskTexture() then
            pcall(map.AddMaskableTexture, map, texture)
        end
    end
    return texture
end

function Unexplored:Clear()
    for i = 1, #self.textures do
        self.textures[i]:Hide()
    end
    self.used = 0
end

--- Draws one overlay's tiles (row by row, `tile` px each, the last row and column partial).
function Unexplored:DrawOverlay(map, overlay, tile, color)
    local width, height, offsetX, offsetY = overlay[1], overlay[2], overlay[3], overlay[4]
    local columns, rows = math.ceil(width / tile), math.ceil(height / tile)
    for row = 1, rows do
        local pixelH = row < rows and tile or (height - tile * (rows - 1))
        local fileH = row < rows and tile or fileSize(pixelH)
        for column = 1, columns do
            local fileID = overlay[4 + (row - 1) * columns + column]
            if fileID then
                local pixelW = column < columns and tile or (width - tile * (columns - 1))
                local fileW = column < columns and tile or fileSize(pixelW)
                local texture = self:Texture(map)
                texture:SetTexture(fileID, nil, nil, "TRILINEAR")
                texture:SetSize(pixelW, pixelH)
                texture:SetTexCoord(0, pixelW / fileW, 0, pixelH / fileH)
                texture:ClearAllPoints()
                texture:SetPoint(
                    "TOPLEFT",
                    self.frame,
                    "TOPLEFT",
                    offsetX + tile * (column - 1),
                    -(offsetY + tile * (row - 1))
                )
                texture:SetDesaturated(true)
                texture:SetVertexColor(color[1], color[2], color[3], color[4])
                texture:Show()
            end
        end
    end
end

--- Draws the unexplored areas of the map shown now (or nothing). Safe to call any time.
function Unexplored:Refresh()
    local map = Core.Map()
    if not (map and self.frame) then
        return
    end
    self:Clear()
    if not (self:Wanted() and map:IsShown()) then
        self.frame:Hide()
        return
    end
    local container = map.GetCanvasContainer and map:GetCanvasContainer()
    local layer = container and container.GetCurrentLayerIndex and container:GetCurrentLayerIndex() or 1
    local mapID = map:GetMapID()
    if layer ~= 1 or not mapID then
        self.frame:Hide()
        return
    end
    local tile = ns.Overlays and ns.Overlays.tile or 256
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    if ok and type(layers) == "table" and layers[1] and type(layers[1].tileWidth) == "number" then
        tile = layers[1].tileWidth
    end
    local color = Core.Hex(opt("colors.unexplored"))
    for _, overlay in ipairs(Unexplored.Missing(mapID)) do
        self:DrawOverlay(map, overlay, tile, color)
    end
    self.frame:Show()
end

-- Life cycle ------------------------------------------------------------------------------------

function Unexplored:InstallHooks(map)
    if self.hooked then
        return
    end
    self.hooked = true
    local refresh = function()
        if self.frame and (self:Wanted() or self.used > 0) then
            self:Refresh()
        end
    end
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", refresh)
    end
    if map.OnCanvasScaleChanged then
        hooksecurefunc(map, "OnCanvasScaleChanged", function()
            -- Only a change of layer matters (it's called on every zoom step).
            local container = map:GetCanvasContainer()
            local layer = container and container:GetCurrentLayerIndex() or 1
            if layer ~= self.layer then
                self.layer = layer
                refresh()
            end
        end)
    end
    map:HookScript("OnShow", refresh)
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", refresh)
end

--- Starts or stops drawing from the options. Safe to call again.
function Unexplored:Apply()
    local map = Core.Map()
    if not (map and map.GetCanvas) then
        return
    end
    self:InstallHooks(map)
    if self:Wanted() then
        self:CreateFrame(map)
        pcall(self.events.RegisterEvent, self.events, "MAP_EXPLORATION_UPDATED")
    else
        self.events:UnregisterAllEvents()
    end
    self:Refresh()
end
