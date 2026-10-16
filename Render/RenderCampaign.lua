local addonName, addon = ...

-- Localize hot-path globals
local ipairs = ipairs

local SECTION_KEY = "Campaign Quests"

local function OnExpandClick()
    local collapsed = addon.db.collapsedSections
    collapsed[SECTION_KEY] = not collapsed[SECTION_KEY]
    addon:RequestUpdate()
end

local function OnExpandEnter(self)
    local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
    tooltip:SetText(self._sectionCollapsed and "Click to Expand" or "Click to Collapse")
    tooltip:Show()
end

local function OnExpandLeave()
    addon:HideSharedTooltip()
end

-------------------------------------------------------------------------------
-- RenderCampaignSection -- Campaign quest rendering in a dedicated pinned frame
-- Returns: campaignYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderCampaignSection(campaignItems)
    local db = self.db
    local campaignFrame = self.campaignFrame
    local campaignYOffset = 0

    if #campaignItems > 0 then
        local isCollapsed = db.collapsedSections[SECTION_KEY] == true

        local header = self:AcquireSectionHeader(campaignFrame, SECTION_KEY, addon.SECTION_HEADER_GOLD, -26)

        -- The expand button may have been styled and bound as a zone header's
        -- (RenderHeaders.lua) by a previous user of this pooled button, so reset its
        -- look, position and handlers whenever it last served something else.
        local expandBtn = header.expandBtn
        if not expandBtn then
            expandBtn = CreateFrame("Button", nil, header)
            header.expandBtn = expandBtn
        end
        if expandBtn._expandMode ~= "campaign" then
            expandBtn:SetText("")
            expandBtn:SetSize(16, 16)
            expandBtn:ClearAllPoints()
            expandBtn:SetPoint("RIGHT", -8, 0)
            expandBtn:SetScript("OnClick", OnExpandClick)
            expandBtn:SetScript("OnEnter", OnExpandEnter)
            expandBtn:SetScript("OnLeave", OnExpandLeave)
            expandBtn._expandMode = "campaign"
            -- RenderHeaders re-applies its own style after this.
            expandBtn._styleSignature = nil
            expandBtn._iconPos = nil
        end

        local iconAtlas = isCollapsed and "UI-QuestTrackerButton-Secondary-Expand" or "UI-QuestTrackerButton-Secondary-Collapse"
        expandBtn:SetNormalAtlas(iconAtlas)
        expandBtn:SetPushedAtlas(iconAtlas)
        expandBtn:SetHighlightAtlas(iconAtlas)
        expandBtn._sectionCollapsed = isCollapsed
        expandBtn:Show()

        campaignYOffset = addon.SECTION_HEADER_HEIGHT

        if not isCollapsed then
            for _, item in ipairs(campaignItems) do
                local h = self:RenderTrackableItem(campaignFrame, item, campaignYOffset, db.spacingMinorHeaderIndent + 10)
                campaignYOffset = campaignYOffset + h + db.spacingItemVertical
            end
        end

        local backdropPadding = 8
        header.styledBackdrop:SetHeight(campaignYOffset + backdropPadding)
        campaignYOffset = campaignYOffset + backdropPadding
    end

    self:FinishPinnedSection(campaignFrame, campaignYOffset, 1)
    return campaignYOffset
end
