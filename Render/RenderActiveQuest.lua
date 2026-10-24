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
