---@diagnostic disable: undefined-global
local addonName, addon = ...
local ipairs, wipe = ipairs, wipe
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
addon.HEADER_TOP_INSET = HEADER_TOP_INSET
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

    -- Compared at 0.1px, the precision that matters on screen.
    topOffset = floor(topOffset * 10 + 0.5) / 10
    bottomOffset = floor(bottomOffset * 10 + 0.5) / 10
    if owner._scrollShadowTopOffset == topOffset and owner._scrollShadowBottomOffset == bottomOffset then return end
    owner._scrollShadowTopOffset, owner._scrollShadowBottomOffset = topOffset, bottomOffset

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
    if self.db.minimized or not scrollFrame:IsShown() then
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

-- Saves a drag-resize as whole pixels. Sizing leaves the frame at a fractional size, so the
-- frame is snapped to the rounded values too, keeping what's shown and what's saved the same.
local function SaveDraggedSize()
    local width = floor(trackerFrame:GetWidth() + 0.5)
    local height = floor(trackerFrame:GetHeight() + 0.5)
    addon.db.frameWidth = width
    addon.db.frameHeight = height
    trackerFrame:SetSize(width, height)
end

-- Re-anchors the tracker by db.frameAnchor (e.g. TOPRIGHT) without moving it on
-- screen, so resizing keeps that point fixed instead of growing around whatever
-- anchor StartMoving happened to leave (often CENTER). The frame is tied to the same
-- point on UIParent, so it also stays put relative to that screen corner/edge.
local function ApplyTrackerAnchor()
    if not trackerFrame then return end
    local anchor = addon.db.frameAnchor or "TOPRIGHT"

    local point, relativeTo, relativePoint = trackerFrame:GetPoint()
    if not point then return end
    if relativeTo and relativeTo ~= UIParent then return end
    if point == anchor and relativePoint == anchor then return end

    local left, right = trackerFrame:GetLeft(), trackerFrame:GetRight()
    local top, bottom = trackerFrame:GetTop(), trackerFrame:GetBottom()
    if not (left and right and top and bottom) then return end

    -- Offsets are in the tracker's own scale; express UIParent's size in it too.
    local ratio = UIParent:GetEffectiveScale() / trackerFrame:GetEffectiveScale()
    local parentW, parentH = UIParent:GetWidth() * ratio, UIParent:GetHeight() * ratio

    local x, y
    if anchor:find("LEFT") then
        x = left
    elseif anchor:find("RIGHT") then
        x = right - parentW
    else
        x = (left + right) / 2 - parentW / 2
    end
    if anchor:find("TOP") then
        y = top - parentH
    elseif anchor:find("BOTTOM") then
        y = bottom
    else
        y = (top + bottom) / 2 - parentH / 2
    end

    trackerFrame:ClearAllPoints()
    trackerFrame:SetPoint(anchor, UIParent, anchor, x, y)
    addon.db.framePosition = {point = anchor, relativePoint = anchor, x = x, y = y}
end

function addon:ApplyTrackerAnchor()
    -- Minimized, the frame is a button-sized box anchored by the button itself.
    if self.db.minimized then return end
    ApplyTrackerAnchor()
end

-- Create the main tracker frame
-- We keep Blizzard's tracker alive but invisible (alpha 0) so the sections that
-- borrow its frames keep updating, and an alive frame still hit-tests: its quest
-- block title buttons swallow clicks aimed at our header buttons whenever its
-- strata outranks ours. Strata outranks frame level, so no amount of levelling
-- fixes that -- we have to share its strata and win on level instead.
--
-- That strata isn't fixed: older clients declare ObjectiveTrackerFrame
-- frameStrata="LOW", the classic beta now runs it at MEDIUM. So read it from the
-- live frame instead of hard-coding it; Core hooks SetFrameStrata to re-run this.
function addon:MatchBlizzardTrackerStrata()
    if not self.trackerFrame then return end

    local strata = "LOW"
    local blizz = ObjectiveTrackerFrame
    if blizz and blizz.GetFrameStrata then
        strata = blizz:GetFrameStrata() or strata
    end

    if self.trackerFrame:GetFrameStrata() ~= strata then
        self.trackerFrame:SetFrameStrata(strata)
    end
