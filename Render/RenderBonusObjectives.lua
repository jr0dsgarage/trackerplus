local addonName, addon = ...

-- Localize hot-path globals
local ipairs = ipairs

-------------------------------------------------------------------------------
-- RenderBonusSection — Bonus objective rendering
-- Returns: bonusYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderBonusSection(bonusObjectives)
    local db = self.db
    local bonusFrame = self.bonusFrame
    local bonusYOffset = 0

    if db.showBonusObjectives and #bonusObjectives > 0 then
        local header = self:AcquireSectionHeader(bonusFrame, "Bonus Objective", db.bonusColor)
        bonusYOffset = addon.SECTION_HEADER_HEIGHT

        for _, item in ipairs(bonusObjectives) do
            local height = self:RenderTrackableItem(bonusFrame, item, bonusYOffset, db.spacingMinorHeaderIndent + 10)
            bonusYOffset = bonusYOffset + height + db.spacingItemVertical
        end

        local backdropPadding = 10
        header.styledBackdrop:SetHeight(bonusYOffset + backdropPadding)
        bonusYOffset = bonusYOffset + backdropPadding
    end

    self:FinishPinnedSection(bonusFrame, bonusYOffset)
    return bonusYOffset
end
