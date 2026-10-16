local addonName, addon = ...

-- Localize hot-path globals
local ipairs = ipairs

local WORLD_QUEST_HEADER_COLOR = { r = 0.204, g = 0.478, b = 0.678, a = 1 } -- #347AAD

-------------------------------------------------------------------------------
-- RenderWorldQuestSection — World quest rendering
-- Returns: wqYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderWorldQuestSection(worldQuestItems)
    local db = self.db
    local wqFrame = self.worldQuestFrame
    local wqYOffset = 0

    -- Only show the section when we actually have world quests to draw. A secondary
    -- C_TaskQuest.GetTrackedQuestIDs check used to live here, but that function does
    -- not exist (C_TaskQuest has no such member), so it never ran -- and had it run
    -- it would only have shown an empty section, since the rows come from
    -- worldQuestItems either way.
    if #worldQuestItems > 0 then
        local header = self:AcquireSectionHeader(wqFrame, "World Quests", WORLD_QUEST_HEADER_COLOR)
        wqYOffset = 24 + 5

        for _, item in ipairs(worldQuestItems) do
            local height = self:RenderTrackableItem(wqFrame, item, wqYOffset, db.spacingMinorHeaderIndent + 10)
            wqYOffset = wqYOffset + height + db.spacingItemVertical
        end

        -- Backdrop covers the full section
        local backdropPadding = 5
        header.styledBackdrop:SetHeight(wqYOffset + backdropPadding)
    end

    -- Minimal height when empty to prevent layout gaps
    self:FinishPinnedSection(wqFrame, wqYOffset, 0.1)
    return wqYOffset
end