end

-- A frame for a top-pinned section. The placeholder horizontal anchors are not
-- cosmetic: UpdateLayoutAnchors runs *after* the section renderers, so a section
-- carrying no anchors at all has width 0 the first time it is rendered. Everything
-- RenderTrackableItem measures is derived from its parent's width, and a font
-- string with no room reports a string height of 0 -- which puts the first
-- objective line on top of the quest title. Because painting only happens when the
-- collected data version changes, that bad first pass then stays on screen until
-- the quest's data next changes. UpdateLayoutAnchors replaces these anchors in the
-- same render pass, so they only ever supply a sane width to measure against.
local function CreatePinnedSection(parent, hidden)
    local section = CreateFrame("Frame", nil, parent)
    section:SetFrameLevel(parent:GetFrameLevel() + 1)
    section:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -HEADER_H)
    section:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -HEADER_H)
    section:SetHeight(1) -- Dynamic, set by renderer + layout
    if hidden then section:Hide() end
    return section
end

local function OnResizeGripUp()
    trackerFrame:StopMovingOrSizing()
    SaveDraggedSize()
    addon:ApplyTrackerAnchor()
    addon:ClaimManualGeometry()
    addon:UpdateContentWidth()
    addon:RequestUpdate()
    addon:UpdateSettingWidgets()
end

-- A corner drag-to-resize grip. `flip` mirrors the art for the left corner.
local function CreateResizeGrip(corner, flip)
    local grip = CreateFrame("Button", nil, trackerFrame)
    grip:SetSize(16, 16)
    grip:SetPoint(corner)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    if flip then
        grip:GetNormalTexture():SetTexCoord(1, 0, 0, 1)
        grip:GetHighlightTexture():SetTexCoord(1, 0, 0, 1)
        grip:GetPushedTexture():SetTexCoord(1, 0, 0, 1)
    end
    grip:SetScript("OnMouseDown", function()
        if not addon.db.locked then
            trackerFrame:StartSizing(corner)
        end
    end)
    grip:SetScript("OnMouseUp", OnResizeGripUp)
    return grip
end

