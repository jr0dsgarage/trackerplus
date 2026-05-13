local addonName, addon = ...

-- Localize hot-path globals
local ipairs, pairs, tostring = ipairs, pairs, tostring
local format = string.format
local max = math.max

local DebugLayout = function(...) return addon.DebugLayout(...) end

-------------------------------------------------------------------------------
-- RenderNormalTrackables — Headers + quest items inside the scroll content frame
-- Returns: renderedNormalItems, renderedHeaders, yOffset
-------------------------------------------------------------------------------
function addon:RenderNormalTrackables(trackables, contentFrame)
    local db = self.db
    local yOffset = 5  -- Start near top of content frame
    local currentMajorCollapsed = false
    local currentMinorCollapsed = false
    local currentMajorHeaderTitle = nil
    local currentMinorHeaderTitle = nil
    local renderedNormalItems = 0
    local renderedHeaders = 0

    -- Compatibility: Auctionator Crafting Search Button — pre-hide before render pass.
    -- Will be reparented and shown when the Professions major header is encountered below.
    if AuctionatorCraftingInfoObjectiveTrackerFrame then
        AuctionatorCraftingInfoObjectiveTrackerFrame:Hide()
    end

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
                local header = self:GetOrCreateButton(contentFrame)
                renderedHeaders = renderedHeaders + 1
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
            
            -- Ensure any hijacked "Active Quest" artifacts are hidden
            if header.styledBackdrop then header.styledBackdrop:Hide() end
            
            -- Compatibility: Auctionator Crafting Search Button
            if isMajor and item.key == "MAJOR_profession" then
                if AuctionatorCraftingInfoObjectiveTrackerFrame then
                    if not (AuctionatorCraftingInfoObjectiveTrackerFrame.IsProtected and AuctionatorCraftingInfoObjectiveTrackerFrame:IsProtected()) then
                        -- Reparent onto this TrackerPlus header so the Search button is visible
                        -- when the Auction House is open and recipes are tracked.
                        if AuctionatorCraftingInfoObjectiveTrackerFrame:GetParent() ~= header then
                            AuctionatorCraftingInfoObjectiveTrackerFrame:SetParent(header)
                        end
                        AuctionatorCraftingInfoObjectiveTrackerFrame:ClearAllPoints()
                        AuctionatorCraftingInfoObjectiveTrackerFrame:SetPoint("TOPRIGHT", header, "TOPRIGHT", -20, -1)
                        AuctionatorCraftingInfoObjectiveTrackerFrame:SetFrameLevel(header:GetFrameLevel() + 5)
                        -- Let Auctionator manage its own visibility (only shows when AH is open + recipes tracked)
                        AuctionatorCraftingInfoObjectiveTrackerFrame:ShowIfRelevant()
                    end
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
                     local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
                     local isMainHeader = self._headerKey and self._headerKey:find("^MAJOR_")
                     if isMainHeader then
                         if self._headerCollapsed then
                             tooltip:SetText("Hold SHIFT to Expand All")
                         else
                             tooltip:SetText("Hold SHIFT to Minimize All")
                         end
                     else
                         if self._headerCollapsed then
                             tooltip:SetText("Click to Expand")
                         else
                             tooltip:SetText("Click to Collapse")
                         end
                     end
                     tooltip:Show()
                end)
                header.expandBtn:SetScript("OnLeave", function() addon:HideSharedTooltip() end)
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
                    header.text:SetPoint("TOPLEFT", 5, -2)
                    header.text:SetPoint("TOPRIGHT", -5, -2)
                elseif iconPos == "right" then
                    -- Icon on Right: Text starts Left, ends before icon
                    header.text:SetPoint("TOPLEFT", 5, -2)
                    header.text:SetPoint("TOPRIGHT", -22, -2)
                else
                    -- Icon on Left (Default): Text starts after icon
                    header.text:SetPoint("TOPLEFT", 22, -2)
                    header.text:SetPoint("TOPRIGHT", -5, -2)
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
            if header.objectiveProgresses then for _, obj in ipairs(header.objectiveProgresses) do obj:Hide() end end
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
                renderedNormalItems = renderedNormalItems + 1
            end
        end
    end

    return renderedNormalItems, renderedHeaders, yOffset
end
