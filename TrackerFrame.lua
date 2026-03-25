---@diagnostic disable: undefined-global
local addonName, addon = ...
local format = string.format
local max, min = math.max, math.min

-- Tracker frame UI with scrollable content (no visible scrollbar)
local trackerFrame = nil
local scrollFrame = nil
local contentFrame = nil
local completedQuestFrame = nil

local SHADOW_FADE_DISTANCE = 100
local SHADOW_SEAM_OFFSET = 1
local SHADOW_BOTTOM_EXTRA_DROP = 3


-- Update scroll shadow opacity based on scroll position.
-- Uses SetAlpha instead of SetHeight so no tainted geometry values enter
-- Blizzard's LayoutFrame comparisons (which would cause taint errors).
function addon:UpdateScrollShadows()
    if not scrollFrame or not self.scrollShadowTop or not self.scrollShadowBottom then return end
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

-- Create the main tracker frame
function addon:CreateTrackerFrame()
    if trackerFrame then
        return trackerFrame
    end
    
    -- Main frame
    trackerFrame = CreateFrame("Frame", "TrackerPlusFrame", UIParent)
    trackerFrame:SetSize(self.db.frameWidth, self.db.frameHeight)
    trackerFrame:SetFrameStrata("MEDIUM")
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
        local pos = addon.db.framePosition
        if trackerFrame and pos and pos.point and pos.x and pos.y then
             trackerFrame:ClearAllPoints()
             -- Use saved relativePoint if available, otherwise fallback to point (legacy support)
             local relativePoint = pos.relativePoint or pos.point
             trackerFrame:SetPoint(pos.point, UIParent, relativePoint, pos.x, pos.y)
        elseif trackerFrame then
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
        -- Update content width
        if contentFrame then contentFrame:SetWidth(addon.db.frameWidth - 2) end
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
        if contentFrame then contentFrame:SetWidth(addon.db.frameWidth - 2) end
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
    scenarioFrame:SetFrameStrata("HIGH") -- Ensure it sits above scrolling content
    scenarioFrame:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 5, -25)
    scenarioFrame:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", -5, -25)
    scenarioFrame:SetHeight(1) -- Dynamic, set by renderer + layout
    self.scenarioFrame = scenarioFrame

    -- Active Quest Frame (Super-tracked quest, sits between Scenario and auto-quest popups)
    local activeQuestFrame = CreateFrame("Frame", nil, trackerFrame)
    activeQuestFrame:SetFrameStrata("HIGH")
    activeQuestFrame:SetHeight(1) -- Dynamic, set by renderer + layout
    activeQuestFrame:Hide()
    self.activeQuestFrame = activeQuestFrame

    -- Campaign Frame (Pinned below Active Quest when campaign quests are present)
    local campaignFrame = CreateFrame("Frame", nil, trackerFrame)
    campaignFrame:SetFrameStrata("HIGH")
    campaignFrame:SetHeight(1)
    campaignFrame:Hide()
    self.campaignFrame = campaignFrame

    -- Auto Quest Frame (Below scenario/active-quest if visible, outside scroll frame)
    local autoQuestFrame = CreateFrame("Frame", nil, trackerFrame)
    autoQuestFrame:SetPoint("TOPLEFT", scenarioFrame, "BOTTOMLEFT", 0, 0)
    autoQuestFrame:SetPoint("TOPRIGHT", scenarioFrame, "BOTTOMRIGHT", 0, 0)
    autoQuestFrame:SetHeight(1) -- Dynamic, set by renderer + layout
    self.autoQuestFrame = autoQuestFrame
    
    -- Completed Quest Frame (Below auto/active quest if visible, outside scroll frame)
    completedQuestFrame = CreateFrame("Frame", nil, trackerFrame)
    completedQuestFrame:SetPoint("TOPLEFT", autoQuestFrame, "BOTTOMLEFT", 0, 0)
    completedQuestFrame:SetPoint("TOPRIGHT", autoQuestFrame, "BOTTOMRIGHT", 0, 0)
    completedQuestFrame:SetHeight(1)
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
    contentFrame:SetSize(self.db.frameWidth - 2, 100) -- Reduce width for scrollbar/padding logic
    scrollFrame:SetScrollChild(contentFrame)

    -- Scroll frame shadow gradients (depth effect: content appears "behind" pinned sections)
    local shadowLevel = 100

    local scrollShadowTop = CreateFrame("Frame", nil, trackerFrame)
    scrollShadowTop:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, SHADOW_SEAM_OFFSET)
    scrollShadowTop:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, SHADOW_SEAM_OFFSET)
    scrollShadowTop:SetHeight(50)
    scrollShadowTop:SetFrameLevel(shadowLevel)
    scrollShadowTop:EnableMouse(false)
    scrollShadowTop:SetAlpha(0) -- start invisible; UpdateScrollShadows drives opacity
    local topGradient = scrollShadowTop:CreateTexture(nil, "OVERLAY")
    topGradient:SetAllPoints()
    topGradient:SetColorTexture(0, 0, 0, 1)
    topGradient:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1))
    self.scrollShadowTop = scrollShadowTop

    local scrollShadowBottom = CreateFrame("Frame", nil, trackerFrame)
    scrollShadowBottom:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMLEFT", 0, SHADOW_SEAM_OFFSET - SHADOW_BOTTOM_EXTRA_DROP)
    scrollShadowBottom:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, SHADOW_SEAM_OFFSET - SHADOW_BOTTOM_EXTRA_DROP)
    scrollShadowBottom:SetHeight(50)
    scrollShadowBottom:SetFrameLevel(shadowLevel)
    scrollShadowBottom:EnableMouse(false)
    scrollShadowBottom:SetAlpha(0) -- start invisible; UpdateScrollShadows drives opacity
    local bottomGradient = scrollShadowBottom:CreateTexture(nil, "OVERLAY")
    bottomGradient:SetAllPoints()
    bottomGradient:SetColorTexture(0, 0, 0, 1)
    bottomGradient:SetGradient("VERTICAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))
    self.scrollShadowBottom = scrollShadowBottom

    -- Main Header Background (Behind Title/Settings)
    trackerFrame.headerBg = trackerFrame:CreateTexture(nil, "BACKGROUND")
    trackerFrame.headerBg:SetPoint("TOPLEFT", 0, 0)
    trackerFrame.headerBg:SetPoint("TOPRIGHT", 0, 0)
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

    local function UpdateMinMaxState()
        -- Ensure we work with screen coordinates to maintain position relative to TOP-RIGHT
        
        -- Determine side based on headerIconPosition or default to Right
        local isLeft = (addon.db.headerIconPosition == "left")

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

                 -- RE-ANCHOR to keep the Corner in place visually
                 local top = trackerFrame:GetTop()
                 local left = trackerFrame:GetLeft()
                 local right = trackerFrame:GetRight()
                 
                 trackerFrame:ClearAllPoints()

                 if isLeft and left and top then
                      -- Use TOPLEFT anchor relative to screen coordinates
                      trackerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
                 elseif right and top then
                      -- Use TOPRIGHT anchor relative to screen coordinates
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
            trackerFrame.title:Hide()
            trackerFrame.headerBg:Hide()
            trackerFrame.bg:Hide()
            if trackerFrame.border then trackerFrame.border:Hide() end
            if trackerFrame.resizeBR then trackerFrame.resizeBR:Hide() end
            if trackerFrame.resizeBL then trackerFrame.resizeBL:Hide() end
            if scrollFrame then scrollFrame:Hide() end
            if self.scenarioFrame then self.scenarioFrame:Hide() end
            if self.activeQuestFrame then self.activeQuestFrame:Hide() end
            if self.campaignFrame then self.campaignFrame:Hide() end
            if self.autoQuestFrame then self.autoQuestFrame:Hide() end
            if self.completedQuestFrame then self.completedQuestFrame:Hide() end
            if self.bonusFrame then self.bonusFrame:Hide() end
            if self.worldQuestFrame then self.worldQuestFrame:Hide() end
            
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
            trackerFrame.title:Show()
            trackerFrame.headerBg:Show()
            trackerFrame.bg:Show()
            if trackerFrame.border then trackerFrame.border:Show() end
            if scrollFrame then scrollFrame:Show() end
            if self.scenarioFrame then self.scenarioFrame:Show() end
            if self.activeQuestFrame and self.activeQuestFrame:GetHeight() > 1 then self.activeQuestFrame:Show() end
            if self.campaignFrame and self.campaignFrame:GetHeight() > 1 then self.campaignFrame:Show() end
            if self.autoQuestFrame and self.autoQuestFrame:GetHeight() > 1 then self.autoQuestFrame:Show() end
            if self.completedQuestFrame and self.completedQuestFrame:GetHeight() > 1 then self.completedQuestFrame:Show() end
            if self.bonusFrame and self.bonusFrame:GetNumChildren() > 0 then self.bonusFrame:Show() end
            if self.worldQuestFrame and self.worldQuestFrame:GetNumChildren() > 0 then self.worldQuestFrame:Show() end
            
            -- Reset button position based on side
            trackerFrame.minMaxBtn:ClearAllPoints()
            if isLeft then
                trackerFrame.minMaxBtn:SetPoint("LEFT", trackerFrame.headerBg, "LEFT", 5, 0)
            else
                trackerFrame.minMaxBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -5, 0)
            end
            
            addon:RequestUpdate()
            
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
end

