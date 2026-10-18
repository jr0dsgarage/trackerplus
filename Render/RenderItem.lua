local addonName, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Localize hot-path globals
local ipairs, type, tostring = ipairs, type, tostring
local format = string.format
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

-- ObjectiveParser.lua loads before this file.
local ParseObjectiveDisplay = addon.ParseObjectiveDisplay
local ResolveTrackableItemData = addon.ResolveTrackableItemData

local DEFAULT_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

-- Row backgrounds: the game's own card atlases, as the Social (friends list) rows use
-- them (Blizzard_FriendsFrame FriendsListSocialCardMixin:GetBestBackgroundAtlas).
-- Stretched to the row, so their native size is ignored.
local ROW_BACKGROUND_DEFAULT = "friends-card-default"
addon.RowBackgroundStyles = {
    {text = "Friend Card", value = "friends-card-default"},
}
local IS_ROW_BACKGROUND = {}
for _, style in ipairs(addon.RowBackgroundStyles) do IS_ROW_BACKGROUND[style.value] = true end

-- Out to the quest-area highlight's box on the left so the POI button sits on the
-- card, and a pixel past the row's top and bottom.
local ROW_BG_LEFT = -8
local ROW_BG_PAD = 1
-- Room between the card's top edge and the row's title and POI button.
local ROW_BG_TOP_INSET = 2

-- Shared with the quest-area highlight's card styles, which overlay this background.
function addon:AnchorRowCard(tex, button)
    tex:SetPoint("TOPLEFT", button, "TOPLEFT", ROW_BG_LEFT, ROW_BG_PAD)
    tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, -ROW_BG_PAD)
end

-- Rows in the Active Quest panel sit on its own backdrop, so they never get one.
local function WantsRowBackground(self, db, parent)
    return db.rowBackgroundEnabled and parent ~= self.activeQuestFrame
end

local function ApplyRowBackground(button, show, db)
    local tex = button.rowBg
    if not show then
        if tex then tex:Hide() end
        return
    end
    if not tex then
        -- Below the row's own bg and the quest-area fill (BACKGROUND 0 and 1).
        tex = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        addon:AnchorRowCard(tex, button)
        button.rowBg = tex
    end
    local atlas = db.rowBackgroundStyle
    if not IS_ROW_BACKGROUND[atlas] then atlas = ROW_BACKGROUND_DEFAULT end
    if tex._atlas ~= atlas then
        -- An atlas missing on this client would leave the texture blank; fall back.
        if C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(atlas) then
            atlas = ROW_BACKGROUND_DEFAULT
        end
        tex:SetAtlas(atlas, false)
        tex._atlas = atlas
    end
    tex:SetAlpha(db.rowBackgroundAlpha or 1)
    tex:Show()
end

local function OnRowClick(self, mouseButton)
    addon:OnTrackableClick(self.trackableData, mouseButton)
end

local function OnRowEnter(self)
    if addon.db.showTooltips then
        addon:ShowTrackableTooltip(self, self.trackableData)
    end
end

local function OnRowLeave()
    addon:HideSharedTooltip()
end

local function OnPOIClick(self)
    if self.questID then
        -- Toggle super tracking
        if C_SuperTrack.GetSuperTrackedQuestID() == self.questID then
            C_SuperTrack.SetSuperTrackedQuestID(0)
        else
            C_SuperTrack.SetSuperTrackedQuestID(self.questID)
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

local function OnItemEnter(self)
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
end

local function OnGroupClick(self)
    LFGListUtil_FindQuestGroup(self.questID)
end

local function OnGroupEnter(self)
    local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
    tooltip:SetText(OBJECTIVES_FIND_GROUP)
    tooltip:Show()