function addon:CreateTrackerFrame()
    if trackerFrame then
        return trackerFrame
    end
    
    -- Main frame
    trackerFrame = CreateFrame("Frame", "TrackerPlusFrame", UIParent)
    -- Published now, not at the end: RestorePosition (below) already needs it.
    self.trackerFrame = trackerFrame
    trackerFrame:SetSize(self.db.frameWidth, self.db.frameHeight)
    -- Sit in the same strata as the frame we replace (see MatchBlizzardTrackerStrata).
    self:MatchBlizzardTrackerStrata()
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
    
    -- Restore position (also re-run on every PLAYER_ENTERING_WORLD)
    addon.RestorePosition = function()
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
    
    -- The optional border is created by UpdateTrackerAppearance on the first render.

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
        -- Swap to the chosen anchor (and save that) so later resizes keep it fixed.
        addon:ApplyTrackerAnchor()
        addon:ClaimManualGeometry()
    end)
    
    -- Resizing Handles (Triangles)
    trackerFrame.resizeBR = CreateResizeGrip("BOTTOMRIGHT", false)
    trackerFrame.resizeBL = CreateResizeGrip("BOTTOMLEFT", true)
    
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
    
    -- Top-pinned sections outside the scroll frame, chained by UpdateLayoutAnchors:
    -- Scenario -> Active Quest (super-tracked) -> Follow the Arrow -> Campaign -> ...
    -- -> Quest Timers ("Quest Timer: MM:SS" rows, filled by RenderQuestTimers.lua,
    -- last so it sits directly above the quest list).
    local scenarioFrame = CreatePinnedSection(trackerFrame, false)
    self.scenarioFrame = scenarioFrame
    self.activeQuestFrame = CreatePinnedSection(trackerFrame, true)
    self.ftaFrame = CreatePinnedSection(trackerFrame, true)
    self.campaignFrame = CreatePinnedSection(trackerFrame, true)
    self.questTimerFrame = CreatePinnedSection(trackerFrame, true)

    -- Auto Quest Frame (Below scenario/active-quest if visible, outside scroll frame)
    local autoQuestFrame = CreateFrame("Frame", nil, trackerFrame)
    autoQuestFrame:SetPoint("TOPLEFT", scenarioFrame, "BOTTOMLEFT", 0, 0)
    autoQuestFrame:SetPoint("TOPRIGHT", scenarioFrame, "BOTTOMRIGHT", 0, 0)
    autoQuestFrame:SetHeight(1) -- Dynamic, set by renderer + layout
    self.autoQuestFrame = autoQuestFrame
    
    -- Completed Quest Frame (Pinned to the scenario frame so borrowed popups stay fixed)
    completedQuestFrame = CreateFrame("Frame", nil, trackerFrame)
    completedQuestFrame:SetPoint("TOPRIGHT", scenarioFrame, "TOPRIGHT", 0, 0)
    completedQuestFrame:SetWidth(self.db.frameWidth - 10)
    completedQuestFrame:SetHeight(1)
    completedQuestFrame:SetFrameLevel(trackerFrame:GetFrameLevel() + 2)
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
    self.scrollFrame = scrollFrame
    scrollFrame:SetPoint("TOPLEFT", completedQuestFrame, "BOTTOMLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", bonusFrame, "TOPRIGHT", 0, 0)
    scrollFrame:EnableMouse(false)
    scrollFrame:EnableMouseWheel(false)
    
    -- Content frame (child of scroll frame)
    contentFrame = CreateFrame("Frame", nil, scrollFrame)
    self.contentFrame = contentFrame
    -- Width is corrected to the scroll viewport by UpdateContentWidth on the first
    -- render; this is only a starting size so the frame has one before then.
    contentFrame:SetSize(max(self.db.frameWidth - 10, 1), 100)
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
    local shadowLevel = trackerFrame:GetFrameLevel()

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

    self:CreateTrackerHeader(trackerFrame)

    trackerFrame:Show()
    self:UpdateTrackerLock()
    self:InitQuestTimerSection()
    
    return trackerFrame
end

-- Update tracker lock state
function addon:UpdateTrackerLock()
    if not trackerFrame then return end
    
    local locked = self.db.locked
    trackerFrame:EnableMouse(not locked)
    trackerFrame.resizeBR:SetShown(not locked)
    trackerFrame.resizeBL:SetShown(not locked)

    -- Gold when locked, grey when unlocked.
    local lockTex = trackerFrame.lockBtn._lockTex
    lockTex:SetDesaturated(not locked)
    if locked then
        lockTex:SetVertexColor(1, 1, 1, 1)
    else
        lockTex:SetVertexColor(0.6, 0.6, 0.6, 1)
    end

    -- Keep the Settings checkbox in step when toggled from the header or slash command.
    local lockCheck = _G[addonName .. "lockedCheck"]
    if lockCheck then
        lockCheck:SetChecked(self.db.locked and true or false)
    end
end

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
    -- The content frame parents the secure quest item buttons, so resizing it is
    -- blocked in combat. Every render path re-runs this once combat ends.
    if not contentFrame or InCombatLockdown() then return end

    local width = scrollFrame:GetWidth()
    if width <= 1 then
        width = self.db.frameWidth - 10
    end

    if width > 1 then
        contentFrame:SetWidth(width)
    end
