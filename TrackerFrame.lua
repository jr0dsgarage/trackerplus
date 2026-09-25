---@diagnostic disable: undefined-global
local addonName, addon = ...
local format = string.format
local max, min, floor = math.max, math.min, math.floor

-- Tracker frame UI with scrollable content (no visible scrollbar)
local trackerFrame = nil
local scrollFrame = nil
local contentFrame = nil
local completedQuestFrame = nil

local SHADOW_FADE_DISTANCE = 100
local SHADOW_SEAM_OFFSET = 1
local SHADOW_BOTTOM_EXTRA_DROP = 3

-- Gap between the top edge of the tracker and the main header background, so the
-- header art doesn't sit flush against the frame's top border.
local HEADER_TOP_INSET = 2
-- Vertical space reserved for the title bar (inset + header art + 1px seam).
local HEADER_H = HEADER_TOP_INSET + 25


-- Keep the scroll gradients spanning the full tracker width while tracking the
-- scrollable area vertically.
--
-- The gradients deliberately do not anchor to the scroll frame horizontally: the
-- scroll frame's own inset from the tracker edges changes depending on which
-- pinned sections are visible (zero directly under the header, otherwise inset by
-- the section side padding), which made the gradients change width with it. So we
-- anchor them to the tracker for width and carry over only the scroll frame's
-- vertical edges here.
local function UpdateScrollShadowAnchors(owner)
    if not (trackerFrame and scrollFrame and owner.scrollShadowTop and owner.scrollShadowBottom) then
        return
    end

    local trackerTop, trackerBottom = trackerFrame:GetTop(), trackerFrame:GetBottom()
    local scrollTop, scrollBottom = scrollFrame:GetTop(), scrollFrame:GetBottom()
    if not (trackerTop and trackerBottom and scrollTop and scrollBottom) then
        return
    end

    -- Both frames share the tracker's scale, so these deltas are usable as offsets.
    local topOffset = (scrollTop - trackerTop) + SHADOW_SEAM_OFFSET
    local bottomOffset = (scrollBottom - trackerBottom) + SHADOW_SEAM_OFFSET - SHADOW_BOTTOM_EXTRA_DROP

    local sig = format("%.1f|%.1f", topOffset, bottomOffset)
    if owner._scrollShadowAnchorSig == sig then return end
    owner._scrollShadowAnchorSig = sig

    owner.scrollShadowTop:ClearAllPoints()
    owner.scrollShadowTop:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 0, topOffset)
    owner.scrollShadowTop:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", 0, topOffset)

    owner.scrollShadowBottom:ClearAllPoints()
    owner.scrollShadowBottom:SetPoint("BOTTOMLEFT", trackerFrame, "BOTTOMLEFT", 0, bottomOffset)
    owner.scrollShadowBottom:SetPoint("BOTTOMRIGHT", trackerFrame, "BOTTOMRIGHT", 0, bottomOffset)
end

-- Update scroll shadow opacity based on scroll position.
-- Uses SetAlpha instead of SetHeight so no tainted geometry values enter
-- Blizzard's LayoutFrame comparisons (which would cause taint errors).
function addon:UpdateScrollShadows()
    if not scrollFrame or not self.scrollShadowTop or not self.scrollShadowBottom then return end

    -- Nothing to shade when the scroll area isn't on screen. A hidden scroll frame
    -- still reports its last scroll range, so without this the gradients would be
    -- driven visible again over the minimized 34x34 button box.
    if (self.db and self.db.minimized) or not scrollFrame:IsShown() then
        self.scrollShadowTop:SetAlpha(0)
        self.scrollShadowBottom:SetAlpha(0)
        return
    end

    UpdateScrollShadowAnchors(self)

    local current = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if maxScroll <= 0 then
        self.scrollShadowTop:SetAlpha(0)
        self.scrollShadowBottom:SetAlpha(0)
        return
    end
    self.scrollShadowTop:SetAlpha(min(1, current / SHADOW_FADE_DISTANCE))
    self.scrollShadowBottom:SetAlpha(min(1, (maxScroll - current) / SHADOW_FADE_DISTANCE))
end

------------------------------------------------------------------------------
-- FollowTheArrow availability
--
-- The header's arrow toggle only makes sense when that addon is actually there,
-- so it stays hidden otherwise rather than offering a control that does nothing.
------------------------------------------------------------------------------

local FTA_ADDON_NAME = "FollowTheArrow"

function addon:IsFollowTheArrowAvailable()
    -- Deliberately keyed on "loaded" rather than merely installed: a disabled
    -- addon shouldn't get a toggle either.
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded then
        local ok, loaded = pcall(isLoaded, FTA_ADDON_NAME)
        if ok and loaded then
            return true
        end
    end

    -- Fallback in case it ships under a different folder name: the globals
    -- FollowTheArrow exposes once it has loaded.
    return (FollowTheArrowAPI ~= nil) or (FTACharDB ~= nil)
end

function addon:UpdateFTAToggleVisibility()
    if not (trackerFrame and trackerFrame.ftaToggleBtn) then return end

    if self.db.minimized or not self:IsFollowTheArrowAvailable() then
        trackerFrame.ftaToggleBtn:Hide()
        return
    end

    trackerFrame.ftaToggleBtn:Show()
    if trackerFrame.ftaToggleBtn.UpdateColor then
        trackerFrame.ftaToggleBtn.UpdateColor()
    end
end

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
    if not trackerFrame then return false end

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
    trackerFrame:SetSize(db.frameWidth, db.frameHeight)
    self:UpdateContentWidth()
    self._appearanceState = nil

    trackerFrame:ClearAllPoints()
    trackerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", geo.left / dstScale, geo.top / dstScale)

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

