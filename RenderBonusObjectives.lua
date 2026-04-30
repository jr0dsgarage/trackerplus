local addonName, addon = ...

-- Localize hot-path globals
local ipairs = ipairs
local format = string.format
local max = math.max

-- Local aliases for addon utilities

-------------------------------------------------------------------------------
-- RenderBonusSection — Bonus objective rendering
-- Returns: bonusYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderBonusSection(bonusObjectives)
    local db = self.db
    local bonusYOffset = 0
    
    -- Manually render bonus items
    if db.showBonusObjectives and #bonusObjectives > 0 then
         -- Render Header (Bonus Objective)
         local header = self:GetOrCreateButton(self.bonusFrame)
         header:SetPoint("TOPLEFT", self.bonusFrame, "TOPLEFT", 0, -bonusYOffset)
         header:SetPoint("TOPRIGHT", self.bonusFrame, "TOPRIGHT", 0, -bonusYOffset)
         
         header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
         -- Use header color or specific bonus color
         local bonusColor = db.bonusColor or {r=1,g=1,b=1,a=1}
         header.text:SetTextColor(bonusColor.r, bonusColor.g, bonusColor.b, bonusColor.a)
         header.text:SetText("Bonus Objective")
         header.text:SetJustifyH("LEFT")
         
         if header.expandBtn then header.expandBtn:Hide() end
         header.text:ClearAllPoints()
         header.text:SetPoint("LEFT", 5, 0)
         header.text:SetPoint("RIGHT", -5, 0)

         -- Reuse Styling Logic from Active Quest (Backdrop)
         if not header.styledBackdrop then
             header.styledBackdrop = CreateFrame("Frame", nil, header, "BackdropTemplate")
             -- Ensure backdrop is behind the text
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
         if header.bg then
             header.bg:SetColorTexture(0, 0, 0, 0) -- No header fill behind text
         end
         header:SetHeight(30)
         header:Show()
         header._scriptMode = "bonusObjectiveHeader"

         -- Cleanup
         if header.poiButton then header.poiButton:Hide() end
         if header.itemButton then header.itemButton:Hide() end
         if header.icon then header.icon:Hide() end
         if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
         if header.objectiveProgresses then for _, obj in ipairs(header.objectiveProgresses) do obj:Hide() end end
         if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end

         local bonusStartY = bonusYOffset
         bonusYOffset = bonusYOffset + 30 
         
         for _, item in ipairs(bonusObjectives) do
            local height = self:RenderTrackableItem(self.bonusFrame, item, bonusYOffset, db.spacingMinorHeaderIndent + 10)
            bonusYOffset = bonusYOffset + height + db.spacingItemVertical
         end

             local totalHeight = bonusYOffset - bonusStartY
             if totalHeight < 30 then totalHeight = 30 end
             local backdropPadding = 10
             header.styledBackdrop:SetHeight(totalHeight + backdropPadding)
             bonusYOffset = bonusYOffset + backdropPadding
    end
    
    -- Update Bonus Frame Height
    if bonusYOffset > 0 then
        self.bonusFrame:SetHeight(bonusYOffset)
        if addon.db.minimized then
             self.bonusFrame:Hide()
        else
             self.bonusFrame:Show()
        end
    else
        self.bonusFrame:Hide()
    end

    return bonusYOffset
end
