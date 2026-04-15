local addonName, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Localize hot-path globals
local ipairs, pairs, pcall, tostring = ipairs, pairs, pcall, tostring
local format, match = string.format, string.match
local max, floor = math.max, math.floor
local bit_band = bit.band
local hooksecurefunc = hooksecurefunc

-- Local aliases for addon utilities
local DebugLayout = function(...) return addon.DebugLayout(...) end

local function EnsureScenarioBorrowAnchor(owner, borrowedFrame)
    if not (owner and owner.scenarioFrame and borrowedFrame) then
        return
    end

    -- Canonical borrow anchor: one point only, pinned to scenarioFrame TOPRIGHT (0, 0).
    -- Repair only when dirty to minimize churn, but strip immediately if Blizzard injects
    -- extra points or wrong offsets.
    pcall(function()
        local parent = borrowedFrame:GetParent()
        local numPoints = borrowedFrame.GetNumPoints and borrowedFrame:GetNumPoints() or 0
        local point, relativeTo, relativePoint, xOfs, yOfs = borrowedFrame:GetPoint(1)
        local isDirty =
            parent ~= owner.scenarioFrame
            or numPoints ~= 1
            or point ~= "TOPRIGHT"
            or relativeTo ~= owner.scenarioFrame
            or relativePoint ~= "TOPRIGHT"
            or tonumber(xOfs or 0) ~= 0
            or tonumber(yOfs or 0) ~= 0

        if not isDirty then
            return
        end

        if addon.LogAt then
            addon:LogAt("trace", "[SCN-ANCHOR-FIX] normalize parent=%s points=%d p=%s rp=%s x=%.1f y=%.1f",
                tostring(parent), tonumber(numPoints or 0), tostring(point), tostring(relativePoint), tonumber(xOfs or 0), tonumber(yOfs or 0))
        end

        borrowedFrame:ClearAllPoints()
        borrowedFrame:SetPoint("TOPRIGHT", owner.scenarioFrame, "TOPRIGHT", 0, 0)
    end)
end

local function InstallScenarioAnchorGuards(owner, borrowedFrame)
    if not (owner and borrowedFrame and hooksecurefunc) then
        return
    end
    if borrowedFrame._trackerPlusAnchorGuardsInstalled then
        return
    end

    borrowedFrame._trackerPlusAnchorGuardsInstalled = true

    local function shouldGuard(frame)
        return frame
            and frame == owner._activeScenarioBorrowedTracker
            and frame:GetParent() == owner.scenarioFrame
            and frame._trackerPlusAnchorLockEnabled
    end

    local function normalizeFromGuard(frame)
        if not shouldGuard(frame) then
            return
        end
        if frame._trackerPlusGuardApplying then
            return
        end

        frame._trackerPlusGuardApplying = true
        EnsureScenarioBorrowAnchor(owner, frame)
        frame._trackerPlusGuardApplying = nil
    end

    hooksecurefunc(borrowedFrame, "SetPoint", function(frame)
        normalizeFromGuard(frame)
    end)

    hooksecurefunc(borrowedFrame, "ClearAllPoints", function(frame)
        normalizeFromGuard(frame)
    end)
end