-- Create the main tracker frame
function addon:CreateTrackerFrame()
    if trackerFrame then
        return trackerFrame
    end
    
    -- Main frame
    trackerFrame = CreateFrame("Frame", "TrackerPlusFrame", UIParent)
    trackerFrame:SetSize(self.db.frameWidth, self.db.frameHeight)
    -- Sit in the same strata as the frame we replace: Blizzard's ObjectiveTrackerFrame
    -- is declared frameStrata="LOW". We keep that tracker alive but invisible (alpha 0)
    -- so the sections that borrow its frames keep updating, and an alive frame still
    -- hit-tests. At BACKGROUND -- the lowest strata there is -- that invisible tracker
    -- and all of its children sat above this entire window, swallowing clicks aimed at
    -- the header buttons. Strata outranks frame level, so no amount of levelling fixed
    -- it. LOW still keeps the tracker behind normal UI panels, which live at MEDIUM and
    -- above.
    trackerFrame:SetFrameStrata("LOW")
    -- Within that strata, sit above Blizzard's suppressed tracker and its children,
    -- which use low default levels. Everything else here derives its level from
    -- GetFrameLevel(), so the relative layering inside the tracker is unchanged.
    trackerFrame:SetFrameLevel(10)
    trackerFrame:SetClampedToScreen(true)
    
    -- Make draggable & resizable (Must be set before SetUserPlaced)
    trackerFrame:SetMovable(true)
    trackerFrame:SetResizable(true)
    
    -- Ensure position is managed by addon, not layout cache
    trackerFrame:SetUserPlaced(false)
    
    -- Set position
    -- Function to restore position
    addon.RestorePosition = function()
        if not trackerFrame then return end

        -- Until the player positions the tracker themselves, sit exactly on top of
        -- the game's own tracker so this is a drop-in replacement on first load.
        if addon:SyncWithBlizzardTracker() then
            return
        end

        local pos = addon.db.framePosition
        if pos and pos.point and pos.x and pos.y then
             trackerFrame:ClearAllPoints()
             -- Use saved relativePoint if available, otherwise fallback to point (legacy support)
             local relativePoint = pos.relativePoint or pos.point
             trackerFrame:SetPoint(pos.point, UIParent, relativePoint, pos.x, pos.y)
        else
             trackerFrame:ClearAllPoints()
             trackerFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -200)
        end
    end
    addon.RestorePosition()
    
    -- Background
    trackerFrame.bg = trackerFrame:CreateTexture(nil, "BACKGROUND")
    trackerFrame.bg:SetAllPoints()
    trackerFrame.bg:SetColorTexture(
        self.db.backgroundColor.r,
        self.db.backgroundColor.g,
        self.db.backgroundColor.b,
        self.db.backgroundColor.a
    )
    
    -- Border (optional)
    if self.db.borderEnabled then
        trackerFrame.border = CreateFrame("Frame", nil, trackerFrame, "BackdropTemplate")
        trackerFrame.border:SetAllPoints()
        trackerFrame.border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = self.db.borderSize,
        })
        trackerFrame.border:SetBackdropBorderColor(
            self.db.borderColor.r,
            self.db.borderColor.g,
            self.db.borderColor.b,
            self.db.borderColor.a
        )
    end
    
    -- Make draggable & resizable
    trackerFrame:EnableMouse(true)
    
    -- Dragging
    trackerFrame:RegisterForDrag("LeftButton")
    trackerFrame:SetScript("OnDragStart", function(self)
        if not addon.db.locked then
            self:StartMoving()
        end
    end)
    trackerFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position including relativePoint
        local point, _, relativePoint, x, y = self:GetPoint()
        addon.db.framePosition = {point = point, relativePoint = relativePoint, x = x, y = y}
        addon:ClaimManualGeometry()
    end)
    
    -- Resizing Handles (Triangles)
    -- Bottom Right
    trackerFrame.resizeBR = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.resizeBR:SetSize(16, 16)
    trackerFrame.resizeBR:SetPoint("BOTTOMRIGHT")
    trackerFrame.resizeBR:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    trackerFrame.resizeBR:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    trackerFrame.resizeBR:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    trackerFrame.resizeBR:SetScript("OnMouseDown", function()
        if not addon.db.locked then
            trackerFrame:StartSizing("BOTTOMRIGHT")
        end
    end)
    trackerFrame.resizeBR:SetScript("OnMouseUp", function()
        trackerFrame:StopMovingOrSizing()
        addon.db.frameWidth = trackerFrame:GetWidth()
        addon.db.frameHeight = trackerFrame:GetHeight()
        addon:ClaimManualGeometry()
        -- Update content width
        addon:UpdateContentWidth()
        addon:RequestUpdate()
        if addon.UpdateSettingWidgets then addon:UpdateSettingWidgets() end
    end)

    -- Bottom Left
    trackerFrame.resizeBL = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.resizeBL:SetSize(16, 16)
    trackerFrame.resizeBL:SetPoint("BOTTOMLEFT")
    trackerFrame.resizeBL:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    trackerFrame.resizeBL:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    trackerFrame.resizeBL:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    trackerFrame.resizeBL:GetNormalTexture():SetTexCoord(1, 0, 0, 1) -- Flip horizontally
    trackerFrame.resizeBL:GetHighlightTexture():SetTexCoord(1, 0, 0, 1)
    trackerFrame.resizeBL:GetPushedTexture():SetTexCoord(1, 0, 0, 1)
    trackerFrame.resizeBL:SetScript("OnMouseDown", function()
        if not addon.db.locked then
            trackerFrame:StartSizing("BOTTOMLEFT")
        end
    end)
    trackerFrame.resizeBL:SetScript("OnMouseUp", function()
        trackerFrame:StopMovingOrSizing()
        addon.db.frameWidth = trackerFrame:GetWidth()
        addon.db.frameHeight = trackerFrame:GetHeight()
        addon:ClaimManualGeometry()
        addon:UpdateContentWidth()
        addon:RequestUpdate()
        if addon.UpdateSettingWidgets then addon:UpdateSettingWidgets() end
    end)
    
    -- Mouse wheel scrolling
    trackerFrame:EnableMouseWheel(true)
    trackerFrame:SetScript("OnMouseWheel", function(self, delta)
        if scrollFrame then
            local current = scrollFrame:GetVerticalScroll()
            local maxScroll = scrollFrame:GetVerticalScrollRange()
            local newScroll = max(0, min(maxScroll, current - (delta * 20)))
            scrollFrame:SetVerticalScroll(newScroll)
            addon:UpdateScrollShadows()
        end
    end)
    
    -- Scenario Frame (Top-pinned, outside scroll frame, anchored dynamically by layout)
    local scenarioFrame = CreateFrame("Frame", nil, trackerFrame)
    scenarioFrame:SetFrameLevel((trackerFrame:GetFrameLevel() or 1) + 1)
    scenarioFrame:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 5, -HEADER_H)
    scenarioFrame:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", -5, -HEADER_H)
    scenarioFrame:SetHeight(1) -- Dynamic, set by renderer + layout
    self.scenarioFrame = scenarioFrame

    -- Active Quest Frame (Super-tracked quest, sits between Scenario and auto-quest popups)
    --
    -- The placeholder horizontal anchors here (and on the two sections below) are not
    -- cosmetic: UpdateLayoutAnchors runs *after* the section renderers, so a section
    -- carrying no anchors at all has width 0 the first time it is rendered. Everything
    -- RenderTrackableItem measures is derived from its parent's width, and a font
    -- string with no room reports a string height of 0 -- which puts the first
    -- objective line on top of the quest title. Because painting only happens when the
    -- collected data version changes, that bad first pass then stays on screen until
    -- the quest's data next changes. UpdateLayoutAnchors replaces these anchors in the
    -- same render pass, so they only ever supply a sane width to measure against.
    local activeQuestFrame = CreateFrame("Frame", nil, trackerFrame)
    activeQuestFrame:SetFrameLevel((trackerFrame:GetFrameLevel() or 1) + 1)
    activeQuestFrame:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 5, -HEADER_H)
    activeQuestFrame:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", -5, -HEADER_H)
    activeQuestFrame:SetHeight(1) -- Dynamic, set by renderer + layout
    activeQuestFrame:Hide()
    self.activeQuestFrame = activeQuestFrame

    -- FTA Frame (Follow the Arrow guide, pinned between Active Quest and Campaign)
    local ftaFrame = CreateFrame("Frame", nil, trackerFrame)
    ftaFrame:SetFrameLevel((trackerFrame:GetFrameLevel() or 1) + 1)
    ftaFrame:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 5, -HEADER_H)
    ftaFrame:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", -5, -HEADER_H)
    ftaFrame:SetHeight(1)
    ftaFrame:Hide()
    self.ftaFrame = ftaFrame

    -- Campaign Frame (Pinned below Active Quest when campaign quests are present)
    local campaignFrame = CreateFrame("Frame", nil, trackerFrame)
    campaignFrame:SetFrameLevel((trackerFrame:GetFrameLevel() or 1) + 1)
    campaignFrame:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 5, -HEADER_H)
    campaignFrame:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", -5, -HEADER_H)
    campaignFrame:SetHeight(1)
    campaignFrame:Hide()
    self.campaignFrame = campaignFrame

    -- Quest Timer Frame ("Quest Timer: MM:SS" rows, last pinned section so it sits
    -- directly above the quest list). Filled by RenderQuestTimers.lua.
    local questTimerFrame = CreateFrame("Frame", nil, trackerFrame)
    questTimerFrame:SetFrameLevel((trackerFrame:GetFrameLevel() or 1) + 1)
    questTimerFrame:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 5, -HEADER_H)
    questTimerFrame:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", -5, -HEADER_H)
    questTimerFrame:SetHeight(1)
    questTimerFrame:Hide()
    self.questTimerFrame = questTimerFrame

    -- Auto Quest Frame (Below scenario/active-quest if visible, outside scroll frame)
    local autoQuestFrame = CreateFrame("Frame", nil, trackerFrame)
    autoQuestFrame:SetPoint("TOPLEFT", scenarioFrame, "BOTTOMLEFT", 0, 0)
    autoQuestFrame:SetPoint("TOPRIGHT", scenarioFrame, "BOTTOMRIGHT", 0, 0)
    autoQuestFrame:SetHeight(1) -- Dynamic, set by renderer + layout
    self.autoQuestFrame = autoQuestFrame
    
    -- Completed Quest Frame (Pinned to the scenario frame so borrowed popups stay fixed)
    completedQuestFrame = CreateFrame("Frame", nil, trackerFrame)
    completedQuestFrame:SetPoint("TOPRIGHT", scenarioFrame, "TOPRIGHT", 0, 0)
    completedQuestFrame:SetWidth((self.db and self.db.frameWidth and (self.db.frameWidth - 10)) or 300)
    completedQuestFrame:SetHeight(1)
    completedQuestFrame:SetFrameLevel((trackerFrame:GetFrameLevel() or 1) + 2)
    self.completedQuestFrame = completedQuestFrame

    -- World Quest Frame (Pinned to absolute bottom)
    local worldQuestFrame = CreateFrame("Frame", nil, trackerFrame)
    worldQuestFrame:SetPoint("BOTTOMLEFT", 5, 5)
    worldQuestFrame:SetPoint("BOTTOMRIGHT", -5, 5)
    worldQuestFrame:SetHeight(1)
    worldQuestFrame:Hide()
    self.worldQuestFrame = worldQuestFrame

    -- Bonus Objective Frame (Pinned above World Quest Frame, defaults to bottom if WQ hidden)
    local bonusFrame = CreateFrame("Frame", nil, trackerFrame)
    bonusFrame:SetPoint("BOTTOMLEFT", worldQuestFrame, "TOPLEFT", 0, 0)
    bonusFrame:SetPoint("BOTTOMRIGHT", worldQuestFrame, "TOPRIGHT", 0, 0)
    bonusFrame:SetHeight(1) 
    bonusFrame:Hide()
    self.bonusFrame = bonusFrame
    
    -- Create scroll frame (fills middle area, anchored dynamically by layout)
    scrollFrame = CreateFrame("ScrollFrame", nil, trackerFrame)
    scrollFrame:SetPoint("TOPLEFT", completedQuestFrame, "BOTTOMLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", bonusFrame, "TOPRIGHT", 0, 0)
    scrollFrame:EnableMouse(false)
    scrollFrame:EnableMouseWheel(false)
    
    -- Content frame (child of scroll frame)
    contentFrame = CreateFrame("Frame", nil, scrollFrame)
    -- Width is corrected to the scroll viewport by UpdateContentWidth on the first
    -- render; this is only a starting size so the frame has one before then.
    contentFrame:SetSize(max((self.db.frameWidth or 0) - 10, 1), 100)
    scrollFrame:SetScrollChild(contentFrame)

    -- Scroll frame shadow gradients (depth effect at the edges of the scroll area).
    --
    -- Frame level: the tracker's own level, so these render behind every other child
    -- frame -- scroll content, pinned sections, header chrome and the corner resize
    -- grips. Frame level outranks draw layer across frames, so nothing else needs to
    -- be raised to stay clear of them.
    --
    -- Anchors: horizontally pinned to the tracker so they are always exactly the
    -- tracker's width. Their vertical placement follows the scroll area and is
    -- applied by UpdateScrollShadows; the offsets below are just a starting point.
    local shadowLevel = trackerFrame:GetFrameLevel() or 1

    local scrollShadowTop = CreateFrame("Frame", nil, trackerFrame)
    scrollShadowTop:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 0, 0)
    scrollShadowTop:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", 0, 0)
    scrollShadowTop:SetHeight(50)
    scrollShadowTop:SetFrameLevel(shadowLevel)
    scrollShadowTop:EnableMouse(false)
    scrollShadowTop:SetAlpha(0) -- start invisible; UpdateScrollShadows drives opacity
    -- ARTWORK (not BACKGROUND): at the tracker's frame level the draw layer breaks
    -- the tie with the tracker's own background texture, so this keeps the gradient
    -- above that while frame level still keeps it below every other child frame.
    local topGradient = scrollShadowTop:CreateTexture(nil, "ARTWORK")
    topGradient:SetAllPoints()
    topGradient:SetColorTexture(0, 0, 0, 1)
    topGradient:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1))
    self.scrollShadowTop = scrollShadowTop

    local scrollShadowBottom = CreateFrame("Frame", nil, trackerFrame)
    scrollShadowBottom:SetPoint("BOTTOMLEFT", trackerFrame, "BOTTOMLEFT", 0, 0)
    scrollShadowBottom:SetPoint("BOTTOMRIGHT", trackerFrame, "BOTTOMRIGHT", 0, 0)
    scrollShadowBottom:SetHeight(50)
    scrollShadowBottom:SetFrameLevel(shadowLevel)
    scrollShadowBottom:EnableMouse(false)
    scrollShadowBottom:SetAlpha(0) -- start invisible; UpdateScrollShadows drives opacity
    local bottomGradient = scrollShadowBottom:CreateTexture(nil, "ARTWORK")
    bottomGradient:SetAllPoints()
    bottomGradient:SetColorTexture(0, 0, 0, 1)
    bottomGradient:SetGradient("VERTICAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))
    self.scrollShadowBottom = scrollShadowBottom

    -- Main Header Background (Behind Title/Settings)
    trackerFrame.headerBg = trackerFrame:CreateTexture(nil, "BACKGROUND")
    trackerFrame.headerBg:SetPoint("TOPLEFT", 0, -HEADER_TOP_INSET)
    trackerFrame.headerBg:SetPoint("TOPRIGHT", 0, -HEADER_TOP_INSET)
    trackerFrame.headerBg:SetHeight(24) -- Standard header height

    -- Title Header (Left aligned)
    trackerFrame.title = trackerFrame:CreateFontString(nil, "OVERLAY")
    trackerFrame.title:SetPoint("LEFT", trackerFrame.headerBg, "LEFT", 8, 0)
    local titleFont = self.db.headerFontFace or "Fonts\\FRIZQT__.TTF"
    local titleSize = self.db.headerFontSize or 14
    trackerFrame.title:SetFont(titleFont, titleSize, self.db.headerFontOutline)
    trackerFrame.title:SetTextColor(
        self.db.headerColor.r,
        self.db.headerColor.g,
        self.db.headerColor.b,
        self.db.headerColor.a
    )
    trackerFrame.title:SetText("Tracker Plus")

    -- FTA Toggle Button (arrow icon, to the left of the lock button)
    trackerFrame.ftaToggleBtn = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.ftaToggleBtn:SetSize(16, 16)
    trackerFrame.ftaToggleBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -74, 0)
    local ftaArrowTex = trackerFrame.ftaToggleBtn:CreateTexture(nil, "ARTWORK")
    ftaArrowTex:SetAllPoints()
    ftaArrowTex:SetTexture("Interface\\Minimap\\MinimapArrow")
    trackerFrame.ftaToggleBtn._arrowTex = ftaArrowTex
    local function UpdateFTAToggleColor()
        if addon.db and addon.db.includeFTAQuests then
            ftaArrowTex:SetVertexColor(1, 0.82, 0, 1)   -- gold when enabled
        else
            ftaArrowTex:SetVertexColor(0.5, 0.5, 0.5, 1) -- grey when disabled
        end
    end
    trackerFrame.ftaToggleBtn.UpdateColor = UpdateFTAToggleColor
    UpdateFTAToggleColor()
    -- Hidden unless FollowTheArrow is actually loaded.
    self:UpdateFTAToggleVisibility()
    trackerFrame.ftaToggleBtn:SetScript("OnClick", function()
        addon.db.includeFTAQuests = not addon.db.includeFTAQuests
        UpdateFTAToggleColor()
        addon:RequestUpdate()
    end)
    trackerFrame.ftaToggleBtn:SetScript("OnEnter", function(self)
        local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
        tooltip:SetText(addon.db.includeFTAQuests and "Disable Follow the Arrow" or "Enable Follow the Arrow")
        tooltip:Show()
    end)
    trackerFrame.ftaToggleBtn:SetScript("OnLeave", function()
        addon:HideSharedTooltip()
    end)

    -- Lock Toggle Button (padlock icon, to the left of the settings button).
    -- Gold when locked, grey when unlocked. The tint is applied by
    -- UpdateTrackerLock so it also follows /tp lock, /tp unlock and the Lock Panel
    -- checkbox.
    trackerFrame.lockBtn = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.lockBtn:SetSize(16, 16)
    trackerFrame.lockBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -54, 0)
    local lockTex = trackerFrame.lockBtn:CreateTexture(nil, "ARTWORK")
    lockTex:SetAllPoints()
    lockTex:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
    trackerFrame.lockBtn._lockTex = lockTex
    trackerFrame.lockBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    trackerFrame.lockBtn:SetScript("OnClick", function(self)
        addon:SetSetting("locked", not addon.db.locked)
        addon:UpdateTrackerLock()
        if self:IsMouseOver() then
            self:GetScript("OnEnter")(self)
        end
    end)
    trackerFrame.lockBtn:SetScript("OnEnter", function(self)
        local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
        tooltip:SetText(addon.db.locked and "Unlock Panel" or "Lock Panel")
        tooltip:Show()
    end)
    trackerFrame.lockBtn:SetScript("OnLeave", function()
        addon:HideSharedTooltip()
    end)

    -- Settings Button (Gear icon)
    trackerFrame.settingsParam = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.settingsParam:SetSize(16, 16)
    -- Center vertically relative to header (-34 ensures it sits to left of minmax button)
    trackerFrame.settingsParam:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -34, 0)
    trackerFrame.settingsParam:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    trackerFrame.settingsParam:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    trackerFrame.settingsParam:SetScript("OnClick", function()
        if addon.OpenSettings then
            addon.OpenSettings()
        else
            print("|cff00ff00TrackerPlus:|r Settings not loaded.")
        end
    end)
    trackerFrame.settingsParam:SetScript("OnEnter", function(self)
        local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
        tooltip:SetText("Open Settings")
        tooltip:Show()
    end)
    trackerFrame.settingsParam:SetScript("OnLeave", function()
        addon:HideSharedTooltip()
    end)

    -- Minimize/Maximize Button
    trackerFrame.minMaxBtn = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.minMaxBtn:SetSize(24, 24) -- 1.5x bigger
    -- Center vertically relative to header
    trackerFrame.minMaxBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -5, 0)
    trackerFrame.minMaxBtn:SetNormalAtlas("UI-QuestTrackerButton-Secondary-Collapse")
    trackerFrame.minMaxBtn:SetPushedAtlas("UI-QuestTrackerButton-Secondary-Collapse")
    trackerFrame.minMaxBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")

    -- Keep the header chrome above everything the tracker renders. Pooled rows and
    -- their children climb well past the default child level -- the Active Quest
    -- row's quest-item icon is raised 25px up into this header strip at row level
    -- +10 and escapes its row via SetClipsChildren(false) -- which left it sitting
    -- on top of the gear and swallowing its clicks.
    local chromeLevel = (trackerFrame:GetFrameLevel() or 1) + 50
    trackerFrame.ftaToggleBtn:SetFrameLevel(chromeLevel)
    trackerFrame.lockBtn:SetFrameLevel(chromeLevel)
    trackerFrame.settingsParam:SetFrameLevel(chromeLevel)
    trackerFrame.minMaxBtn:SetFrameLevel(chromeLevel)

    local function UpdateMinMaxState()
        if addon.db.minimized then
            -- Minimized State: Only Maximize button visible
            -- Save current dimensions if not already small
            if trackerFrame:GetWidth() > 50 then
                 addon.db.savedWidth = trackerFrame:GetWidth()
                 addon.db.savedHeight = trackerFrame:GetHeight()

                 -- Save position
                 local point, relativeTo, relativePoint, x, y = trackerFrame:GetPoint()
                 -- Ensure we only save if relativeTo is UIParent or nil (Screen), otherwise default logic
                 if relativeTo == UIParent or relativeTo == nil then
                      addon.db.savedPoint = {point = point, relativePoint = relativePoint, x = x, y = y}
                 end

                 -- Capture geometry before clearing points: an unanchored frame
                 -- reports nil edges.
                 --
                 -- The collapsed frame is a 34x34 box with the button centred in it,
                 -- so anchoring the box's CENTER to where the collapse button sits
                 -- right now leaves the maximize button in exactly the same place.
                 local btn = trackerFrame.minMaxBtn
                 local centerX, centerY
                 if btn then
                      local btnLeft, btnBottom = btn:GetLeft(), btn:GetBottom()
                      if btnLeft and btnBottom then
                           centerX = btnLeft + (btn:GetWidth() or 0) / 2
                           centerY = btnBottom + (btn:GetHeight() or 0) / 2
                      end
                 end

                 local top = trackerFrame:GetTop()
                 local right = trackerFrame:GetRight()

                 trackerFrame:ClearAllPoints()

                 if centerX and centerY then
                      trackerFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX, centerY)
                 elseif right and top then
                      -- Button not laid out yet; keep the tracker's top-right corner,
                      -- which is the corner the header chrome is anchored to.
                      trackerFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
                 end
            end

            -- Size to fit just the button (plus defined border padding)
            -- 34x34 box allows 24x24 button to sit with 5px padding (34-24)/2 = 5
            trackerFrame:SetSize(34, 34) 
            
            -- Gold-only textures (Plus)
            -- Quest Log option (Atlas)
            trackerFrame.minMaxBtn:SetNormalAtlas("UI-QuestTrackerButton-Secondary-Expand")
            trackerFrame.minMaxBtn:SetPushedAtlas("UI-QuestTrackerButton-Secondary-Expand") 
            
            -- Hide Elements
            trackerFrame.settingsParam:Hide()
            trackerFrame.lockBtn:Hide()
            if trackerFrame.ftaToggleBtn then trackerFrame.ftaToggleBtn:Hide() end
            trackerFrame.title:Hide()
            trackerFrame.headerBg:Hide()
            trackerFrame.bg:Hide()
            if trackerFrame.border then trackerFrame.border:Hide() end
            if trackerFrame.resizeBR then trackerFrame.resizeBR:Hide() end
            if trackerFrame.resizeBL then trackerFrame.resizeBL:Hide() end
            if scrollFrame then scrollFrame:Hide() end
            if self.scrollShadowTop then self.scrollShadowTop:Hide() end
            if self.scrollShadowBottom then self.scrollShadowBottom:Hide() end
            if self.scenarioFrame then self.scenarioFrame:Hide() end
            if self.activeQuestFrame then self.activeQuestFrame:Hide() end
            if self.campaignFrame then self.campaignFrame:Hide() end
            if self.autoQuestFrame then self.autoQuestFrame:Hide() end
            if self.completedQuestFrame then self.completedQuestFrame:Hide() end
            if self.bonusFrame then self.bonusFrame:Hide() end
            if self.worldQuestFrame then self.worldQuestFrame:Hide() end
            if self.questTimerFrame then self.questTimerFrame:Hide() end
            
            -- Center button
            trackerFrame.minMaxBtn:ClearAllPoints()
            trackerFrame.minMaxBtn:SetPoint("CENTER", trackerFrame, "CENTER", 0, 0)
        else
            -- Restored State
            trackerFrame:SetSize(addon.db.savedWidth or 300, addon.db.savedHeight or 400)
            
            -- Restore Position if saved
            if addon.db.savedPoint then
                 trackerFrame:ClearAllPoints()
                 local point = addon.db.savedPoint.point or "TOPLEFT"
                 local relativePoint = addon.db.savedPoint.relativePoint or "TOPLEFT"
                 local x = addon.db.savedPoint.x or 100
                 local y = addon.db.savedPoint.y or -200
                 trackerFrame:SetPoint(point, UIParent, relativePoint, x, y)
                 addon.db.savedPoint = nil
            end
            
            -- Gold-only textures (Minus)
            trackerFrame.minMaxBtn:SetNormalAtlas("UI-QuestTrackerButton-Secondary-Collapse")
            trackerFrame.minMaxBtn:SetPushedAtlas("UI-QuestTrackerButton-Secondary-Collapse")

            -- Show Elements
            trackerFrame.settingsParam:Show()
            trackerFrame.lockBtn:Show()
            -- Stays hidden when FollowTheArrow isn't loaded.
            addon:UpdateFTAToggleVisibility()
            trackerFrame.title:Show()
            trackerFrame.headerBg:Show()
            trackerFrame.bg:Show()
            if trackerFrame.border then trackerFrame.border:Show() end
            if scrollFrame then scrollFrame:Show() end
            if self.scrollShadowTop then self.scrollShadowTop:Show() end
            if self.scrollShadowBottom then self.scrollShadowBottom:Show() end
            if self.scenarioFrame then self.scenarioFrame:Show() end
            if self.activeQuestFrame and self.activeQuestFrame:GetHeight() > 1 then self.activeQuestFrame:Show() end
            if self.campaignFrame and self.campaignFrame:GetHeight() > 1 then self.campaignFrame:Show() end
            if self.autoQuestFrame and self.autoQuestFrame:GetHeight() > 1 then self.autoQuestFrame:Show() end
            if self.completedQuestFrame and self.completedQuestFrame:GetHeight() > 1 then self.completedQuestFrame:Show() end
            if self.bonusFrame and self.bonusFrame:GetNumChildren() > 0 then self.bonusFrame:Show() end
            if self.worldQuestFrame and self.worldQuestFrame:GetNumChildren() > 0 then self.worldQuestFrame:Show() end
            
            -- Always right-aligned, matching where the button is first anchored and
            -- keeping it in the same chrome row as the settings, lock and Follow the
            -- Arrow buttons (anchored RIGHT at -34, -54 and -74). This used to follow
            -- db.headerIconPosition, but that setting controls which side the
            -- expand/collapse arrows sit on for headers inside the quest list, not the
            -- tracker window's own chrome. Since it defaults to "left", the button
            -- jumped to the left edge on first load and broke up that row.
            trackerFrame.minMaxBtn:ClearAllPoints()
            trackerFrame.minMaxBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -5, 0)
            
            addon:RequestUpdate()
            if addon.RefreshQuestTimers then addon:RefreshQuestTimers() end
            
            -- Restore lock state (handles resize buttons)
            addon:UpdateTrackerLock()
        end
        
        -- After manipulation, ensure position is saved so reloading keeps the anchor choice
        local point, relativeTo, relativePoint, x, y = trackerFrame:GetPoint()
        addon.db.framePosition = {point = point, relativePoint = relativePoint, x = x, y = y}
    end

    trackerFrame.minMaxBtn:SetScript("OnClick", function()
        addon.db.minimized = not addon.db.minimized
        UpdateMinMaxState()
    end)
    
    -- Update tracker frame button state on demand
    function addon:UpdateMinMaxState()
        UpdateMinMaxState()
    end

    -- Initialize state
    UpdateMinMaxState()
    
    -- Store references
    self.trackerFrame = trackerFrame
    self.scrollFrame = scrollFrame
    self.contentFrame = contentFrame
    self.scenarioFrame = scenarioFrame
    
    -- Show frame
    trackerFrame:Show()
    
    self:UpdateTrackerLock()

    if self.InitQuestTimerSection then self:InitQuestTimerSection() end
    
    return trackerFrame
