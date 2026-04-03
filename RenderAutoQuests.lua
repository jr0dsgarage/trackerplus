local addonName, addon = ...

-- Localize hot-path globals
local ipairs, pairs = ipairs, pairs
local max = math.max

-------------------------------------------------------------------------------
-- RenderAutoQuestSection — renders auto-quest popups using mirror data
-------------------------------------------------------------------------------
function addon:RenderAutoQuestSection(autoQuests)
    local completedQuestFrame = self.completedQuestFrame
    local autoQuestFrame = self.autoQuestFrame

    -- We do not use the old autoQuestFrame logic anymore, but keep it hidden
    autoQuestFrame:SetHeight(1)
    autoQuestFrame:Hide()

    -- Restore any popup frames stolen by an old hijack session
    self._stolenPopups = self._stolenPopups or {}
    for popup, _ in pairs(self._stolenPopups) do
        if not InCombatLockdown() and popup._trackerPlusOriginalParent and not (popup.IsProtected and popup:IsProtected()) then
            popup:SetParent(popup._trackerPlusOriginalParent)
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", popup._trackerPlusOriginalParent, "TOPLEFT", 0, 0)
            popup._trackerPlusOriginalParent = nil
        end
    end
    wipe(self._stolenPopups)

    if #autoQuests > 0 then
        local yOff = 5
        local indent = (self.db.spacingMinorHeaderIndent or 5) + 10
        local itemSpacing = self.db.spacingItemVertical or 4

        for _, item in ipairs(autoQuests) do
            local h = self:RenderTrackableItem(completedQuestFrame, item, yOff, indent)
            yOff = yOff + h + itemSpacing
        end

        completedQuestFrame:SetHeight(yOff + 5)
        if addon.db.minimized then
            completedQuestFrame:Hide()
        else
            completedQuestFrame:Show()
        end
    else
        -- Defensive cleanup: ensure any lingering child widgets are hidden
        -- when no auto-quest popups remain.
        if not InCombatLockdown() then
            for _, child in ipairs({completedQuestFrame:GetChildren()}) do
                if not (child.IsProtected and child:IsProtected()) then
                    pcall(function()
                        child:Hide()
                    end)
                end
            end
        end
        completedQuestFrame:SetHeight(1)
        completedQuestFrame:Hide()
    end
end