end

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
    -- Returned with every recycled child (objective lines, bars, POI/item/group
    -- buttons) already hidden.
    local button = self:GetOrCreateButton(parent)
    if button.expandBtn then button.expandBtn:Hide() end -- Left over from a header

    button:SetPoint("TOPLEFT", parent, "TOPLEFT", indent, -yOffset)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -yOffset)

    local showRowBg = WantsRowBackground(self, db, parent)
    local topInset = showRowBg and ROW_BG_TOP_INSET or 0

    -- POI Button (Using Blizzard Template for authenticity)
    if not button.poiButton then
        button.poiButton = CreateFrame("Button", nil, button, "POIButtonTemplate")
        button.poiButton:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 0) -- Nudged left
        button.poiButton:SetScale(0.75) -- Slightly smaller
        -- Override click handling to our logic
        button.poiButton:SetScript("OnClick", OnPOIClick)
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
             secureBtn:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -topInset) -- Right aligned
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
            secureBtn:SetScript("OnEnter", OnItemEnter)
            secureBtn:SetScript("OnLeave", OnRowLeave)
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
        do
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

        -- Keep the button level with the title's first line as the quest name font
        -- grows or shrinks. Its position was tuned at size 12, and the line's middle
        -- moves down by half of any size increase. Offsets are in the button's own
        -- (0.75-scaled) units, hence the division.
        local poiShift = ((db.fontSize or 12) - 12) / 2
        button.poiButton:ClearAllPoints()
        button.poiButton:SetPoint("TOPLEFT", button, "TOPLEFT", -4, -(poiShift + topInset) / 0.75)
        
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
            
            button.groupButton:SetScript("OnClick", OnGroupClick)
            button.groupButton:SetScript("OnEnter", OnGroupEnter)
            button.groupButton:SetScript("OnLeave", OnRowLeave)
        end
        
        button.groupButton.questID = item.id
        button.groupButton:Show()
    end

    -- Quest rows leave room for the POI button on the left.
    local leftPadding = isQuest and db.spacingPOIButton or db.spacingMinorHeaderIndent
    
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
    button.text:SetPoint("TOPLEFT", leftPadding, -2 - topInset)
    button.text:SetPoint("TOPRIGHT", rightPadding, -2 - topInset)

    local titleText = item.title
    if db.showQuestLevel and item.level and item.level > 0 then
        titleText = format("[%d%s] %s", item.level, item.isGroupQuest and "+" or "", titleText)
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
    local height = max(db.fontSize + 4, textHeight + 4) + topInset

    -- Objectives
    if not item.collapsed and item.objectives and #item.objectives > 0 then
        local currentY = -(textHeight + 2 + topInset)
        local isAchievementObjective = (item.type == "achievement")
        
        for objIndex, obj in ipairs(item.objectives) do
            local parsed = ParseObjectiveDisplay(item, obj, objIndex)
            local prefixText = parsed.prefixText
            local bodyText = parsed.bodyText
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
                bulletLine:SetFont(db.objectiveFontFace, db.objectiveFontSize, db.fontOutline)
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
                prefixLine:SetFont(db.objectiveFontFace, db.objectiveFontSize, db.fontOutline)
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
            objLine:SetFont(db.objectiveFontFace, db.objectiveFontSize, db.fontOutline)
            objLine:SetTextColor(objColor.r, objColor.g, objColor.b, objColor.a)
            objLine:SetText(isAchievementObjective and achievementBodyText or bodyText)
            objLine:SetJustifyH("LEFT")
            if isAchievementObjective and not HasVisibleText(achievementBodyText) then
                objLine:Hide()
            else
                objLine:Show()
            end
            
            local lineH = objLine:GetStringHeight()
            local minLineH = max(1, db.objectiveFontSize)
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
                progressLine:SetFont(db.objectiveFontFace, db.objectiveFontSize, db.fontOutline)
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
                    -- Prefer Blizzard's own objective bar; fall back to building one.
                    local pcallStatus, newBar = pcall(CreateFrame, "Frame", nil, button, "QuestObjectiveProgressBarTemplate")
                    
                    if pcallStatus and newBar then
                         bar = newBar
                         bar.isTemplate = true
                    else
                         -- Texture, background color and border are applied by the
                         -- style check below on first use.
                         bar = CreateFrame("StatusBar", nil, button)
                         bar:SetSize(1, 15)
                         bar.bg = bar:CreateTexture(nil, "BACKGROUND")
                         bar.bg:SetAllPoints()
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
                        local barTex = DEFAULT_BAR_TEXTURE
                        if LSM and db.barTexture then
                            barTex = LSM:Fetch("statusbar", db.barTexture) or barTex
                        end
                        bar:SetStatusBarTexture(barTex)
                        bar.bg:SetColorTexture(bgR, bgG, bgB, bgA)
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
                if bar._anchorLeft ~= barLeft or bar._anchorTop ~= barTop or bar._anchorInset ~= barRightInset then
                    bar:ClearAllPoints()
                    bar:SetPoint("TOPLEFT", button, "TOPLEFT", barLeft, barTop)
                    bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", -barRightInset, barTop)
                    bar._anchorLeft, bar._anchorTop, bar._anchorInset = barLeft, barTop, barRightInset
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
    
    button:SetHeight(height)
    button.trackableData = item

    ApplyRowBackground(button, showRowBg, db)

    -- Stripe beside quests the player is standing in; it spans the row's full height.
    -- Not in the Active Quest panel, which has its own backdrop.
    local highlightQuestID = isQuest and parent ~= self.activeQuestFrame and item.id or nil
    self:ApplyQuestAreaHighlight(button, highlightQuestID)

    if button._scriptMode ~= "trackable" then
        button:SetScript("OnClick", OnRowClick)
        button:SetScript("OnMouseUp", nil)
        button:SetScript("OnEnter", OnRowEnter)
        button:SetScript("OnLeave", OnRowLeave)
        button._scriptMode = "trackable"
    end
    
    return height
end
