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
-- RenderWorldQuestSection — World quest rendering
-- Returns: wqYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderWorldQuestSection(worldQuestItems)
    local db = self.db
    local wqYOffset = 0
    local wqFrame = self.worldQuestFrame
    local hasBlizzardWQContent = false
    local noHijackContext = addon.IsNoHijackContext and addon:IsNoHijackContext()

    -- Hijacking Strategy for World Quests
    local wqTracker = WorldQuestObjectiveTracker

    -- Ground-truth check: only show WQ section when quests are actively tracked
    local hasAnyTrackedWQ = (#worldQuestItems > 0)
    if not hasAnyTrackedWQ and C_TaskQuest and C_TaskQuest.GetTrackedQuestIDs then
        local ids = C_TaskQuest.GetTrackedQuestIDs()
        if ids and #ids > 0 then
            hasAnyTrackedWQ = true
        end
    end

    local useBlizzardWQ = (not addon.disableBlizzardTrackerHijack) and (not noHijackContext) and hasAnyTrackedWQ and (wqTracker and wqTracker.ContentsFrame) and (#worldQuestItems == 0)
    if useBlizzardWQ and addon.IsUnsafeHijackFrame and addon:IsUnsafeHijackFrame(wqTracker) then
        useBlizzardWQ = false
    end
    local preferManualWQ = (#worldQuestItems > 0)
    if preferManualWQ then
        useBlizzardWQ = false
    end

    -- If nothing to track, restore any previously hijacked frame and bail out early
    if not hasAnyTrackedWQ then
        if wqTracker and wqTracker.ContentsFrame then
            local contents = wqTracker.ContentsFrame
            RestoreHijackedParent(self, contents, wqFrame, wqTracker, "_wqOriginalParent")
        end
        ResetAnchorState(self, "_wqContentsAnchored", "_wqContentsWidth")
        hasBlizzardWQContent = false
        useBlizzardWQ = false
    end

    if useBlizzardWQ then
         local contents = wqTracker.ContentsFrame
         local blizzardWQHeight = contents:GetHeight() or 0
         
         -- Use IsShown() instead of IsVisible() because parent might be hidden
         -- If we are already hijacking (parent is wqFrame) and collapsed, we assume we still have control
         local isHijacked = (contents:GetParent() == wqFrame)
         local isCollapsed = db.collapsedSections and db.collapsedSections["World Quests"]
         
         local hasContent = false
         if isHijacked and isCollapsed then hasContent = true end

         -- Prefer concrete visible child rows over container size, since the Blizzard
         -- frame can report non-zero height even when rows have not rendered yet.
         for _, child in pairs({contents:GetChildren()}) do
             if child:IsShown() and child:GetHeight() > 8 then
                 hasContent = true
                 blizzardWQHeight = max(blizzardWQHeight, child:GetHeight() or 10)
             end
         end

         if not hasContent and contents.WidgetContainer and contents.WidgetContainer:IsShown() then
             local widgetHeight = contents.WidgetContainer:GetHeight() or 0
             if widgetHeight > 8 then
                 hasContent = true
                 blizzardWQHeight = max(blizzardWQHeight, widgetHeight)
             end
         end
         
         if hasContent then
              hasBlizzardWQContent = true
              -- Hijack it!
                pcall(function()
                   if contents:GetParent() ~= wqFrame then
                       EnsureHijackedParent(self, contents, wqFrame, "_wqOriginalParent", "HIGH", 100)
                       ResetAnchorState(self, "_wqContentsAnchored", "_wqContentsWidth")
                   end

                   local wqWidth = self.db.frameWidth - 10
                   if not self._wqContentsAnchored or self._wqContentsWidth ~= wqWidth then
                      contents:ClearAllPoints()
                      -- Position it BELOW the header (which we will create manually below at y=0)
                      contents:SetPoint("TOP", wqFrame, "TOP", 0, -28)
                      contents:SetWidth(wqWidth)
                      self._wqContentsAnchored = true
                      self._wqContentsWidth = wqWidth
                   end

                   EnsureFrameVisible(contents)
              
                   if contents.WidgetContainer then
                       EnsureFrameVisible(contents.WidgetContainer)
                   end
              
                   -- Try to trigger internal update
                   if wqTracker.Update then wqTracker:Update() end
              end)
              
              if blizzardWQHeight < 20 then blizzardWQHeight = 40 end
              -- Calculate offset including the header we are about to make
              wqYOffset = blizzardWQHeight + 35 
         else
              -- Restore if empty
                RestoreHijackedParent(self, contents, wqFrame, wqTracker, "_wqOriginalParent")
                ResetAnchorState(self, "_wqContentsAnchored", "_wqContentsWidth")
                 hasBlizzardWQContent = false
         end
    end

        if not useBlizzardWQ then
            -- Ensure Blizzard WQ frame is restored when we switch to manual mode.
            if wqTracker and wqTracker.ContentsFrame then
                local contents = wqTracker.ContentsFrame
                RestoreHijackedParent(self, contents, wqFrame, wqTracker, "_wqOriginalParent")
            end
            ResetAnchorState(self, "_wqContentsAnchored", "_wqContentsWidth")
            hasBlizzardWQContent = false
        end

    -- Render the Header container for World Quests (Either used by Hijacked frame or manual items)
    if wqFrame and (hasBlizzardWQContent or #worldQuestItems > 0) then
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

        -- If Hijacked frame was found, we don't need to manually render items.
           if useBlizzardWQ and hasBlizzardWQContent and wqYOffset > 0 then
             local contents = wqTracker.ContentsFrame
             EnsureFrameVisible(contents)
             if contents.WidgetContainer then
                 EnsureFrameVisible(contents.WidgetContainer)
             end
           elseif #worldQuestItems > 0 and (wqYOffset == 0 or not hasBlizzardWQContent) then
               -- Fallback: manual render when Blizzard WQ container is missing/empty.
             wqYOffset = 24 + 5
             for _, item in ipairs(worldQuestItems) do
                 local height = self:RenderTrackableItem(wqFrame, item, wqYOffset, db.spacingMinorHeaderIndent + 10)
                 wqYOffset = wqYOffset + height + db.spacingItemVertical
             end
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
