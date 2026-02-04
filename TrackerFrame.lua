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

local WHITE_TEXTURE = "Interface\\BUTTONS\\WHITE8X8"

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
             trackerFrame:SetPoint(addon.db.framePosition.point, UIParent, addon.db.framePosition.point, addon.db.framePosition.x, addon.db.framePosition.y)
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
        -- Save position
        local point, _, _, x, y = self:GetPoint()
        addon.db.framePosition = {point = point, x = x, y = y}
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
    
    -- Scenario Frame (Pinned to top, below title)
    -- This resides outside the scroll frame so it doesn't scroll
    local scenarioFrame = CreateFrame("Frame", nil, trackerFrame)
    scenarioFrame:SetPoint("TOPLEFT", 5, -25)
    scenarioFrame:SetPoint("TOPRIGHT", -5, -25)
    scenarioFrame:SetHeight(1) -- Will be dynamic
    
    -- Create scroll frame (Below scenario frame)
    scrollFrame = CreateFrame("ScrollFrame", nil, trackerFrame)
    scrollFrame:SetPoint("TOPLEFT", scenarioFrame, "BOTTOMLEFT", 0, 0) -- Attach to bottom of scenario frame
    scrollFrame:SetPoint("BOTTOMRIGHT", -5, 5)
    scrollFrame:EnableMouse(false)
    scrollFrame:EnableMouseWheel(false)
    
    -- Content frame (child of scroll frame)
    contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetSize(self.db.frameWidth - 2, 100) -- Reduce width for scrollbar/padding logic
    scrollFrame:SetScrollChild(contentFrame)
    
    -- Title Header (Left aligned)
    trackerFrame.title = trackerFrame:CreateFontString(nil, "OVERLAY")
    trackerFrame.title:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 8, -6)
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
    trackerFrame.settingsParam:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", -5, -5)
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
        -- Keep settings button clickable? No, if locked, maybe we want it hidden or clickable through passthrough?
        -- Actually, usually you want settings accessible. But EnableMouse(false) kills children input too unless FrameLevel is higher?
        -- No, children of mouse-disabled frames can still be mouse enabled.
    else
        trackerFrame:EnableMouse(true)
        if trackerFrame.resizeBR then trackerFrame.resizeBR:Show() end
        if trackerFrame.resizeBL then trackerFrame.resizeBL:Show() end
    end
end

