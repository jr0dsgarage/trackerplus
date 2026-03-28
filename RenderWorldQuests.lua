local addonName, addon = ...

-- Localize hot-path globals
local ipairs, pairs = ipairs, pairs
local format = string.format
local max = math.max

-- Local aliases for addon utilities

-------------------------------------------------------------------------------
-- RenderWorldQuestSection — World quest rendering
-- Returns: wqYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderWorldQuestSection(worldQuestItems)
    local db = self.db
    local wqYOffset = 0
    local wqFrame = self.worldQuestFrame

    -- Ground-truth check: only show WQ section when quests are actively tracked
    local hasAnyTrackedWQ = (#worldQuestItems > 0)
    if not hasAnyTrackedWQ and C_TaskQuest and C_TaskQuest.GetTrackedQuestIDs then
        local ids = C_TaskQuest.GetTrackedQuestIDs()
        if ids and #ids > 0 then
            hasAnyTrackedWQ = true
        end
    end

    -- If nothing to track, bail out early
    if not hasAnyTrackedWQ then
        if wqFrame then
            wqFrame:SetHeight(0.1)
            wqFrame:Hide()
        end
        return 0
    end

    -- Render the Header container for World Quests
    if wqFrame and #worldQuestItems > 0 then
        -- Header
        local header = self:GetOrCreateButton(wqFrame)
        header:SetPoint("TOPLEFT", wqFrame, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", wqFrame, "TOPRIGHT", 0, 0)
        
        header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
        header.text:SetTextColor(0.204, 0.478, 0.678, 1)  -- #347AAD
        header.text:SetText("World Quests")
        header.text:SetJustifyH("LEFT")
        header.text:ClearAllPoints()
        header.text:SetPoint("LEFT", 5, 0)
        header.text:SetPoint("RIGHT", -5, 0)
        
        -- No expand/collapse button (matching Bonus Objective style)
        if header.expandBtn then header.expandBtn:Hide() end
        
        -- Styled Backdrop (matching Bonus Objective style)
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
        
        if header.bg then
            header.bg:SetColorTexture(0, 0, 0, 0)
        end
        
        -- Cleanup header recycling
        if header.poiButton then header.poiButton:Hide() end
        if header.itemButton then header.itemButton:Hide() end
        if header.distance then header.distance:Hide() end
        if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
        if header.objectiveBullets then for _, obj in ipairs(header.objectiveBullets) do obj:Hide() end end
        if header.objectivePrefixes then for _, obj in ipairs(header.objectivePrefixes) do obj:Hide() end end
        if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end

        header:SetHeight(30)
        header:Show()
        header._scriptMode = "worldQuestHeader"
        wqYOffset = 24 + 5
        for _, item in ipairs(worldQuestItems) do
            local height = self:RenderTrackableItem(wqFrame, item, wqYOffset, db.spacingMinorHeaderIndent + 10)
            wqYOffset = wqYOffset + height + db.spacingItemVertical
        end

          -- Set styledBackdrop height to cover the full section
          local backdropPadding = 5
        header.styledBackdrop:SetHeight(wqYOffset + backdropPadding)
        header.styledBackdrop:Show()
    end
    
    if wqFrame then
        if wqYOffset > 0 then
            wqFrame:SetHeight(wqYOffset)
            if addon.db.minimized then
                 wqFrame:Hide()
            else
                 wqFrame:Show()
            end
        else
            wqFrame:SetHeight(0.1) -- Minimal height to prevent layout gaps
            wqFrame:Hide()
        end
    end

    return wqYOffset
end
