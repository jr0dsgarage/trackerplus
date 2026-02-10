---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Tracker frame UI with scrollable content (no visible scrollbar)
local trackerFrame = nil
local scrollFrame = nil
local contentFrame = nil
local trackableButtons = {}
local activeButtons = 0
local secureButtons = {} -- Pool for SecureActionButtons
local activeSecureButtons = 0

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
        if trackerFrame and addon.db.framePosition then
             trackerFrame:ClearAllPoints()
             -- Use saved relativePoint if available, otherwise fallback to point (legacy support)
             local relativePoint = addon.db.framePosition.relativePoint or addon.db.framePosition.point
             trackerFrame:SetPoint(addon.db.framePosition.point, UIParent, relativePoint, addon.db.framePosition.x, addon.db.framePosition.y)
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
            local newScroll = math.max(0, math.min(maxScroll, current - (delta * 20)))
            scrollFrame:SetVerticalScroll(newScroll)
        end
    end)
    
    -- Auto Quest Frame (Pinned to top, below title)
    -- This resides outside the scroll frame so it doesn't scroll
    local autoQuestFrame = CreateFrame("Frame", nil, trackerFrame)
    autoQuestFrame:SetPoint("TOPLEFT", 5, -25)
    autoQuestFrame:SetPoint("TOPRIGHT", -5, -25)
    autoQuestFrame:SetHeight(1) -- Will be dynamic
    self.autoQuestFrame = autoQuestFrame

    -- Widget Frame (For Progress Bars / Power Bars)
    -- Resides between Auto Quest and Scenario
    local widgetFrame = CreateFrame("Frame", nil, trackerFrame)
    widgetFrame:SetPoint("TOPLEFT", autoQuestFrame, "BOTTOMLEFT", 0, -5)
    widgetFrame:SetPoint("TOPRIGHT", autoQuestFrame, "BOTTOMRIGHT", 0, -5)
    widgetFrame:SetHeight(1) -- Will be dynamic
    self.widgetFrame = widgetFrame

    -- Scenario Frame (Pinned to Widget Frame)
    -- This resides outside the scroll frame so it doesn't scroll
    local scenarioFrame = CreateFrame("Frame", nil, trackerFrame)
    scenarioFrame:SetPoint("TOPLEFT", widgetFrame, "BOTTOMLEFT", 0, -5)
    scenarioFrame:SetPoint("TOPRIGHT", widgetFrame, "BOTTOMRIGHT", 0, -5)
    scenarioFrame:SetHeight(1) -- Will be dynamic
    self.scenarioFrame = scenarioFrame

    -- Bonus Objective Frame (Pinned to bottom)
    local bonusFrame = CreateFrame("Frame", nil, trackerFrame)
    bonusFrame:SetPoint("BOTTOMLEFT", 5, 5)
    bonusFrame:SetPoint("BOTTOMRIGHT", -5, 5)
    bonusFrame:SetHeight(1) 
    bonusFrame:Hide()
    self.bonusFrame = bonusFrame
    
    -- Create scroll frame (Between Scenario and Bonus)
    scrollFrame = CreateFrame("ScrollFrame", nil, trackerFrame)
    scrollFrame:SetPoint("TOPLEFT", scenarioFrame, "BOTTOMLEFT", 0, 0) -- Attach to bottom of scenario frame
    scrollFrame:SetPoint("BOTTOMRIGHT", -5, 5) -- Default bottom, will be adjusted dynamically
    scrollFrame:EnableMouse(false)
    scrollFrame:EnableMouseWheel(false)
    
    -- Content frame (child of scroll frame)
    contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetSize(self.db.frameWidth - 2, 100) -- Reduce width for scrollbar/padding logic
    scrollFrame:SetScrollChild(contentFrame)
    
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
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open Settings")
        GameTooltip:Show()
    end)
    trackerFrame.settingsParam:SetScript("OnLeave", function()
        GameTooltip:Hide()
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
        -- NOTE: This re-anchoring logic is causing issues with position persistence and restoration.
        -- Removing it allows the standard movable frame logic to hold the user's preferred anchor.
        
        -- local right = trackerFrame:GetRight()
        -- local top = trackerFrame:GetTop()
        -- if right and top then
        --      trackerFrame:ClearAllPoints()
        --      trackerFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
        -- end

        if addon.db.minimized then
            -- Minimized State: Only Maximize button visible
            -- Save current dimensions if not already small
            if trackerFrame:GetWidth() > 50 then
                 addon.db.savedWidth = trackerFrame:GetWidth()
                 addon.db.savedHeight = trackerFrame:GetHeight()
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
            if self.bonusFrame then self.bonusFrame:Hide() end
            
            -- Center button
            trackerFrame.minMaxBtn:ClearAllPoints()
            trackerFrame.minMaxBtn:SetPoint("CENTER", trackerFrame, "CENTER", 0, 0)
        else
            -- Restored State
            trackerFrame:SetSize(addon.db.savedWidth or 300, addon.db.savedHeight or 400)
            
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
            
            -- Reset button position
            trackerFrame.minMaxBtn:ClearAllPoints()
            trackerFrame.minMaxBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -5, 0)
            
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

-- Helper to create 1px border lines
local function CreateBorderLines(bar)
    if bar.border then return end
    
    -- Border (Using textures for 1px thickness)
    bar.border = CreateFrame("Frame", nil, bar)
    bar.border:SetPoint("TOPLEFT", -1, 1)
    bar.border:SetPoint("BOTTOMRIGHT", 1, -1)
    
    local function CreateLine(p) 
        local t = p:CreateTexture(nil, "BORDER") 
        t:SetColorTexture(1, 1, 1, 1) 
        return t 
    end
    
    bar.border.top = CreateLine(bar.border)
    bar.border.top:SetPoint("TOPLEFT")
    bar.border.top:SetPoint("TOPRIGHT")
    bar.border.top:SetHeight(1)
    
    bar.border.bottom = CreateLine(bar.border)
    bar.border.bottom:SetPoint("BOTTOMLEFT")
    bar.border.bottom:SetPoint("BOTTOMRIGHT")
    bar.border.bottom:SetHeight(1)
    
    bar.border.left = CreateLine(bar.border)
    bar.border.left:SetPoint("TOPLEFT")
    bar.border.left:SetPoint("BOTTOMLEFT")
    bar.border.left:SetWidth(1)
    
    bar.border.right = CreateLine(bar.border)
    bar.border.right:SetPoint("TOPRIGHT")
    bar.border.right:SetPoint("BOTTOMRIGHT")
    bar.border.right:SetWidth(1)
end