-- Update tracker display with trackables
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
    
    -- Extract Scenarios first (Always separate)
    local scenarios = {}
    local remainingTrackables = {}
    
    for _, item in ipairs(trackables) do
        if item.type == "scenario" then
            table.insert(scenarios, item)
        else
            table.insert(remainingTrackables, item)
        end
    end
    
    if addon.Log then addon:Log("Scenarios: %d | Remaining: %d", #scenarios, #remainingTrackables) end
    
    self.currentScenarios = scenarios
    trackables = remainingTrackables
    
    -- Group trackables if needed
    if db.groupByZone or db.groupByCategory then
        trackables = self:OrganizeTrackables(trackables)
    end
    
    local superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
    
    --------------------------------------------------------------------------
    -- 1. Render Scenarios (Sticky Header)
    --------------------------------------------------------------------------
    local scenarioHeight = 0
    local scenarioYOffset = 0 -- Start at 0 relative to scenarioFrame
    
    if self.currentScenarios and #self.currentScenarios > 0 then
        -- Render Header
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
                             
                             progressValue = percent
                             progressMax = 100
                             progressText = string.format("%d%%", math.floor(percent))
                            
                             -- Override text line to NOT show "Hyperspawn: 136/160"
                             objText = "  - " .. obj.text
                        elseif obj.numRequired and obj.numRequired > 0 then
                             if not foundPercent then
                                 local cur = obj.numFulfilled or 0
                                 local req = obj.numRequired or 0
                                 
                                 if req > 0 then
                                     percent = (cur / req) * 100
                                 else
                                     -- Fallback: If required is missing/zero, AND no string info found...
                                     -- It's possible "quantityString" was just "136" (points) without max.
                                     -- If cur > 100, assume it is NOT a percent
                                     if cur <= 100 then
                                         percent = cur
                                     else
                                         -- Assume we are in fail state, show 100% or ?
                                         percent = 100 
                                     end
                                 end
                             end
                             
                             -- 3. Clamp and Display
                             -- Ensure we stay within 0-100 visual range
                             if percent > 100 then percent = 100 end
                             if percent < 0 then percent = 0 end
                             
                             progressValue = percent
                             progressMax = 100
                             progressText = string.format("%d%%", math.floor(percent))
                            
                             -- Override text line to NOT show "Hyperspawn: 136/160"
                             objText = "  - " .. obj.text
                        elseif obj.numRequired and obj.numRequired > 0 then
                            -- Standard X/Y objective, but maybe use a bar for visuals?
                            if obj.text and not string.find(obj.text, "/") then
                                -- If text doesn't already contain "0/3", append it
                                objText = string.format("  - %s: %d/%d", obj.text, obj.numFulfilled or 0, obj.numRequired)
                            else
                                objText = "  - " .. obj.text
                            end
                            
                            -- Don't force bar unless we want to styling-wise. 
                            -- But if user sees 67/160 and wants 67%, they probably have a bar in default UI.
                            -- Let's stick to flags for now to be safe.
                            if obj.numRequired > 20 then -- Arbitrary threshold for "big numbers" that look good as bars
                                isProgressBar = true
                                progressValue = obj.numFulfilled or 0
                                progressMax = obj.numRequired
                                progressText = string.format("%d%%", math.floor((progressValue/progressMax)*100))
                            end
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
                                bar = CreateFrame("StatusBar", nil, button)
                                bar:SetSize(1, 14) -- width dynamic
                                bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                                bar.bg = bar:CreateTexture(nil, "BACKGROUND")
                                bar.bg:SetAllPoints()
                                bar.bg:SetColorTexture(0, 0, 0, 0.5)
                                
                                bar.value = bar:CreateFontString(nil, "OVERLAY")
                                bar.value:SetFont(db.fontFace, 10, "OUTLINE")
                                bar.value:SetPoint("CENTER")
                                
                                -- Border
                                local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
                                border:SetPoint("TOPLEFT", -1, 1)
                                border:SetPoint("BOTTOMRIGHT", 1, -1)
                                border:SetBackdrop({
                                    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
                                })
                                border:SetBackdropBorderColor(0, 0, 0, 1)
                                
                                button.progressBars[objIndex] = bar
                            end
                            
                            bar:SetPoint("TOPLEFT", 20, -height)
                            bar:SetPoint("TOPRIGHT", -20, -height)
                            bar:SetMinMaxValues(0, progressMax)
                            bar:SetValue(progressValue)
                            bar:SetStatusBarColor(0, 0.5, 1, 1) -- Blueish
                            
                            bar.value:SetText(progressText)
                            
                            bar:Show()
                            height = height + 18
                        elseif button.progressBars and button.progressBars[objIndex] then
                             button.progressBars[objIndex]:Hide()
                        end
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
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.trackerFrame, "BOTTOMRIGHT", -5, 5)

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
            -- If this is the Professions major header, try to hijack the Auctionator frame
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
            
            -- Reset Styles
            header.expandBtn:SetNormalTexture(0)
            header.expandBtn:SetPushedTexture(0)
            header.expandBtn:SetHighlightTexture(0)
            header.expandBtn:SetText("")
            
            local iconStyle = db.headerIconStyle or "standard"
            local isCollapsed = item.collapsed
            
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
                    fontString:SetJustifyH("LEFT")
                end
            elseif iconStyle == "text_arrows" then
                header.expandBtn:SetSize(16, 16)
                header.expandBtn:SetText(isCollapsed and ">" or "v")
                 
                local fontString = header.expandBtn:GetFontString()
                if fontString then
                    fontString:SetFont(db.headerFontFace, db.headerFontSize, db.headerFontOutline)
                    fontString:SetTextColor(db.headerColor.r, db.headerColor.g, db.headerColor.b, 1)
                    fontString:SetJustifyH("CENTER")
                end
            end
            
            header.expandBtn:Show()
            
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
            header.text:SetJustifyH("LEFT")
            
            -- RESET TEXT POINT for recycled headers to remove old indentation
            -- Ensure text is properly left-aligned regardless of prior usage
            header.text:ClearAllPoints()
            header.text:SetPoint("LEFT", 22, 0) -- Indent passed the icon
            header.text:SetPoint("RIGHT", -5, 0)
            
            header.bg:SetColorTexture(0, 0, 0, isMajor and 0.4 or 0.2)
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
            local button = self:GetOrCreateButton(contentFrame)
            if button.expandBtn then button.expandBtn:Hide() end -- Hide expand button if recycled
            button:Show()
            
            -- Padding/Indentation for button text
            local indent = db.spacingTrackableIndent
            
            -- Reset button point completely to avoid previous anchor persistence
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", indent, -yOffset)
            button:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -5, -yOffset)
            
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
                         -- Function C_SuperTrack.SetSuperTrackedQuestID(questID)
                         C_SuperTrack.SetSuperTrackedQuestID(self.questID)
                         PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                     end
                end)
                
                -- Ensure it doesn't consume mouse events incorrectly (though Button usually does)
                button.poiButton:RegisterForClicks("LeftButtonUp")
            end
            
            -- Quest Item Button
            if item.item then
                local secureBtn = self:GetOrCreateSecureButton(button)
                secureBtn:SetPoint("TOPLEFT", button, "TOPLEFT", 18, 0) -- Adjusted for tighter layout
                secureBtn:SetSize(18, 18) -- Slightly smaller
                secureBtn:SetAttribute("type", "item")
                secureBtn:SetAttribute("item", item.item.link)
                secureBtn.icon:SetTexture(item.item.texture)
                secureBtn:Show()
                button.itemButton = secureBtn
                
                -- Update padding since we have an item button now
                leftPadding = db.spacingPOIButton + db.spacingItemButton
            else
                if button.itemButton then button.itemButton:Hide() end
                -- Reset padding
                leftPadding = db.spacingPOIButton
            end

            -- Configure POI Button Appearance using Standard Utils
            local isQuest = (item.type == "quest" or item.isWorldQuest)
            local superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
            
            -- Only attempt to use POIButtonUtil if it exists globally
            if isQuest and POIButtonUtil then
                button.poiButton:Show()
                if button.icon then button.icon:Hide() end
                
                -- Update internal state
                button.poiButton.questID = item.id
                -- Check if SetQuestID exists on the button (from template)
                if button.poiButton.SetQuestID then
                    button.poiButton:SetQuestID(item.id)
                end
                
                -- Determine Style
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
                
                -- Selection State
                local isSelected = (item.id == superTrackedQuestID)
                if button.poiButton.SetSelected then
                    button.poiButton:SetSelected(isSelected)
                end
                
                -- Ensure padding allows for the button
                 if leftPadding < db.spacingPOIButton then leftPadding = db.spacingPOIButton end

            else
                -- Achievements / Professions -> No standard POI button
                button.poiButton:Hide()
                if button.icon then button.icon:Hide() end -- Or show generic icon
                
                -- Reduce padding since there is no icon
                leftPadding = db.spacingMinorHeaderIndent
            end

            -- Update Layout based on dynamic padding (re-apply padding changes)
            if item.item then
                 leftPadding = db.spacingPOIButton + db.spacingItemButton
            elseif not isQuest then
                 leftPadding = db.spacingMinorHeaderIndent
            else
                 -- Quest, no item
                 leftPadding = db.spacingPOIButton
            end
            
            -- RESET TEXT POINT for recycled buttons
            button.text:ClearAllPoints()
            -- Force text indentation so recycled buttons don't keep strange offsets
            button.text:SetPoint("TOPLEFT", leftPadding, -2) 
            button.text:SetPoint("TOPRIGHT", -2, -2)

            -- Title with level/type
            local titleText = item.title
            if db.showQuestLevel and item.level then
                titleText = string.format("[%d] %s", item.level, titleText)
            end
            if db.showQuestType and item.questType then
                titleText = titleText .. " (" .. item.questType .. ")"
            end
            
            button.text:SetFont(db.fontFace, db.fontSize, db.fontOutline)
            local color = item.color or db.questColor
            if isSelected then
               color = {r=1, g=0.82, b=0, a=1} -- Yellow for selected
            end
            button.text:SetTextColor(color.r, color.g, color.b, color.a)
            button.text:SetText(titleText)
            button.text:SetPoint("TOPLEFT", leftPadding, -2) -- Adjusted padding
            button.text:SetJustifyH("LEFT")
            
            button.bg:SetColorTexture(0, 0, 0, 0)
            
            -- Calculate height based on content
            -- Use exact measurements for wrapped text
            local textHeight = button.text:GetStringHeight()
            local height = math.max(db.fontSize + 4, textHeight + 4)
            
            -- Add objectives
            if item.objectives and #item.objectives > 0 then
                local currentY = -(textHeight + 2) -- Start below title
                
                for objIndex, obj in ipairs(item.objectives) do
                    local objText = "  - " .. obj.text
                    local isProgressBar = false
                    local progressValue = 0
                    local progressMax = 100
                    
                    -- Check for Progress Bar Requirement (% in text)
                    if obj.text and string.find(obj.text, "%%") then
                         isProgressBar = true
                         -- Parse percentage from text (e.g. "Energy: 50%")
                         local val = string.match(obj.text, "(%d+)%%")
                         if val then
                             progressValue = tonumber(val)
                             progressMax = 100
                         end
                         
                         -- Clean text: remove percentages like "(50%)" or "50%"
                         local cleanText = obj.text
                         cleanText = cleanText:gsub("%s*%(%d+%%%)", "") -- Remove (50%)
                         cleanText = cleanText:gsub("%s*%d+%%", "")     -- Remove 50%
                         cleanText = cleanText:gsub(":%s*$", "")         -- Remove trailing colon
                         cleanText = cleanText:gsub("^%s+", ""):gsub("%s+$", "") -- Trim
                         
                         if cleanText == "" then cleanText = obj.text:gsub("%s*%(%d+%%%)", "") end -- Fallback if we emptied it too much
                         
                         objText = "  - " .. cleanText
                    elseif obj.numRequired and obj.numRequired > 0 then
                        -- Clean text if it already starts with numbers to avoid duplication
                        -- e.g. "18/26 Slay Orcs" -> "Slay Orcs"
                        local cleanText = obj.text:gsub("^%d+/%d+%s*", "")
                        cleanText = cleanText:gsub("^%s+", "") -- trim leading space
                        objText = string.format("  - %d/%d %s", obj.numFulfilled or 0, obj.numRequired, cleanText)
                    end
                    
                    -- Create objective line
                    if not button.objectives then
                        button.objectives = {}
                    end
                    
                    local objLine = button.objectives[objIndex]
                    if not objLine then
                        objLine = button:CreateFontString(nil, "OVERLAY")
                        button.objectives[objIndex] = objLine
                    end
                    
                    -- Indent objectives to match title text
                    -- Explicit width constraint for objectives to also wrap relative to parent
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

                    -- Render Progress Bar if needed
                    if isProgressBar then
                        if not button.progressBars then button.progressBars = {} end
                        local bar = button.progressBars[objIndex]
                        if not bar then
                            bar = CreateFrame("StatusBar", nil, button)
                            bar:SetSize(1, 10) -- width dynamic, height thinner than scenarios
                            bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                            bar.bg = bar:CreateTexture(nil, "BACKGROUND")
                            bar.bg:SetAllPoints()
                            bar.bg:SetColorTexture(0, 0, 0, 0.5)
                            
                            -- Border
                            local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
                            border:SetPoint("TOPLEFT", -1, 1)
                            border:SetPoint("BOTTOMRIGHT", 1, -1)
                            border:SetBackdrop({
                                edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
                            })
                            border:SetBackdropBorderColor(0, 0, 0, 1)
                            
                            -- Text Label
                            bar.value = bar:CreateFontString(nil, "OVERLAY") 
                            bar.value:SetFont(db.fontFace, 9, "OUTLINE")
                            bar.value:SetPoint("CENTER")
                            
                            button.progressBars[objIndex] = bar
                        end
                        
                        -- Layout Bar
                        bar:SetPoint("TOPLEFT", button, "TOPLEFT", leftPadding + db.spacingObjectiveIndent, currentY)
                        bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", -db.spacingProgressBarInset, currentY)
                        
                        bar:SetMinMaxValues(0, progressMax)
                        bar:SetValue(progressValue)
                        bar:SetStatusBarColor(0, 0.5, 1, 1) -- Blueish
                        
                        if bar.value then
                             bar.value:SetText(progressValue .. "%")
                        end
                        
                        bar:Show()
                        
                        lastHeight = 14 -- Bar height + padding
                        currentY = currentY - lastHeight
                        height = height + lastHeight
                    elseif button.progressBars and button.progressBars[objIndex] then
                         button.progressBars[objIndex]:Hide()
                    end
                end
                
                -- Hide unused objective lines & bars
                if button.objectives then
                    for i = #item.objectives + 1, #button.objectives do
                        button.objectives[i]:Hide()
                    end
                end
                if button.progressBars then
                    for i = #item.objectives + 1, #button.progressBars do
                        button.progressBars[i]:Hide()
                    end
                end
            else
                -- Hide all objectives if none
                if button.objectives then
                    for _, objLine in ipairs(button.objectives) do
                        objLine:Hide()
                    end
                end
                if button.progressBars then
                    for _, bar in ipairs(button.progressBars) do
                        bar:Hide()
                    end
                end
            end
            
            -- Add distance if enabled
            if db.showDistance and item.distance and item.distance < 999999 then
                if not button.distance then
                    button.distance = button:CreateFontString(nil, "OVERLAY")
                end
                button.distance:SetPoint("TOPRIGHT", button, "TOPRIGHT", -5, -2)
                button.distance:SetFont(db.fontFace, db.fontSize - 2, db.fontOutline)
                button.distance:SetTextColor(0.7, 0.7, 0.7, 1)
                button.distance:SetText(string.format("%.0f yds", item.distance))
                button.distance:Show()
            else
                if button.distance then
                    button.distance:Hide()
                end
            end
            
            button:SetHeight(height)
            button:Show()
            
            -- Store trackable data on button
            button.trackableData = item
            
            -- Click handling
            button:SetScript("OnClick", function(self, mouseButton)
                addon:OnTrackableClick(self.trackableData, mouseButton)
            end)
            -- Clear potential conflicts
            button:SetScript("OnMouseUp", nil)
            
            -- Tooltip
            if db.showTooltips then
                button:SetScript("OnEnter", function(self)
                    addon:ShowTrackableTooltip(self, self.trackableData)
                end)
                button:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end
            
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
    
    -- Leftovers (if any new types added later)
    -- ...
    
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
        
        -- Cooldown (Optional)
        -- button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        
        -- Hover
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        
        -- Register
        button:RegisterForClicks("AnyUp", "AnyDown")
        
        table.insert(secureButtons, button)
    end
    
    -- Re-parenting secure frames in combat is restricted, but we can usually SetParent if not restricted environment?
    -- Safest is just to place it visually.
    if not InCombatLockdown() then
        button:SetParent(parent)
    end
    
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
            if trackable.type == "quest" then
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
                    StaticPopup_Show("ABANDON_QUEST", GetAbandonQuestName())
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
end

-- Refresh the tracker display
function addon:RefreshDisplay()
    self:RequestUpdate()
end
