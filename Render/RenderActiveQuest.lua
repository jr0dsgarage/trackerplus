local addonName, addon = ...

-- Localize hot-path globals
local ipairs = ipairs

-------------------------------------------------------------------------------
-- RenderActiveQuestSection — Super-tracked quest rendering
-- Returns: aqYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderActiveQuestSection(superTrackedItems)
    local db = self.db
    local aqFrame = self.activeQuestFrame
    local aqYOffset = 0

    if (self._cachedSuperTrackedQuestID or 0) > 0 and #superTrackedItems > 0 then
        local header = self:AcquireSectionHeader(aqFrame, "Active Quest", addon.SECTION_HEADER_GOLD)
        aqYOffset = addon.SECTION_HEADER_HEIGHT

        -- Spoken's Play button just past the "Active Quest" title, for the quest
        -- shown here. Its own setting, independent of the per-row Play buttons.
        local quest = superTrackedItems[1]
        if db.spokenPlayButtonActiveQuest and quest then
            local playButton = self:ApplySpokenPlayButton(header, quest.id, quest.title, addon.SPOKEN_HEADER_BUTTON_SIZE)
            if playButton then
                playButton:SetPoint("LEFT", header.text, "LEFT", header.text:GetStringWidth() + 6, 0)
            end
        elseif header.spokenPlayButton then
            header.spokenPlayButton:Hide()
        end

        for _, item in ipairs(superTrackedItems) do
            local h = self:RenderTrackableItem(aqFrame, item, aqYOffset, db.spacingMinorHeaderIndent + 10)
            aqYOffset = aqYOffset + h + db.spacingItemVertical
        end

        local backdropPadding = 10
        header.styledBackdrop:SetHeight(aqYOffset + backdropPadding)
        aqYOffset = aqYOffset + backdropPadding
    end

    self:FinishPinnedSection(aqFrame, aqYOffset)
    return aqYOffset
end
