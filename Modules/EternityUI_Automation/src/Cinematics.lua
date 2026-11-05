-- Cinematics and clutter: skip cinematics (all or the ones already seen) and movies, hide the
-- talking head and take a screenshot on achievements.

---@type string, EternityUIAutomationNamespace
local _, ns = ...
local Core, L = ns.Core, ns.L

local Cinematics = {}
Core.Cinematics = Cinematics

local DB_VERSION = 1

--- EternityUIAutomationDB, account-wide: the cinematics already seen, by place.
function Cinematics.DB()
    local db = _G.EternityUIAutomationDB
    if type(db) ~= "table" or db.version ~= DB_VERSION or type(db.cinematics) ~= "table" then
        db = { version = DB_VERSION, cinematics = {} }
        _G.EternityUIAutomationDB = db
    end
    return db
end

--- Where a cinematic plays: the map and subzone, so each one is remembered on its own.
function Cinematics.PlaceKey()
    local mapID = C_Map.GetBestMapForUnit("player") or 0
    return mapID .. ":" .. (GetSubZoneText() or "")
end

--- Whether to skip a cinematic with the given mode, and remembers it as seen. Pure apart from
--- the saved list.
function Cinematics.ShouldSkip(mode, key)
    local seen = Cinematics.DB().cinematics
    local already = seen[key] == true
    seen[key] = true
    return mode == "all" or (mode == "seen" and already)
end

Core.Add({
    id = "skipCinematics",
    events = { "CINEMATIC_START" },
    Enabled = function()
        return Core.On("cinematics.skipCinematics")
    end,
    OnEvent = function(_, _, canBeCancelled)
        if not Cinematics.ShouldSkip(Core.Opt("cinematics.skipCinematics"), Cinematics.PlaceKey()) then
            return
        end
        -- Blizzard opens its frame on the same event: cancel on the next frame. A vehicle scene
        -- that can't be cancelled is left alone (Blizzard's own cancel would exit the vehicle).
        Core.After(0, function()
            if canBeCancelled then
                StopCinematic()
            elseif CanCancelScene() then
                CancelScene()
            else
                return
            end
            Core.Report(L.CINEMATIC_SKIPPED)
        end)
    end,
})

local movies = Core.Add({
    id = "skipMovies",
    Enabled = function()
        return Core.On("cinematics.skipMovies")
    end,
})

function movies:OnApply(on)
    local frame = _G.MovieFrame
    if not on or self.hooked or not frame or not frame.PlayMovie or not frame.FinishMovie then
        return
    end
    self.hooked = true
    hooksecurefunc(frame, "PlayMovie", function(movieFrame)
        -- FinishMovie brings the UI back, which can't happen in combat.
        if Core.Active(self) and movieFrame.movieID and not InCombatLockdown() then
            movieFrame:FinishMovie()
            Core.Report(L.MOVIE_SKIPPED)
        end
    end)
end

local talkingHead = Core.Add({
    id = "hideTalkingHead",
    -- In some clients the talking head loads on demand.
    events = { "ADDON_LOADED" },
    Enabled = function()
        return Core.On("cinematics.hideTalkingHead")
    end,
})

function talkingHead:OnApply(on)
    local frame = _G.TalkingHeadFrame
    if not on or self.hooked or not frame or not frame.PlayCurrent then
        return
    end
    self.hooked = true
    hooksecurefunc(frame, "PlayCurrent", function(head)
        if Core.Active(self) then
            if head.CloseImmediately then
                head:CloseImmediately()
            else
                head:Hide()
            end
        end
    end)
end

function talkingHead:OnEvent(_, name)
    if name == "Blizzard_TalkingHeadUI" then
        self:OnApply(self.on)
    end
end

Core.Add({
    id = "screenshotAchievement",
    events = { "ACHIEVEMENT_EARNED" },
    Enabled = function()
        return Core.On("cinematics.screenshotAchievement")
    end,
    OnEvent = function(_, _, _, alreadyEarned)
        if not alreadyEarned then
            -- Leaves time for the achievement toast to show.
            Core.After(1, Screenshot)
        end
    end,
})