end

------------------------------------------------------------------------------
-- Dynamic Layout Engine
-- Call this after setting section heights and visibility in the render cycle.
-- Top-pinned, in order (TOP_SECTIONS): Scenario -> Active Quest -> FTA -> Campaign
-- -> Auto Quest -> Completed Quest -> Quest Timer, then the ScrollFrame.
-- Bottom-pinned: BonusFrame (if needed) -> WorldQuestFrame (always last)
------------------------------------------------------------------------------
local TOP_SECTIONS = {
    "scenarioFrame", "activeQuestFrame", "ftaFrame", "campaignFrame",
    "autoQuestFrame", "completedQuestFrame", "questTimerFrame",
}
local LAYOUT_PAD  = 4    -- vertical gap between sections
local LAYOUT_SIDE = 5    -- horizontal inset from tracker edges

-- Reused across calls. layoutState holds, per top section, its rounded height
-- (0 = hidden), then the bonus and world quest visibility, so anchors are only
-- touched when one of those changes.
local layoutState, visibleTop = {}, {}

local function SectionHeight(frame)
    if frame:IsShown() then
        local height = frame:GetHeight()
        if height > 1 then return floor(height + 0.5) end
    end
    return 0
end

-- Stores value in layoutState[i]; true if it differs from what was there.
local function Track(i, value)
    if layoutState[i] ~= value then
        layoutState[i] = value
        return true
    end
    return false
end

