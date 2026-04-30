local addonName, addon = ...

-- Localize hot-path globals
local ipairs = ipairs
local max = math.max

-------------------------------------------------------------------------------
-- RenderCampaignSection -- Campaign quest rendering in a dedicated pinned frame
-- Returns: campaignYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderCampaignSection(campaignItems)
    local db = self.db
    local campaignFrame = self.campaignFrame
    local campaignYOffset = 0

    if not campaignFrame then
        return 0
    end

    if #campaignItems > 0 then
        db.collapsedSections = db.collapsedSections or {}
        local isCollapsed = db.collapsedSections["Campaign Quests"] == true

        local header = self:GetOrCreateButton(campaignFrame)
        header:SetPoint("TOPLEFT", campaignFrame, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", campaignFrame, "TOPRIGHT", 0, 0)

        header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
        header.text:SetTextColor(1, 0.82, 0, 1)
        header.text:SetText("Campaign Quests")
        header.text:SetJustifyH("LEFT")
        header.text:ClearAllPoints()
        header.text:SetPoint("LEFT", 5, 0)
        header.text:SetPoint("RIGHT", -26, 0)

        if not header.expandBtn then
            header.expandBtn = CreateFrame("Button", nil, header)
            header.expandBtn:SetSize(16, 16)
            header.expandBtn:SetPoint("RIGHT", -8, 0)
        end

        local iconAtlas = isCollapsed and "UI-QuestTrackerButton-Secondary-Expand" or "UI-QuestTrackerButton-Secondary-Collapse"
        header.expandBtn:SetNormalAtlas(iconAtlas)
        header.expandBtn:SetPushedAtlas(iconAtlas)
        header.expandBtn:SetHighlightAtlas(iconAtlas)
        header.expandBtn._sectionCollapsed = isCollapsed
        header.expandBtn:Show()

        if not header.expandBtn._campaignHandlersBound then
            header.expandBtn:SetScript("OnClick", function(self)
                addon.db.collapsedSections = addon.db.collapsedSections or {}
                addon.db.collapsedSections["Campaign Quests"] = not addon.db.collapsedSections["Campaign Quests"]
                addon:RequestUpdate()
            end)
            header.expandBtn:SetScript("OnEnter", function(self)
                local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
                if self._sectionCollapsed then
                    tooltip:SetText("Click to Expand")
                else
                    tooltip:SetText("Click to Collapse")
                end
                tooltip:Show()
            end)
            header.expandBtn:SetScript("OnLeave", function()
                addon:HideSharedTooltip()
            end)
            header.expandBtn._campaignHandlersBound = true
        end

        if not header.styledBackdrop then
            header.styledBackdrop = CreateFrame("Frame", nil, header, "BackdropTemplate")
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
        header._scriptMode = "campaignHeader"

        if header.poiButton then header.poiButton:Hide() end
        if header.itemButton then header.itemButton:Hide() end
        if header.icon then header.icon:Hide() end
        if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
            if header.objectiveProgresses then for _, obj in ipairs(header.objectiveProgresses) do obj:Hide() end end
        if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end

        campaignYOffset = campaignYOffset + 30

        if not isCollapsed then
            for _, item in ipairs(campaignItems) do
                local h = self:RenderTrackableItem(campaignFrame, item, campaignYOffset, db.spacingMinorHeaderIndent + 10)
                campaignYOffset = campaignYOffset + h + db.spacingItemVertical
            end
        end

        local sectionHeight = max(30, campaignYOffset)
        local backdropPadding = 8
        header.styledBackdrop:SetHeight(sectionHeight + backdropPadding)
        campaignYOffset = sectionHeight + backdropPadding
    end

    if campaignYOffset > 0 then
        campaignFrame:SetHeight(campaignYOffset)
        if addon.db.minimized then
            campaignFrame:Hide()
        else
            campaignFrame:Show()
        end
    else
        campaignFrame:SetHeight(1)
        campaignFrame:Hide()
    end

    return campaignYOffset
end