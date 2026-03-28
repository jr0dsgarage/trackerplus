local addonName, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Localize hot-path globals
local ipairs, pairs, pcall, tostring = ipairs, pairs, pcall, tostring
local format, match = string.format, string.match
local max, floor = math.max, math.floor
local bit_band = bit.band

-- Local aliases for addon utilities
local DebugLayout = function(...) return addon.DebugLayout(...) end

local function EnsureBorrowedScenarioAnchor(owner, borrowedFrame)
    local scenarioFrame = owner and owner.scenarioFrame
    if not scenarioFrame or not borrowedFrame then return end

    if not scenarioFrame._borrowAnchorEnforcerInstalled then
        scenarioFrame:HookScript("OnUpdate", function(frame)
            local borrowed = frame.borrowedFrame
            if not borrowed or borrowed:GetParent() ~= frame then return end

            local point, relativeTo, relativePoint, x, y = borrowed:GetPoint(1)
            local needsReset = borrowed:GetNumPoints() ~= 1
                or point ~= "TOPRIGHT"
                or relativeTo ~= frame
                or relativePoint ~= "TOPRIGHT"
                or x ~= 0
                or y ~= 0

            if needsReset then
                borrowed:ClearAllPoints()
                borrowed:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            end
        end)
        scenarioFrame._borrowAnchorEnforcerInstalled = true
    end

    borrowedFrame:ClearAllPoints()
    borrowedFrame:SetPoint("TOPRIGHT", scenarioFrame, "TOPRIGHT", 0, 0)
end

