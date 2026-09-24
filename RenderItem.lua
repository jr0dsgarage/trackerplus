local addonName, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Localize hot-path globals
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local format, match = string.format, string.match
local max, floor = math.max, math.floor
local InCombatLockdown = InCombatLockdown

-- Item lookups live in the C_Item namespace on current clients; the old globals
-- (GetItemInfo/GetItemInfoInstant/GetItemIcon) no longer exist and calling them
-- raises "attempt to call a nil value". Resolve once, keeping the legacy globals
-- as a fallback for older clients this .toc also targets.
--
-- Note C_Item.GetItemIcon is NOT the replacement for the old GetItemIcon: it takes
-- an ItemLocation (bag/slot), not a link. GetItemIconByID is the link/ID version.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemIconByID = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

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

local function HasVisibleText(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

local function ResolveAchievementObjectiveText(item, objectiveText, parsedBodyText)
    local bodyText = parsedBodyText
    if not HasVisibleText(bodyText) and HasVisibleText(objectiveText) then
        bodyText = objectiveText
    end

    local titleMatches = HasVisibleText(bodyText)
        and HasVisibleText(item and item.title)
        and bodyText == item.title

    if (not HasVisibleText(bodyText) or titleMatches) and HasVisibleText(item and item.description) then
        bodyText = item.description
    end

    if not HasVisibleText(bodyText) and HasVisibleText(item and item.title) then
        bodyText = item.title
    end

    return bodyText or ""
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
    if button.objectiveProgresses then
        local arr = button.objectiveProgresses
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
    -- Secure button geometry/attribute mutation is deferred entirely while in combat:
    -- SetAttribute/SetPoint/SetSize on an actionable SecureActionButtonTemplate button
    -- can taint mid-combat. If one is already shown from a prior render, leave it as-is;
    -- the next out-of-combat render will catch up (see Core.lua's pendingUpdate pattern).
    if itemData and not InCombatLockdown() then
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
        if itemData.link then
            secureBtn:SetAttribute("type", "item")
            secureBtn:SetAttribute("item", itemData.link)
        else
            -- No usable item link (texture-only data): clear the secure action so this
            -- button isn't left actionable with an empty target.
            secureBtn:SetAttribute("type", nil)
            secureBtn:SetAttribute("item", nil)
        end
        secureBtn.itemLink = itemData.link

        if not secureBtn._handlersBound then
            secureBtn:SetScript("OnEnter", function(self)
                if not self.itemLink then return end
                local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
                local itemName
                if GetItemInfo then
                    local ok, name = pcall(GetItemInfo, self.itemLink)
                    if ok then itemName = name end
                end
                tooltip:SetText(itemName or self.itemLink)
                tooltip:AddLine("Click to use this item", 0.85, 0.85, 0.85)
                tooltip:Show()
            end)
            secureBtn:SetScript("OnLeave", function()
                addon:HideSharedTooltip()
            end)
            secureBtn._handlersBound = true
        end

        -- Robust Icon handling
        local texture = itemData.texture
        
        -- Try to fetch via API if missing
        if not texture and itemData.link then
            if GetItemIconByID then
                local ok, icon = pcall(GetItemIconByID, itemData.link)
                if ok then texture = icon end
            end

            -- If the icon lookup fails (returns nil), try Instant info which is
            -- cache-independent for icons
            if not texture and GetItemInfoInstant then
                local ok, _, _, _, _, iconID = pcall(GetItemInfoInstant, itemData.link)
                if ok and iconID then texture = iconID end
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
            if not start and itemData.link and GetItemInfoInstant then
                local okID, itemID = pcall(GetItemInfoInstant, itemData.link)
                -- GetItemCooldown lives on C_Item now; C_Container kept a copy on
                -- some clients, so take whichever this one actually has.
                local getCooldown = (C_Item and C_Item.GetItemCooldown)
                    or (C_Container and C_Container.GetItemCooldown)
                if okID and itemID and getCooldown then
                    local okCD, cdStart, cdDuration, cdEnable = pcall(getCooldown, itemID)
                    if okCD then
                        start, duration, enable = cdStart, cdDuration, cdEnable
                    end
                end
            end
            
            if start and duration and (enable == 1 or enable == true) then
                secureBtn.cooldown:SetCooldown(start, duration)
            else
                secureBtn.cooldown:Hide()
            end
        end
        
        -- leftPadding is handled separately now as item is on the right
    elseif itemData then
        -- Item exists but we're in combat lockdown: leave whatever is already shown
        -- (if anything) untouched rather than hiding/reconfiguring a secure button.
    else
        if button.itemButton then
            button.itemButton.itemLink = nil
            button.itemButton:Hide()
            button.itemButton = nil
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

        -- Force selection if this is the Active Quest item, or if IDs match
        local isSelected = (item.id == superTrackedQuestID) or (item.type == "supertrack")

        -- Selection has to be set BEFORE the style is repainted. Blizzard's
        -- POIButtonMixin:SetSelected only stores the flag; UpdateButtonStyle is what
        -- actually paints it (it reads IsSelected to show/hide the glow). Painting
        -- first meant every row was drawn with the *previous* render's selection, and
        -- because these buttons come from a pool and rows shift between renders, a
        -- recycled button kept the old highlight -- so after super-tracking changed,
        -- the wrong row stayed lit while the Active Quest section showed the right one.
        if button.poiButton.SetSelected then
            button.poiButton:SetSelected(isSelected)
        end

        if button.poiButton.UpdateButtonStyle then
            button.poiButton:UpdateButtonStyle()
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
    -- Shared with the map pins (see Core.lua) so a quest can't be one color here and
    -- another on the map -- the super-track gold used to be applied only here, which
    -- left a super-tracked completed quest gold in the tracker but green on its pin.
    local color = self:ApplySuperTrackedTitleColor(item.id, item.color or db.questColor, superTrackedQuestID)
    button.text:SetTextColor(color.r, color.g, color.b, color.a)
    button.text:SetText(titleText)
    button.text:SetJustifyH("LEFT")
    button.text:SetWordWrap(true)
    
    button.bg:SetColorTexture(0, 0, 0, 0)
    
    -- Force width calculation for accurate multi-line height measurement.
    --
    -- A frame whose anchors haven't resolved yet reports a width of 0, not nil, so
    -- this needs a real zero check -- `or 300` alone never fires and every width
    -- below comes out negative.
    local parentWidth = parent:GetWidth() or 0
    if parentWidth <= 1 then
        parentWidth = (self.trackerFrame and self.trackerFrame:GetWidth()) or 0
        if parentWidth <= 1 then
            parentWidth = db.frameWidth or 300
        end
    end
    local buttonWidth = parentWidth - indent - 5
    local textWidth = buttonWidth - leftPadding + rightPadding

    -- Always set an explicit width (clamped to a small positive minimum) so a pooled
    -- text widget never keeps a stale width from whatever item last used it, which
    -- would otherwise miscalculate this item's wrap/height.
    button.text:SetWidth(max(textWidth, 1))

    -- Floor the measurement at one line. A title always occupies at least one, but a
    -- font string with no room to lay out reports 0 -- and that value also seeds
    -- currentY below, which would stack the first objective straight on top of the
    -- title. Painting only happens when the collected data version changes, so a row
    -- laid out from a bad measurement stays wrong on screen until the quest's data
    -- next changes; the floor keeps that from being possible.
    local textHeight = max(button.text:GetStringHeight() or 0, db.fontSize + 2)
    local height = max(db.fontSize + 4, textHeight + 4)
    
    -- Objectives
    if not item.collapsed and item.objectives and #item.objectives > 0 then
        local currentY = -(textHeight + 2)
        
        for objIndex, obj in ipairs(item.objectives) do
            local parsed = ParseObjectiveDisplay(item, obj, objIndex)
            local prefixText = parsed.prefixText
            local bodyText = parsed.bodyText
            local isAchievementObjective = (item.type == "achievement")
            local achievementBodyText = bodyText
            if isAchievementObjective then
                achievementBodyText = ResolveAchievementObjectiveText(item, obj.text, bodyText)
            end
            local isAchievementTextThenProgress = (isAchievementObjective and prefixText ~= "" and HasVisibleText(achievementBodyText))
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
            local objColor = obj.finished and db.completeColor or db.objectiveColor
            if isAchievementObjective then
                bulletLine:Hide()
            else
                bulletLine:SetPoint("TOPLEFT", button, "TOPLEFT", leftPadding + db.spacingObjectiveIndent, currentY)
                bulletLine:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
                bulletLine:SetTextColor(objColor.r, objColor.g, objColor.b, objColor.a)
                bulletLine:SetText("  -")
                bulletLine:Show()
            end

            -- Prepare Prefix
            if not button.objectivePrefixes then button.objectivePrefixes = {} end
            local prefixLine = button.objectivePrefixes[objIndex]
            if not prefixLine then
                prefixLine = button:CreateFontString(nil, "OVERLAY")
                button.objectivePrefixes[objIndex] = prefixLine
            end
            
            local prefixWidth = 0
            if prefixText ~= "" and not isAchievementTextThenProgress then
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
            if isAchievementTextThenProgress then
                gap = 0
            end
            
            local bodyIndent = leftPadding + db.spacingObjectiveIndent + indentAmount + prefixWidth + gap
            if isAchievementObjective then
                bodyIndent = leftPadding + db.spacingObjectiveIndent + 2
            end
            
            -- Width reduced by indent to account for hanging indent
            -- use buttonWidth (calculated from parent) instead of button:GetWidth() which is 0 on first render
            objLine:SetWidth(max(buttonWidth - bodyIndent - 5, 1))
            objLine:SetWordWrap(true)
            objLine:ClearAllPoints()
            -- Anchor to right of prefix (or bullet if no prefix)
            objLine:SetPoint("TOPLEFT", button, "TOPLEFT", bodyIndent, currentY)
            objLine:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
            --local objColor = obj.finished and db.completeColor or db.objectiveColor -- Already set above
            objLine:SetTextColor(objColor.r, objColor.g, objColor.b, objColor.a)
            objLine:SetText(isAchievementObjective and achievementBodyText or bodyText)
            objLine:SetJustifyH("LEFT")
            if isAchievementObjective and not HasVisibleText(achievementBodyText) then
                objLine:Hide()
            else
                objLine:Show()
            end
            
            local lineH = objLine:GetStringHeight()
            local minLineH = max(1, db.fontSize - 1)
            if lineH < minLineH then
                lineH = minLineH
            end
            if not isAchievementObjective or HasVisibleText(achievementBodyText) then
                currentY = currentY - (lineH + 2)
                height = height + (lineH + 2)
            end

            if isAchievementTextThenProgress then
                if not button.objectiveProgresses then button.objectiveProgresses = {} end
                local progressLine = button.objectiveProgresses[objIndex]
                if not progressLine then
                    progressLine = button:CreateFontString(nil, "OVERLAY")
                    button.objectiveProgresses[objIndex] = progressLine
                end

                progressLine:SetWidth(max(buttonWidth - bodyIndent - 5, 1))
                progressLine:SetWordWrap(true)
                progressLine:ClearAllPoints()
                progressLine:SetPoint("TOPLEFT", button, "TOPLEFT", bodyIndent, currentY)
                progressLine:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
                progressLine:SetTextColor(objColor.r, objColor.g, objColor.b, objColor.a)
                progressLine:SetText(" - " .. prefixText)
                progressLine:SetJustifyH("LEFT")
                progressLine:Show()

                local progressLineH = progressLine:GetStringHeight()
                if progressLineH < minLineH then
                    progressLineH = minLineH
                end
                currentY = currentY - (progressLineH + 2)
                height = height + (progressLineH + 2)
            elseif button.objectiveProgresses and button.objectiveProgresses[objIndex] then
                button.objectiveProgresses[objIndex]:Hide()
            end

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

    -- Stripe beside quests the player is standing in; it spans the row's full height.
    self:ApplyQuestAreaHighlight(button, isQuest and item.id or nil)

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
