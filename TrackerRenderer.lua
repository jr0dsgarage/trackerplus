local addonName, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local objectiveParseCache = {}
local objectiveParseCacheCount = 0

local function ClearArray(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

local function GetObjectiveParseKey(item, obj, objIndex)
    return table.concat({
        tostring(item.id or item.title or ""),
        tostring(objIndex),
        tostring(obj.type or ""),
        tostring(obj.text or ""),
        tostring(obj.quantityString or ""),
        tostring(obj.numFulfilled or ""),
        tostring(obj.numRequired or ""),
    }, "\31")
end

local function ParseObjectiveDisplay(item, obj, objIndex)
    local cacheKey = GetObjectiveParseKey(item, obj, objIndex)
    local cached = objectiveParseCache[cacheKey]
    if cached then
        return cached
    end

    local parsed = {
        prefixText = "",
        bodyText = "",
        isProgressBar = false,
        progressValue = 0,
        progressMax = 100,
    }

    local required = tonumber(obj.numRequired)
    local fulfilled = tonumber(obj.numFulfilled)

    if obj.type == "progressbar" then
        parsed.isProgressBar = true

        -- Follow Blizzard's task progress source when available.
        if C_TaskQuest and C_TaskQuest.GetQuestProgressBarInfo and item and item.id then
            local taskProgress = C_TaskQuest.GetQuestProgressBarInfo(item.id)
            if taskProgress ~= nil then
                parsed.progressValue = tonumber(taskProgress) or 0
                parsed.progressMax = 100
            else
                -- Fallback to explicit objective percentage if provided by Blizzard objective text.
                local percentMatch = string.match(obj.quantityString or "", "(%d+)%%")
                if not percentMatch then
                    percentMatch = string.match(obj.text or "", "(%d+)%%")
                end
                if percentMatch then
                    parsed.progressValue = tonumber(percentMatch) or 0
                    parsed.progressMax = 100
                elseif required and required > 0 then
                    parsed.progressValue = fulfilled or 0
                    parsed.progressMax = required
                else
                    local ratioFulfilled, ratioRequired = string.match(obj.quantityString or "", "(%d+)%s*/%s*(%d+)")
                    if not ratioFulfilled then
                        ratioFulfilled, ratioRequired = string.match(obj.text or "", "(%d+)%s*/%s*(%d+)")
                    end
                    if ratioFulfilled and ratioRequired then
                        parsed.progressValue = tonumber(ratioFulfilled) or 0
                        parsed.progressMax = tonumber(ratioRequired) or 100
                    else
                        parsed.progressValue = fulfilled or 0
                        parsed.progressMax = 100
                    end
                end
            end
        elseif required and required > 0 then
            parsed.progressValue = fulfilled or 0
            parsed.progressMax = required
        else
            local percentMatch = string.match(obj.quantityString or "", "(%d+)%%")
            if not percentMatch then
                percentMatch = string.match(obj.text or "", "(%d+)%%")
            end

            if percentMatch then
                parsed.progressValue = tonumber(percentMatch) or 0
                parsed.progressMax = 100
            else
                local ratioFulfilled, ratioRequired = string.match(obj.quantityString or "", "(%d+)%s*/%s*(%d+)")
                if not ratioFulfilled then
                    ratioFulfilled, ratioRequired = string.match(obj.text or "", "(%d+)%s*/%s*(%d+)")
                end

                if ratioFulfilled and ratioRequired then
                    parsed.progressValue = tonumber(ratioFulfilled) or 0
                    parsed.progressMax = tonumber(ratioRequired) or 100
                else
                    parsed.progressValue = fulfilled or 0
                    parsed.progressMax = 100
                end
            end
        end

        if parsed.progressMax <= 0 then parsed.progressMax = 100 end
        if parsed.progressValue < 0 then parsed.progressValue = 0 end
        if parsed.progressValue > parsed.progressMax then parsed.progressValue = parsed.progressMax end

        -- Follow Blizzard completion state for visibility, not just computed percentage.
        -- If Blizzard marks objective or quest complete, hide the progress bar row.
        local objectiveFinished = (obj.finished == true)
        local questFinished = (item and (item.isComplete == true or item.isFinished == true))
        if objectiveFinished or questFinished then
            parsed.isProgressBar = false
        end

        local cleanText = obj.text or ""
        cleanText = cleanText:gsub("%s*%(%d+%%%)", "")
        cleanText = cleanText:gsub("%s*%d+%%", "")
        cleanText = cleanText:gsub("^%d+/%d+%s*", "")
        cleanText = cleanText:gsub(":%s*$", "")
        cleanText = cleanText:gsub("^%s+", ""):gsub("%s+$", "")
        if cleanText == "" and obj.text then
            cleanText = obj.text:gsub("%s*%(%d+%%%)", "")
        end
        parsed.bodyText = (cleanText or "Progress")
    elseif obj.quantityString and obj.quantityString ~= "" then
        parsed.bodyText = (obj.text or ""):gsub("^%d+/%d+%s*", ""):gsub("^%s+", "")
        parsed.prefixText = obj.quantityString
    elseif obj.numRequired and obj.numRequired > 0 then
        parsed.bodyText = (obj.text or ""):gsub("^%d+/%d+%s*", ""):gsub("^%s+", "")
        parsed.prefixText = string.format("%d/%d", obj.numFulfilled or 0, obj.numRequired)
    else
        local p, b = (obj.text or ""):match("^%s*([%d]+/[%d]+)%s+(.*)$")
        if p then
            parsed.prefixText = p
            parsed.bodyText = b
        else
            parsed.bodyText = (obj.text or "")
        end
    end

    if parsed.prefixText ~= "" and (not parsed.bodyText or parsed.bodyText == "") then
        parsed.bodyText = " "
    end

    objectiveParseCache[cacheKey] = parsed
    objectiveParseCacheCount = objectiveParseCacheCount + 1
    if objectiveParseCacheCount > 4000 then
        wipe(objectiveParseCache)
        objectiveParseCacheCount = 0
    end

    return parsed
end

-- Update tracker display with trackables
function addon:RenderTrackableItem(parent, item, yOffset, indent)
    local db = self.db
    local button = self:GetOrCreateButton(parent)
    if button.expandBtn then button.expandBtn:Hide() end -- Hide expand button if recycled
    
    -- Cleanup recycled elements
    if button.objectiveBullets then for _, v in ipairs(button.objectiveBullets) do v:Hide() end end
    if button.objectives then for _, v in ipairs(button.objectives) do v:Hide() end end
    if button.objectivePrefixes then for _, v in ipairs(button.objectivePrefixes) do v:Hide() end end
    if button.progressBars then for _, v in ipairs(button.progressBars) do v:Hide() end end

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
        secureBtn:SetAttribute("item", item.item.link)
        
        -- Robust Icon handling
        local texture = item.item.texture
        
        -- Try to fetch via API if missing
        if not texture and item.item.link then
             texture = GetItemIcon(item.item.link)
             
             -- If GetItemIcon fails (returns nil), try Instant info which is cache-independent for icons
             if not texture then
                  local _, _, _, _, iconID = GetItemInfoInstant(item.item.link)
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
        if item.type == "supertrack" then
             -- Icon is 36px wide and sits at -5px from right. Left edge is at -41px.
             -- Add padding so text doesn't overlap (approx -45px)
             rightPadding = -45 
        else
             rightPadding = -22 -- Make room for item button
        end
    end

    button.text:ClearAllPoints()
    button.text:SetPoint("TOPLEFT", leftPadding, -2) 
    button.text:SetPoint("TOPRIGHT", rightPadding, -2)

    local titleText = item.title
    if db.showQuestLevel and item.level and item.level > 0 then
        titleText = string.format("[%d] %s", item.level, titleText)
    end

    local function NormalizeHeaderText(value)
        if not value or value == "" then return "" end
        local normalized = tostring(value):lower()
        normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
        normalized = normalized:gsub("[^%w%s]", "")
        normalized = normalized:gsub("%s+", " ")
        return normalized
    end

    local function IsQuestTypeRedundant(typeText)
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

    if item.questType
        and not item.isWorldQuest
        and item.type ~= "worldquest"
        and not IsQuestTypeRedundant(item.questType) then
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
            local minLineH = math.max(1, db.fontSize - 1)
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
                         local bgC = db.barBackgroundColor or {r=0,g=0,b=0,a=0.5}
                         bar.bg:SetColorTexture(bgC.r, bgC.g, bgC.b, bgC.a)
                         
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
                     local barTex = "Interface\\TargetingFrame\\UI-StatusBar"
                     if LSM and db.barTexture then
                          barTex = LSM:Fetch("statusbar", db.barTexture) or barTex
                     end
                     local bgC = db.barBackgroundColor or {r=0,g=0,b=0,a=0.5}
                     local styleSig = string.format("%s|%d|%.3f|%.3f|%.3f|%.3f",
                         tostring(barTex),
                         db.barBorderSize or 0,
                         bgC.r or 0, bgC.g or 0, bgC.b or 0, bgC.a or 0
                     )
                     if bar._styleSig ~= styleSig then
                         bar:SetStatusBarTexture(barTex)
                         if bar.bg then bar.bg:SetColorTexture(bgC.r, bgC.g, bgC.b, bgC.a) end
                         addon:CreateBorderLines(bar, db.barBorderSize)
                         bar._styleSig = styleSig
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
                local anchorKey = string.format("%d|%d|%d", barLeft, barTop, barRightInset)
                if bar._anchorKey ~= anchorKey then
                    bar:ClearAllPoints()
                    bar:SetPoint("TOPLEFT", button, "TOPLEFT", barLeft, barTop)
                    bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", -barRightInset, barTop)
                    bar._anchorKey = anchorKey
                end
                
                local percent = 0
                if progressMax > 0 then
                    percent = math.floor((progressValue / progressMax) * 100)
                end
                local dispText = percent .. "%"
                if progressMax > 0 and progressMax ~= 100 then
                    dispText = string.format("%d/%d (%d%%)", math.floor(progressValue), math.floor(progressMax), percent)
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
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button._scriptMode = "trackable"
    end
    
    return height
end

function addon:UpdateTrackerDisplay(trackables)
    local trackerFrame = self.trackerFrame
    local contentFrame = self.contentFrame

    if not trackerFrame or not contentFrame then
        return
    end
    
    self:ResetButtonPool()
    
    local db = self.db

    local function ApplyConfiguredHeaderBackground(header)
        local bgStyle = db.headerBackgroundStyle or "tracker"
        header.bg:ClearAllPoints()

        if bgStyle == "none" then
            header.bg:SetAllPoints(header)
            header.bg:SetColorTexture(0, 0, 0, 0)
        elseif bgStyle == "questlog" then
            header.bg:SetPoint("TOPLEFT", header, "TOPLEFT", 2, 0)
            header.bg:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -2, 0)
            if header.bg.SetAtlas then
                header.bg:SetAtlas("QuestLog-tab")
                header.bg:SetVertexColor(1, 1, 1, 1)
            else
                header.bg:SetTexture("Interface\\QuestFrame\\QuestLog-tab")
                header.bg:SetTexCoord(0, 1, 0, 1)
            end
        else
            header.bg:SetAllPoints(header)
            if header.bg.SetAtlas then
                header.bg:SetAtlas("UI-QuestTracker-Secondary-Objective-Header")
                header.bg:SetVertexColor(1, 1, 1, 1)
            else
                header.bg:SetColorTexture(0, 0, 0, 0.2)
            end
        end
    end
    
    -- Extract Scenarios and Super Tracked items first
    self._tmpScenarios = self._tmpScenarios or {}
    self._tmpAutoQuests = self._tmpAutoQuests or {}
    self._tmpSuperTrackedItems = self._tmpSuperTrackedItems or {}
    self._tmpBonusObjectives = self._tmpBonusObjectives or {}
    self._tmpWorldQuestItems = self._tmpWorldQuestItems or {}
    self._tmpRemainingTrackables = self._tmpRemainingTrackables or {}

    local scenarios = self._tmpScenarios
    local autoQuests = self._tmpAutoQuests
    local superTrackedItems = self._tmpSuperTrackedItems
    local bonusObjectives = self._tmpBonusObjectives
    local worldQuestItems = self._tmpWorldQuestItems
    local remainingTrackables = self._tmpRemainingTrackables

    ClearArray(scenarios)
    ClearArray(autoQuests)
    ClearArray(superTrackedItems)
    ClearArray(bonusObjectives)
    ClearArray(worldQuestItems)
    ClearArray(remainingTrackables)
    
    local superTrackedQuestID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID()) or 0

    for _, item in ipairs(trackables) do
        if item.type == "scenario" then
            table.insert(scenarios, item)
        elseif item.type == "autoquest" then
            table.insert(autoQuests, item)
        elseif item.type == "supertrack" then
            if superTrackedQuestID > 0
                and item.id
                and item.id == superTrackedQuestID
                and item.title
                and item.title ~= "" then
                table.insert(superTrackedItems, item)
            end
        elseif item.type == "bonus" then
            table.insert(bonusObjectives, item)
        elseif item.type == "worldquest" then
            table.insert(worldQuestItems, item)
        else
            table.insert(remainingTrackables, item)
        end
    end
    
    self.currentScenarios = scenarios
    trackables = remainingTrackables
    
    -- Group trackables if needed
    if db.groupByZone or db.groupByCategory then
        trackables = self:OrganizeTrackables(trackables)
    end
    
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
              if button.objectiveBullets then for _, obj in ipairs(button.objectiveBullets) do obj:Hide() end end
              if button.objectivePrefixes then for _, obj in ipairs(button.objectivePrefixes) do obj:Hide() end end
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
                   button.popupBackdrop:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
                   button.popupBackdrop:SetBackdropBorderColor(1, 0.8, 0, 1) -- Gold Border
                   button.popupBackdrop:SetPoint("TOPLEFT", 0, 0)
                   button.popupBackdrop:SetPoint("BOTTOMRIGHT", 0, 0)
                   button.popupBackdrop:SetFrameLevel(button:GetFrameLevel()+1) 
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
              if button._scriptMode ~= "autoquest" then
                  button:SetScript("OnClick", function(self, mouseButton)
                      addon:OnTrackableClick(self.trackableData, mouseButton)
                  end)
                  button:SetScript("OnMouseUp", nil)
                  button:SetScript("OnEnter", nil)
                  button:SetScript("OnLeave", nil)
                  button._scriptMode = "autoquest"
              end
              
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
             pcall(function()
                -- Reparent to our dedicated frame
                if widgetContainer:GetParent() ~= self.widgetFrame then
                    widgetContainer:SetParent(self.widgetFrame)
                    widgetContainer:SetFrameStrata("HIGH")
                    self._widgetContainerAnchored = false
                end

                if not self._widgetContainerAnchored then
                    widgetContainer:ClearAllPoints()
                    widgetContainer:SetPoint("TOP", self.widgetFrame, "TOP", 0, -5)
                    self._widgetContainerAnchored = true
                end
                
                widgetContainer:Show()
             end)
            
            -- Calculate height
            widgetHeight = widgetContainer:GetHeight() or 0
            
            -- Ignore negligible height (often ghost frames)
            if widgetHeight < 2 then widgetHeight = 0 end
        end
        
        -- Exact height if content exists, otherwise 1px
        local finalWidgetH = (widgetHeight > 0) and (widgetHeight + 5) or 1
        self.widgetFrame:SetHeight(finalWidgetH)

        -- Dynamic Anchoring to remove gaps
        if self.autoQuestFrame then
             local aqVisible = (self.autoQuestFrame:GetHeight() > 10)
             -- Use 0 padding if not visible, standard -5 if visible
             local padding = aqVisible and -5 or 0
               if self._widgetFramePadding ~= padding then
                  self.widgetFrame:ClearAllPoints()
                  self.widgetFrame:SetPoint("TOPLEFT", self.autoQuestFrame, "BOTTOMLEFT", 0, padding)
                  self.widgetFrame:SetPoint("TOPRIGHT", self.autoQuestFrame, "BOTTOMRIGHT", 0, padding)
                  self._widgetFramePadding = padding
               end
        end
        else
            self._widgetContainerAnchored = false
            self._widgetFramePadding = nil
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
            local scenarioTopInset = 5
            local scenarioBottomPadding = 14
         -- We are using Blizzard's frame, so we hijack it.
         local contents = scenarioTracker.ContentsFrame
         
         -- Parent it to our frame
         if contents:GetParent() ~= self.scenarioFrame then
              contents:SetParent(self.scenarioFrame)
              -- FORCE STRATA: The user screenshot showed LOW, but our frame is MEDIUM.
              -- We must bring it up to at least MEDIUM or HIGH to be seen on top of our bg.
              contents:SetFrameStrata("HIGH") 
              contents:SetFrameLevel(100)
              
                -- Create a solid opaque backdrop behind the hijacked scenario frame to hide content below it
              if not self.scenarioFrame.bgMask then
                   self.scenarioFrame.bgMask = self.scenarioFrame:CreateTexture(nil, "BACKGROUND")
                   self.scenarioFrame.bgMask:SetColorTexture(0, 0, 0, 0.9) -- Dark opaque background
              end
         end

            -- Keep mask anchors in sync every update (not only on first reparent),
            -- so height changes from scenario criteria updates do not leave visual gaps.
            if self.scenarioFrame.bgMask then
                self.scenarioFrame.bgMask:ClearAllPoints()
                self.scenarioFrame.bgMask:SetPoint("TOPLEFT", self.scenarioFrame, "TOPLEFT", 0, 0)
                self.scenarioFrame.bgMask:SetPoint("TOPRIGHT", self.scenarioFrame, "TOPRIGHT", 0, 0)
                self.scenarioFrame.bgMask:SetPoint("BOTTOM", contents, "BOTTOM", 0, -scenarioBottomPadding)
                self.scenarioFrame.bgMask:Show()
            end

            local scenarioWidth = self.db.frameWidth - 5
            if not self._scenarioContentsAnchored or self._scenarioContentsWidth ~= scenarioWidth then
                contents:ClearAllPoints()
                 contents:SetPoint("TOP", self.scenarioFrame, "TOP", -20, -scenarioTopInset)
                -- Constrain width so it fits our frame (and forces word wrap if supported)
                contents:SetWidth(scenarioWidth)
                self._scenarioContentsAnchored = true
                self._scenarioContentsWidth = scenarioWidth
            end
         
         contents:Show()
         
         -- Attempt to find internal WidgetContainer and force show it
         if contents.WidgetContainer then
             contents.WidgetContainer:Show()
         end
         
         -- Try to force update safely
         if scenarioTracker.Update then
                pcall(function() scenarioTracker:Update() end)
         end

         -- The height of the blizzard frame varies. We need to update our container to match it.
         local blizzardHeight = contents:GetHeight() or 0
         if contents.WidgetContainer and contents.WidgetContainer.GetHeight then
             blizzardHeight = math.max(blizzardHeight, contents.WidgetContainer:GetHeight() or 0)
         end
         
         -- If height is 0 (collapsed/hidden), force a minimum reasonable height so widgets aren't crushed
         if not blizzardHeight or blizzardHeight < 40 then 
             blizzardHeight = 100 
             contents:SetHeight(blizzardHeight) -- Force the frame open
         end

         scenarioHeight = blizzardHeight + scenarioTopInset + scenarioBottomPadding
         scenarioYOffset = scenarioHeight
         
    else
        self._scenarioContentsAnchored = false
        self._scenarioContentsWidth = nil
        if self.scenarioFrame and self.scenarioFrame.bgMask then
             self.scenarioFrame.bgMask:Hide()
        end
    end

    if (not useBlizzardScenario) and self.currentScenarios and #self.currentScenarios > 0 then
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
        if header.objectiveBullets then for _, obj in ipairs(header.objectiveBullets) do obj:Hide() end end
        if header.objectivePrefixes then for _, obj in ipairs(header.objectivePrefixes) do obj:Hide() end end
        if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end
        if header.distance then header.distance:Hide() end
        
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
              if button.expandBtn then button.expandBtn:Hide() end
              if button.distance then button.distance:Hide() end
              
              if button.objectives then for _, obj in ipairs(button.objectives) do obj:Hide() end end
              if button.objectiveBullets then for _, obj in ipairs(button.objectiveBullets) do obj:Hide() end end
              if button.objectivePrefixes then for _, obj in ipairs(button.objectivePrefixes) do obj:Hide() end end
              if button.progressBars then for _, bar in ipairs(button.progressBars) do bar:Hide() end end
              
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
                 -- Higher frame level to cover other elements if needed, but not too high
                 button.stageBox:SetFrameLevel(button:GetFrameLevel() + 5) 
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
                             local cur = obj.numFulfilled or 0
                             local req = obj.numRequired or 0
                             local percent

                             if req > 0 then
                                 percent = (cur / req) * 100
                             elseif cur <= 100 then
                                 percent = cur
                             else
                                 percent = 100
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
                                    
                                    local barTex = "Interface\\TargetingFrame\\UI-StatusBar"
                                    if LSM and db.barTexture then
                                         barTex = LSM:Fetch("statusbar", db.barTexture) or barTex
                                    end
                                    bar:SetStatusBarTexture(barTex)
                                    
                                    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
                                    bar.bg:SetAllPoints()
                                    local bgC = db.barBackgroundColor or {r=0,g=0,b=0,a=0.5}
                                    bar.bg:SetColorTexture(bgC.r, bgC.g, bgC.b, bgC.a)
                                    
                                    bar.value = bar:CreateFontString(nil, "OVERLAY")
                                    bar.value:SetFont(db.fontFace, 10, "OUTLINE")
                                    bar.value:SetPoint("CENTER")
                                    
                                    addon:CreateBorderLines(bar, db.barBorderSize)
                                    bar.isTemplate = false
                                end
                                button.progressBars[objIndex] = bar
                            end
                            
                            -- Update style only when settings changed
                            if not bar.isTemplate then
                                 local barTex = "Interface\\TargetingFrame\\UI-StatusBar"
                                 if LSM and db.barTexture then
                                      barTex = LSM:Fetch("statusbar", db.barTexture) or barTex
                                 end
                                 local bgC = db.barBackgroundColor or {r=0,g=0,b=0,a=0.5}
                                 local styleSig = string.format("%s|%d|%.3f|%.3f|%.3f|%.3f",
                                     tostring(barTex),
                                     db.barBorderSize or 0,
                                     bgC.r or 0, bgC.g or 0, bgC.b or 0, bgC.a or 0
                                 )
                                 if bar._styleSig ~= styleSig then
                                     bar:SetStatusBarTexture(barTex)
                                     if bar.bg then bar.bg:SetColorTexture(bgC.r, bgC.g, bgC.b, bgC.a) end
                                     addon:CreateBorderLines(bar, db.barBorderSize)
                                     bar._styleSig = styleSig
                                 end
                            elseif bar.Bar then
                                 local borderSize = db.barBorderSize or 0
                                 if bar._borderSizeApplied ~= borderSize then
                                     addon:CreateBorderLines(bar.Bar, borderSize)
                                     bar._borderSizeApplied = borderSize
                                 end
                            end

                            local anchorKey = string.format("%d|%d|%d", 20, -height, 20)
                            if bar._anchorKey ~= anchorKey then
                                bar:ClearAllPoints()
                                bar:SetPoint("TOPLEFT", 20, -height)
                                bar:SetPoint("TOPRIGHT", -20, -height)
                                bar._anchorKey = anchorKey
                            end
                            
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
        if superTrackedQuestID > 0 and #superTrackedItems > 0 then
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
         
         -- User requested "a few pixels bigger"
         local backdropPadding = 10
         header.styledBackdrop:SetHeight(totalHeight + backdropPadding)
         
         -- Increase frame offset so the scroll frame below doesn't overlap the backdrop
         scenarioYOffset = scenarioYOffset + backdropPadding
    end
    
    --------------------------------------------------------------------------
    -- 1.5 Render Bonus Objectives (Pinned to Bottom)
    --------------------------------------------------------------------------
    local bonusYOffset = 0
    
    -- Strategy: Hijack Blizzard's BonusObjectiveTracker frame if it exists and has content
    local bonusTracker = BonusObjectiveTracker
    local useBlizzardBonus = (bonusTracker and bonusTracker.ContentsFrame)
    
    if useBlizzardBonus then
         local contents = bonusTracker.ContentsFrame
         local blizzardBonusHeight = contents:GetHeight() or 0
         
         -- Use IsShown() instead of IsVisible() because our parent (ObjectiveTrackerFrame) might be hidden
         local hasContent = blizzardBonusHeight > 1 and contents:IsShown()
         
         -- Also check if there are actual child frames with bars (sometimes height is 0 but children exist)
         if not hasContent then
             -- ContentsFrame might report height but children are individually visible
             for _, child in pairs({contents:GetChildren()}) do
                 -- Check IsShown because IsVisible fails if we hid the main tracker
                 if child:IsShown() and child:GetHeight() > 1 then
                     hasContent = true
                     blizzardBonusHeight = math.max(blizzardBonusHeight, 10) -- Will recalculate below
                     break
                 end
             end
         end
         
         if hasContent then
              -- Reparent to our bonusFrame
                pcall(function()
                  if contents:GetParent() ~= self.bonusFrame then
                       contents:SetParent(self.bonusFrame)
                       contents:SetFrameStrata("HIGH")
                       contents:SetFrameLevel(100)
                       self._bonusContentsAnchored = false
                       self._bonusContentsWidth = nil
                  end

                    local bonusWidth = self.db.frameWidth - 10
                    if not self._bonusContentsAnchored or self._bonusContentsWidth ~= bonusWidth then
                        contents:ClearAllPoints()
                        contents:SetPoint("TOP", self.bonusFrame, "TOP", 0, -5)
                        contents:SetWidth(bonusWidth)
                        self._bonusContentsAnchored = true
                        self._bonusContentsWidth = bonusWidth
                    end

                   contents:Show()
                   contents:SetAlpha(1) -- Force visibility even if parent OTF is Alpha 0
                   
                   -- Recursively set alpha on children to override parent fade?
                   -- Frames inherit Alpha by default (use SetIgnoreParentAlpha if available)
                   if contents.SetIgnoreParentAlpha then
                        contents:SetIgnoreParentAlpha(true)
                   end

                   -- Ensure children are shown (some instances hide children but show parent)
                   if contents.WidgetContainer then 
                        contents.WidgetContainer:Show() 
                        contents.WidgetContainer:SetAlpha(1)
                   end
              end)
              
              -- Recalculate height after reparenting (layout may have changed)
              blizzardBonusHeight = contents:GetHeight() or 0
              if blizzardBonusHeight < 20 then blizzardBonusHeight = 60 end -- Minimum if we know there's content
              
              bonusYOffset = blizzardBonusHeight + 10
              
         else
              -- No bonus content - restore to its original parent if we stole it
              if contents:GetParent() == self.bonusFrame then
                   pcall(function()
                       contents:SetParent(bonusTracker)
                       contents:ClearAllPoints()
                       contents:SetPoint("TOPLEFT", bonusTracker, "TOPLEFT", 0, 0)
                   end)
              end
                self._bonusContentsAnchored = false
                self._bonusContentsWidth = nil
         end
    end

        if not useBlizzardBonus then
            self._bonusContentsAnchored = false
            self._bonusContentsWidth = nil
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
         ApplyConfiguredHeaderBackground(header)
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
        if addon.db.minimized then
             self.bonusFrame:Hide()
        else
             self.bonusFrame:Show()
        
             -- DEBUG: If logic says we are showing it, but it's invisible, force visibility on children
             if useBlizzardBonus and self.bonusFrame:GetNumChildren() > 0 then
                  local kids = {self.bonusFrame:GetChildren()}
                  for _, kid in ipairs(kids) do
                       kid:Show()
                       kid:SetAlpha(1)
                  end
             end
        end
    else
        self.bonusFrame:Hide()
    end
    
    -- 1.6 Render World Quests (Pinned to Absolute Bottom)
    --------------------------------------------------------------------------
    local wqYOffset = 0
    local wqFrame = self.worldQuestFrame
    local hasBlizzardWQContent = false
    local manualWQRendered = 0
    
    -- Hijacking Strategy for World Quests
    local wqTracker = WorldQuestObjectiveTracker
    local useBlizzardWQ = (wqTracker and wqTracker.ContentsFrame)
    local preferManualWQ = (#worldQuestItems > 0)
    if preferManualWQ then
        useBlizzardWQ = false
    end
    
    if useBlizzardWQ then
         local contents = wqTracker.ContentsFrame
         local blizzardWQHeight = contents:GetHeight() or 0
         
         -- Use IsShown() instead of IsVisible() because parent might be hidden
         -- If we are already hijacking (parent is wqFrame) and collapsed, we assume we still have control
         local isHijacked = (contents:GetParent() == wqFrame)
         local isCollapsed = db.collapsedSections and db.collapsedSections["World Quests"]
         
         local hasContent = false
         if isHijacked and isCollapsed then hasContent = true end

         -- Prefer concrete visible child rows over container size, since the Blizzard
         -- frame can report non-zero height even when rows have not rendered yet.
         for _, child in pairs({contents:GetChildren()}) do
             if child:IsShown() and child:GetHeight() > 8 then
                 hasContent = true
                 blizzardWQHeight = math.max(blizzardWQHeight, child:GetHeight() or 10)
             end
         end

         if not hasContent and contents.WidgetContainer and contents.WidgetContainer:IsShown() then
             local widgetHeight = contents.WidgetContainer:GetHeight() or 0
             if widgetHeight > 8 then
                 hasContent = true
                 blizzardWQHeight = math.max(blizzardWQHeight, widgetHeight)
             end
         end
         
         if hasContent then
              hasBlizzardWQContent = true
              -- Hijack it!
                pcall(function()
                  if contents:GetParent() ~= wqFrame then
                       contents:SetParent(wqFrame)
                       contents:SetFrameStrata("HIGH")
                       contents:SetFrameLevel(100)
                       self._wqContentsAnchored = false
                       self._wqContentsWidth = nil
                   end

                   local wqWidth = self.db.frameWidth - 10
                   if not self._wqContentsAnchored or self._wqContentsWidth ~= wqWidth then
                      contents:ClearAllPoints()
                      -- Position it BELOW the header (which we will create manually below at y=0)
                      contents:SetPoint("TOP", wqFrame, "TOP", 0, -28)
                      contents:SetWidth(wqWidth)
                      self._wqContentsAnchored = true
                      self._wqContentsWidth = wqWidth
                   end

                   contents:Show()
                   contents:SetAlpha(1)
                   if contents.SetIgnoreParentAlpha then contents:SetIgnoreParentAlpha(true) end
              
                   if contents.WidgetContainer then
                       contents.WidgetContainer:Show()
                       contents.WidgetContainer:SetAlpha(1)
                   end
              
                   -- Try to trigger internal update
                   if wqTracker.Update then wqTracker:Update() end
              end)
              
              if blizzardWQHeight < 20 then blizzardWQHeight = 40 end
              -- Calculate offset including the header we are about to make
              wqYOffset = blizzardWQHeight + 35 
         else
              -- Restore if empty
              if contents:GetParent() == wqFrame then
                   pcall(function()
                       contents:SetParent(wqTracker)
                       contents:ClearAllPoints()
                       contents:SetPoint("TOPLEFT", wqTracker, "TOPLEFT", 0, 0)
                   end)
              end
                self._wqContentsAnchored = false
                self._wqContentsWidth = nil
                 hasBlizzardWQContent = false
         end
    end

        if not useBlizzardWQ then
            -- Ensure Blizzard WQ frame is restored when we switch to manual mode.
            if wqTracker and wqTracker.ContentsFrame then
                local contents = wqTracker.ContentsFrame
                if contents:GetParent() == wqFrame then
                    pcall(function()
                        contents:SetParent(wqTracker)
                        contents:ClearAllPoints()
                        contents:SetPoint("TOPLEFT", wqTracker, "TOPLEFT", 0, 0)
                    end)
                end
            end
            self._wqContentsAnchored = false
            self._wqContentsWidth = nil
            hasBlizzardWQContent = false
        end

    -- Render the Header container for World Quests (Either used by Hijacked frame or manual items)
    if wqFrame and (hasBlizzardWQContent or #worldQuestItems > 0) then
        if not db.collapsedSections then db.collapsedSections = {} end
        local collapsed = db.collapsedSections["World Quests"]
        
        -- Header
        local header = self:GetOrCreateButton(wqFrame)
        header:SetPoint("TOPLEFT", wqFrame, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", wqFrame, "TOPRIGHT", 0, 0)
        
        header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
        header.text:SetTextColor(db.headerColor.r, db.headerColor.g, db.headerColor.b, db.headerColor.a)
        header.text:SetText("World Quests")
        header.text:SetJustifyH("LEFT")
        header.text:ClearAllPoints()
        header.text:SetPoint("LEFT", 5, 0)
        header.text:SetPoint("RIGHT", -25, 0)
        
        -- Expand Button
        if not header.expandBtn then
             header.expandBtn = CreateFrame("Button", nil, header)
             header.expandBtn:SetSize(16, 16)
        end
        header.expandBtn:SetPoint("RIGHT", -8, 0)
        header.expandBtn:Show()
        
        -- Expand/Collapse Logic
        local function UpdateWQCollapseIcon()
            local atlas = collapsed and "UI-QuestTrackerButton-Secondary-Expand" or "UI-QuestTrackerButton-Secondary-Collapse"
            header.expandBtn:SetNormalAtlas(atlas)
            header.expandBtn:SetPushedAtlas(atlas)
        end
        UpdateWQCollapseIcon()
        
        header.expandBtn:SetScript("OnClick", function()
            db.collapsedSections["World Quests"] = not db.collapsedSections["World Quests"]
            addon:RequestUpdate()
        end)
        
        ApplyConfiguredHeaderBackground(header)
        
        -- Cleanup header recycling
        if header.poiButton then header.poiButton:Hide() end
        if header.itemButton then header.itemButton:Hide() end
        if header.distance then header.distance:Hide() end
        if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
        if header.objectiveBullets then for _, obj in ipairs(header.objectiveBullets) do obj:Hide() end end
        if header.objectivePrefixes then for _, obj in ipairs(header.objectivePrefixes) do obj:Hide() end end
        if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end
        if header.styledBackdrop then header.styledBackdrop:Hide() end

        -- If Hijacked frame was found, we don't need to manually render items, 
        -- BUT if hijacked frame was found and YOffset > 0, we just set the header. 
        -- If we are collapsed, we need to hide the hijacked frame!
        
           if useBlizzardWQ and hasBlizzardWQContent and wqYOffset > 0 then
             local contents = wqTracker.ContentsFrame
             if collapsed then
                  contents:Hide()
                  wqYOffset = 24
             else
                  contents:Show()
                  contents:SetAlpha(1)
                   if contents.SetIgnoreParentAlpha then contents:SetIgnoreParentAlpha(true) end
                  
                  if contents.WidgetContainer then
                       contents.WidgetContainer:Show()
                       contents.WidgetContainer:SetAlpha(1)
                  end
             end
           elseif #worldQuestItems > 0 and (wqYOffset == 0 or not hasBlizzardWQContent) then
               -- Fallback: manual render when Blizzard WQ container is missing/empty.
             wqYOffset = 24 + 5
             
             if not collapsed then
                for _, item in ipairs(worldQuestItems) do
                    local height = self:RenderTrackableItem(wqFrame, item, wqYOffset, db.spacingMinorHeaderIndent + 10)
                    wqYOffset = wqYOffset + height + db.spacingItemVertical
                    manualWQRendered = manualWQRendered + 1
                end
            end
        end

        if addon.Log then
            local diagSig = table.concat({
                tostring(useBlizzardWQ),
                tostring(hasBlizzardWQContent),
                tostring(#worldQuestItems),
                tostring(manualWQRendered),
                tostring(collapsed),
                tostring(wqYOffset),
            }, "|")
            if self._wqDiagSig ~= diagSig then
                addon:Log("WQ diag: useBlizz=%s hasBlizz=%s items=%d manual=%d collapsed=%s y=%d", tostring(useBlizzardWQ), tostring(hasBlizzardWQContent), #worldQuestItems, manualWQRendered, tostring(collapsed), wqYOffset)
                self._wqDiagSig = diagSig
            end
        end
    end
    
    if wqFrame then
        if wqYOffset > 0 then
            wqFrame:SetHeight(wqYOffset)
            if addon.db.minimized then
                 wqFrame:Hide()
            else
                 wqFrame:Show()
            end
        else
            wqFrame:SetHeight(0.1) -- Minimal height to prevent layout gaps
            wqFrame:Hide()
        end
    end

        -- Update Scenario Frame Height & ScrollFrame Anchor
        local topParent, topPoint, topRelPoint, topX, topY
    if scenarioYOffset > 0 then
        self.scenarioFrame:SetHeight(scenarioYOffset)
        if addon.db.minimized then
            self.scenarioFrame:Hide()
        else
            self.scenarioFrame:Show()
        end
           topParent, topPoint, topRelPoint, topX, topY = self.scenarioFrame, "TOPLEFT", "BOTTOMLEFT", 0, -4
    else
        self.scenarioFrame:Hide()
           topParent, topPoint, topRelPoint, topX, topY = self.trackerFrame, "TOPLEFT", "TOPLEFT", 0, -25
    end
    
    -- Bottom Anchor Logic: Stack Scroll -> Bonus -> WQ -> Bottom
        local bottomParent
    if bonusYOffset > 0 then
            bottomParent = self.bonusFrame
    elseif wqYOffset > 0 and wqFrame then
            bottomParent = wqFrame
    else
            bottomParent = self.trackerFrame
        end

        local anchorSignature = table.concat({
           tostring(topParent), tostring(topPoint), tostring(topRelPoint), tostring(topX), tostring(topY),
           tostring(bottomParent),
        }, "|")

        if self._scrollAnchorSignature ~= anchorSignature then
            self.scrollFrame:ClearAllPoints()
            self.scrollFrame:SetPoint(topPoint, topParent, topRelPoint, topX, topY)
            if bottomParent == self.trackerFrame then
                self.scrollFrame:SetPoint("BOTTOMRIGHT", self.trackerFrame, "BOTTOMRIGHT", -5, 5)
            else
                self.scrollFrame:SetPoint("BOTTOMRIGHT", bottomParent, "TOPRIGHT", 0, 0)
            end
            self._scrollAnchorSignature = anchorSignature
    end

    --------------------------------------------------------------------------
    -- 2. Render Normal Trackables (In ScrollFrame)
    --------------------------------------------------------------------------
    local yOffset = 5  -- Start near top of content frame
    local currentMajorCollapsed = false
    local currentMinorCollapsed = false
    local currentMajorHeaderTitle = nil
    local currentMinorHeaderTitle = nil
    
    -- Display trackables
    for _, item in ipairs(trackables) do
        if item.isHeader then
            local isMajor = item.headerType == "major"

            -- Update collapse state
            if isMajor then
                currentMajorCollapsed = item.collapsed
                currentMinorCollapsed = false -- Reset minor scope when entering new major section
                currentMajorHeaderTitle = item.title
                currentMinorHeaderTitle = nil
            else
                currentMinorCollapsed = item.collapsed
                currentMinorHeaderTitle = item.title
            end

            -- Skip rendering minor headers if the major section is collapsed
            if not (not isMajor and currentMajorCollapsed) then
                -- Zone/Category Header
                local header = self:GetOrCreateButton(contentFrame) -- Use contentFrame
            if header._scriptMode ~= "header" then
                -- Invalidate cached header presentation when recycling a non-header frame.
                -- Without this, stale cached anchors/atlas/text style can cause missing or malformed headers.
                header._textStyleSignature = nil
                header._textLayoutSignature = nil
                header._bgSignature = nil
                header._height = nil
                header._titleText = nil
                if header.expandBtn then
                    header.expandBtn._styleSignature = nil
                    header.expandBtn._iconPos = nil
                end
            end
            header:Show()
            
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
            
            -- Collapse/Expand Icon
            if not header.expandBtn then
                header.expandBtn = CreateFrame("Button", nil, header)
                header.expandBtn:SetPoint("LEFT", 4, 0)
            end
            
            
            local iconStyle = db.headerIconStyle or "standard"
            local iconPos = db.headerIconPosition or "left"
            local isCollapsed = item.collapsed
            
            -- Position Button (Left or Right)
            if header.expandBtn._iconPos ~= iconPos then
                header.expandBtn:ClearAllPoints()
                if iconPos == "right" then
                    header.expandBtn:SetPoint("RIGHT", -8, 0)
                else
                    header.expandBtn:SetPoint("LEFT", 8, 0)
                end
                header.expandBtn._iconPos = iconPos
            end
            
            -- Reset button state to prevent specific style overlapping (e.g. Text + Texture)
            local styleSignature = table.concat({
                tostring(iconStyle), tostring(iconPos), tostring(isCollapsed)
            }, "|")
            if header.expandBtn._styleSignature ~= styleSignature then
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
                        
                        local atlas = isCollapsed and "UI-QuestTrackerButton-Secondary-Expand" or "UI-QuestTrackerButton-Secondary-Collapse"
                        
                        -- Apply Atlas
                        header.expandBtn:SetNormalAtlas(atlas)
                        header.expandBtn:SetPushedAtlas(atlas)
                        header.expandBtn:SetHighlightAtlas(atlas)
                    end
                end
                header.expandBtn._styleSignature = styleSignature
            end
            
            header.expandBtn._headerKey = item.key
            header.expandBtn._headerCollapsed = isCollapsed
            if not header.expandBtn._handlersBound then
                -- Icon Tooltip & Click (Exclusive)
                header.expandBtn:SetScript("OnClick", function(self)
                     local isMainHeader = self._headerKey and self._headerKey:find("^MAJOR_")
                     addon:ToggleHeader(self._headerKey, isMainHeader and IsShiftKeyDown())
                end)
                
                header.expandBtn:SetScript("OnEnter", function(self)
                     GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                     local isMainHeader = self._headerKey and self._headerKey:find("^MAJOR_")
                     if isMainHeader then
                         if self._headerCollapsed then
                             GameTooltip:SetText("Hold SHIFT to Expand All", 1, 1, 1)
                         else
                             GameTooltip:SetText("Hold SHIFT to Minimize All", 1, 1, 1)
                         end
                     else
                         if self._headerCollapsed then
                             GameTooltip:SetText("Click to Expand", 1, 1, 1)
                         else
                             GameTooltip:SetText("Click to Collapse", 1, 1, 1)
                         end
                     end
                     GameTooltip:Show()
                end)
                header.expandBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                header.expandBtn._handlersBound = true
            end

            
            -- Title Text
            local headerFontSize = isMajor and (db.headerFontSize + 2) or db.headerFontSize
            local headerColorR = isMajor and db.headerColor.r or (db.headerColor.r * 0.9)
            local headerColorG = isMajor and db.headerColor.g or (db.headerColor.g * 0.9)
            local headerColorB = isMajor and db.headerColor.b or (db.headerColor.b * 0.9)
            local headerTextStyleSignature = table.concat({
                tostring(db.headerFontFace),
                tostring(headerFontSize),
                tostring(db.headerFontOutline),
                tostring(headerColorR),
                tostring(headerColorG),
                tostring(headerColorB),
                tostring(db.headerColor.a)
            }, ":")
            if header._textStyleSignature ~= headerTextStyleSignature then
                header.text:SetFont(db.headerFontFace, headerFontSize, db.headerFontOutline)
                header.text:SetTextColor(headerColorR, headerColorG, headerColorB, db.headerColor.a)
                header.text:SetJustifyH("LEFT")
                header._textStyleSignature = headerTextStyleSignature
            end

            if header._titleText ~= item.title then
                header.text:SetText(item.title)
                header._titleText = item.title
            end

            local headerTextLayoutSignature = table.concat({iconStyle, iconPos}, ":")
            if header._textLayoutSignature ~= headerTextLayoutSignature then
                -- RESET TEXT POINT for recycled headers
                header.text:ClearAllPoints()

                if iconStyle == "none" then
                     -- No icon: Text fills full width with small padding
                    header.text:SetPoint("LEFT", 5, 0)
                    header.text:SetPoint("RIGHT", -5, 0)
                elseif iconPos == "right" then
                    -- Icon on Right: Text starts Left, ends before icon
                    header.text:SetPoint("LEFT", 5, 0)
                    header.text:SetPoint("RIGHT", -22, 0)
                else
                    -- Icon on Left (Default): Text starts after icon
                    header.text:SetPoint("LEFT", 22, 0)
                    header.text:SetPoint("RIGHT", -5, 0)
                end
                header._textLayoutSignature = headerTextLayoutSignature
            end
            
            local bgStyle = db.headerBackgroundStyle or "tracker"

            local bgSignature = table.concat({bgStyle, tostring(isMajor and 1 or 0)}, ":")
            if header._bgSignature ~= bgSignature then
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
                header._bgSignature = bgSignature
            end

            local headerHeight = isMajor and 24 or 20
            if header._height ~= headerHeight then
                header:SetHeight(headerHeight)
                header._height = headerHeight
            end
            header:Show()
            
            -- Store header data for click handling
            header.trackableData = item
            header._headerKey = item.key
            if header._scriptMode ~= "header" then
                header:SetScript("OnClick", function(self, mouseButton)
                    if mouseButton == "LeftButton" then
                        local isMainHeader = self._headerKey and self._headerKey:find("^MAJOR_")
                        -- Shift recursive toggle is only for major/main headers
                        addon:ToggleHeader(self._headerKey, isMainHeader and IsShiftKeyDown())
                    end
                end)
                -- Clear other scripts that might conflict
                header:SetScript("OnMouseUp", nil)

                -- Removed Tooltip from main header bar area per user request
                header:SetScript("OnEnter", nil)
                header:SetScript("OnLeave", nil)
                header._scriptMode = "header"
            end
            
            yOffset = yOffset + (isMajor and db.spacingMajorHeaderAfter or db.spacingMinorHeaderAfter)
            
            -- Cleanup extra elements if reused
            if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
            if header.objectiveBullets then for _, obj in ipairs(header.objectiveBullets) do obj:Hide() end end
            if header.objectivePrefixes then for _, obj in ipairs(header.objectivePrefixes) do obj:Hide() end end
            if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end
            if header.distance then header.distance:Hide() end
            
            -- Ensure POI buttons and Item buttons are hidden on headers
            if header.poiButton then header.poiButton:Hide() end
            if header.itemButton then header.itemButton:Hide() end
            if header.icon then header.icon:Hide() end
            end -- End skip minor header check

        else
            -- Trackable item (quest, achievement, etc.)
            -- Only render if neither the major nor minor header is collapsed
            if not currentMajorCollapsed and not currentMinorCollapsed then
                item._majorHeaderTitle = currentMajorHeaderTitle
                item._minorHeaderTitle = currentMinorHeaderTitle
                local height = self:RenderTrackableItem(contentFrame, item, yOffset, db.spacingTrackableIndent)
                yOffset = yOffset + height + db.spacingItemVertical
            end
        end
    end
    
    -- Update content frame height
    contentFrame:SetHeight(math.max(yOffset, self.db.frameHeight))

    -- Hide only unused pooled buttons after this frame has been fully rendered.
    self:FinalizeButtonPool()
    
    -- Update tracker frame appearance
    self:UpdateTrackerAppearance()
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
