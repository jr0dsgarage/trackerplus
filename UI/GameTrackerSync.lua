---@diagnostic disable: undefined-global
local _, addon = ...

local floor = math.floor

------------------------------------------------------------------------------
-- Game tracker geometry adoption
--
-- Until the player positions/sizes TrackerPlus themselves, it places itself
-- exactly over the game's own objective tracker so it drops in as a direct
-- replacement. The game's Edit Mode moves and sizes that very frame, so reading
-- the live frame is also how we follow Edit Mode changes -- there's no need to
-- parse Edit Mode layout data ourselves.
------------------------------------------------------------------------------

-- Candidate names for the game's own tracker, newest naming first.
local BLIZZARD_TRACKER_FRAMES = {
    "ObjectiveTrackerFrame", -- modern tracker; also the Edit Mode "ObjectiveTracker" system frame
    "WatchFrame",            -- Cata/MoP-era tracker
    "QuestWatchFrame",       -- vanilla/TBC-era tracker
}

-- Below this a tracker is treated as collapsed/not laid out rather than a real size.
local MIN_ADOPTABLE_SIZE = 50

function addon:GetBlizzardTrackerFrame()
    for i = 1, #BLIZZARD_TRACKER_FRAMES do
        local name = BLIZZARD_TRACKER_FRAMES[i]
        local frame = _G and _G[name]
        if frame and frame.GetLeft and frame.GetWidth then
            return frame, name
        end
    end
    return nil
end

-- Returns { left, top, width, height, source } in absolute screen pixels, or nil
-- when the game's tracker is missing or not laid out yet.
function addon:GetBlizzardTrackerGeometry()
    local frame, name = self:GetBlizzardTrackerFrame()
    if not frame then return nil end

    local ok, geo = pcall(function()
        local scale = frame:GetEffectiveScale() or 1
        local left, top = frame:GetLeft(), frame:GetTop()
        local width, height = frame:GetWidth(), frame:GetHeight()
        if not (left and top and width and height) then return nil end

        -- A collapsed or empty tracker can report a near-zero height. When the
        -- player has moved it out of its default position the game stores the
        -- height they chose in Edit Mode on the frame, so prefer that.
        if height < MIN_ADOPTABLE_SIZE then
            local editModeHeight = tonumber(frame.editModeHeight)
            if editModeHeight and editModeHeight >= MIN_ADOPTABLE_SIZE then
                height = editModeHeight
            end
        end

        return {
            left = left * scale,
            top = top * scale,
            width = width * scale,
            height = height * scale,
            source = name,
        }
    end)

    if not ok or not geo then return nil end
    if geo.width < MIN_ADOPTABLE_SIZE or geo.height < MIN_ADOPTABLE_SIZE then return nil end
    return geo
end

-- Place and size our tracker exactly over the game's tracker.
-- Returns true when geometry was adopted.
function addon:SyncWithBlizzardTracker()
    if not addon.trackerFrame then return false end

    local db = self.db
    if not db.matchBlizzardTracker then return false end
    if db.minimized then return false end

    local geo = self:GetBlizzardTrackerGeometry()
    if not geo then return false end

    -- SetSize and SetPoint offsets are expressed in the frame's own coordinate
    -- space, so convert absolute pixels through the scale our frame ends up at.
    local uiScale = (UIParent and UIParent:GetEffectiveScale()) or 1
    local dstScale = uiScale * (db.frameScale or 1)
    if dstScale <= 0 then return false end

    db.frameWidth = floor((geo.width / dstScale) + 0.5)
    db.frameHeight = floor((geo.height / dstScale) + 0.5)

    -- Apply the adopted size directly rather than going through
    -- UpdateTrackerAppearance: this also runs during CreateTrackerFrame, before the
    -- background/border/content children exist, and that function would create the
    -- border frame early and have it duplicated moments later. Dropping the cached
    -- appearance state makes the next appearance pass re-apply everything cleanly.
    addon.trackerFrame:SetSize(db.frameWidth, db.frameHeight)
    self:UpdateContentWidth()
    self._appearanceState = nil

    addon.trackerFrame:ClearAllPoints()
    addon.trackerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", geo.left / dstScale, geo.top / dstScale)

    if addon.LogAt then
        addon:LogAt("info", "Matched game tracker (%s): %dx%d", tostring(geo.source), db.frameWidth, db.frameHeight)
    end

    -- Size changed, so section anchors need recomputing on the next paint.
    self._layoutDirty = true
    if self.RequestUpdate then
        self:RequestUpdate()
    end

    if self.UpdateSettingWidgets then
        self:UpdateSettingWidgets()
    end

    return true
end

-- Called when the player drags or resizes the tracker: they've taken manual
-- control, so stop mirroring the game's tracker from here on.
function addon:ClaimManualGeometry()
    if self.db.matchBlizzardTracker then
        self.db.matchBlizzardTracker = false
        if self.UpdateSettingWidgets then
            self:UpdateSettingWidgets()
        end
    end
end