-- Update tracker display with trackables
function addon:RenderTrackableItem(parent, item, yOffset, indent)
    local db = self.db
    local button = self:GetOrCreateButton(parent)
    if button.expandBtn then button.expandBtn:Hide() end -- Hide expand button if recycled
    button:Show()
    
    -- Reset button point completely to avoid previous anchor persistence
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", indent, -yOffset)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -yOffset)
    
    -- POI Button logic
    local leftPadding = db.spacingPOIButton  -- Internal padding within the button for the icon check

     -- POI Button (Using Blizzard Template for authenticity)
    if not button.poiButton then
        -- Use POIButtonTemplate to get exact Blizzard look/behavior
        button.poiButton = CreateFrame("Button", nil, button, "POIButtonTemplate")
        button.poiButton:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 0) -- Nudged left
        button.poiButton:SetScale(0.75) -- Slightly smaller
        
        -- Override click handling to our logic
        button.poiButton:SetScript("OnClick", function(self)
             if self.questID then
                 -- Toggle super tracking
                 if C_SuperTrack.GetSuperTrackedQuestID() == self.questID then
                     C_SuperTrack.SetSuperTrackedQuestID(0)
                 else
                     C_SuperTrack.SetSuperTrackedQuestID(self.questID)
                 end
                 PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
             end
        end)
        
        button.poiButton:RegisterForClicks("LeftButtonUp")
    end
    
    -- Quest Item Button
    if item.item then
        local secureBtn = self:GetOrCreateSecureButton(button)
        secureBtn:ClearAllPoints()
        secureBtn:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, 0) -- Right aligned
        secureBtn:SetSize(18, 18) -- Slightly smaller
        secureBtn:SetAttribute("type", "item")
        secureBtn:SetAttribute("item", item.item.link)
        secureBtn.icon:SetTexture(item.item.texture)
        secureBtn:Show()
        button.itemButton = secureBtn
        
        -- Update Cooldown
        if secureBtn.cooldown then
            local start, duration, enable
            -- Try specific quest log cooldown first
            local logIndex = item.logIndex or C_QuestLog.GetLogIndexForQuestID(item.id)
            if logIndex then
                start, duration, enable = GetQuestLogSpecialItemCooldown(logIndex)
            end
            
            -- Fallback to standard item cooldown if needed
            if not start and item.item.link then
                local itemID = GetItemInfoInstant(item.item.link)
                if itemID then
                     start, duration, enable = C_Container.GetItemCooldown(itemID)
                end
            end
            
            if start and duration and (enable == 1 or enable == true) then
                secureBtn.cooldown:SetCooldown(start, duration)
            else
                secureBtn.cooldown:Hide()
            end
        end
        
        -- leftPadding is handled separately now as item is on the right
    else
        if button.itemButton then button.itemButton:Hide() end
    end

    -- Configure POI Button Appearance
    local isQuest = (item.type == "quest" or item.isWorldQuest or item.type == "supertrack")
    local superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
    
    if isQuest and POIButtonUtil then
        button.poiButton:Show()
        if button.icon then button.icon:Hide() end
        
        button.poiButton.questID = item.id
        if button.poiButton.SetQuestID then
            button.poiButton:SetQuestID(item.id)
        end
        
        local style = POIButtonUtil.Style.QuestInProgress
        if item.isComplete then
            style = POIButtonUtil.Style.QuestComplete
        elseif item.isWorldQuest then
            style = POIButtonUtil.Style.WorldQuest
        end

        if button.poiButton.SetStyle then
            button.poiButton:SetStyle(style)
        end
        
        if button.poiButton.UpdateButtonStyle then
            button.poiButton:UpdateButtonStyle()
        end
        
        -- Force selection if this is the Active Quest item, or if IDs match
        local isSelected = (item.id == superTrackedQuestID) or (item.type == "supertrack")
        
        if button.poiButton.SetSelected then
            button.poiButton:SetSelected(isSelected)
        end

        -- Ensure visual consistency for active state, forcing the glow if the template allows
        if button.poiButton.SelectionGlow then
            if isSelected then
                button.poiButton.SelectionGlow:Show()
            else
                button.poiButton.SelectionGlow:Hide()
            end
        end
        
         if leftPadding < db.spacingPOIButton then leftPadding = db.spacingPOIButton end

    else
        button.poiButton:Hide()
        if button.icon then button.icon:Hide() end
    end
    
    if not isQuest then
         leftPadding = db.spacingMinorHeaderIndent
    else
         leftPadding = db.spacingPOIButton
    end
    
    local rightPadding = -2
    if item.item then
        rightPadding = -22 -- Make room for item button
    end

    button.text:ClearAllPoints()
    button.text:SetPoint("TOPLEFT", leftPadding, -2) 
    button.text:SetPoint("TOPRIGHT", rightPadding, -2)

    local titleText = item.title
    if db.showQuestLevel and item.level and item.level > 0 then
        titleText = string.format("[%d] %s", item.level, titleText)
    end
    if db.showQuestType and item.questType then
        titleText = titleText .. " (" .. item.questType .. ")"
    end
    
    button.text:SetFont(db.fontFace, db.fontSize, db.fontOutline)
    local color = item.color or db.questColor
    if item.id == superTrackedQuestID then
       color = {r=1, g=0.82, b=0, a=1} -- Yellow for selected
    end
    button.text:SetTextColor(color.r, color.g, color.b, color.a)
    button.text:SetText(titleText)
    button.text:SetJustifyH("LEFT")
    button.text:SetWordWrap(true)
    
    button.bg:SetColorTexture(0, 0, 0, 0)
    
    -- Force width calculation for accurate multi-line height measurement
    -- If the button hasn't been laid out yet, GetStringHeight() returns 1 line height
    local parentWidth = parent:GetWidth() or 300
    local buttonWidth = parentWidth - indent - 5
    local textWidth = buttonWidth - leftPadding + rightPadding
    
    if textWidth > 0 then
        button.text:SetWidth(textWidth)
    end
    
    local textHeight = button.text:GetStringHeight()
    button.text:SetWidth(0) -- Release fixed width to allow anchors to work on resize
    local height = math.max(db.fontSize + 4, textHeight + 4)
    
    -- Objectives
    if item.objectives and #item.objectives > 0 then
        local currentY = -(textHeight + 2)
        
        for objIndex, obj in ipairs(item.objectives) do
            -- DEBUG: Log objective processing for bonus/tasks
            if addon.Log and (item.type == "bonus" or item.type == "quest" or item.type == "supertrack") then
                 addon:Log("Rendering Obj [%d] for '%s': Text='%s', Type='%s', Finished=%s, NumFul=%s, NumReq=%s", 
                     objIndex, item.title, tostring(obj.text), tostring(obj.type), tostring(obj.finished), tostring(obj.numFulfilled), tostring(obj.numRequired))
            end

            local objText = "  - " .. (obj.text or "")
            local isProgressBar = false
            local progressValue = 0
            local progressMax = 100
            
            -- Determine if this should be a progress bar
            -- Only use progress bars if explicitly set or if the text contains a percentage
            if obj.type == "progressbar" or (obj.text and string.find(obj.text, "%%")) then
                 isProgressBar = true
                 
                 -- Try to extract percent from text first (most accurate for raw percent bars)
                 local val = string.match(obj.text or "", "(%d+)%%")
                 
                 if val then
                     progressValue = tonumber(val)
                     progressMax = 100
                 elseif obj.numFulfilled and obj.numRequired and obj.numRequired > 0 then
                     -- Calculate percent from raw numbers
                     progressValue = obj.numFulfilled
                     progressMax = obj.numRequired
                 elseif obj.type == "progressbar" then
                      val = obj.numFulfilled 
                      progressValue = tonumber(val) or 0
                      progressMax = 100
                 end

                 -- Text Cleanup
                 local cleanText = obj.text or ""
                 cleanText = cleanText:gsub("%s*%(%d+%%%)", "") -- remove (45%)
                 cleanText = cleanText:gsub("%s*%d+%%", "")      -- remove 45%
                 cleanText = cleanText:gsub("^%d+/%d+%s*", "")   -- remove 0/100 at start
                 cleanText = cleanText:gsub(":%s*$", "")
                 cleanText = cleanText:gsub("^%s+", ""):gsub("%s+$", "")
                 
                 if cleanText == "" and obj.text then cleanText = obj.text:gsub("%s*%(%d+%%%)", "") end
                 objText = "  - " .. (cleanText or "Progress")
                 
            elseif obj.quantityString and obj.quantityString ~= "" then
                local cleanText = (obj.text or ""):gsub("^%d+/%d+%s*", "")
                cleanText = cleanText:gsub("^%s+", "")
                objText = string.format("  - %s %s", obj.quantityString, cleanText)
            elseif obj.numRequired and obj.numRequired > 0 then
                local cleanText = (obj.text or ""):gsub("^%d+/%d+%s*", "")
                cleanText = cleanText:gsub("^%s+", "")
                objText = string.format("  - %d/%d %s", obj.numFulfilled or 0, obj.numRequired, cleanText)
            end
            
            if not button.objectives then button.objectives = {} end
            local objLine = button.objectives[objIndex]
            if not objLine then
                objLine = button:CreateFontString(nil, "OVERLAY")
                button.objectives[objIndex] = objLine
            end
            
            objLine:SetWidth(button:GetWidth() - leftPadding - db.spacingObjectiveIndent - 5)
            objLine:SetWordWrap(true)
            objLine:ClearAllPoints()
            objLine:SetPoint("TOPLEFT", button, "TOPLEFT", leftPadding + db.spacingObjectiveIndent, currentY)
            objLine:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
            local objColor = obj.finished and db.completeColor or db.objectiveColor
            objLine:SetTextColor(objColor.r, objColor.g, objColor.b, objColor.a)
            objLine:SetText(objText)
            objLine:SetJustifyH("LEFT")
            objLine:Show()
            
            local lineH = objLine:GetStringHeight()
            currentY = currentY - (lineH + 2)
            height = height + (lineH + 2)

            if isProgressBar then
                if not button.progressBars then button.progressBars = {} end
                local bar = button.progressBars[objIndex]
                
                local padding = db.spacingProgressBarPadding or 0

                if not bar then
                    -- Use Blizzard Template (QuestProgressBarTemplate or QuestObjectiveProgressBarTemplate)
                    -- Check for standard templates implicitly by using them
                    -- We'll try "QuestObjectiveProgressBarTemplate" which is common in modern WoW
                    -- Fallback logic embedded within the object use
                    local pcallStatus, newBar = pcall(CreateFrame, "Frame", nil, button, "QuestObjectiveProgressBarTemplate")
                    
                    if pcallStatus and newBar then
                         bar = newBar
                         bar.isTemplate = true
                         if addon.Log then addon:Log("Created Bar Template. Has .Bar? %s", tostring(bar.Bar ~= nil)) end
                    else
                         -- Fallback to manual creation
                         bar = CreateFrame("StatusBar", nil, button)
                         bar:SetSize(1, 15)
                         bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                         bar.bg = bar:CreateTexture(nil, "BACKGROUND")
                         bar.bg:SetAllPoints()
                         bar.bg:SetColorTexture(0, 0, 0, 0.5)
                         
                         CreateBorderLines(bar)
     
                         bar.value = bar:CreateFontString(nil, "OVERLAY") 
                         bar.value:SetFont(db.fontFace, 9, "OUTLINE")
                         bar.value:SetPoint("CENTER")
                         bar.isTemplate = false
                    end
                    button.progressBars[objIndex] = bar
                end
                
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", button, "TOPLEFT", leftPadding + db.spacingObjectiveIndent, currentY - padding)
                bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", -db.spacingProgressBarInset, currentY - padding)
                
                local percent = 0
                if progressMax > 0 then
                    percent = math.floor((progressValue / progressMax) * 100)
                end
                local dispText = percent .. "%"

                if bar.isTemplate and bar.Bar then
                    bar.Bar:SetMinMaxValues(0, progressMax)
                    bar.Bar:SetValue(progressValue)
                    bar.Bar:SetStatusBarColor(0, 0.5, 1, 1)
                    if bar.Bar.Label then bar.Bar.Label:SetText(dispText) end
                elseif bar.SetMinMaxValues then
                    bar:SetHeight(15)
                    bar:SetMinMaxValues(0, progressMax)
                    bar:SetValue(progressValue)
                    bar:SetStatusBarColor(0, 0.5, 1, 1)
                    if bar.value then bar.value:SetText(dispText) end
                else
                    if addon.Log then addon:Log("Error: Invalid Bar Object - No .Bar and no SetMinMaxValues") end
                end
                
                bar:Show()

                local barH = 19
                currentY = currentY - barH - padding
                height = height + barH + padding
            elseif button.progressBars and button.progressBars[objIndex] then
                 button.progressBars[objIndex]:Hide()
            end
        end
        
        if button.objectives then
            for i = #item.objectives + 1, #button.objectives do button.objectives[i]:Hide() end
        end
        if button.progressBars then
             for i = #item.objectives + 1, #button.progressBars do button.progressBars[i]:Hide() end
        end
    else
        if button.objectives then for _, objLine in ipairs(button.objectives) do objLine:Hide() end end
        if button.progressBars then for _, bar in ipairs(button.progressBars) do bar:Hide() end end
    end
    
    if db.showDistance and item.distance and item.distance < 999999 then
        if not button.distance then button.distance = button:CreateFontString(nil, "OVERLAY") end
        button.distance:SetPoint("TOPRIGHT", button, "TOPRIGHT", -5, -2)
        button.distance:SetFont(db.fontFace, db.fontSize - 2, db.fontOutline)
        button.distance:SetTextColor(0.7, 0.7, 0.7, 1)
        button.distance:SetText(string.format("%.0f yds", item.distance))
        button.distance:Show()
    else
        if button.distance then button.distance:Hide() end
    end
    
    button:SetHeight(height)
    button:Show()
    button.trackableData = item
    
    button:SetScript("OnClick", function(self, mouseButton)
        addon:OnTrackableClick(self.trackableData, mouseButton)
    end)
    button:SetScript("OnMouseUp", nil)
    
    if db.showTooltips then
        button:SetScript("OnEnter", function(self)
            addon:ShowTrackableTooltip(self, self.trackableData)
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    return height
end

function addon:UpdateTrackerDisplay(trackables)
    if not trackerFrame or not contentFrame then
        return
    end
    
    if addon.Log then addon:Log("UpdateTrackerDisplay: Need to render %d items", #trackables) end

    -- Reset button pool
    activeButtons = 0
    
    -- Hide all buttons first
    for _, button in ipairs(trackableButtons) do
        button:Hide()
    end
    
    -- Hide safe secure buttons (can only be done out of combat)
    if not InCombatLockdown() then
        activeSecureButtons = 0
        for _, btn in ipairs(secureButtons) do
            btn:Hide()
        end
    end
    
    local db = self.db
    
    -- Extract Scenarios and Super Tracked items first
    local scenarios = {}
    local autoQuests = {}
    local superTrackedItems = {}
    local bonusObjectives = {}
    local remainingTrackables = {}
    
    for _, item in ipairs(trackables) do
        if item.type == "scenario" then
            table.insert(scenarios, item)
        elseif item.type == "autoquest" then
            table.insert(autoQuests, item)
        elseif item.type == "supertrack" then
            table.insert(superTrackedItems, item)
        elseif item.type == "bonus" then
            table.insert(bonusObjectives, item)
        else
            table.insert(remainingTrackables, item)
        end
    end
    
    if addon.Log then addon:Log("Scenarios: %d | Bonus: %d | Remaining: %d", #scenarios, #bonusObjectives, #remainingTrackables) end
    
    self.currentScenarios = scenarios
    trackables = remainingTrackables
    
    -- Group trackables if needed
    if db.groupByZone or db.groupByCategory then
        trackables = self:OrganizeTrackables(trackables)
    end
    
    local superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()

    -- Render Auto Quests with native Blizzard text when possible
    if #autoQuests > 0 then
         -- Determine vertical offset
         local autoQuestFrame = self.autoQuestFrame
         local currentY = 0
         
         for _, item in ipairs(autoQuests) do
              local button = self:GetOrCreateButton(autoQuestFrame)
              
              -- Reset
              button:ClearAllPoints()
              button:SetPoint("TOPLEFT", autoQuestFrame, "TOPLEFT", 5, -currentY)
              button:SetPoint("TOPRIGHT", autoQuestFrame, "TOPRIGHT", -5, -currentY)
              button:Show()
              
              -- Hide unnecessary components
              if button.poiButton then button.poiButton:Hide() end
              if button.itemButton then button.itemButton:Hide() end
              if button.objectives then for _, obj in ipairs(button.objectives) do obj:Hide() end end
              if button.progressBars then for _, bar in ipairs(button.progressBars) do bar:Hide() end end
              if button.expandBtn then button.expandBtn:Hide() end
              if button.stageBox then button.stageBox:Hide() end
              if button.distance then button.distance:Hide() end
              button.bg:SetColorTexture(0, 0, 0, 0)
              
              -- Styled Backdrop (Gold/Yellow Border)
              if not button.popupBackdrop then
                   button.popupBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
                   button.popupBackdrop:SetBackdrop({
                        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 16,
                        insets = { left = 4, right = 4, top = 4, bottom = 4 }
                   })
                   button.popupBackdrop:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                   button.popupBackdrop:SetBackdropBorderColor(1, 0.8, 0, 1) -- Gold Border
                   button.popupBackdrop:SetPoint("TOPLEFT", 0, 0)
                   button.popupBackdrop:SetPoint("BOTTOMRIGHT", 0, 0)
                   button.popupBackdrop:SetFrameLevel(button:GetFrameLevel()) 
              end
              button.popupBackdrop:Show()
              
              -- 3. Icon (Large, Left)
              if not button.largeIcon then
                   -- Container
                   button.largeIcon = CreateFrame("Frame", nil, button)
                   button.largeIcon:SetSize(60, 60)
                   button.largeIcon:SetPoint("LEFT", 0, 0)
                   
                   -- 3a. Background
                   button.largeIcon.Bg = button.largeIcon:CreateTexture(nil, "BACKGROUND")
                   button.largeIcon.Bg:SetTexture(404985)
                   button.largeIcon.Bg:SetTexCoord(0.302734375, 0.419921875, 0.015625, 0.953125)
                   button.largeIcon.Bg:SetAllPoints()

                   -- 3b. Symbol (! or ?)
                   button.largeIcon.Symbol = button.largeIcon:CreateTexture(nil, "ARTWORK")
                   button.largeIcon.Symbol:SetSize(19, 33)
                   button.largeIcon.Symbol:SetPoint("CENTER", 0, 0)
                   button.largeIcon.Symbol:SetTexture(404985)
                   
                   -- 3c. Shine
                   button.largeIcon.Shine = button.largeIcon:CreateTexture(nil, "OVERLAY")
                   button.largeIcon.Shine:SetTexture("Interface\\ItemSocketingFrame\\UI-ItemSockets-GoldShine")
                   button.largeIcon.Shine:SetBlendMode("ADD")
                   button.largeIcon.Shine:SetAllPoints()
                   button.largeIcon.Shine:SetAlpha(0.8)

                   -- 3d. Red Flash
                   button.largeIcon.Flash = button.largeIcon:CreateTexture(nil, "OVERLAY")
                   button.largeIcon.Flash:SetTexture(404985)
                   button.largeIcon.Flash:SetTexCoord(0.216796875, 0.298828125, 0.015625, 0.671875)
                   button.largeIcon.Flash:SetVertexColor(1, 0, 0, 0.498) 
                   button.largeIcon.Flash:SetBlendMode("ADD")
                   button.largeIcon.Flash:SetSize(42, 42)
                   button.largeIcon.Flash:SetPoint("CENTER", 0, 0)
                   
                   -- 3e. Pulse Animation
                   button.largeIcon.Flash.AnimGroup = button.largeIcon.Flash:CreateAnimationGroup()
                   button.largeIcon.Flash.AnimGroup:SetLooping("BOUNCE")
                   local alphaAnim = button.largeIcon.Flash.AnimGroup:CreateAnimation("Alpha")
                   alphaAnim:SetFromAlpha(0.1)
                   alphaAnim:SetToAlpha(1)
                   alphaAnim:SetDuration(1.0)
                   alphaAnim:SetSmoothing("IN_OUT")
              end
              button.largeIcon:Show()
              button.largeIcon.Flash.AnimGroup:Play()
              
              if item.popUpType == "COMPLETE" then
                   button.largeIcon.Symbol:SetTexCoord(0.17578125, 0.212890625, 0.015625, 0.53125)
              else
                   button.largeIcon.Symbol:SetTexCoord(0.134765625, 0.171875, 0.015625, 0.53125)
              end
              
              -- 4. Text (Two lines)
              button.text:ClearAllPoints()
              button.text:SetPoint("TOPLEFT", button.largeIcon, "TOPRIGHT", 10, -18)
              button.text:SetPoint("TOPRIGHT", -5, -18)
              button.text:SetFont(db.fontFace, db.fontSize + 1, db.fontOutline)
              button.text:SetTextColor(1, 0.82, 0, 1) -- Gold
              
              local topText = (item.popUpType == "COMPLETE") and "Click to complete quest" or "New Quest Available"
              button.text:SetText(topText)
              button.text:SetJustifyH("LEFT")
              
              if not button.subText then
                   button.subText = button:CreateFontString(nil, "OVERLAY")
              end
              button.subText:SetFont(db.fontFace, db.fontSize + 2, db.fontOutline)
              button.subText:SetTextColor(1, 1, 1, 1)
              button.subText:SetPoint("TOPLEFT", button.text, "BOTTOMLEFT", 0, -2)
              button.subText:SetPoint("TOPRIGHT", button.text, "BOTTOMRIGHT", 0, -2)
              button.subText:SetText(item.title)
              button.subText:SetJustifyH("LEFT")
              button.subText:Show()
              
              button.height = 70 -- Larger hit area
              button:SetHeight(70)
              
              -- Interaction
              button.trackableData = item
              button:SetScript("OnClick", function(self, mouseButton)
                  addon:OnTrackableClick(self.trackableData, mouseButton)
              end)
              
              currentY = currentY + 70 + 5
         end
         
         autoQuestFrame:SetHeight(currentY)
         autoQuestFrame:Show()
    else
         self.autoQuestFrame:SetHeight(1)
         self.autoQuestFrame:Hide()
    end

    --------------------------------------------------------------------------
    -- 0. Render Widgets (Power Bars, PvP Bars)
    --------------------------------------------------------------------------
    local widgetContainer = ObjectiveTrackerUIWidgetContainer
    local widgetHeight = 0
    
    if self.widgetFrame then  -- Safety Check
        if widgetContainer then
             -- Use pcall to prevent taint/secure errors from crashing execution
             local status, err = pcall(function()
                -- Reparent to our dedicated frame
                if widgetContainer:GetParent() ~= self.widgetFrame then
                    widgetContainer:SetParent(self.widgetFrame)
                    widgetContainer:SetFrameStrata("HIGH")
                end
                
                -- Force re-anchoring
                widgetContainer:ClearAllPoints()
                widgetContainer:SetPoint("TOP", self.widgetFrame, "TOP", 0, -5)
                
                widgetContainer:Show()
             end)
             
             if not status and addon.Log then
                  addon:Log("Widget Reparent Error: %s", tostring(err))
             end
            
            -- Calculate height
            widgetHeight = widgetContainer:GetHeight() or 0
            
            -- Ignore negligible height (often ghost frames)
            if widgetHeight < 2 then widgetHeight = 0 end

            if addon.Log then addon:Log("Widget Layout: H=%s", widgetHeight) end
        end
        
        -- Exact height if content exists, otherwise 1px
        local finalWidgetH = (widgetHeight > 0) and (widgetHeight + 5) or 1
        self.widgetFrame:SetHeight(finalWidgetH)

        -- Dynamic Anchoring to remove gaps
        if self.autoQuestFrame then
             local aqVisible = (self.autoQuestFrame:GetHeight() > 10)
             -- Use 0 padding if not visible, standard -5 if visible
             local padding = aqVisible and -5 or 0
             self.widgetFrame:ClearAllPoints()
             self.widgetFrame:SetPoint("TOPLEFT", self.autoQuestFrame, "BOTTOMLEFT", 0, padding)
             self.widgetFrame:SetPoint("TOPRIGHT", self.autoQuestFrame, "BOTTOMRIGHT", 0, padding)
        end
    else
         if addon.Log then addon:Log("CRITICAL: self.widgetFrame is missing in UpdateTrackerDisplay") end
    end
    
    -- Dynamic Anchoring for Scenario Frame
    if self.scenarioFrame and self.widgetFrame then
          local widgetVisible = (self.widgetFrame:GetHeight() > 2)
          local padding = widgetVisible and -5 or 0
          self.scenarioFrame:ClearAllPoints()
          -- Use a tighter anchor
          self.scenarioFrame:SetPoint("TOPLEFT", self.widgetFrame, "BOTTOMLEFT", 0, padding)
          self.scenarioFrame:SetPoint("TOPRIGHT", self.widgetFrame, "BOTTOMRIGHT", 0, padding)
     end
    
    --------------------------------------------------------------------------
    -- 1. Render Scenarios (Sticky Header) - USING BLIZZARD FRAME
    --------------------------------------------------------------------------
    
    -- Check if we are in a Scenario and have the Blizzard frame available
    local scenarioTracker = ScenarioObjectiveTracker
    local useBlizzardScenario = (C_Scenario.IsInScenario() and scenarioTracker and scenarioTracker.ContentsFrame)
    
    local scenarioHeight = 0
    local scenarioYOffset = 0 -- Start at 0 relative to scenarioFrame
    
    if useBlizzardScenario then
         -- We are using Blizzard's frame, so we hijack it.
         local contents = scenarioTracker.ContentsFrame
         
         -- DEBUG: Print status
         if addon.Log then addon:Log("Blizzard Scenario Frame Found. Parent: %s | Height: %s | Visible: %s", 
             tostring(contents:GetParent():GetName()), tostring(contents:GetHeight()), tostring(contents:IsVisible())) 
         end
         
         -- Parent it to our frame
         if contents:GetParent() ~= self.scenarioFrame then
              contents:SetParent(self.scenarioFrame)
              -- FORCE STRATA: The user screenshot showed LOW, but our frame is MEDIUM.
              -- We must bring it up to at least MEDIUM or HIGH to be seen on top of our bg.
              contents:SetFrameStrata("HIGH") 
              contents:SetFrameLevel(100)
         end
         
         -- Clear points and set to top-center of our container
         contents:ClearAllPoints()
         contents:SetPoint("TOP", self.scenarioFrame, "TOP", -20, -5)
         -- Constrain width so it fits our frame (and forces word wrap if supported)
         contents:SetWidth(self.db.frameWidth - 5)
         
         contents:Show()
         
         -- Attempt to find internal WidgetContainer and force show it
         if contents.WidgetContainer then
             contents.WidgetContainer:Show()
             if addon.Log then addon:Log("WidgetContainer: Vis=%s | Height=%s", 
                 tostring(contents.WidgetContainer:IsVisible()), tostring(contents.WidgetContainer:GetHeight())) 
             end
         end
         
         -- Try to force update safely
         if scenarioTracker.Update then
             local status, err = pcall(function() scenarioTracker:Update() end)
             if not status and addon.Log then
                 addon:Log("Blizzard Update Failed: %s", tostring(err))
             end
         end

         -- The height of the blizzard frame varies. We need to update our container to match it.
         local blizzardHeight = contents:GetHeight()
         
         -- If height is 0 (collapsed/hidden), force a minimum reasonable height so widgets aren't crushed
         if not blizzardHeight or blizzardHeight < 40 then 
             blizzardHeight = 100 
             contents:SetHeight(blizzardHeight) -- Force the frame open
         end
         
         scenarioHeight = blizzardHeight
         scenarioYOffset = scenarioHeight + 30 -- Increase padding to prevent overlap with headers
         
         if addon.Log then addon:Log("Scenario Final Layout: Height=%s | YOffset=%s", scenarioHeight, scenarioYOffset) end
         
    elseif self.currentScenarios and #self.currentScenarios > 0 then
        -- Manual rendering fallback
        local header = self:GetOrCreateButton(self.scenarioFrame) -- Use scenarioFrame as parent
        header:SetPoint("TOPLEFT", self.scenarioFrame, "TOPLEFT", 0, -scenarioYOffset)
        header:SetPoint("TOPRIGHT", self.scenarioFrame, "TOPRIGHT", 0, -scenarioYOffset)
        
        header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
        header.text:SetTextColor(db.headerColor.r, db.headerColor.g, db.headerColor.b, db.headerColor.a)
        header.text:SetText("Scenario / Dungeon")
        header.text:SetJustifyH("LEFT")
        
        -- Hide the expand/collapse button for scenarios
        if header.expandBtn then
             header.expandBtn:Hide()
        end
        -- Reset text position since there is no icon
        header.text:ClearAllPoints()
        header.text:SetPoint("LEFT", 5, 0)
        header.text:SetPoint("RIGHT", -5, 0)
        
        header.bg:SetColorTexture(0, 0, 0, 0.4)
        header:SetHeight(24)
        header:Show()
        
        -- Cleanup header parts
        if header.poiButton then header.poiButton:Hide() end
        if header.itemButton then header.itemButton:Hide() end
        if header.icon then header.icon:Hide() end
        if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
        
        scenarioYOffset = scenarioYOffset + 26
        
        -- Render Scenario Content
        for _, item in ipairs(self.currentScenarios) do
              local button = self:GetOrCreateButton(self.scenarioFrame)
              button:SetPoint("TOPLEFT", self.scenarioFrame, "TOPLEFT", 5, -scenarioYOffset)
              button:SetPoint("TOPRIGHT", self.scenarioFrame, "TOPRIGHT", -5, -scenarioYOffset)
              
              -- Setup Button Appearance (Copied from below logic)
              button.text:SetFont(db.fontFace, db.fontSize + 2, db.fontOutline) -- Slightly larger for Scenario Title
              local color = item.color or {r=1, g=1, b=1, a=1}
              button.text:SetTextColor(color.r, color.g, color.b, color.a)
              button.text:SetText(item.title)
              button.text:SetPoint("TOPLEFT", 5, -2) -- Simple padding
              button.bg:SetColorTexture(0, 0, 0, 0)
              
              if button.poiButton then button.poiButton:Hide() end
              if button.itemButton then button.itemButton:Hide() end
              
              local height = db.fontSize + 6

              -- Stage Box (New)
              if item.stageName then
                 if not button.stageBox then
                    -- Create the container
                    button.stageBox = CreateFrame("Frame", nil, button, "BackdropTemplate")
                    button.stageBox:SetBackdrop({
                        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 16,
                        insets = { left = 4, right = 4, top = 4, bottom = 4 }
                    })
                    button.stageBox:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
                    button.stageBox:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
                    
                    button.stageBox.text = button.stageBox:CreateFontString(nil, "OVERLAY")
                    button.stageBox.text:SetPoint("CENTER")
                 end
                 
                 button.stageBox:SetPoint("TOPLEFT", button, "TOPLEFT", 10, -height)
                 button.stageBox:SetPoint("TOPRIGHT", button, "TOPRIGHT", -10, -height)
                 button.stageBox.text:SetFont(db.headerFontFace, db.fontSize + 4, db.headerFontOutline)
                 button.stageBox.text:SetText(item.stageName)
                 button.stageBox:SetHeight(30)
                 button.stageBox:Show()
                 
                 height = height + 35
              elseif button.stageBox then
                 button.stageBox:Hide()
              end
              
              -- Objectives
               if item.objectives and #item.objectives > 0 then
                    for objIndex, obj in ipairs(item.objectives) do
                        -- Filter unwanted "Progress" objective 
                        if obj.text == "Progress" then
                             if button.objectives and button.objectives[objIndex] then button.objectives[objIndex]:Hide() end
                             if button.progressBars and button.progressBars[objIndex] then button.progressBars[objIndex]:Hide() end
                        else
                        local objText = "  - " .. obj.text
                        local isProgressBar = false
                        local progressValue = 0
                        local progressMax = 100
                        local progressText = ""

                        -- Determine if it's a ProgressBar criteria
                        -- Bit 1 (value 1) is usually ShowProgressBar. 
                        local flags = obj.flags or 0
                        local hasProgressBarFlag = bit.band(flags, 1) == 1
                        
                        -- Relaxed Check: If quantityString has '%', force it to be a progress bar
                        -- This catches cases where the flag is missing but the intent is clear
                        if obj.quantityString and string.find(obj.quantityString, "%%") then
                             hasProgressBarFlag = true
                        end
                        
                        -- Do not show progress bars if quest or objective is complete
                        local isObjComplete = obj.finished or (obj.numRequired and obj.numRequired > 0 and obj.numFulfilled and obj.numFulfilled >= obj.numRequired)
                        if item.isComplete or isObjComplete then
                             hasProgressBarFlag = false
                        end

                        if hasProgressBarFlag then
                             isProgressBar = true
                             
                             -- Simplified Percentage Logic
                             local percent = 0
                             local foundPercent = false
                             
                             -- 1. Trust explicitly provided string percentages (e.g. "67%")
                             if obj.quantityString then
                                 local val = string.match(obj.quantityString, "(%d+)%%")
                                 if val then
                                     local v = tonumber(val)
                                     -- Sanity Check: If the string says "136%", it's likely Points, not Percent.
                                     -- Most ProgressBars shouldn't exceed 100%.
                                     if v <= 100 then
                                         percent = v
                                         foundPercent = true
                                     end
                                 end
                             end
                             
                             -- 2. If no valid string percentage found...
                             if not foundPercent then
                                 -- Check if numFulfilled looks like a percentage (0-100) while totalQuantity is "Points" (>100)
                                 -- Case: Num=85, Req=160. String="136%".
                                 if (obj.numRequired and obj.numRequired > 100) and (obj.numFulfilled and obj.numFulfilled <= 100) then
                                     percent = obj.numFulfilled
                                 else
                                     -- Standard calculation: 5/10 = 50%
                                     local cur = obj.numFulfilled or 0
                                     local req = obj.numRequired or 0
                                     
                                     if req > 0 then
                                         percent = (cur / req) * 100
                                     else
                                         percent = cur
                                     end
                                 end
                             end
                             
                             -- 3. Clamp and Display
                             if percent > 100 then percent = 100 end
                             if percent < 0 then percent = 0 end
                             
                             -- If calculated percent is 100% (or more), treat as complete and hide bar
                             if percent >= 100 then
                                isProgressBar = false
                             end
                             
                             progressValue = percent
                             progressMax = 100
                             progressText = string.format("%d%%", math.floor(percent))
                            
                             objText = "  - " .. obj.text
                        elseif obj.numRequired and obj.numRequired > 0 then
                             if not foundPercent then
                                 local cur = obj.numFulfilled or 0
                                 local req = obj.numRequired or 0
                                 
                                 if req > 0 then
                                     percent = (cur / req) * 100
                                 elseif cur <= 100 then
                                     percent = cur
                                 else
                                     percent = 100
                                 end
                             end
                             
                             -- 3. Clamp and Display
                             -- Ensure we stay within 0-100 visual range
                             if percent > 100 then percent = 100 end
                             if percent < 0 then percent = 0 end
                             
                             progressValue = percent
                             progressMax = 100
                             progressText = string.format("%d%%", math.floor(percent))
                            
                             objText = "  - " .. obj.text
                        elseif obj.quantityString and obj.quantityString ~= "" then
                             -- Fallback if numRequired is 0 but we have a quantity string (common in some scenarios)
                             objText = string.format("  - %s: %s", obj.text, obj.quantityString)
                        end
                         
                        if not button.objectives then button.objectives = {} end

                        
                        -- Ensure Text Line Exists
                        local objLine = button.objectives[objIndex]
                        if not objLine then
                            objLine = button:CreateFontString(nil, "OVERLAY")
                            button.objectives[objIndex] = objLine
                        end
                        
                        objLine:SetParent(button)
                        objLine:SetPoint("TOPLEFT", button.text, "BOTTOMLEFT", 0, -(height - (db.fontSize + 4))) -- anchor relative to accumulated height
                        objLine:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
                        local objColor = obj.finished and db.completeColor or db.objectiveColor
                        objLine:SetTextColor(objColor.r, objColor.g, objColor.b, objColor.a)
                        objLine:SetText(objText)
                        objLine:SetJustifyH("LEFT")
                        objLine:Show()
                        
                        height = height + (db.fontSize + 2)
                        
                        -- Progress Bar Handling
                        if isProgressBar then
                            if not button.progressBars then button.progressBars = {} end
                            local bar = button.progressBars[objIndex]
                            if not bar then
                                local pcallStatus, newBar = pcall(CreateFrame, "Frame", nil, button, "QuestObjectiveProgressBarTemplate")
                                if pcallStatus and newBar then
                                    bar = newBar
                                    bar.isTemplate = true
                                else
                                    bar = CreateFrame("StatusBar", nil, button)
                                    bar:SetSize(1, 21) 
                                    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                                    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
                                    bar.bg:SetAllPoints()
                                    bar.bg:SetColorTexture(0, 0, 0, 0.5)
                                    
                                    bar.value = bar:CreateFontString(nil, "OVERLAY")
                                    bar.value:SetFont(db.fontFace, 10, "OUTLINE")
                                    bar.value:SetPoint("CENTER")
                                    
                                    bar.border = CreateFrame("Frame", nil, bar)
                                    bar.border:SetPoint("TOPLEFT", -1, 1)
                                    bar.border:SetPoint("BOTTOMRIGHT", 1, -1)
                                    
                                    local function CreateLine(p) local t = p:CreateTexture(nil, "BORDER") t:SetColorTexture(1, 1, 1, 1) return t end
                                    bar.border.top = CreateLine(bar.border)
                                    bar.border.top:SetPoint("TOPLEFT")
                                    bar.border.top:SetPoint("TOPRIGHT")
                                    bar.border.top:SetHeight(1)
                                    
                                    bar.border.bottom = CreateLine(bar.border)
                                    bar.border.bottom:SetPoint("BOTTOMLEFT")
                                    bar.border.bottom:SetPoint("BOTTOMRIGHT")
                                    bar.border.bottom:SetHeight(1)
                                    
                                    bar.border.left = CreateLine(bar.border)
                                    bar.border.left:SetPoint("TOPLEFT")
                                    bar.border.left:SetPoint("BOTTOMLEFT")
                                    bar.border.left:SetWidth(1)
                                    
                                    bar.border.right = CreateLine(bar.border)
                                    bar.border.right:SetPoint("TOPRIGHT")
                                    bar.border.right:SetPoint("BOTTOMRIGHT")
                                    bar.border.right:SetWidth(1)
                                    bar.isTemplate = false
                                end
                                button.progressBars[objIndex] = bar
                            end
                            
                            bar:ClearAllPoints()
                            bar:SetPoint("TOPLEFT", 20, -height)
                            bar:SetPoint("TOPRIGHT", -20, -height)
                            
                            if bar.isTemplate and bar.Bar then
                                 bar.Bar:SetMinMaxValues(0, progressMax)
                                 bar.Bar:SetValue(progressValue)
                                 bar.Bar:SetStatusBarColor(0, 0.5, 1, 1)
                                 if bar.Bar.Label then bar.Bar.Label:SetText(progressText) end
                            else
                                bar:SetHeight(21)
                                bar:SetMinMaxValues(0, progressMax)
                                bar:SetValue(progressValue)
                                bar:SetStatusBarColor(0, 0.5, 1, 1) 
                                if bar.value then bar.value:SetText(progressText) end
                            end
                            
                            bar:Show()
                            height = height + 25
                        elseif button.progressBars and button.progressBars[objIndex] then
                             button.progressBars[objIndex]:Hide()
                        end
                        end -- End of skip check
                    end
                    
                    -- Start hiding unused bars
                    if button.progressBars then
                         for i = #item.objectives + 1, #button.progressBars do
                             button.progressBars[i]:Hide()
                         end
                    end
               end
               
               button:SetHeight(height + 4)
               button:Show()
               scenarioYOffset = scenarioYOffset + height + 8
        end
    end
    
    
    -- Render Super Tracked Items (Pinned)
    if #superTrackedItems > 0 then
         -- Add Header if scenarios exist or just to separate
         if scenarioYOffset > 0 then
              scenarioYOffset = scenarioYOffset + 10
         end

         local header = self:GetOrCreateButton(self.scenarioFrame)
         header:SetPoint("TOPLEFT", self.scenarioFrame, "TOPLEFT", 0, -scenarioYOffset)
         header:SetPoint("TOPRIGHT", self.scenarioFrame, "TOPRIGHT", 0, -scenarioYOffset)
         
         header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
         header.text:SetTextColor(1, 0.82, 0, 1) -- Gold
         header.text:SetText("Active Quest")
         header.text:SetJustifyH("LEFT")
         
         if header.expandBtn then header.expandBtn:Hide() end
         header.text:ClearAllPoints()
         header.text:SetPoint("LEFT", 5, 0)
         header.text:SetPoint("RIGHT", -5, 0)
         
         -- Create or show styled backdrop (Scenario Stage Box style)
         if not header.styledBackdrop then
             header.styledBackdrop = CreateFrame("Frame", nil, header, "BackdropTemplate")
             -- Note: Anchors are set below to accommodate dynamic content height
             
             -- Ensure backdrop is behind the text (which is a region of header)
             -- We need header to be at least level 2 to safely put this at level - 1 relative to it?
             -- Actually, simple SetFrameStrata("BACKGROUND") might be safer if header is LOW/MEDIUM
             if header:GetFrameLevel() > 1 then
                 header.styledBackdrop:SetFrameLevel(header:GetFrameLevel() - 1)
             else
                 header.styledBackdrop:SetFrameLevel(1)
                 header:SetFrameLevel(2)
             end
             
             header.styledBackdrop:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 }
             })
             header.styledBackdrop:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
             header.styledBackdrop:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
         end
         
         -- Configure Backdrop Anchors (covering Header + Items)
         header.styledBackdrop:ClearAllPoints()
         header.styledBackdrop:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
         header.styledBackdrop:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
         -- Bottom/Height will be set after item loop
         
         header.styledBackdrop:Show()
         header.bg:SetColorTexture(0, 0, 0, 0) -- Hide default flat bg
         
         header:SetHeight(30)
         header:Show()
         
         -- Cleanup header parts
         if header.poiButton then header.poiButton:Hide() end
         if header.itemButton then header.itemButton:Hide() end
         if header.icon then header.icon:Hide() end
         if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
         if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end

         -- Capture start Y for backdrop calculation (This is the top of the header)
         local activeQuestStartY = scenarioYOffset
         scenarioYOffset = scenarioYOffset + 30 -- Advance past header height

         for _, item in ipairs(superTrackedItems) do
            local height = self:RenderTrackableItem(self.scenarioFrame, item, scenarioYOffset, db.spacingMinorHeaderIndent + 10)
            scenarioYOffset = scenarioYOffset + height + db.spacingItemVertical
         end

         -- Update backdrop height to cover items
         -- Total height is current cursor - startY
         local totalHeight = scenarioYOffset - activeQuestStartY
         -- Add a bit of padding at the bottom for aesthetics
         if totalHeight < 30 then totalHeight = 30 end -- Minimum height
         header.styledBackdrop:SetHeight(totalHeight + 5)
    end
    
    --------------------------------------------------------------------------
    -- 1.5 Render Bonus Objectives (Pinned to Bottom)
    --------------------------------------------------------------------------
    local bonusYOffset = 0
    
    -- Strategy: Hijack Blizzard's BonusObjectiveTracker frame if it exists and has content
    local bonusTracker = BonusObjectiveTracker
    local useBlizzardBonus = (bonusTracker and bonusTracker.ContentsFrame)
    
    if addon.Log then
         addon:Log("Checking BonusTracker: Exists=%s | ContentsFrame=%s", 
             tostring(bonusTracker ~= nil), 
             tostring(bonusTracker and bonusTracker.ContentsFrame ~= nil))
    end
    
    if useBlizzardBonus then
         local contents = bonusTracker.ContentsFrame
         local blizzardBonusHeight = contents:GetHeight() or 0
         local hasContent = blizzardBonusHeight > 1 and contents:IsVisible()
         
         -- Also check if there are actual child frames with bars
         if not hasContent then
             -- ContentsFrame might report height but children are individually visible
             for _, child in pairs({contents:GetChildren()}) do
                 if child:IsVisible() and child:GetHeight() > 1 then
                     hasContent = true
                     blizzardBonusHeight = math.max(blizzardBonusHeight, 10) -- Will recalculate below
                     break
                 end
             end
         end
         
         if addon.Log then 
              addon:Log("BonusObjectiveTracker: Vis=%s | Height=%s | HasContent=%s | Parent=%s", 
                  tostring(contents:IsVisible()), tostring(blizzardBonusHeight), tostring(hasContent),
                  contents:GetParent() and contents:GetParent():GetName() or "nil")
         end
         
         if hasContent then
              -- Reparent to our bonusFrame
              local status, err = pcall(function()
                  if contents:GetParent() ~= self.bonusFrame then
                       contents:SetParent(self.bonusFrame)
                       contents:SetFrameStrata("HIGH")
                       contents:SetFrameLevel(100)
                  end
                  
                  contents:ClearAllPoints()
                   contents:ClearAllPoints()
                   contents:SetPoint("TOP", self.bonusFrame, "TOP", 0, -5)
                   contents:SetWidth(self.db.frameWidth - 10)
                   contents:Show()

                   -- Force update if module exists
                   if bonusTracker.Update then bonusTracker:Update() end
              end)
              
              if not status and addon.Log then
                   addon:Log("BonusObjectiveTracker Reparent Error: %s", tostring(err))
              end
              
              -- Recalculate height after reparenting (layout may have changed)
              blizzardBonusHeight = contents:GetHeight() or 0
              if blizzardBonusHeight < 20 then blizzardBonusHeight = 60 end -- Minimum if we know there's content
              
              bonusYOffset = blizzardBonusHeight + 10
              
              if addon.Log then addon:Log("Bonus Blizzard Frame: Final H=%s", blizzardBonusHeight) end
         else
              -- No bonus content - restore to its original parent if we stole it
              if contents:GetParent() == self.bonusFrame then
                   pcall(function()
                       contents:SetParent(bonusTracker)
                       contents:ClearAllPoints()
                       contents:SetPoint("TOPLEFT", bonusTracker, "TOPLEFT", 0, 0)
                   end)
              end
         end
    end
    
    -- Fallback: Manually render bonus items if we collected any and Blizzard frame isn't available
    if bonusYOffset == 0 and db.showBonusObjectives and #bonusObjectives > 0 then
         -- Render Header (Bonus Objective)
         local header = self:GetOrCreateButton(self.bonusFrame)
         header:SetPoint("TOPLEFT", self.bonusFrame, "TOPLEFT", 0, -bonusYOffset)
         header:SetPoint("TOPRIGHT", self.bonusFrame, "TOPRIGHT", 0, -bonusYOffset)
         
         header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
         -- Use header color or specific bonus color
         local bonusColor = db.bonusColor or {r=1,g=1,b=1,a=1}
         header.text:SetTextColor(bonusColor.r, bonusColor.g, bonusColor.b, bonusColor.a)
         header.text:SetText("Bonus Objective")
         header.text:SetJustifyH("LEFT")
         
         if header.expandBtn then header.expandBtn:Hide() end
         header.text:ClearAllPoints()
         header.text:SetPoint("LEFT", 5, 0)
         header.text:SetPoint("RIGHT", -5, 0)

         -- Reuse Styling Logic from Active Quest (Backdrop)
         if not header.styledBackdrop then
             header.styledBackdrop = CreateFrame("Frame", nil, header, "BackdropTemplate")
             -- Ensure backdrop is behind the text
             if header:GetFrameLevel() > 1 then
                 header.styledBackdrop:SetFrameLevel(header:GetFrameLevel() - 1)
             else
                 header.styledBackdrop:SetFrameLevel(1)
                 header:SetFrameLevel(2)
             end
             
             header.styledBackdrop:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 }
             })
             header.styledBackdrop:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
             header.styledBackdrop:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
         end
         
         header.styledBackdrop:ClearAllPoints()
         header.styledBackdrop:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
         header.styledBackdrop:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
         
         header.styledBackdrop:Show()
         header.bg:SetColorTexture(0, 0, 0, 0) 
         header:SetHeight(30)
         header:Show()
         
         -- Cleanup 
         if header.poiButton then header.poiButton:Hide() end
         if header.itemButton then header.itemButton:Hide() end
         if header.icon then header.icon:Hide() end
         if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
         if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end

         local bonusStartY = bonusYOffset
         bonusYOffset = bonusYOffset + 30 
         
         for _, item in ipairs(bonusObjectives) do
            local height = self:RenderTrackableItem(self.bonusFrame, item, bonusYOffset, db.spacingMinorHeaderIndent + 10)
            bonusYOffset = bonusYOffset + height + db.spacingItemVertical
         end

         local totalHeight = bonusYOffset - bonusStartY
         if totalHeight < 30 then totalHeight = 30 end
         header.styledBackdrop:SetHeight(totalHeight + 5)
    end
    
    -- Update Bonus Frame Height
    if bonusYOffset > 0 then
        self.bonusFrame:SetHeight(bonusYOffset)
        self.bonusFrame:Show()
    else
        self.bonusFrame:Hide()
    end

    -- Update Scenario Frame Height & ScrollFrame Anchor
    self.scrollFrame:ClearAllPoints()
    if scenarioYOffset > 0 then
        self.scenarioFrame:SetHeight(scenarioYOffset)
        self.scenarioFrame:Show()
        self.scrollFrame:SetPoint("TOPLEFT", self.scenarioFrame, "BOTTOMLEFT", 0, 0)
    else
        self.scenarioFrame:Hide()
        self.scrollFrame:SetPoint("TOPLEFT", self.trackerFrame, "TOPLEFT", 0, -25)
    end
    
    if bonusYOffset > 0 then
         self.scrollFrame:SetPoint("BOTTOMRIGHT", self.bonusFrame, "TOPRIGHT", 0, 0)
    else
         self.scrollFrame:SetPoint("BOTTOMRIGHT", self.trackerFrame, "BOTTOMRIGHT", -5, 5)
    end

    if addon.Log then 
        addon:Log("ScenarioFrame Height: %d | YOffset: %d", scenarioYOffset, scenarioYOffset)
        addon:Log("Geometry: TF Vis=%s H=%s | SF Vis=%s H=%s",
            tostring(self.trackerFrame:IsVisible()), tostring(self.trackerFrame:GetHeight()),
            tostring(self.scrollFrame:IsVisible()), tostring(self.scrollFrame:GetHeight())
        )
    end

    --------------------------------------------------------------------------
    -- 2. Render Normal Trackables (In ScrollFrame)
    --------------------------------------------------------------------------
    local yOffset = 5  -- Start near top of content frame
    
    -- Display trackables
    for _, item in ipairs(trackables) do
        if item.isHeader then
            -- Zone/Category Header
            local header = self:GetOrCreateButton(contentFrame) -- Use contentFrame
            header:Show()
            
            -- Major headers (Category) vs Minor headers (Zone)
            local isMajor = item.headerType == "major"
            
            -- Padding/Indentation
            local xOffset = isMajor and db.spacingMajorHeaderIndent or db.spacingMinorHeaderIndent
            
            header:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", xOffset, -yOffset)
            header:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, -yOffset)
            
            -- Compatibility: Auctionator Crafting Search Button
            if isMajor and item.key == "MAJOR_profession" then
                if AuctionatorCraftingInfoObjectiveTrackerFrame then
                     AuctionatorCraftingInfoObjectiveTrackerFrame:SetParent(header)
                     AuctionatorCraftingInfoObjectiveTrackerFrame:ClearAllPoints()
                     AuctionatorCraftingInfoObjectiveTrackerFrame:SetPoint("TOPRIGHT", header, "TOPRIGHT", -10, 0)
                     AuctionatorCraftingInfoObjectiveTrackerFrame:SetFrameLevel(header:GetFrameLevel() + 5)
                     -- Force show if it was hidden by parent hiding
                     AuctionatorCraftingInfoObjectiveTrackerFrame:Show()
                end
            end
            
            -- Font Styling
            if isMajor then
                header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
                header.text:SetTextColor(db.headerColor.r, db.headerColor.g, db.headerColor.b, db.headerColor.a)
            else
                header.text:SetFont(db.headerFontFace, db.headerFontSize, db.headerFontOutline)
                header.text:SetTextColor(db.headerColor.r * 0.9, db.headerColor.g * 0.9, db.headerColor.b * 0.9, db.headerColor.a)
            end
            
            -- Collapse/Expand Icon
            if not header.expandBtn then
                header.expandBtn = CreateFrame("Button", nil, header)
                header.expandBtn:SetPoint("LEFT", 4, 0)
            end
            
            
            local iconStyle = db.headerIconStyle or "standard"
            local iconPos = db.headerIconPosition or "left"
            local isCollapsed = item.collapsed
            
            -- Position Button (Left or Right)
            header.expandBtn:ClearAllPoints()
            if iconPos == "right" then
                header.expandBtn:SetPoint("RIGHT", -8, 0)
            else
                header.expandBtn:SetPoint("LEFT", 8, 0)
            end
            
            -- Reset button state to prevent specific style overlapping (e.g. Text + Texture)
            header.expandBtn:SetText("")
            header.expandBtn:SetNormalTexture("")
            header.expandBtn:SetPushedTexture("")
            header.expandBtn:SetHighlightTexture("")
            -- Note: Setting Texture to "" usually clears Atlas as well in WoW API
            
            if iconStyle == "none" then
                header.expandBtn:Hide()
            else
                header.expandBtn:Show()
                if iconStyle == "standard" then
                    header.expandBtn:SetSize(16, 16)
                    header.expandBtn:SetNormalTexture(isCollapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
                    header.expandBtn:SetPushedTexture(isCollapsed and "Interface\\Buttons\\UI-PlusButton-Down" or "Interface\\Buttons\\UI-MinusButton-Down")
                    header.expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
                elseif iconStyle == "square" then
                    -- Classic UI Square Buttons (Plus/Minus usually represented by Expand/Collapse textures)
                    header.expandBtn:SetSize(16, 16)
                    -- Note: ExpandButton-Up shows a Plus. CollapseButton-Up shows a Minus.
                    header.expandBtn:SetNormalTexture(isCollapsed and "Interface\\Buttons\\UI-Panel-ExpandButton-Up" or "Interface\\Buttons\\UI-Panel-CollapseButton-Up")
                    header.expandBtn:SetPushedTexture(isCollapsed and "Interface\\Buttons\\UI-Panel-ExpandButton-Down" or "Interface\\Buttons\\UI-Panel-CollapseButton-Down")
                    -- header.expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight") -- Often doesn't exact match, skip or find better
                elseif iconStyle == "text_brackets" then
                    header.expandBtn:SetSize(24, 16)
                    header.expandBtn:SetText(isCollapsed and "[+]" or "[-]")
                    
                    local fontString = header.expandBtn:GetFontString()
                    if fontString then
                        fontString:SetFont(db.headerFontFace, db.headerFontSize, db.headerFontOutline)
                        fontString:SetTextColor(db.headerColor.r, db.headerColor.g, db.headerColor.b, 1)
                        if iconPos == "right" then
                            fontString:SetJustifyH("RIGHT")
                        else
                            fontString:SetJustifyH("LEFT")
                        end
                    end
                elseif iconStyle == "questlog" then
                    header.expandBtn:SetSize(16, 16)
                    
                    -- Use Atlas for texture
                    -- isCollapsed means "I am closed, show a Plus (Expand)"
                    -- not isCollapsed means "I am open, show a Minus (Collapse)"
                    
                    -- User provided specific Atlas names:
                    -- Expand:  "UI-QuestTrackerButton-Secondary-Expand"
                    -- Collapse: "UI-QuestTrackerButton-Secondary-Collapse"
                    
                    local atlas = isCollapsed and "UI-QuestTrackerButton-Secondary-Expand" or "UI-QuestTrackerButton-Secondary-Collapse"
                    
                    -- Apply Atlas
                    header.expandBtn:SetNormalAtlas(atlas)
                    header.expandBtn:SetPushedAtlas(atlas)
                    header.expandBtn:SetHighlightAtlas(atlas)
                end
            end
            
            -- Icon Tooltip & Click (Exclusive)
            header.expandBtn:SetScript("OnClick", function(self)
                 -- Trigger parental click logic or direct
                 addon:ToggleHeader(item.key, IsShiftKeyDown())
            end)
            
            header.expandBtn:SetScript("OnEnter", function(self)
                 if isMajor or true then -- Show on all? or just Major? User said "Over the +"
                     GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                     if item.collapsed then
                         GameTooltip:SetText("Hold SHIFT to Expand All", 1, 1, 1)
                     else
                         GameTooltip:SetText("Hold SHIFT to Minimize All", 1, 1, 1)
                     end
                     GameTooltip:Show()
                 end
            end)
            header.expandBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            
            -- Title Text
            header.text:SetText(item.title)
            
            -- RESET TEXT POINT for recycled headers
            header.text:ClearAllPoints()
            
            if iconStyle == "none" then
                 -- No icon: Text fills full width with small padding
                header.text:SetPoint("LEFT", 5, 0)
                header.text:SetPoint("RIGHT", -5, 0)
                header.text:SetJustifyH("LEFT")
            elseif iconPos == "right" then
                -- Icon on Right: Text starts Left, ends before icon
                header.text:SetPoint("LEFT", 5, 0)
                header.text:SetPoint("RIGHT", -22, 0)
                header.text:SetJustifyH("LEFT")
            else
                -- Icon on Left (Default): Text starts after icon
                header.text:SetPoint("LEFT", 22, 0)
                header.text:SetPoint("RIGHT", -5, 0)
                header.text:SetJustifyH("LEFT") 
            end
            
            local bgStyle = db.headerBackgroundStyle or "tracker"
            
            header.bg:ClearAllPoints()
            
            if bgStyle == "none" then
                header.bg:SetAllPoints(header)
                header.bg:SetColorTexture(0, 0, 0, 0)
            elseif bgStyle == "questlog" then
                 -- Shrink by 2px on each side
                 header.bg:SetPoint("TOPLEFT", header, "TOPLEFT", 2, 0)
                 header.bg:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -2, 0)
                 
                 -- Use the texture identified from the Quest Log frame
                 if header.bg.SetAtlas then
                     header.bg:SetAtlas("QuestLog-tab")
                     header.bg:SetVertexColor(1, 1, 1, 1)
                 else
                     -- Fallback (though SetAtlas should exist in Retail)
                     header.bg:SetTexture("Interface\\QuestFrame\\QuestLog-tab")
                     header.bg:SetTexCoord(0, 1, 0, 1) 
                 end
                 header.bg:SetVertexColor(1, 1, 1, 1)
            else
                header.bg:SetAllPoints(header)
                -- Tracker Default (Blizzard Style)
                if header.bg.SetAtlas then
                    -- Use Secondary for category headers (Quests, Achievements, etc.)
                    header.bg:SetAtlas("UI-QuestTracker-Secondary-Objective-Header")
                else
                    header.bg:SetColorTexture(0, 0, 0, isMajor and 0.4 or 0.2)
                end
                header.bg:SetVertexColor(1, 1, 1, 1)
            end
            
            header:SetHeight(isMajor and 24 or 20)
            header:Show()
            
            -- Store header data for click handling
            header.trackableData = item
            header:SetScript("OnClick", function(self, mouseButton)
                if mouseButton == "LeftButton" then
                    -- Pass IsShiftKeyDown() to support recursive toggle
                    addon:ToggleHeader(item.key, IsShiftKeyDown())
                end
            end)
            -- Clear other scripts that might conflict
            header:SetScript("OnMouseUp", nil)
            
            -- Removed Tooltip from main header bar area per user request
            header:SetScript("OnEnter", nil)
            header:SetScript("OnLeave", nil)
            
            yOffset = yOffset + (isMajor and db.spacingMajorHeaderAfter or db.spacingMinorHeaderAfter)
            
            -- Cleanup extra elements if reused
            if header.objectives then
                for _, obj in ipairs(header.objectives) do obj:Hide() end
            end
            if header.progressBars then
                for _, bar in ipairs(header.progressBars) do bar:Hide() end
            end
            if header.distance then header.distance:Hide() end
            
            -- Ensure POI buttons and Item buttons are hidden on headers
            if header.poiButton then header.poiButton:Hide() end
            if header.itemButton then header.itemButton:Hide() end
            if header.icon then header.icon:Hide() end

        else
            -- Trackable item (quest, achievement, etc.)
            local height = self:RenderTrackableItem(contentFrame, item, yOffset, db.spacingTrackableIndent)
            yOffset = yOffset + height + db.spacingItemVertical
        end
    end
    
    -- Update content frame height
    contentFrame:SetHeight(math.max(yOffset, self.db.frameHeight))
    if addon.Log then addon:Log("ContentFrame Final Height: %d | Buttons Used: %d", contentFrame:GetHeight(), activeButtons) end
    
    -- Update tracker frame appearance
    self:UpdateTrackerAppearance()