function addon:UpdateLayoutAnchors()
    if not self.trackerFrame then return end

    -- A nil signature (set by the renderer) forces a full re-anchor.
    local changed = self._layoutSignature == nil

    wipe(visibleTop)
    for i, key in ipairs(TOP_SECTIONS) do
        local frame = self[key]
        local height = SectionHeight(frame)
        changed = Track(i, height) or changed
        if height > 0 then visibleTop[#visibleTop + 1] = frame end
    end
    local bonusVisible = SectionHeight(self.bonusFrame) > 0
    local wqVisible = SectionHeight(self.worldQuestFrame) > 0
    changed = Track(#TOP_SECTIONS + 1, bonusVisible) or changed
    changed = Track(#TOP_SECTIONS + 2, wqVisible) or changed

    if not changed then return end
    self._layoutSignature = true

    ---------------------------------------------------------------------------
    -- Top-anchored sections, chained in order
    ---------------------------------------------------------------------------
    local prevFrame = self.trackerFrame
    for _, section in ipairs(visibleTop) do
        -- Only re-anchor this section when the frame above it changed. Everything
        -- else about the anchor follows from that: the first section sits under
        -- the header inset from the tracker's sides, later ones flush below the
        -- previous section. Re-anchoring unchanged sections (scenarioFrame
        -- especially) momentarily detached them and produced a visible flash/drop.
        if section._tpLayoutAnchorPrev ~= prevFrame then
            section:ClearAllPoints()
            if prevFrame == self.trackerFrame then
                section:SetPoint("TOPLEFT", prevFrame, "TOPLEFT", LAYOUT_SIDE, -HEADER_H)
                section:SetPoint("TOPRIGHT", prevFrame, "TOPRIGHT", -LAYOUT_SIDE, -HEADER_H)
            else
                section:SetPoint("TOPLEFT", prevFrame, "BOTTOMLEFT", 0, -LAYOUT_PAD)
                section:SetPoint("TOPRIGHT", prevFrame, "BOTTOMRIGHT", 0, -LAYOUT_PAD)
            end
            section._tpLayoutAnchorPrev = prevFrame
        end
        prevFrame = section
    end

    ---------------------------------------------------------------------------
    -- ScrollFrame — fills between last top section and first bottom section
    ---------------------------------------------------------------------------
    local scroll = self.scrollFrame
    scroll:ClearAllPoints()

    if prevFrame == self.trackerFrame then
        -- No top sections visible; scroll starts right below the header
        scroll:SetPoint("TOPLEFT", self.trackerFrame, "TOPLEFT", 0, -HEADER_H)
    else
        scroll:SetPoint("TOPLEFT", prevFrame, "BOTTOMLEFT", 0, -LAYOUT_PAD)
    end

    if bonusVisible then
        scroll:SetPoint("BOTTOMRIGHT", self.bonusFrame, "TOPRIGHT", 0, 0)
    elseif wqVisible then
        scroll:SetPoint("BOTTOMRIGHT", self.worldQuestFrame, "TOPRIGHT", 0, 0)
    else
        scroll:SetPoint("BOTTOMRIGHT", self.trackerFrame, "BOTTOMRIGHT", -LAYOUT_SIDE, LAYOUT_SIDE)
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
        and s.borderStyle == db.borderStyle
        and s.backgroundStyle == db.backgroundStyle
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
    s.borderStyle = db.borderStyle
    s.backgroundStyle = db.backgroundStyle
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
    
    local borderFile, _, borderInnerEdge = self:ResolvePanelMedia("border", db.borderStyle)

    -- Update background
    if trackerFrame.bg then
        local bg = trackerFrame.bg
        local color = db.backgroundColor
        local backgroundFile = self:ResolvePanelMedia("background", db.backgroundStyle)
        if self:IsSolidPanelMedia(backgroundFile) then
            -- Undo a texture's tint, which would otherwise carry over.
            bg:SetVertexColor(1, 1, 1, 1)
            bg:SetColorTexture(color.r, color.g, color.b, color.a)
        else
            -- Stretched over the whole panel, in the texture's own colors (the Background
            -- color is only for Solid).
            bg:SetTexture(backgroundFile)
            bg:SetHorizTile(false)
            bg:SetVertTile(false)
            bg:SetTexCoord(0, 1, 0, 1)
            bg:SetVertexColor(1, 1, 1, 1)
        end
    end
    
    -- Update border
    if db.borderEnabled then
        local border = trackerFrame.border
        if not border then
            border = CreateFrame("Frame", nil, trackerFrame, "BackdropTemplate")
            trackerFrame.border = border
        end
        -- Drawn over the panel's contents, so section headers don't cover a textured border's
        -- inner edge.
        border:SetFrameLevel(trackerFrame:GetFrameLevel() + 100)

        -- Pushed out so the inner edge of the border's art sits exactly on the panel's edge, and
        -- grows outwards with its size. A solid border is all art; textured ones are transparent
        -- past their inner edge, and that part lies over the panel.
        local edgeSize = db.borderSize or 1
        local solidBorder = self:IsSolidPanelMedia(borderFile)
        local outset = math.floor(edgeSize * borderInnerEdge + 0.5)
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", -outset, outset)
        border:SetPoint("BOTTOMRIGHT", outset, -outset)

        -- A new table each time: SetBackdrop ignores the table it already has, even if its
        -- contents changed, so editing one in place never redraws the border.
        border:SetBackdrop({
            edgeFile = borderFile,
            edgeSize = edgeSize,
        })
        -- The Border color is for Solid; textures are drawn in their own colors.
        local color = solidBorder and db.borderColor or { r = 1, g = 1, b = 1, a = 1 }
        border:SetBackdropBorderColor(color.r, color.g, color.b, color.a)
        border:Show()
    else
        if trackerFrame.border then
            trackerFrame.border:Hide()
        end
    end
    
    -- Update size, keeping the chosen anchor point where it is
    ApplyTrackerAnchor()
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

-- Refresh the tracker display after a style setting changed (fonts, sizes, colors,
-- spacing). UpdateTracker only repaints when the collected data or frame size
-- changed, so without marking the layout dirty a style change would sit unseen
-- until the next unrelated quest event.
function addon:RefreshDisplay()
    self._layoutDirty = true
    self:RequestUpdate()
end
