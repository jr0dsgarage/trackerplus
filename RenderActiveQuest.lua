local addonName, addon = ...

-- Localize hot-path globals
local ipairs = ipairs
local format = string.format

-------------------------------------------------------------------------------
-- RenderActiveQuestSection — Super-tracked quest rendering
-- Returns: aqYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderActiveQuestSection(superTrackedItems)
    local db = self.db
    local aqYOffset = 0
    local superTrackedQuestID = self._cachedSuperTrackedQuestID or 0

    if not self.activeQuestFrame then return 0 end

    if superTrackedQuestID > 0 and #superTrackedItems > 0 then
        local aqFrame = self.activeQuestFrame

        local header = self:GetOrCreateButton(aqFrame)
        header:SetPoint("TOPLEFT",  aqFrame, "TOPLEFT",  0, -aqYOffset)
        header:SetPoint("TOPRIGHT", aqFrame, "TOPRIGHT", 0, -aqYOffset)

        header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
        header.text:SetTextColor(1, 0.82, 0, 1) -- Gold
        header.text:SetText("Active Quest")
        header.text:SetJustifyH("LEFT")

        if header.expandBtn then header.expandBtn:Hide() end
        header.text:ClearAllPoints()
        header.text:SetPoint("LEFT", 5, 0)
        header.text:SetPoint("RIGHT", -5, 0)

        -- Styled backdrop (covers header + items below)
        if not header.styledBackdrop then
            header.styledBackdrop = CreateFrame("Frame", nil, header, "BackdropTemplate")
            if header:GetFrameLevel() > 1 then
                header.styledBackdrop:SetFrameLevel(header:GetFrameLevel() - 1)
            else
                header.styledBackdrop:SetFrameLevel(1)
                header:SetFrameLevel(2)
            end
            header.styledBackdrop:SetBackdrop({
                bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 }
            })
            header.styledBackdrop:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
            header.styledBackdrop:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        end

        header.styledBackdrop:ClearAllPoints()
        header.styledBackdrop:SetPoint("TOPLEFT",  header, "TOPLEFT",  0, 0)
        header.styledBackdrop:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
        header.styledBackdrop:Show()
        header.bg:SetColorTexture(0, 0, 0, 0)

        header:SetHeight(30)
        header:Show()
        header._scriptMode = "activeQuestHeader"

        if header.poiButton  then header.poiButton:Hide()  end
        if header.itemButton then header.itemButton:Hide() end
        if header.icon       then header.icon:Hide()       end
        if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
        if header.objectiveProgresses then for _, obj in ipairs(header.objectiveProgresses) do obj:Hide() end end
        if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end

        local startY = aqYOffset
        aqYOffset = aqYOffset + 30

        for _, item in ipairs(superTrackedItems) do
            local h = self:RenderTrackableItem(aqFrame, item, aqYOffset, db.spacingMinorHeaderIndent + 10)
            aqYOffset = aqYOffset + h + db.spacingItemVertical
        end

        local totalHeight = aqYOffset - startY
        if totalHeight < 30 then totalHeight = 30 end
        local backdropPadding = 10
        header.styledBackdrop:SetHeight(totalHeight + backdropPadding)
        aqYOffset = aqYOffset + backdropPadding
    end

    -- Show/hide and size activeQuestFrame based on content
    if aqYOffset > 0 then
        self.activeQuestFrame:SetHeight(aqYOffset)
        if addon.db.minimized then
            self.activeQuestFrame:Hide()
        else
            self.activeQuestFrame:Show()
        end
    else
        self.activeQuestFrame:Hide()
    end

    return aqYOffset
end