local function DescribeAnchor(frame)
    if not frame then
        return "frame=nil"
    end

    local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    local relName = relativeTo and (relativeTo.GetName and relativeTo:GetName() or tostring(relativeTo)) or "nil"
    local frameName = frame.GetName and frame:GetName() or "<unnamed>"
    local top = frame.GetTop and (frame:GetTop() or 0) or 0
    local bottom = frame.GetBottom and (frame:GetBottom() or 0) or 0
    local height = frame.GetHeight and (frame:GetHeight() or 0) or 0
    local shown = frame.IsShown and frame:IsShown() or false
    local parent = frame.GetParent and frame:GetParent() or nil
    local parentName = parent and (parent.GetName and parent:GetName() or tostring(parent)) or "nil"
    local numPoints = frame.GetNumPoints and frame:GetNumPoints() or 0

    return format(
        "%s parent=%s p=%s rel=%s rp=%s x=%.1f y=%.1f top=%.1f bottom=%.1f h=%.1f shown=%s pts=%d",
        tostring(frameName),
        tostring(parentName),
        tostring(point),
        tostring(relName),
        tostring(relativePoint),
        tonumber(xOfs or 0),
        tonumber(yOfs or 0),
        tonumber(top or 0),
        tonumber(bottom or 0),
        tonumber(height or 0),
        tostring(shown),
        tonumber(numPoints or 0)
    )
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
    local scenarioAPI = _G and _G.C_Scenario
    local inScenario = (scenarioAPI and scenarioAPI.IsInScenario and scenarioAPI.IsInScenario()) or false
    
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
    -- Scenario frame borrowing (borrow full tracker frame for stable lifetime)
    ---------------------------------------------------------------------------
    if scenarioTracker and scenarioTracker.ContentsFrame and not hasManualScenarioData and inScenario then
        local contents = scenarioTracker.ContentsFrame
        local borrowedFrame = scenarioTracker
        local trackerChanged = self._activeScenarioBorrowedTracker ~= borrowedFrame
        
        if addon.LogAt then
            addon:LogAt("trace", "[SCN-BORROW] borrowing full tracker=%s trackerShown=%s trackerH=%.1f contentsShown=%s contentsH=%.1f",
                tostring(scenarioTrackerName), tostring(scenarioTracker:IsShown()), tonumber(scenarioTracker:GetHeight() or 0),
                tostring(contents:IsShown()), tonumber(contents:GetHeight() or 0))
        end

        -- Borrow full tracker frame so its internal subtree remains coherent.
        if borrowedFrame then
            if trackerChanged and self._activeScenarioBorrowedTracker and self.RestoreBorrowedFrames then
                self._activeScenarioBorrowedTracker._trackerPlusAnchorLockEnabled = nil
                self:RestoreBorrowedFrames()
            end

            -- Store original parent for later restoration
            if not InCombatLockdown() and not borrowedFrame._trackerPlusOriginalParent then
                borrowedFrame._trackerPlusOriginalParent = borrowedFrame:GetParent()
                borrowedFrame._trackerPlusOriginalPoint1,
                borrowedFrame._trackerPlusOriginalRelTo,
                borrowedFrame._trackerPlusOriginalPoint2,
                borrowedFrame._trackerPlusOriginalX,
                borrowedFrame._trackerPlusOriginalY = borrowedFrame:GetPoint(1)

                if addon.LogAt then
                    addon:LogAt("trace", "[SCN-BORROW] stored original parent, reparenting %s to scenarioFrame",
                        tostring(borrowedFrame.GetName and borrowedFrame:GetName() or "<unnamed>"))
                end
            end
            
            -- Reparent/anchor only when needed to avoid visible popping from
            -- repeated mutation each render tick.
            if not InCombatLockdown() and borrowedFrame:GetParent() ~= self.scenarioFrame then
                borrowedFrame:SetParent(self.scenarioFrame)
            end

            InstallScenarioAnchorGuards(self, borrowedFrame)
            borrowedFrame._trackerPlusAnchorLockEnabled = true

            -- Keep anchor stable without forcing a full re-anchor every frame.
            EnsureScenarioBorrowAnchor(self, borrowedFrame)

            self._activeScenarioBorrowedTracker = borrowedFrame
            
            -- Use the larger of tracker/contents heights so the slot doesn't collapse.
            local trackerHeight = borrowedFrame:GetHeight() or 0
            local contentsHeight = contents:GetHeight() or 0
            local widgetHeight = max(trackerHeight, contentsHeight)
            if widgetHeight > 20 then
                self._lastScenarioBorrowHeight = widgetHeight
            else
                widgetHeight = self._lastScenarioBorrowHeight or widgetHeight
            end
            if widgetHeight < 40 then widgetHeight = 40 end
            scenarioYOffset = widgetHeight + 5
            
            if addon.LogAt then
                addon:LogAt("trace", "[SCN-BORROW] active frame=%s trackerChanged=%s trackerH=%.1f contentsH=%.1f yOffset=%.1f",
                    tostring(borrowedFrame.GetName and borrowedFrame:GetName() or "<unnamed>"),
                    tostring(trackerChanged), tonumber(trackerHeight or 0), tonumber(contentsHeight or 0), tonumber(scenarioYOffset or 0))
                addon:LogAt("trace", "[SCN-ANCHOR] scenario=%s", DescribeAnchor(self.scenarioFrame))
                addon:LogAt("trace", "[SCN-ANCHOR] tracker=%s", DescribeAnchor(borrowedFrame))
                addon:LogAt("trace", "[SCN-ANCHOR] contents=%s", DescribeAnchor(contents))
            end
        end
    elseif hasManualScenarioData then
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

    if (not scenarioTracker or not inScenario) and self._activeScenarioBorrowedTracker and self.RestoreBorrowedFrames then
        self._activeScenarioBorrowedTracker._trackerPlusAnchorLockEnabled = nil
        self:RestoreBorrowedFrames()
        self._activeScenarioBorrowedTracker = nil
    end

    if not scenarioTracker and addon.LogAt then
        addon:LogAt("trace", "[SCN-BORROW] no-active-tracker")
    end

    if (not scenarioTracker or not inScenario) and ObjectiveTrackerFrame and addon.db and addon.db.enabled and not InCombatLockdown() then
        ObjectiveTrackerFrame:SetAlpha(0)
        ObjectiveTrackerFrame:EnableMouse(false)
    end

    return scenarioYOffset
end