end

-- Update tracker lock state
function addon:UpdateTrackerLock()
    if not trackerFrame then return end
    
    if self.db.locked then
        trackerFrame:EnableMouse(false)
        if trackerFrame.resizeBR then trackerFrame.resizeBR:Hide() end
        if trackerFrame.resizeBL then trackerFrame.resizeBL:Hide() end
    else
        trackerFrame:EnableMouse(true)
        if trackerFrame.resizeBR then trackerFrame.resizeBR:Show() end
        if trackerFrame.resizeBL then trackerFrame.resizeBL:Show() end
    end

    local lockTex = trackerFrame.lockBtn and trackerFrame.lockBtn._lockTex
    if lockTex then
        if self.db.locked then
            lockTex:SetDesaturated(false)
            lockTex:SetVertexColor(1, 1, 1, 1)
        else
            lockTex:SetDesaturated(true)
            lockTex:SetVertexColor(0.6, 0.6, 0.6, 1)
        end
    end

    -- Keep the Settings checkbox in step when toggled from the header or slash command.
    local lockCheck = _G[addonName .. "lockedCheck"]
    if lockCheck then
        lockCheck:SetChecked(self.db.locked and true or false)
    end
end

------------------------------------------------------------------------------
-- Dynamic Layout Engine
-- Call this after setting section heights and visibility in the render cycle.
    -- Order: ScenarioFrame -> ActiveQuestFrame -> FTAFrame -> CampaignFrame -> AutoQuestFrame -> CompletedQuestFrame -> QuestTimerFrame -> ScrollFrame
