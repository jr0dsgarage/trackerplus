local addonName, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Localize hot-path globals
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local format, match = string.format, string.match
local max, floor = math.max, math.floor

-- Local aliases for addon utilities (populated after load)
local ParseObjectiveDisplay = function(...) return addon.ParseObjectiveDisplay(...) end
local ResolveTrackableItemData = function(...) return addon.ResolveTrackableItemData(...) end

local function NormalizeHeaderText(value)
    if not value or value == "" then return "" end
    local normalized = tostring(value):lower()
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    normalized = normalized:gsub("[^%w%s]", "")
    normalized = normalized:gsub("%s+", " ")
    return normalized
end

local function IsQuestTypeRedundant(item, typeText)
    local qType = NormalizeHeaderText(typeText)
    if qType == "" then return true end

    local minorHeader = NormalizeHeaderText(item._minorHeaderTitle)
    local majorHeader = NormalizeHeaderText(item._majorHeaderTitle)
    local zoneHeader = NormalizeHeaderText(item.zone)

    if qType == minorHeader or qType == majorHeader or qType == zoneHeader then
        return true
    end
    if minorHeader ~= "" and (minorHeader:find(qType, 1, true) or qType:find(minorHeader, 1, true)) then
        return true
    end
    if zoneHeader ~= "" and (zoneHeader:find(qType, 1, true) or qType:find(zoneHeader, 1, true)) then
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- RenderTrackableItem — renders a single quest/achievement row
-------------------------------------------------------------------------------
function addon:RenderTrackableItem(parent, item, yOffset, indent)
    local db = self.db
    local button = self:GetOrCreateButton(parent)
    if button.expandBtn then button.expandBtn:Hide() end -- Hide expand button if recycled
    
    -- Cleanup recycled elements (use numeric for loops - faster than ipairs)
    if button.objectiveBullets then
        local arr = button.objectiveBullets
        for i = 1, #arr do arr[i]:Hide() end
    end
    if button.objectives then
        local arr = button.objectives
        for i = 1, #arr do arr[i]:Hide() end
    end
    if button.objectivePrefixes then
        local arr = button.objectivePrefixes
        for i = 1, #arr do arr[i]:Hide() end
    end
    if button.progressBars then
        local arr = button.progressBars
        for _, frame in pairs(arr) do
            if frame then frame:Hide() end
        end
    end

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
    local itemData = ResolveTrackableItemData(item)
    if itemData then
        local secureBtn = self:GetOrCreateSecureButton(button)
        secureBtn:ClearAllPoints()
        
        local btnSize = 18
        if item.type == "supertrack" then
             btnSize = 36 -- 2x Normal Size (18 * 2)
             -- Move up into the header space (Active Quest backdrop corner)
             -- Button is at yOffset (approx 30px down). 
             -- We want Icon at -5px from top. Button is at -30px. Difference is +25px.
             -- Button is at -5px from right. We want Icon at -5px from right. Difference is 0px.
             secureBtn:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 25) 
             secureBtn:SetFrameLevel(button:GetFrameLevel() + 10) -- Ensure on top of header/backdrop
        else
             secureBtn:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, 0) -- Right aligned
        end

        secureBtn:SetSize(btnSize, btnSize) 
        button:SetClipsChildren(false) -- Allow button to extend outside (for supertrack)
        secureBtn:SetAttribute("type", "item")
        secureBtn:SetAttribute("item", itemData.link)
        secureBtn.itemLink = itemData.link

        secureBtn:SetScript("OnEnter", function(self)
            if not self.itemLink then return end
            local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
            local itemName = GetItemInfo(self.itemLink)
            tooltip:SetText(itemName or self.itemLink)
            tooltip:AddLine("Click to use this item", 0.85, 0.85, 0.85)
            tooltip:Show()
        end)
        secureBtn:SetScript("OnLeave", function()
            addon:HideSharedTooltip()
        end)
        
        -- Robust Icon handling
        local texture = itemData.texture
        
        -- Try to fetch via API if missing
           if not texture and itemData.link then
               texture = GetItemIcon(itemData.link)
             
             -- If GetItemIcon fails (returns nil), try Instant info which is cache-independent for icons
             if not texture then
                   local _, _, _, _, iconID = GetItemInfoInstant(itemData.link)
                  if iconID then texture = iconID end
             end
        end

        -- Final Fallback: Red Question Mark (134400) to ensure visibility
        if not texture then
             texture = 134400 
        end

        secureBtn.icon:SetTexture(texture)
        secureBtn.icon:Show() -- Enforce visibility
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
            if not start and itemData.link then
                local itemID = GetItemInfoInstant(itemData.link)
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
        if button.itemButton then
            button.itemButton.itemLink = nil
            button.itemButton:Hide()
        end
    end

    -- Configure POI Button Appearance
    local isQuest = (item.type == "quest" or item.type == "campaign" or item.isWorldQuest or item.type == "supertrack")
    local superTrackedQuestID = self._cachedSuperTrackedQuestID or 0
    
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
    
    -- Group Finder Button
    local showGroupButton = (item.isWorldQuest or item.type == "bonus") and item.canCreateGroup == true
    
    if showGroupButton then
        if not button.groupButton then
            button.groupButton = CreateFrame("Button", nil, button)
            button.groupButton:SetSize(16, 16)
            
            button.groupButton:SetNormalAtlas("socialqueuing-icon-eye")
            button.groupButton:SetHighlightAtlas("socialqueuing-icon-eye")
            button.groupButton:GetHighlightTexture():SetAlpha(0.5)
            
            button.groupButton:SetScript("OnClick", function(self)
                LFGListUtil_FindQuestGroup(self.questID)
            end)
            
            button.groupButton:SetScript("OnEnter", function(self)
                local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
                tooltip:SetText(OBJECTIVES_FIND_GROUP)
                tooltip:Show()
            end)
            button.groupButton:SetScript("OnLeave", function() addon:HideSharedTooltip() end)
        end
        
        button.groupButton.questID = item.id
        button.groupButton:Show()
    else
        if button.groupButton then button.groupButton:Hide() end
    end

    if not isQuest then
         leftPadding = db.spacingMinorHeaderIndent
    else
         leftPadding = db.spacingPOIButton
    end
    
    local rightPadding = -2
    if itemData then
        if item.type == "supertrack" then
             -- Icon is 36px wide and sits at -5px from right. Left edge is at -41px.
             -- Add padding so text doesn't overlap (approx -45px)
             rightPadding = -45 
        else
             rightPadding = -22 -- Make room for item button
        end
    end
    
    -- Adjust for Group Button
    if showGroupButton then
         button.groupButton:ClearAllPoints()
            if itemData and button.itemButton then
              -- Place to the left of the item button
              if item.type == "supertrack" then
                   button.groupButton:SetPoint("RIGHT", button, "RIGHT", -45, 0)
                   rightPadding = rightPadding - 18
              else
                   button.groupButton:SetPoint("RIGHT", button.itemButton, "LEFT", -2, 0)
                   rightPadding = rightPadding - 18
              end
         else
              -- No item button, place at right edge
              button.groupButton:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
              rightPadding = -20
         end
    end

    button.text:ClearAllPoints()
    button.text:SetPoint("TOPLEFT", leftPadding, -2) 
    button.text:SetPoint("TOPRIGHT", rightPadding, -2)

    local titleText = item.title
    if db.showQuestLevel and item.level and item.level > 0 then
        titleText = format("[%d] %s", item.level, titleText)
    end

    if item.questType
        and not item.isWorldQuest
        and item.type ~= "worldquest"
        and not IsQuestTypeRedundant(item, item.questType) then
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
    local height = max(db.fontSize + 4, textHeight + 4)
    
    -- Objectives
    if not item.collapsed and item.objectives and #item.objectives > 0 then
        local currentY = -(textHeight + 2)
        
        for objIndex, obj in ipairs(item.objectives) do
            local parsed = ParseObjectiveDisplay(item, obj, objIndex)
            local prefixText = parsed.prefixText
            local bodyText = parsed.bodyText
            local isProgressBar = parsed.isProgressBar
            local progressValue = parsed.progressValue
            local progressMax = parsed.progressMax
            
            -- Prepare Bullet
            if not button.objectiveBullets then button.objectiveBullets = {} end
            local bulletLine = button.objectiveBullets[objIndex]
            if not bulletLine then
                bulletLine = button:CreateFontString(nil, "OVERLAY")
                button.objectiveBullets[objIndex] = bulletLine
            end
            
            local indentAmount = 14 -- Roughly width of "  - "
            
            bulletLine:SetPoint("TOPLEFT", button, "TOPLEFT", leftPadding + db.spacingObjectiveIndent, currentY)
            bulletLine:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
            local objColor = obj.finished and db.completeColor or db.objectiveColor
            bulletLine:SetTextColor(objColor.r, objColor.g, objColor.b, objColor.a)
            bulletLine:SetText("  -")
            bulletLine:Show()

            -- Prepare Prefix
            if not button.objectivePrefixes then button.objectivePrefixes = {} end
            local prefixLine = button.objectivePrefixes[objIndex]
            if not prefixLine then
                prefixLine = button:CreateFontString(nil, "OVERLAY")
                button.objectivePrefixes[objIndex] = prefixLine
            end
            
            local prefixWidth = 0
            if prefixText ~= "" then
                prefixLine:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
                prefixLine:SetTextColor(objColor.r, objColor.g, objColor.b, objColor.a)
                prefixLine:SetText(prefixText)
                prefixLine:ClearAllPoints()
                prefixLine:SetPoint("TOPLEFT", button, "TOPLEFT", leftPadding + db.spacingObjectiveIndent + indentAmount, currentY)
                prefixLine:Show()
                prefixWidth = prefixLine:GetStringWidth()
            else
                prefixLine:Hide()
            end

            -- Prepare Text (Body)
            if not button.objectives then button.objectives = {} end
            local objLine = button.objectives[objIndex]
            if not objLine then
                objLine = button:CreateFontString(nil, "OVERLAY")
                button.objectives[objIndex] = objLine
            end
            
            -- Gap between prefix and body (Reduced to match request)
            local gap = (prefixText ~= "") and 1 or 0
            
            local bodyIndent = leftPadding + db.spacingObjectiveIndent + indentAmount + prefixWidth + gap
            
            -- Width reduced by indent to account for hanging indent
            -- use buttonWidth (calculated from parent) instead of button:GetWidth() which is 0 on first render
            objLine:SetWidth(buttonWidth - bodyIndent - 5)
            objLine:SetWordWrap(true)
            objLine:ClearAllPoints()
            -- Anchor to right of prefix (or bullet if no prefix)
            objLine:SetPoint("TOPLEFT", button, "TOPLEFT", bodyIndent, currentY)
            objLine:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
            --local objColor = obj.finished and db.completeColor or db.objectiveColor -- Already set above
            objLine:SetTextColor(objColor.r, objColor.g, objColor.b, objColor.a)
            objLine:SetText(bodyText)
            objLine:SetJustifyH("LEFT")
            objLine:Show()
            
            local lineH = objLine:GetStringHeight()
            local minLineH = max(1, db.fontSize - 1)
            if lineH < minLineH then
                lineH = minLineH
            end
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
                    else
                         -- Fallback to manual creation
                         bar = CreateFrame("StatusBar", nil, button)
                         bar:SetSize(1, 15)
                         
                         local barTex = "Interface\\TargetingFrame\\UI-StatusBar"
                         if LSM and db.barTexture then
                              barTex = LSM:Fetch("statusbar", db.barTexture) or barTex
                         end
                         bar:SetStatusBarTexture(barTex)
                         
                         bar.bg = bar:CreateTexture(nil, "BACKGROUND")
                         bar.bg:SetAllPoints()
                        local bgC = db.barBackgroundColor
                        local bgR = bgC and bgC.r or 0
                        local bgG = bgC and bgC.g or 0
                        local bgB = bgC and bgC.b or 0
                        local bgA = bgC and bgC.a or 0.5
                        bar.bg:SetColorTexture(bgR, bgG, bgB, bgA)
                         
                         addon:CreateBorderLines(bar, db.barBorderSize)
     
                         bar.value = bar:CreateFontString(nil, "OVERLAY") 
                         bar.value:SetFont(db.fontFace, 9, "OUTLINE")
                         bar.value:SetPoint("CENTER")
                         bar.isTemplate = false
                    end
                    button.progressBars[objIndex] = bar
                end
                
                -- Update bar style only when settings changed
                if not bar.isTemplate then
                     local bgC = db.barBackgroundColor
                     local bgR = bgC and bgC.r or 0
                     local bgG = bgC and bgC.g or 0
                     local bgB = bgC and bgC.b or 0
                     local bgA = bgC and bgC.a or 0.5
                     local barTextureKey = db.barTexture or ""
                     local borderSize = db.barBorderSize or 0

                     if bar._barTextureKey ~= barTextureKey
                        or bar._barBorderSize ~= borderSize
                        or bar._barBgR ~= bgR
                        or bar._barBgG ~= bgG
                        or bar._barBgB ~= bgB
                        or bar._barBgA ~= bgA then
                        local barTex = "Interface\\TargetingFrame\\UI-StatusBar"
                        if LSM and db.barTexture then
                            barTex = LSM:Fetch("statusbar", db.barTexture) or barTex
                        end
                         bar:SetStatusBarTexture(barTex)
                        if bar.bg then bar.bg:SetColorTexture(bgR, bgG, bgB, bgA) end
                        addon:CreateBorderLines(bar, borderSize)
                        bar._barTextureKey = barTextureKey
                        bar._barBorderSize = borderSize
                        bar._barBgR = bgR
                        bar._barBgG = bgG
                        bar._barBgB = bgB
                        bar._barBgA = bgA
                     end
                elseif bar.Bar then
                     local borderSize = db.barBorderSize or 0
                     if bar._borderSizeApplied ~= borderSize then
                         addon:CreateBorderLines(bar.Bar, borderSize)
                         bar._borderSizeApplied = borderSize
                     end
                end

                local barLeft = leftPadding + db.spacingObjectiveIndent
                local barTop = currentY - padding
                local barRightInset = db.spacingProgressBarInset
                local anchorKey = format("%d|%d|%d", barLeft, barTop, barRightInset)
                if bar._anchorKey ~= anchorKey then
                    bar:ClearAllPoints()
                    bar:SetPoint("TOPLEFT", button, "TOPLEFT", barLeft, barTop)
                    bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", -barRightInset, barTop)
                    bar._anchorKey = anchorKey
                end
                
                local percent = 0
                if progressMax > 0 then
                    percent = floor((progressValue / progressMax) * 100)
                end
                local dispText = percent .. "%"
                if progressMax > 0 and progressMax ~= 100 then
                    dispText = format("%d/%d (%d%%)", floor(progressValue), floor(progressMax), percent)
                end

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
                end
                
                bar:Show()

                local barH = 19
                currentY = currentY - barH - padding
                height = height + barH + padding
            elseif button.progressBars and button.progressBars[objIndex] then
                 button.progressBars[objIndex]:Hide()
            end
        end
    end
    
    if button.distance then button.distance:Hide() end
    
    button:SetHeight(height)
    button:Show()
    button.trackableData = item

    if button._scriptMode ~= "trackable" then
        button:SetScript("OnClick", function(self, mouseButton)
            addon:OnTrackableClick(self.trackableData, mouseButton)
        end)
        button:SetScript("OnMouseUp", nil)
        button:SetScript("OnEnter", function(self)
            if addon.db and addon.db.showTooltips then
                addon:ShowTrackableTooltip(self, self.trackableData)
            end
        end)
        button:SetScript("OnLeave", function() addon:HideSharedTooltip() end)
        button._scriptMode = "trackable"
    end
    
    return height
end