-------------------------------------------------------------------------------
-- RenderScenarioSection — manual mirror rendering
-- Returns: scenarioYOffset (total height consumed by scenario section)
-------------------------------------------------------------------------------
function addon:RenderScenarioSection()
    local db = self.db
    local hasManualScenarioData = false
    local scenarioTracker = nil
    local scenarioTrackerName = nil
    
    -- Detect active Blizzard scenario tracker (Delves, Scenarios, Dungeons)
    local candidates = {
        "DelvesObjectiveTracker",
        "DelveObjectiveTracker", 
        "ScenarioObjectiveTracker",
    }
    for _, name in ipairs(candidates) do
        local tracker = _G and _G[name]
        if tracker and tracker.ContentsFrame then
            local trackerShown = tracker:IsShown()
            local contentsShown = tracker.ContentsFrame:IsShown()
            local trackerAlpha = tracker.GetAlpha and tracker:GetAlpha() or -1
            local contentsAlpha = tracker.ContentsFrame.GetAlpha and tracker.ContentsFrame:GetAlpha() or -1
            local trackerHeight = tracker:GetHeight() or 0
            local contentsHeight = tracker.ContentsFrame:GetHeight() or 0
            local contentsChildren = tracker.ContentsFrame.GetNumChildren and tracker.ContentsFrame:GetNumChildren() or 0

            if addon.LogAt then
                addon:LogAt("trace", "[SCN-BORROW] candidate=%s shown=%s cShown=%s alpha=%.2f cAlpha=%.2f h=%.1f cH=%.1f cChildren=%d",
                    tostring(name), tostring(trackerShown), tostring(contentsShown), trackerAlpha, contentsAlpha, trackerHeight, contentsHeight, contentsChildren)
            end

            if trackerShown and contentsShown then
                scenarioTracker = tracker
                scenarioTrackerName = name
                break
            end
        end
    end
    
    if self.currentScenarios and #self.currentScenarios > 0 then
        for _, scenarioItem in ipairs(self.currentScenarios) do
            if not scenarioItem.isDummy then
                hasManualScenarioData = true
                break
            end
        end
    end

    if addon.LogAt then
        addon:LogAt("trace", "[SCN-BORROW] selected=%s manualData=%s scenarioCount=%d",
            tostring(scenarioTrackerName), tostring(hasManualScenarioData), tonumber((self.currentScenarios and #self.currentScenarios) or 0))
    end

    local scenarioYOffset = 0

    ---------------------------------------------------------------------------
    -- Show Blizzard scenario/delve frame visually
    ---------------------------------------------------------------------------
    if scenarioTracker and scenarioTracker.ContentsFrame and not hasManualScenarioData then
        -- Borrow the scenario tracker itself into TrackerPlus so the default
        -- ObjectiveTracker panel can remain hidden.
        local contents = scenarioTracker.ContentsFrame
        local hostFrame = scenarioTracker
        local objectiveAlphaBefore = ObjectiveTrackerFrame and ObjectiveTrackerFrame.GetAlpha and ObjectiveTrackerFrame:GetAlpha() or -1
        local objectiveShownBefore = ObjectiveTrackerFrame and ObjectiveTrackerFrame:IsShown() or false
        local parentFrame = hostFrame:GetParent()
        local parentName = parentFrame and parentFrame.GetName and parentFrame:GetName() or "<nil>"

        local visibleChildren = 0
        for _, child in pairs({contents:GetChildren()}) do
            if child:IsShown() then
                visibleChildren = visibleChildren + 1
            end
        end

        if addon.LogAt then
            addon:LogAt("trace", "[SCN-BORROW] pre-show tracker=%s parent=%s hostShown=%s hostAlpha=%.2f contentShown=%s contentAlpha=%.2f widget=%s visibleChildren=%d",
                tostring(scenarioTrackerName), tostring(parentName), tostring(hostFrame:IsShown()), hostFrame:GetAlpha() or -1,
                tostring(contents:IsShown()), contents:GetAlpha() or -1, tostring(contents.WidgetContainer ~= nil), visibleChildren)
        end

        -- Restore any previously borrowed scenario subtree if we are switching trackers.
        if self.scenarioFrame and self.scenarioFrame.borrowedFrame and self.scenarioFrame.borrowedFrame ~= hostFrame then
            self:RestoreAllHijackedFrames()
        end

        -- Borrow the full scenario host so the subtree keeps its natural geometry,
        -- but enforce our pinned anchors because Blizzard's layout code may try to
        -- move it after we attach it.
        if not InCombatLockdown() and not (hostFrame.IsProtected and hostFrame:IsProtected()) then
            if hostFrame:GetParent() ~= self.scenarioFrame then
                addon.scenarioHostOriginalParent = hostFrame:GetParent()
                hostFrame:SetParent(self.scenarioFrame)
            end
            self.scenarioFrame.borrowedFrame = hostFrame
            EnsureBorrowedScenarioAnchor(self, hostFrame)
        end

        -- Keep the default ObjectiveTracker hidden while the borrowed subtree is
        -- rendered under TrackerPlus.
        if ObjectiveTrackerFrame and not InCombatLockdown() then
            ObjectiveTrackerFrame:SetAlpha(0)
        end

        -- Keep the owning module alive and visible under TrackerPlus.
        hostFrame:Show()
        hostFrame:SetAlpha(1)
        if hostFrame.SetIgnoreParentAlpha then
            hostFrame:SetIgnoreParentAlpha(true)
        end
        contents:Show()
        contents:SetAlpha(1)
        if contents.SetIgnoreParentAlpha then
            contents:SetIgnoreParentAlpha(true)
        end
        if contents.WidgetContainer then 
            contents.WidgetContainer:Show()
            contents.WidgetContainer:SetAlpha(1)
            if contents.WidgetContainer.SetIgnoreParentAlpha then
                contents.WidgetContainer:SetIgnoreParentAlpha(true)
            end
        end

        local objectiveAlphaAfter = ObjectiveTrackerFrame and ObjectiveTrackerFrame.GetAlpha and ObjectiveTrackerFrame:GetAlpha() or -1
        local objectiveShownAfter = ObjectiveTrackerFrame and ObjectiveTrackerFrame:IsShown() or false
        local widgetShown = contents.WidgetContainer and contents.WidgetContainer:IsShown() or false
        local widgetHeight = contents.WidgetContainer and (contents.WidgetContainer:GetHeight() or 0) or 0
        local hostTop = hostFrame:GetTop() or -1
        local hostBottom = hostFrame:GetBottom() or -1
        local contentTop = contents:GetTop() or -1
        local contentBottom = contents:GetBottom() or -1

        if addon.LogAt then
            addon:LogAt("trace", "[SCN-BORROW] post-show objShown=%s->%s objAlpha=%.2f->%.2f hostShown=%s cShown=%s widgetShown=%s widgetH=%.1f hostTop=%.1f hostBottom=%.1f cTop=%.1f cBottom=%.1f",
                tostring(objectiveShownBefore), tostring(objectiveShownAfter), objectiveAlphaBefore, objectiveAlphaAfter,
                tostring(hostFrame:IsShown()), tostring(contents:IsShown()), tostring(widgetShown), widgetHeight,
                hostTop, hostBottom, contentTop, contentBottom)
        end
        
        -- Calculate reserved space from the stable host frame.
        local blizzardHeight = hostFrame:GetHeight() or contents:GetHeight() or 0
        if blizzardHeight < 20 then blizzardHeight = 60 end

        if addon.LogAt and blizzardHeight >= 20 and not widgetShown and visibleChildren == 0 then
            addon:LogAt("warn", "[SCN-BORROW] reserved-height-without-widget tracker=%s h=%.1f cH=%.1f", tostring(scenarioTrackerName), hostFrame:GetHeight() or 0, contents:GetHeight() or 0)
        end
        
        scenarioYOffset = blizzardHeight + 15
        DebugLayout(self, "[SCN] Borrowed Blizzard scenario frame, height=%d", blizzardHeight)
    elseif hasManualScenarioData then
        self:RestoreAllHijackedFrames()
        local header = self:GetOrCreateButton(self.scenarioFrame) -- Use scenarioFrame as parent
        header:ClearAllPoints()
        header:SetPoint("TOPRIGHT", self.scenarioFrame, "TOPRIGHT", 0, -scenarioYOffset)
        header:SetWidth(self.db.frameWidth - 10)
        
        header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
        header.text:SetTextColor(db.headerColor.r, db.headerColor.g, db.headerColor.b, db.headerColor.a)
        header.text:SetText("Scenario / Dungeon")
        header.text:SetJustifyH("LEFT")
        
        -- Hide the expand/collapse button for scenarios
        if header.expandBtn then
             header.expandBtn:Hide()
        end
        -- Reset text position since there is no icon
        header.text:ClearAllPoints()
        header.text:SetPoint("LEFT", 5, 0)
        header.text:SetPoint("RIGHT", -5, 0)
        
        header.bg:SetColorTexture(0, 0, 0, 0.4)
        header:SetHeight(24)
        header:Show()
        header._scriptMode = "scenarioHeader"

        -- Cleanup header parts
        if header.poiButton then header.poiButton:Hide() end
        if header.itemButton then header.itemButton:Hide() end
        if header.icon then header.icon:Hide() end
        if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
        if header.objectiveBullets then for _, obj in ipairs(header.objectiveBullets) do obj:Hide() end end
        if header.objectivePrefixes then for _, obj in ipairs(header.objectivePrefixes) do obj:Hide() end end
        if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end
        if header.distance then header.distance:Hide() end
        
        scenarioYOffset = scenarioYOffset + 26
        
        -- Render Scenario Content
        for _, item in ipairs(self.currentScenarios) do
              local button = self:GetOrCreateButton(self.scenarioFrame)
              button:ClearAllPoints()
              button:SetPoint("TOPRIGHT", self.scenarioFrame, "TOPRIGHT", -5, -scenarioYOffset)
              button:SetWidth(self.db.frameWidth - 20)
              
              -- Setup Button Appearance
              button.text:SetFont(db.fontFace, db.fontSize + 2, db.fontOutline) -- Slightly larger for Scenario Title
              local color = item.color or {r=1, g=1, b=1, a=1}
              button.text:SetTextColor(color.r, color.g, color.b, color.a)
              button.text:SetText(item.title)
              button.text:SetPoint("TOPLEFT", 5, -2) -- Simple padding
              button.bg:SetColorTexture(0, 0, 0, 0)
              
              if button.poiButton then button.poiButton:Hide() end
              if button.itemButton then button.itemButton:Hide() end
              if button.expandBtn then button.expandBtn:Hide() end
              if button.distance then button.distance:Hide() end
              
              if button.objectives then for _, obj in ipairs(button.objectives) do obj:Hide() end end
              if button.objectiveBullets then for _, obj in ipairs(button.objectiveBullets) do obj:Hide() end end
              if button.objectivePrefixes then for _, obj in ipairs(button.objectivePrefixes) do obj:Hide() end end
              if button.progressBars then for _, bar in ipairs(button.progressBars) do bar:Hide() end end
              
              local height = db.fontSize + 6

              -- Stage Box
              if item.stageName then
                 if not button.stageBox then
                    -- Create the container
                    button.stageBox = CreateFrame("Frame", nil, button, "BackdropTemplate")
                    button.stageBox:SetBackdrop({
                        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 16,
                        insets = { left = 4, right = 4, top = 4, bottom = 4 }
                    })
                    button.stageBox:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
                    button.stageBox:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
                    
                    button.stageBox.text = button.stageBox:CreateFontString(nil, "OVERLAY")
                    button.stageBox.text:SetPoint("CENTER")
                 end
                 
                 button.stageBox:SetPoint("TOPLEFT", button, "TOPLEFT", 10, -height)
                 button.stageBox:SetPoint("TOPRIGHT", button, "TOPRIGHT", -10, -height)
                 button.stageBox.text:SetFont(db.headerFontFace, db.fontSize + 4, db.headerFontOutline)
                 button.stageBox.text:SetText(item.stageName)
                 button.stageBox:SetHeight(30)
                 -- Higher frame level to cover other elements if needed, but not too high
                 button.stageBox:SetFrameLevel(button:GetFrameLevel() + 5) 
                 button.stageBox:Show()
                 
                 height = height + 35
              elseif button.stageBox then
                 button.stageBox:Hide()
              end
              
              -- Objectives
               if item.objectives and #item.objectives > 0 then
                    for objIndex, obj in ipairs(item.objectives) do
                        -- Filter unwanted "Progress" objective 
                        if obj.text == "Progress" then
                             if button.objectives and button.objectives[objIndex] then button.objectives[objIndex]:Hide() end
                             if button.progressBars and button.progressBars[objIndex] then button.progressBars[objIndex]:Hide() end
                        else
                        local objText = "  - " .. obj.text
                        local isProgressBar = false
                        local progressValue = 0
                        local progressMax = 100
                        local progressText = ""

                        -- Determine if it's a ProgressBar criteria
                        -- Bit 1 (value 1) is usually ShowProgressBar. 
                        local flags = obj.flags or 0
                        local hasProgressBarFlag = bit_band(flags, 1) == 1
                        
                        -- Relaxed Check: If quantityString has '%', force it to be a progress bar
                        -- This catches cases where the flag is missing but the intent is clear
                        if obj.quantityString and string.find(obj.quantityString, "%%") then
                             hasProgressBarFlag = true
                        end
                        
                        -- Do not show progress bars if quest or objective is complete
                        local isObjComplete = obj.finished or (obj.numRequired and obj.numRequired > 0 and obj.numFulfilled and obj.numFulfilled >= obj.numRequired)
                        if item.isComplete or isObjComplete then
                             hasProgressBarFlag = false
                        end

                        if hasProgressBarFlag then
                             isProgressBar = true
                             
                             -- Simplified Percentage Logic
                             local percent = 0
                             local foundPercent = false
                             
                             -- 1. Trust explicitly provided string percentages (e.g. "67%")
                             if obj.quantityString then
                                 local val = string.match(obj.quantityString, "(%d+)%%")
                                 if val then
                                     local v = tonumber(val)
                                     if v <= 100 then
                                         percent = v
                                         foundPercent = true
                                     end
                                 end
                             end
                             
                             -- 2. If no valid string percentage found...
                             if not foundPercent then
                                 if (obj.numRequired and obj.numRequired > 100) and (obj.numFulfilled and obj.numFulfilled <= 100) then
                                     percent = obj.numFulfilled
                                 else
                                     local cur = obj.numFulfilled or 0
                                     local req = obj.numRequired or 0
                                     
                                     if req > 0 then
                                         percent = (cur / req) * 100
                                     else
                                         percent = cur
                                     end
                                 end
                             end
                             
                             -- 3. Clamp and Display
                             if percent > 100 then percent = 100 end
                             if percent < 0 then percent = 0 end
                             
                             -- If calculated percent is 100% (or more), treat as complete and hide bar
                             if percent >= 100 then
                                isProgressBar = false
                             end
                             
                             progressValue = percent
                             progressMax = 100
                             progressText = format("%d%%", floor(percent))
                            
                             objText = "  - " .. obj.text
                        elseif obj.numRequired and obj.numRequired > 0 then
                             local cur = obj.numFulfilled or 0
                             local req = obj.numRequired or 0
                             local percent

                             if req > 0 then
                                 percent = (cur / req) * 100
                             elseif cur <= 100 then
                                 percent = cur
                             else
                                 percent = 100
                             end
                             
                             if percent > 100 then percent = 100 end
                             if percent < 0 then percent = 0 end
                             
                             progressValue = percent
                             progressMax = 100
                             progressText = format("%d%%", floor(percent))
                            
                             objText = "  - " .. obj.text
                        elseif obj.quantityString and obj.quantityString ~= "" then
                             -- Fallback if numRequired is 0 but we have a quantity string (common in some scenarios)
                             objText = format("  - %s: %s", obj.text, obj.quantityString)
                        end
                        
                        if not button.objectives then button.objectives = {} end

                        -- Ensure Text Line Exists
                        local objLine = button.objectives[objIndex]
                        if not objLine then
                            objLine = button:CreateFontString(nil, "OVERLAY")
                            button.objectives[objIndex] = objLine
                        end
                        
                        objLine:SetParent(button)
                        objLine:SetPoint("TOPLEFT", button.text, "BOTTOMLEFT", 0, -(height - (db.fontSize + 4)))
                        objLine:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
                        local objColor = obj.finished and db.completeColor or db.objectiveColor
                        objLine:SetTextColor(objColor.r, objColor.g, objColor.b, objColor.a)
                        objLine:SetText(objText)
                        objLine:SetJustifyH("LEFT")
                        objLine:Show()
                        
                        height = height + (db.fontSize + 2)
                        
                        -- Progress Bar Handling
                        if isProgressBar then
                            if not button.progressBars then button.progressBars = {} end
                            local bar = button.progressBars[objIndex]
                            if not bar then
                                local pcallStatus, newBar = pcall(CreateFrame, "Frame", nil, button, "QuestObjectiveProgressBarTemplate")
                                if pcallStatus and newBar then
                                    bar = newBar
                                    bar.isTemplate = true
                                else
                                    bar = CreateFrame("StatusBar", nil, button)
                                    bar:SetSize(1, 21) 
                                    
                                    local barTex = "Interface\\TargetingFrame\\UI-StatusBar"
                                    if LSM and db.barTexture then
                                         barTex = LSM:Fetch("statusbar", db.barTexture) or barTex
                                    end
                                    bar:SetStatusBarTexture(barTex)
                                    
                                    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
                                    bar.bg:SetAllPoints()
                                    local bgC = db.barBackgroundColor or {r=0,g=0,b=0,a=0.5}
                                    bar.bg:SetColorTexture(bgC.r, bgC.g, bgC.b, bgC.a)
                                    
                                    bar.value = bar:CreateFontString(nil, "OVERLAY")
                                    bar.value:SetFont(db.fontFace, 10, "OUTLINE")
                                    bar.value:SetPoint("CENTER")
                                    
                                    addon:CreateBorderLines(bar, db.barBorderSize)
                                    bar.isTemplate = false
                                end
                                button.progressBars[objIndex] = bar
                            end
                            
                            -- Update style only when settings changed
                            if not bar.isTemplate then
                                 local barTex = "Interface\\TargetingFrame\\UI-StatusBar"
                                 if LSM and db.barTexture then
                                      barTex = LSM:Fetch("statusbar", db.barTexture) or barTex
                                 end
                                 local bgC = db.barBackgroundColor or {r=0,g=0,b=0,a=0.5}
                                 local styleSig = format("%s|%d|%.3f|%.3f|%.3f|%.3f",
                                     tostring(barTex),
                                     db.barBorderSize or 0,
                                     bgC.r or 0, bgC.g or 0, bgC.b or 0, bgC.a or 0
                                 )
                                 if bar._styleSig ~= styleSig then
                                     bar:SetStatusBarTexture(barTex)
                                     if bar.bg then bar.bg:SetColorTexture(bgC.r, bgC.g, bgC.b, bgC.a) end
                                     addon:CreateBorderLines(bar, db.barBorderSize)
                                     bar._styleSig = styleSig
                                 end
                            elseif bar.Bar then
                                 local borderSize = db.barBorderSize or 0
                                 if bar._borderSizeApplied ~= borderSize then
                                     addon:CreateBorderLines(bar.Bar, borderSize)
                                     bar._borderSizeApplied = borderSize
                                 end
                            end

                            local anchorKey = format("%d|%d|%d", 20, -height, 20)
                            if bar._anchorKey ~= anchorKey then
                                bar:ClearAllPoints()
                                bar:SetPoint("TOPLEFT", 20, -height)
                                bar:SetPoint("TOPRIGHT", -20, -height)
                                bar._anchorKey = anchorKey
                            end
                            
                            if bar.isTemplate and bar.Bar then
                                 bar.Bar:SetMinMaxValues(0, progressMax)
                                 bar.Bar:SetValue(progressValue)
                                 bar.Bar:SetStatusBarColor(0, 0.5, 1, 1)
                                 if bar.Bar.Label then bar.Bar.Label:SetText(progressText) end
                            else
                                bar:SetHeight(21)
                                bar:SetMinMaxValues(0, progressMax)
                                bar:SetValue(progressValue)
                                bar:SetStatusBarColor(0, 0.5, 1, 1) 
                                if bar.value then bar.value:SetText(progressText) end
                            end
                            
                            bar:Show()
                            height = height + 25
                        elseif button.progressBars and button.progressBars[objIndex] then
                             button.progressBars[objIndex]:Hide()
                        end
                        end -- End of skip check
                    end
                    
                    -- Start hiding unused bars
                    if button.progressBars then
                         for i = #item.objectives + 1, #button.progressBars do
                             button.progressBars[i]:Hide()
                         end
                    end
               end
               
               button:SetHeight(height + 4)
               button:Show()
               button._scriptMode = "scenarioRow"
               scenarioYOffset = scenarioYOffset + height + 8
        end
    end

    -- Hide Blizzard frame if we rendered manual content
    local scenarioTracker2 = _G and (_G.DelvesObjectiveTracker or _G.DelveObjectiveTracker or _G.ScenarioObjectiveTracker)
    if scenarioTracker2 and hasManualScenarioData then
        scenarioTracker2:Hide()
        if addon.LogAt then
            local n = scenarioTracker2.GetName and scenarioTracker2:GetName() or "<unknown>"
            addon:LogAt("trace", "[SCN-BORROW] manual-data-active hiding=%s", tostring(n))
        end
    elseif not scenarioTracker then
        self:RestoreAllHijackedFrames()
        -- No scenario tracker active and no manual content — hide ObjectiveTrackerFrame
        if ObjectiveTrackerFrame then
            ObjectiveTrackerFrame:SetAlpha(0)
        end
        if addon.LogAt then
            addon:LogAt("trace", "[SCN-BORROW] no-active-tracker objectiveTrackerAlphaSet=0")
        end
    end

    return scenarioYOffset
end
