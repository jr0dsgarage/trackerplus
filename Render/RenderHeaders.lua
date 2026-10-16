local addonName, addon = ...

-- Localize hot-path globals
local ipairs, tostring = ipairs, tostring
local format = string.format

local function OnExpandClick(self)
    local isMainHeader = self._headerKey and self._headerKey:find("^MAJOR_")
    addon:ToggleHeader(self._headerKey, isMainHeader and IsShiftKeyDown())
end

local function OnExpandEnter(self)
    local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
    local isMainHeader = self._headerKey and self._headerKey:find("^MAJOR_")
    if isMainHeader then
        tooltip:SetText(self._headerCollapsed and "Hold SHIFT to Expand All" or "Hold SHIFT to Minimize All")
    else
        tooltip:SetText(self._headerCollapsed and "Click to Expand" or "Click to Collapse")
    end
    tooltip:Show()
end

local function OnExpandLeave()
    addon:HideSharedTooltip()
end

local function OnHeaderClick(self, mouseButton)
    if mouseButton == "LeftButton" then
        local isMainHeader = self._headerKey and self._headerKey:find("^MAJOR_")
        -- Shift recursive toggle is only for major/main headers
        addon:ToggleHeader(self._headerKey, isMainHeader and IsShiftKeyDown())
    end
end

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

    -- Header presentation depends only on settings, so its cache signatures are
    -- built once per pass and compared per header.
    local iconStyle = db.headerIconStyle or "standard"
    local iconPos = db.headerIconPosition or "left"
    local bgStyle = db.headerBackgroundStyle or "questlog"
    local headerColor = db.headerColor
    local expandSigCollapsed = iconStyle .. "|" .. iconPos .. "|1"
    local expandSigExpanded = iconStyle .. "|" .. iconPos .. "|0"
    local textLayoutSig = iconStyle .. ":" .. iconPos
    local bgSigMajor, bgSigMinor = bgStyle .. ":1", bgStyle .. ":0"
    local textStyleSigMajor = format("%s:%s:%s:%s:%s:%s:%s", tostring(db.headerFontFace), tostring(db.headerFontSize + 2),
        tostring(db.headerFontOutline), tostring(headerColor.r), tostring(headerColor.g), tostring(headerColor.b), tostring(headerColor.a))
    local textStyleSigMinor = format("%s:%s:%s:%s:%s:%s:%s", tostring(db.headerFontFace), tostring(db.headerFontSize),
        tostring(db.headerFontOutline), tostring(headerColor.r * 0.9), tostring(headerColor.g * 0.9), tostring(headerColor.b * 0.9), tostring(headerColor.a))

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
            
            -- Padding/Indentation
            local xOffset = isMajor and db.spacingMajorHeaderIndent or db.spacingMinorHeaderIndent
            
            header:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", xOffset, -yOffset)
            header:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, -yOffset)
            
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
            local styleSignature = isCollapsed and expandSigCollapsed or expandSigExpanded
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
            -- Shared with the Campaign header's expand button (RenderCampaign.lua),
            -- so rebind whenever it last served that.
            if header.expandBtn._expandMode ~= "header" then
                header.expandBtn:SetScript("OnClick", OnExpandClick)
                header.expandBtn:SetScript("OnEnter", OnExpandEnter)
                header.expandBtn:SetScript("OnLeave", OnExpandLeave)
                header.expandBtn._expandMode = "header"
            end

            
            -- Title Text
            local headerTextStyleSignature = isMajor and textStyleSigMajor or textStyleSigMinor
            if header._textStyleSignature ~= headerTextStyleSignature then
                local shade = isMajor and 1 or 0.9
                header.text:SetFont(db.headerFontFace, isMajor and (db.headerFontSize + 2) or db.headerFontSize, db.headerFontOutline)
                header.text:SetTextColor(headerColor.r * shade, headerColor.g * shade, headerColor.b * shade, headerColor.a)
                header.text:SetJustifyH("LEFT")
                header._textStyleSignature = headerTextStyleSignature
            end

            if header._titleText ~= item.title then
                header.text:SetText(item.title)
                header._titleText = item.title
            end

            if header._textLayoutSignature ~= textLayoutSig then
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
                header._textLayoutSignature = textLayoutSig
            end
            
            local bgSignature = isMajor and bgSigMajor or bgSigMinor
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
            
            -- Store header data for click handling
            header.trackableData = item
            header._headerKey = item.key
            if header._scriptMode ~= "header" then
                header:SetScript("OnClick", OnHeaderClick)
                -- Clear other scripts that might conflict
                header:SetScript("OnMouseUp", nil)

                -- Removed Tooltip from main header bar area per user request
                header:SetScript("OnEnter", nil)
                header:SetScript("OnLeave", nil)
                header._scriptMode = "header"
            end
            
            yOffset = yOffset + (isMajor and db.spacingMajorHeaderAfter or db.spacingMinorHeaderAfter)
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