------------------------------------------------------------------------------
-- Dynamic Layout Engine
-- Call this after setting section heights and visibility in the render cycle.
    -- Order: ScenarioFrame -> ActiveQuestFrame -> CampaignFrame -> AutoQuestFrame -> CompletedQuestFrame -> ScrollFrame
-- Bottom-pinned: BonusFrame (if needed) -> WorldQuestFrame (always last)
------------------------------------------------------------------------------
function addon:UpdateLayoutAnchors()
    if not self.trackerFrame then return end

    local HEADER_H = 25   -- pixels reserved for the title bar
    local PAD      = 4    -- vertical gap between sections
    local SIDE     = 5    -- horizontal inset from tracker edges

    -- Determine section visibility
    local scenVisible  = self.scenarioFrame    and self.scenarioFrame:IsShown()    and self.scenarioFrame:GetHeight()    > 1
    local acqVisible   = self.activeQuestFrame and self.activeQuestFrame:IsShown() and self.activeQuestFrame:GetHeight() > 1
    local campVisible  = self.campaignFrame    and self.campaignFrame:IsShown()    and self.campaignFrame:GetHeight()    > 1
    local aqVisible    = self.autoQuestFrame   and self.autoQuestFrame:IsShown()   and self.autoQuestFrame:GetHeight()   > 1
    local cqVisible    = self.completedQuestFrame and self.completedQuestFrame:IsShown() and self.completedQuestFrame:GetHeight() > 1
    local bonusVisible = self.bonusFrame     and self.bonusFrame:IsShown()     and self.bonusFrame:GetHeight()     > 1
    local wqVisible    = self.worldQuestFrame and self.worldQuestFrame:IsShown() and self.worldQuestFrame:GetHeight() > 1

    -- Build a change-detection signature so we only touch anchors when needed.
    local sig = format("%s|%s|%s|%s|%s|%.0f|%.0f|%.0f|%.0f|%.0f|%s|%s",
        tostring(scenVisible),
        tostring(acqVisible),
        tostring(campVisible),
        tostring(aqVisible),
        tostring(cqVisible),
        scenVisible  and self.scenarioFrame:GetHeight()    or 0,
        acqVisible   and self.activeQuestFrame:GetHeight() or 0,
        campVisible  and self.campaignFrame:GetHeight()    or 0,
        aqVisible    and self.autoQuestFrame:GetHeight()   or 0,
        cqVisible    and self.completedQuestFrame:GetHeight() or 0,
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
    if campVisible  then topSections[#topSections + 1] = self.campaignFrame    end
    if aqVisible    then topSections[#topSections + 1] = self.autoQuestFrame   end
    if cqVisible    then topSections[#topSections + 1] = self.completedQuestFrame end

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
    if contentFrame then
        contentFrame:SetWidth(db.frameWidth - 2)
    end
    
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
            trackerFrame.headerBg:SetPoint("TOPLEFT", 0, 0)
            trackerFrame.headerBg:SetPoint("TOPRIGHT", 0, 0)
            trackerFrame.headerBg:SetColorTexture(0, 0, 0, 0)
        elseif bgStyle == "questlog" then
            -- Initial Quest Log style adjustments (shrink width by 4px total)
            trackerFrame.headerBg:SetPoint("TOPLEFT", 2, 0)
            trackerFrame.headerBg:SetPoint("TOPRIGHT", -2, 0)
            
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
            trackerFrame.headerBg:SetPoint("TOPLEFT", 0, 0)
            trackerFrame.headerBg:SetPoint("TOPRIGHT", 0, 0)
            
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