end

-- Toggle header collapse state
function addon:ToggleHeader(key, recursive)
    if not self.db.collapsedHeaders then self.db.collapsedHeaders = {} end
    
    if recursive and key:find("MAJOR_") then
        -- Recursive toggling logic (Shift+Click)
        local currentState = self.db.collapsedHeaders[key]
        
        if not currentState then 
            -- Currently Expanded ([-]) -> Minimize Children
            self.db.collapsedHeaders[key] = false -- Keep Parent Expanded
            
            -- Collapse known children (from Render Cache)
            if self.knownMinorKeys and self.knownMinorKeys[key] then
                for _, minorKey in ipairs(self.knownMinorKeys[key]) do
                    self.db.collapsedHeaders[minorKey] = true
                end
            end
            
            -- Also catch persistent entries
            local type = key:match("MAJOR_(.+)")
            local prefix = "MINOR_" .. type .. "_"
            for k, _ in pairs(self.db.collapsedHeaders) do
                if k:find("^" .. prefix) then
                    self.db.collapsedHeaders[k] = true
                end
            end
        else
            -- Currently Collapsed ([+]) -> Expand All
            self.db.collapsedHeaders[key] = false -- Expand Parent
            
            -- Expand all children (remove from DB so they default to nil/Expanded)
            local type = key:match("MAJOR_(.+)")
            local prefix = "MINOR_" .. type .. "_"
            for k, _ in pairs(self.db.collapsedHeaders) do
                if k:find("^" .. prefix) then
                    self.db.collapsedHeaders[k] = nil
                end
            end
        end
    else
        -- Standard Click
        local newState = not self.db.collapsedHeaders[key]
        self.db.collapsedHeaders[key] = newState
    end
    
    self:RequestUpdate()