-- Bottom-pinned: BonusFrame (if needed) -> WorldQuestFrame (always last)
------------------------------------------------------------------------------
-- Match the scroll content to the scroll frame's viewport.
--
-- A ScrollFrame clips its child to the viewport, so anything wider has its right edge
-- cut off -- and every row and header inside is anchored to the full width of this
-- frame, so it is their right edges that get clipped, not empty space. The width used
-- to be db.frameWidth - 2, but the viewport is inset from the tracker's edges by
-- UpdateLayoutAnchors (by SIDE on each side once a pinned section is showing), so the
-- content always overhung it by several pixels and every header background ran off
-- the right-hand side.
--
-- Measured from the scroll frame rather than recomputed from the insets so the two
-- cannot disagree; the inset arithmetic is only a fallback for the first pass, before
-- the scroll frame's own anchors have resolved.
function addon:UpdateContentWidth()
    if not contentFrame then return end

    local width = scrollFrame and scrollFrame:GetWidth() or 0
    if width <= 1 then
        width = (self.db.frameWidth or 0) - 10
    end

    if width > 1 then
        contentFrame:SetWidth(width)
    end
end

function addon:UpdateLayoutAnchors()
    if not self.trackerFrame then return end

    local PAD      = 4    -- vertical gap between sections
    local SIDE     = 5    -- horizontal inset from tracker edges

    -- Determine section visibility
    local scenVisible  = self.scenarioFrame    and self.scenarioFrame:IsShown()    and self.scenarioFrame:GetHeight()    > 1
    local acqVisible   = self.activeQuestFrame and self.activeQuestFrame:IsShown() and self.activeQuestFrame:GetHeight() > 1
    local ftaVisible   = self.ftaFrame         and self.ftaFrame:IsShown()         and self.ftaFrame:GetHeight()         > 1
    local campVisible  = self.campaignFrame    and self.campaignFrame:IsShown()    and self.campaignFrame:GetHeight()    > 1
    local aqVisible    = self.autoQuestFrame   and self.autoQuestFrame:IsShown()   and self.autoQuestFrame:GetHeight()   > 1
    local cqVisible    = self.completedQuestFrame and self.completedQuestFrame:IsShown() and self.completedQuestFrame:GetHeight() > 1
    local qtVisible    = self.questTimerFrame  and self.questTimerFrame:IsShown()  and self.questTimerFrame:GetHeight()  > 1
    local bonusVisible = self.bonusFrame     and self.bonusFrame:IsShown()     and self.bonusFrame:GetHeight()     > 1
    local wqVisible    = self.worldQuestFrame and self.worldQuestFrame:IsShown() and self.worldQuestFrame:GetHeight() > 1

    -- Build a change-detection signature so we only touch anchors when needed.
    local sig = format("%s|%s|%s|%s|%s|%s|%s|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%s|%s",
        tostring(scenVisible),
        tostring(acqVisible),
        tostring(ftaVisible),
        tostring(campVisible),
        tostring(aqVisible),
        tostring(cqVisible),
        tostring(qtVisible),
        scenVisible  and self.scenarioFrame:GetHeight()    or 0,
        acqVisible   and self.activeQuestFrame:GetHeight() or 0,
        ftaVisible   and self.ftaFrame:GetHeight()         or 0,
        campVisible  and self.campaignFrame:GetHeight()    or 0,
        aqVisible    and self.autoQuestFrame:GetHeight()   or 0,
        cqVisible    and self.completedQuestFrame:GetHeight() or 0,
        qtVisible    and self.questTimerFrame:GetHeight()  or 0,
        tostring(bonusVisible),
        tostring(wqVisible))

    if self._layoutSignature == sig then return end
    self._layoutSignature = sig

    ---------------------------------------------------------------------------
    -- Top-anchored sections, chained in order
    ---------------------------------------------------------------------------
    local topSections = {}
    if scenVisible  then topSections[#topSections + 1] = self.scenarioFrame    end
    if acqVisible   then topSections[#topSections + 1] = self.activeQuestFrame end
    if ftaVisible   then topSections[#topSections + 1] = self.ftaFrame         end
    if campVisible  then topSections[#topSections + 1] = self.campaignFrame    end
    if aqVisible    then topSections[#topSections + 1] = self.autoQuestFrame   end
    if cqVisible    then topSections[#topSections + 1] = self.completedQuestFrame end
    if qtVisible    then topSections[#topSections + 1] = self.questTimerFrame  end
    local prevFrame  = self.trackerFrame
    local prevPoint  = "TOPLEFT"
    local prevPointR = "TOPRIGHT"
    local yOff       = -HEADER_H
    local xL, xR     = SIDE, -SIDE

    for _, section in ipairs(topSections) do
        -- Only call ClearAllPoints+SetPoint on this particular section when its
        -- own anchor parameters changed.  The outer sig catches any downstream
        -- change (e.g. activeQuestFrame height changing), which previously caused
        -- ClearAllPoints to be called on *every* section including scenarioFrame —
        -- momentarily detaching it and producing the visible flash/drop.
        local sectionSig = format("%s|%s|%s|%d|%d",
            tostring(prevFrame), prevPoint, prevPointR, xL, yOff)
        if section._tpLayoutAnchorSig ~= sectionSig then
            section:ClearAllPoints()
            section:SetPoint("TOPLEFT",  prevFrame, prevPoint,  xL, yOff)
            section:SetPoint("TOPRIGHT", prevFrame, prevPointR, xR, yOff)
            section._tpLayoutAnchorSig = sectionSig
        end
        prevFrame  = section
        prevPoint  = "BOTTOMLEFT"
        prevPointR = "BOTTOMRIGHT"
        yOff       = -PAD
        xL, xR     = 0, 0
    end

    ---------------------------------------------------------------------------
    -- ScrollFrame — fills between last top section and first bottom section
    ---------------------------------------------------------------------------
    if self.scrollFrame then
        self.scrollFrame:ClearAllPoints()

        if prevFrame == self.trackerFrame then
            -- No top sections visible; scroll starts right below the header
            self.scrollFrame:SetPoint("TOPLEFT", self.trackerFrame, "TOPLEFT", 0, -HEADER_H)
        else
            self.scrollFrame:SetPoint("TOPLEFT", prevFrame, "BOTTOMLEFT", 0, -PAD)
        end

        if bonusVisible then
            self.scrollFrame:SetPoint("BOTTOMRIGHT", self.bonusFrame, "TOPRIGHT", 0, 0)
        elseif wqVisible then
            self.scrollFrame:SetPoint("BOTTOMRIGHT", self.worldQuestFrame, "TOPRIGHT", 0, 0)
        else
            self.scrollFrame:SetPoint("BOTTOMRIGHT", self.trackerFrame, "BOTTOMRIGHT", -SIDE, SIDE)
        end
    end
end

-- Update tracker appearance (colors, fonts, etc.)
function addon:UpdateTrackerAppearance()
    if not trackerFrame then return end
    
    local db = self.db

    self._appearanceState = self._appearanceState or {}
    local s = self._appearanceState

    local minimized = db.minimized == true
    local borderEnabled = db.borderEnabled == true
    local bgStyle = db.headerBackgroundStyle or "tracker"

    local unchanged =
        s.minimized == minimized
        and s.frameScale == (db.frameScale or 1)
        and s.frameWidth == (db.frameWidth or 0)
        and s.frameHeight == (db.frameHeight or 0)
        and s.bgR == (db.backgroundColor and db.backgroundColor.r or 0)
        and s.bgG == (db.backgroundColor and db.backgroundColor.g or 0)
        and s.bgB == (db.backgroundColor and db.backgroundColor.b or 0)
        and s.bgA == (db.backgroundColor and db.backgroundColor.a or 0)
        and s.borderEnabled == borderEnabled
        and s.borderSize == (db.borderSize or 0)
        and s.borderR == (db.borderColor and db.borderColor.r or 0)
        and s.borderG == (db.borderColor and db.borderColor.g or 0)
        and s.borderB == (db.borderColor and db.borderColor.b or 0)
        and s.borderA == (db.borderColor and db.borderColor.a or 0)
        and s.headerFontFace == db.headerFontFace
        and s.headerFontSize == (db.headerFontSize or 0)
        and s.headerFontOutline == db.headerFontOutline
        and s.headerR == (db.headerColor and db.headerColor.r or 0)
        and s.headerG == (db.headerColor and db.headerColor.g or 0)
        and s.headerB == (db.headerColor and db.headerColor.b or 0)
        and s.headerA == (db.headerColor and db.headerColor.a or 0)
        and s.headerBackgroundStyle == bgStyle

    if unchanged then
        return
    end

    s.minimized = minimized
    s.frameScale = db.frameScale or 1
    s.frameWidth = db.frameWidth or 0
    s.frameHeight = db.frameHeight or 0
    s.bgR = db.backgroundColor and db.backgroundColor.r or 0
    s.bgG = db.backgroundColor and db.backgroundColor.g or 0
    s.bgB = db.backgroundColor and db.backgroundColor.b or 0
    s.bgA = db.backgroundColor and db.backgroundColor.a or 0
    s.borderEnabled = borderEnabled
    s.borderSize = db.borderSize or 0
    s.borderR = db.borderColor and db.borderColor.r or 0
    s.borderG = db.borderColor and db.borderColor.g or 0
    s.borderB = db.borderColor and db.borderColor.b or 0
    s.borderA = db.borderColor and db.borderColor.a or 0
    s.headerFontFace = db.headerFontFace
    s.headerFontSize = db.headerFontSize or 0
    s.headerFontOutline = db.headerFontOutline
    s.headerR = db.headerColor and db.headerColor.r or 0
    s.headerG = db.headerColor and db.headerColor.g or 0
    s.headerB = db.headerColor and db.headerColor.b or 0
    s.headerA = db.headerColor and db.headerColor.a or 0
    s.headerBackgroundStyle = bgStyle

    if db.minimized then
        trackerFrame:SetSize(34, 34)
        trackerFrame:SetScale(db.frameScale)
        return
    end
    
    -- Update background
    if trackerFrame.bg then
        trackerFrame.bg:SetColorTexture(
            db.backgroundColor.r,
            db.backgroundColor.g,
            db.backgroundColor.b,
            db.backgroundColor.a
        )
    end
    
    -- Update border
    if db.borderEnabled then
        if not trackerFrame.border then
            trackerFrame.border = CreateFrame("Frame", nil, trackerFrame, "BackdropTemplate")
            trackerFrame.border:SetAllPoints()
        end
        self._trackerBorderBackdrop = self._trackerBorderBackdrop or {
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = db.borderSize,
        }
        self._trackerBorderBackdrop.edgeSize = db.borderSize
        trackerFrame.border:SetBackdrop(self._trackerBorderBackdrop)
        trackerFrame.border:SetBackdropBorderColor(
            db.borderColor.r,
            db.borderColor.g,
            db.borderColor.b,
            db.borderColor.a
        )
        trackerFrame.border:Show()
    else
        if trackerFrame.border then
            trackerFrame.border:Hide()
        end
    end
    
    -- Update size
    trackerFrame:SetSize(db.frameWidth, db.frameHeight)
    
    -- Update content width synchronously
    self:UpdateContentWidth()
    
    -- Update scale
    trackerFrame:SetScale(db.frameScale)
    
    -- Update title
    if trackerFrame.title then
        trackerFrame.title:SetFont(db.headerFontFace, db.headerFontSize, db.headerFontOutline)
        trackerFrame.title:SetTextColor(db.headerColor.r, db.headerColor.g, db.headerColor.b, db.headerColor.a)
    end
    
    -- Update Main Header Background
    if trackerFrame.headerBg then
        
        trackerFrame.headerBg:ClearAllPoints()
        
        if bgStyle == "none" then
            trackerFrame.headerBg:SetPoint("TOPLEFT", 0, -HEADER_TOP_INSET)
            trackerFrame.headerBg:SetPoint("TOPRIGHT", 0, -HEADER_TOP_INSET)
            trackerFrame.headerBg:SetColorTexture(0, 0, 0, 0)
        elseif bgStyle == "questlog" then
            -- Initial Quest Log style adjustments (shrink width by 4px total)
            trackerFrame.headerBg:SetPoint("TOPLEFT", 2, -HEADER_TOP_INSET)
            trackerFrame.headerBg:SetPoint("TOPRIGHT", -2, -HEADER_TOP_INSET)
            
            if trackerFrame.headerBg.SetAtlas then
                trackerFrame.headerBg:SetAtlas("QuestLog-tab")
                trackerFrame.headerBg:SetVertexColor(1, 1, 1, 1)
            else
                trackerFrame.headerBg:SetTexture("Interface\\QuestFrame\\QuestLog-tab")
                trackerFrame.headerBg:SetTexCoord(0, 1, 0, 1)
                trackerFrame.headerBg:SetVertexColor(1, 1, 1, 1)
            end
        else
            -- Tracker Default
            trackerFrame.headerBg:SetPoint("TOPLEFT", 0, -HEADER_TOP_INSET)
            trackerFrame.headerBg:SetPoint("TOPRIGHT", 0, -HEADER_TOP_INSET)

            if trackerFrame.headerBg.SetAtlas then
                 -- Using Primary for the Main Header as it is the "Main" header
                trackerFrame.headerBg:SetAtlas("UI-QuestTracker-Primary-Objective-Header")
            else
                trackerFrame.headerBg:SetColorTexture(0, 0, 0, 0.4)
            end
            trackerFrame.headerBg:SetVertexColor(1, 1, 1, 1)
        end
        trackerFrame.headerBg:SetHeight(24)
    end
end

-- Refresh the tracker display
function addon:RefreshDisplay()
    self:RequestUpdate()
end
