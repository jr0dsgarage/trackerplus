local addonName, addon = ...

-- Localize hot-path globals
local ipairs, pairs, pcall = ipairs, pairs, pcall
local format = string.format
local max = math.max

-- Local aliases for addon utilities
local EnsureFrameVisible = function(...) return addon.EnsureFrameVisible(...) end
local EnsureHijackedParent = function(...) return addon.EnsureHijackedParent(...) end
local RestoreHijackedParent = function(...) return addon.RestoreHijackedParent(...) end
local ResetAnchorState = function(...) return addon.ResetAnchorState(...) end

-------------------------------------------------------------------------------
-- RenderBonusSection — Bonus objective rendering
-- Returns: bonusYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderBonusSection(bonusObjectives)
    local db = self.db
    local bonusYOffset = 0
    local preferManualBonus = (#bonusObjectives > 0)
    local noHijackContext = addon.IsNoHijackContext and addon:IsNoHijackContext()

    -- Strategy: Hijack Blizzard's BonusObjectiveTracker frame if it exists and has content
    local bonusTracker = BonusObjectiveTracker
    local useBlizzardBonus = (not addon.disableBlizzardTrackerHijack) and (not noHijackContext) and (bonusTracker and bonusTracker.ContentsFrame and not preferManualBonus)
    if useBlizzardBonus and addon.IsUnsafeHijackFrame and addon:IsUnsafeHijackFrame(bonusTracker) then
        useBlizzardBonus = false
    end

    if useBlizzardBonus then
         local contents = bonusTracker.ContentsFrame
         local blizzardBonusHeight = contents:GetHeight() or 0
         
         -- Use IsShown() instead of IsVisible() because our parent (ObjectiveTrackerFrame) might be hidden
         local hasContent = blizzardBonusHeight > 1 and contents:IsShown()
         
         -- Also check if there are actual child frames with bars (sometimes height is 0 but children exist)
         if not hasContent then
             -- ContentsFrame might report height but children are individually visible
             for _, child in pairs({contents:GetChildren()}) do
                 -- Check IsShown because IsVisible fails if we hid the main tracker
                 if child:IsShown() and child:GetHeight() > 1 then
                     hasContent = true
                     blizzardBonusHeight = max(blizzardBonusHeight, 10) -- Will recalculate below
                     break
                 end
             end
         end
         
         if hasContent then
              -- Reparent to our bonusFrame
                pcall(function()
                   if contents:GetParent() ~= self.bonusFrame then
                       EnsureHijackedParent(self, contents, self.bonusFrame, "_bonusOriginalParent", "HIGH", 100)
                       ResetAnchorState(self, "_bonusContentsAnchored", "_bonusContentsWidth")
                  end

                    local bonusWidth = self.db.frameWidth - 10
                    if not self._bonusContentsAnchored or self._bonusContentsWidth ~= bonusWidth then
                        contents:ClearAllPoints()
                        contents:SetPoint("TOP", self.bonusFrame, "TOP", 0, -5)
                        contents:SetWidth(bonusWidth)
                        self._bonusContentsAnchored = true
                        self._bonusContentsWidth = bonusWidth
                    end

                    EnsureFrameVisible(contents)

                   -- Ensure children are shown (some instances hide children but show parent)
                   if contents.WidgetContainer then 
                        EnsureFrameVisible(contents.WidgetContainer)
                   end
              end)
              
              -- Recalculate height after reparenting (layout may have changed)
              blizzardBonusHeight = contents:GetHeight() or 0
              if blizzardBonusHeight < 20 then blizzardBonusHeight = 60 end -- Minimum if we know there's content
              
              bonusYOffset = blizzardBonusHeight + 10
              
         else
              -- No bonus content - restore to its original parent if we stole it
              RestoreHijackedParent(self, contents, self.bonusFrame, bonusTracker, "_bonusOriginalParent")
                 ResetAnchorState(self, "_bonusContentsAnchored", "_bonusContentsWidth")
         end
    end

        if not useBlizzardBonus then
            if bonusTracker and bonusTracker.ContentsFrame then
                local contents = bonusTracker.ContentsFrame
                RestoreHijackedParent(self, contents, self.bonusFrame, bonusTracker, "_bonusOriginalParent")
            end
            ResetAnchorState(self, "_bonusContentsAnchored", "_bonusContentsWidth")
        end
    
    -- Fallback: Manually render bonus items if we collected any and Blizzard frame isn't available
    if bonusYOffset == 0 and db.showBonusObjectives and #bonusObjectives > 0 then
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