end

-- Organize trackables into Major/Minor hierarchy
function addon:OrganizeTrackables(trackables)
    self.knownMinorKeys = {} -- Reset cache
    local organized = {}
    -- Scenarios should already be extracted by ExtractScenarios, but just in case
    
    local buckets = {
        quest = {},
        achievement = {},
        profession = {},
        monthly = {},
        endeavor = {},
    }
    
    -- Bucketing
    for _, item in ipairs(trackables) do
        local type = item.type
        if type ~= "scenario" then
            if not buckets[type] then buckets[type] = {} end
            table.insert(buckets[type], item)
        end
    end
    
    -- Function to sort and add buckets
    local function AddBucket(type, title)
        local items = buckets[type]
        if items and #items > 0 then
            -- Major Header
            local majorKey = "MAJOR_" .. type
            self.knownMinorKeys[majorKey] = {} -- Init cache for this header
            local majorCollapsed = self.db.collapsedHeaders[majorKey]
            
            table.insert(organized, {
                isHeader = true,
                headerType = "major",
                title = title,
                key = majorKey,
                collapsed = majorCollapsed
            })
            
            if not majorCollapsed then
                -- Group by Minor (Zone or Category)
                local zones = {}
                for _, item in ipairs(items) do
                    local zone = item.zone or "General"
                    -- Simplify "World Quest" zones
                    if item.isWorldQuest then zone = "World Quests - " .. zone end
                    
                    if not zones[zone] then zones[zone] = {} end
                    table.insert(zones[zone], item)
                end
                
                -- Sort Zones
                local sortedZones = {}
                for zoneName, _ in pairs(zones) do table.insert(sortedZones, zoneName) end
                table.sort(sortedZones)
                
                for _, zoneName in ipairs(sortedZones) do
                    local zoneItems = zones[zoneName]
                    local minorKey = "MINOR_" .. type .. "_" .. zoneName
                    table.insert(self.knownMinorKeys[majorKey], minorKey) -- Cache minor key
                    local minorCollapsed = self.db.collapsedHeaders[minorKey]
                    
                    -- Minor Header
                    table.insert(organized, {
                        isHeader = true,
                        headerType = "minor",
                        title = zoneName,
                        key = minorKey,
                        collapsed = minorCollapsed
                    })
                    
                    if not minorCollapsed then
                        -- Sort items inside zone
                        -- (Uses existing sorting logic if previously sorted, otherwise re-sort)
                        -- For now, just add them
                        for _, item in ipairs(zoneItems) do
                            table.insert(organized, item)
                        end
                    end
                end
            end
        end
    end
    
    -- Add in desired order
    AddBucket("quest", "Quests")
    -- AddBucket("scenario", "Dungeons & Scenarios") -- Scenarios handled separately
    AddBucket("achievement", "Achievements")
    AddBucket("profession", "Professions")
    AddBucket("monthly", "Monthly Activities")
    AddBucket("endeavor", "Endeavors")
    
    return organized
end

-- Get or create a button from the pool
function addon:GetOrCreateButton(parent)
    activeButtons = activeButtons + 1
    
    local btn
    if trackableButtons[activeButtons] then
        btn = trackableButtons[activeButtons]
        -- Re-parent if necessary
        if parent and btn:GetParent() ~= parent then
             btn:SetParent(parent)
        end
        btn:ClearAllPoints()
    else
        -- Create new button
        btn = CreateFrame("Button", nil, parent or contentFrame)
        btn:SetHeight(20)
        
        -- Background
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0, 0, 0, 0)
        
        -- Text
        btn.text = btn:CreateFontString(nil, "OVERLAY")
        btn.text:SetPoint("TOPLEFT", 2, -2)
        btn.text:SetPoint("TOPRIGHT", -2, -2)
        btn.text:SetJustifyH("LEFT")
        btn.text:SetWordWrap(true)
        
        -- Enable mouse
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        table.insert(trackableButtons, btn)
    end
    
    -- Reset Custom Elements (Cleanup from potentially being used as a Popup/AutoQuest)
    if btn.popupBackdrop then btn.popupBackdrop:Hide() end
    if btn.largeIcon then btn.largeIcon:Hide() end
    if btn.stageBox then btn.stageBox:Hide() end
    if btn.subText then btn.subText:Hide() end
    
    -- IMPORTANT: Clear points on reuse to prevent anchor conflicts
    btn:ClearAllPoints()
    btn:Show()
    
    -- Nuclear option: Ensure any lingering children like ProgressBars are hidden
    if btn.progressBars then
        for _, bar in pairs(btn.progressBars) do
            bar:Hide()
        end
    end
    if btn.objectives then
        for _, obj in pairs(btn.objectives) do
            obj:Hide()
        end
    end
    if btn.distance then btn.distance:Hide() end
    if btn.stageBox then btn.stageBox:Hide() end
    if btn.styledBackdrop then btn.styledBackdrop:Hide() end
    if btn.SetBackdrop then btn:SetBackdrop(nil) end
    
    return btn
end

-- Get or create a secure button for Queue/Item use
function addon:GetOrCreateSecureButton(parent)
    activeSecureButtons = activeSecureButtons + 1
    
    local button
    if secureButtons[activeSecureButtons] then
        button = secureButtons[activeSecureButtons]
    else
        -- Create new secure button
        button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
        button:SetSize(20, 20)
        
        -- Icon
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        
        -- Cooldown
        button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        button.cooldown:SetAllPoints()
        button.cooldown:SetHideCountdownNumbers(false)
        
        -- Hover
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        
        -- Register
        button:RegisterForClicks("AnyUp", "AnyDown")
        
        table.insert(secureButtons, button)
    end
    
    -- Re-parenting secure frames in combat is restricted, so we ensure this is only called out of combat.
    button:SetParent(parent)
    
    return button
end

-- Handle trackable click
function addon:OnTrackableClick(trackable, mouseButton)
    if not trackable then return end
    
    if mouseButton == "LeftButton" then
        if IsShiftKeyDown() then
             -- Shift+Left: Stop Tracking
            if trackable.type == "quest" then
                C_QuestLog.RemoveQuestWatch(trackable.id)
            elseif trackable.type == "achievement" then
                if C_ContentTracking and C_ContentTracking.StopTracking then
                    C_ContentTracking.StopTracking(Enum.ContentTrackingType.Achievement, trackable.id, Enum.ContentTrackingStopType.Manual)
                elseif RemoveTrackedAchievement then
                    RemoveTrackedAchievement(trackable.id)
                end
            elseif trackable.type == "profession" then
                C_TradeSkillUI.SetRecipeTracked(trackable.id, false, trackable.isRecraft)
            elseif trackable.type == "monthly" then
                C_PerksProgram.RemoveTrackedPerksActivity(trackable.id)
            elseif trackable.type == "endeavor" then
                if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RemoveTrackedInitiativeTask then
                     C_NeighborhoodInitiative.RemoveTrackedInitiativeTask(trackable.id)
                else
                    print("Shift-click to remove Endeavors not supported.")
                end
            end
            self:RequestUpdate()
        else
            -- Left click: Focus/navigate to quest
            if trackable.type == "autoquest" then
                if trackable.popUpType == "COMPLETE" then
                     if ShowQuestComplete then ShowQuestComplete(trackable.questID) end
                elseif trackable.popUpType == "OFFER" then
                     if ShowQuestOffer then ShowQuestOffer(trackable.questID) end
                end
            elseif trackable.type == "quest" then
                local questID = trackable.id
                if questID then
                    -- Show on map
                    if QuestMapFrame and QuestMapFrame.GetDetailQuestID and QuestMapFrame:GetDetailQuestID() == questID and QuestMapFrame:IsVisible() then
                        -- Already shown, do nothing or toggle? Standard behavior is just show.
                    else
                        -- Ensure map is open
                        if not WorldMapFrame or not WorldMapFrame:IsShown() then
                             ToggleWorldMap()
                        end
                        -- Select quest
                        if QuestMapFrame then
                             QuestMapFrame_ShowQuestDetails(questID)
                        end
                    end
                end
            elseif trackable.type == "achievement" then
                -- Open achievement UI
                if not AchievementFrame then
                    AchievementFrame_LoadUI()
                end
                if AchievementFrame then
                    ShowUIPanel(AchievementFrame)
                    AchievementFrame_SelectAchievement(trackable.id)
                end
            elseif trackable.type == "profession" then
                if C_TradeSkillUI.OpenRecipe then
                    C_TradeSkillUI.OpenRecipe(trackable.id)
                else
                    local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(trackable.id)
                    if info and info.professionID then
                        C_TradeSkillUI.OpenTradeSkill(info.professionID)
                    end
                end
            elseif trackable.type == "monthly" then
                if not EncounterJournal then EncounterJournal_LoadUI() end
                if not EncounterJournal:IsShown() then ToggleEncounterJournal() end
                -- Try to switch to Monthly Activities tab if possible (Tab 3 usually)
                -- Specific API to open directly to activity?
                -- EncounterJournal_DisplayMonthlyActivities() is standard if available
                if EncounterJournal_DisplayMonthlyActivities then
                    EncounterJournal_DisplayMonthlyActivities()
                end
            elseif trackable.type == "endeavor" then
                if HousingFramesUtil and HousingFramesUtil.OpenFrameToTaskID then
                    HousingFramesUtil.OpenFrameToTaskID(trackable.id)
                end
            end
        end
    elseif mouseButton == "RightButton" then
        -- Right click: Context Menu
        if trackable.type == "quest" then
            MenuUtil.CreateContextMenu(UIParent, function(owner, rootDescription)
                rootDescription:CreateTitle(trackable.title)
                
                -- Focus (Super Track)
                rootDescription:CreateButton("Focus Quest", function()
                    C_SuperTrack.SetSuperTrackedQuestID(trackable.id)
                end)
                
                -- Stop Tracking
                rootDescription:CreateButton("Stop Tracking", function()
                    C_QuestLog.RemoveQuestWatch(trackable.id)
                    addon:RequestUpdate()
                end)
                
                -- Open Quest Log (Show in Map)
                rootDescription:CreateButton("Show in Quest Log", function()
                     if not WorldMapFrame or not WorldMapFrame:IsShown() then ToggleWorldMap() end
                     QuestMapFrame_ShowQuestDetails(trackable.id)
                end)
                
                -- Share
                if IsInGroup() then
                    rootDescription:CreateButton("Share Quest", function()
                        C_QuestLog.SetSelectedQuest(trackable.id)
                        QuestLogPushQuest()
                    end)
                end
                
                -- Link to Chat
                rootDescription:CreateButton("Link to Chat", function()
                    local link = GetQuestLink(trackable.id)
                    if link then
                        ChatEdit_InsertLink(link)
                    end
                end)
                
                -- Abandon (Cautious)
                rootDescription:CreateButton("Abandon Quest", function()
                    C_QuestLog.SetSelectedQuest(trackable.id)
                    C_QuestLog.SetAbandonQuest()
                    local title = C_QuestLog.GetTitleForQuestID(trackable.id)
                    StaticPopup_Show("ABANDON_QUEST", title)
                end)
            end)
        end
    end
end

-- Show trackable tooltip
function addon:ShowTrackableTooltip(button, trackable)
    if not trackable then return end
    
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    
    if trackable.type == "quest" then
        GameTooltip:SetQuestLogItem("quest", trackable.id)
    elseif trackable.type == "achievement" then
        GameTooltip:SetText(trackable.title)
        if trackable.description then
            GameTooltip:AddLine(trackable.description, 1, 1, 1, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("%d points", trackable.points or 0), 1, 0.82, 0)
    end
    
    GameTooltip:Show()
end

-- Update tracker appearance (colors, fonts, etc.)
function addon:UpdateTrackerAppearance()
    if not trackerFrame then return end
    
    local db = self.db
    
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
        trackerFrame.border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = db.borderSize,
        })
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
        local bgStyle = db.headerBackgroundStyle or "tracker"
        
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
