local addonName, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Localize hot-path globals
local ipairs, pairs, pcall, tostring = ipairs, pairs, pcall, tostring
local format, match = string.format, string.match
local max, floor = math.max, math.floor
local bit_band = bit.band

-- Local aliases for addon utilities
local GetScenarioTrackerSource = function() return addon.GetScenarioTrackerSource() end
local EnsureFrameVisible = function(...) return addon.EnsureFrameVisible(...) end
local EnsureHijackedParent = function(...) return addon.EnsureHijackedParent(...) end
local RestoreHijackedParent = function(...) return addon.RestoreHijackedParent(...) end
local ResetAnchorState = function(...) return addon.ResetAnchorState(...) end
local DebugLayout = function(...) return addon.DebugLayout(...) end

-------------------------------------------------------------------------------
-- RenderScenarioSection — Blizzard frame hijacking + manual fallback
-- Returns: scenarioYOffset (total height consumed by scenario section)
-------------------------------------------------------------------------------
function addon:RenderScenarioSection()
    local db = self.db
    local scenarioTracker = GetScenarioTrackerSource()
    local isInScenario = (C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario()) or false

    local forceManualScenario = false
    local hasManualScenarioData = false
    if self.currentScenarios and #self.currentScenarios > 0 then
        for _, scenarioItem in ipairs(self.currentScenarios) do
            if not scenarioItem.isDummy then
                hasManualScenarioData = true
                break
            end
        end
    end

    local isScenarioActive = isInScenario or hasManualScenarioData
    local useBlizzardScenario = not addon.disableBlizzardTrackerHijack and isScenarioActive and scenarioTracker and scenarioTracker.ContentsFrame
    
    addon:LogAt("trace", "[SCENARIO] isScenarioActive=%s, disableHijack=%s, tracker=%s, useBlizzardScenario=%s", tostring(isScenarioActive), tostring(addon.disableBlizzardTrackerHijack), tostring(scenarioTracker and scenarioTracker:GetName()), tostring(useBlizzardScenario))

    local scenarioHeight = 0
    local scenarioYOffset = 0 -- Start at 0 relative to scenarioFrame

        if useBlizzardScenario then
            local scenarioBottomPadding = 24
         -- We are using Blizzard's frame, so we hijack it.
         local hostFrame = scenarioTracker
         local contents = scenarioTracker.ContentsFrame
         local hasScenarioContent = false
         local rawHeight = 0
         local widgetHeight = 0
         local visibleChildren = 0
         local maxVisibleChildHeight = 0

            -- Reparent hostFrame into our scenarioFrame once.
            -- After SetParent(), Blizzard's own tracker Update() loop will try to
            -- re-anchor the frame back into ObjectiveTrackerFrame via SetPoint().
            -- We lock the frame to fill scenarioFrame and hook SetPoint to swallow
            -- any repositioning Blizzard attempts, so our layout is never overridden.
            local wasHijacked = (hostFrame:GetParent() ~= self.scenarioFrame)
            EnsureHijackedParent(self, hostFrame, self.scenarioFrame, "_scenarioOriginalParent", "HIGH", 100)

            local RIGHT_INSET = 0  -- scenarioFrame's own 5px inset is sufficient

            if wasHijacked then
                -- Swallow any SetPoint calls Blizzard makes on this frame (e.g. from
                -- DelvesObjectiveTracker:Update / ScenarioObjectiveTracker:Update).
                -- The hook re-applies our TOPLEFT anchor, computed so the widget's
                -- right edge sits RIGHT_INSET pixels inside scenarioFrame.
                if not hostFrame._tpSetPointHooked then
                    hooksecurefunc(hostFrame, "SetPoint", function(f)
                        if f._tpLockAnchors and not f._tpReanchorring then
                            f._tpReanchorring = true
                            local sw = addon.scenarioFrame and addon.scenarioFrame:GetWidth() or 0
                            local hw = f:GetWidth() or 0
                            if sw > 10 and hw > 10 then
                                local xOff = sw - hw - RIGHT_INSET
                                f:ClearAllPoints()
                                f:SetPoint("TOPLEFT", addon.scenarioFrame, "TOPLEFT", xOff, 0)
                            end
                            f._tpReanchorring = false
                        end
                    end)
                    hostFrame._tpSetPointHooked = true
                end
                hostFrame._tpLockAnchors = true
            end

            -- Always re-enforce TOPLEFT anchor every render pass. We position the
            -- widget so its right edge lands RIGHT_INSET px inside scenarioFrame.
            -- We do NOT call SetWidth — Blizzard keeps its natural widget size.
            hostFrame._tpReanchorring = true
            local sw = self.scenarioFrame:GetWidth() or 0
            local hw = hostFrame:GetWidth() or 0
            if sw > 10 and hw > 10 then
                local xOff = sw - hw - RIGHT_INSET
                hostFrame:ClearAllPoints()
                hostFrame:SetPoint("TOPLEFT", self.scenarioFrame, "TOPLEFT", xOff, 0)
                DebugLayout(self, "[SCN] TOPLEFT anchor enforced, xOff=%d (sw=%d hw=%d)", xOff, sw, hw)
            else
                -- Fallback: frame sizes not resolved yet, pin to right edge temporarily
                hostFrame:ClearAllPoints()
                hostFrame:SetPoint("TOPRIGHT", self.scenarioFrame, "TOPRIGHT", -RIGHT_INSET, 0)
                DebugLayout(self, "[SCN] TOPRIGHT fallback (sw=%d hw=%d)", sw, hw)
            end
            hostFrame._tpReanchorring = false

            if self.scenarioFrame.bgMask then self.scenarioFrame.bgMask:Hide() end

            -- Let Blizzard keep its natural widths for ContentsFrame,
            -- WidgetContainer, and Header — we only control position, not size.

            if hostFrame.Header then

                if hostFrame.Header.Text and not hostFrame._trackerPlusHeaderHooked then
                    local function TrackerPlus_UpdateScenarioHeader(textStr)
                        if textStr._tpUpdating then return end
                        textStr._tpUpdating = true

                        local inInstance, instanceType = IsInInstance()
                        if inInstance then
                            if instanceType == "party" then
                                textStr:SetText(TRACKER_HEADER_DUNGEON or "Dungeon")
                            elseif instanceType == "scenario" then
                                local name = GetInstanceInfo()
                                if name and name ~= "" then
                                    textStr:SetText(name)
                                else
                                    textStr:SetText("Delve / Scenario")
                                end
                            end
                        end
                        textStr._tpUpdating = false
                    end
                    hooksecurefunc(hostFrame.Header.Text, "SetText", TrackerPlus_UpdateScenarioHeader)
                    TrackerPlus_UpdateScenarioHeader(hostFrame.Header.Text)
                    hostFrame._trackerPlusHeaderHooked = true
                end
            end

         EnsureFrameVisible(hostFrame)
         EnsureFrameVisible(contents)

         -- Attempt to find internal WidgetContainer and force show it
         if contents.WidgetContainer then
             EnsureFrameVisible(contents.WidgetContainer)
         end

         -- Hook OnSizeChanged so that Blizzard's roll-up/down animations (which resize
         -- hostFrame and ContentsFrame every frame) trigger a layout refresh.  The
         -- RequestUpdate("scenarios") call feeds into the existing 50ms burst throttle so
         -- we don't re-render on every animation frame.
         if not hostFrame._trackerPlusSizeHooked then
             hostFrame:HookScript("OnSizeChanged", function()
                 addon:RequestUpdate("scenarios")
             end)
             if contents then
                 contents:HookScript("OnSizeChanged", function()
                     addon:RequestUpdate("scenarios")
                 end)
             end
             hostFrame._trackerPlusSizeHooked = true
         end

         -- The height of the blizzard frame varies. We need to update our container to match it.
         -- Use robust child-scanning to determine true content height, as GetHeight() on the container 
         -- is often unreliable during objective updates or animations.
         local blizzardHeight = 0
         
         -- hostFrame has only a TOPRIGHT top-anchor; its height is driven by Blizzard's
         -- internal layout and is independent of scenarioFrame's height, so reading
         -- hostFrame:GetHeight() here does NOT create a feedback loop.
         rawHeight = max(contents:GetHeight() or 0, hostFrame:GetHeight() or 0)
         DebugLayout(self, "[SCN] HEIGHT rawHeight=%.2f (contents=%.2f hostFrame=%.2f)",
             rawHeight, contents:GetHeight() or 0, hostFrame:GetHeight() or 0)

         -- Method 2: Check WidgetContainer
         if contents.WidgetContainer and contents.WidgetContainer:IsShown() then
             local wH = contents.WidgetContainer:GetHeight() or 0
             widgetHeight = wH
             if wH > blizzardHeight then blizzardHeight = wH end
             if wH > 8 then hasScenarioContent = true end
         end

         -- Method 3: Scan visible children and compute vertical extent (stacked rows).
         local minBottom = nil
         local maxChildTop = nil
         local scenFrameHasPosition = (self.scenarioFrame:GetTop() ~= nil)
         local function AccumulateChildExtent(parentFrame)
             if not parentFrame or not parentFrame.GetNumChildren then return end
             for _, child in pairs({parentFrame:GetChildren()}) do
                 if child:IsShown() then
                     visibleChildren = visibleChildren + 1
                     local childHeight = child:GetHeight() or 0
                     if childHeight > maxVisibleChildHeight then
                         maxVisibleChildHeight = childHeight
                     end
                     if childHeight > 8 then
                         hasScenarioContent = true
                     end

                     -- Only read screen coordinates when our parent has a valid position
                     if scenFrameHasPosition then
                         local childTop = child:GetTop()
                         if childTop and (not maxChildTop or childTop > maxChildTop) then
                             maxChildTop = childTop
                         end

                         local childBottom = child:GetBottom()
                         if childBottom then
                             if not minBottom or childBottom < minBottom then
                                 minBottom = childBottom
                             end
                         end
                     end
                 end
             end
         end

         local maxTop = nil
         local hostTop = hostFrame:GetTop()
         local contentsTop = contents:GetTop()
         if hostTop and contentsTop then
             maxTop = max(hostTop, contentsTop)
         else
             maxTop = hostTop or contentsTop
         end

         AccumulateChildExtent(contents)
         AccumulateChildExtent(hostFrame)

         if maxChildTop and minBottom then
             local extentHeight = maxChildTop - minBottom
             if extentHeight > blizzardHeight then
                 blizzardHeight = extentHeight
             end
         end

         -- Always floor blizzardHeight at rawHeight (= max of hostFrame and ContentsFrame
         -- reported heights).  Sub-component scans (WidgetContainer, individual children)
         -- can return a value smaller than the full visual widget, which would make the
         -- scenarioFrame too short and let Blizzard's content overlap the quest area below.
         if rawHeight > blizzardHeight then
             blizzardHeight = rawHeight
         end
         if blizzardHeight < 1 and maxVisibleChildHeight > 0 then
             blizzardHeight = maxVisibleChildHeight
         end
         if blizzardHeight > 8 and (contents:IsShown() or hostFrame:IsShown()) then
             hasScenarioContent = true
         end

         addon:LogAt("trace", "[SCENARIO] hasContent=%s, hTop=%s, cTop=%s, minB=%s, childH=%s, m3WH=%s", tostring(hasScenarioContent), tostring(hostTop), tostring(contentsTop), tostring(minBottom), tostring(maxChildTop), tostring(blizzardHeight))

         -- Fail-safe: Blizzard can report transient zero sizes during scenario transitions.
         -- If we are in a scenario and have a hijacked host frame, keep the section alive.
         if not hasScenarioContent and isScenarioActive and (hostFrame:IsShown() or contents:IsShown()) then
             addon:LogAt("trace", "[SCENARIO] FAIL-SAFE ACTIVATED")
             hasScenarioContent = true
             blizzardHeight = max(blizzardHeight, self._lastScenarioBlizzardHeight or 90)
         end

         if hasScenarioContent then
             -- If height is suspiciously small while content exists, enforce a modest floor.
             if blizzardHeight < 30 then
                 blizzardHeight = max(self._lastScenarioBlizzardHeight or 60, 60)
             end

             self._lastScenarioBlizzardHeight = blizzardHeight

             -- When Blizzard scenario is collapsed, we typically only have header-level content.
             -- Reduce reserved bottom padding so Active Quest snaps closer to Delves header.
             local effectiveBottomPadding = scenarioBottomPadding
             if blizzardHeight <= 36 then
                 effectiveBottomPadding = 8
             end

             scenarioHeight = blizzardHeight + effectiveBottomPadding + 10 -- Extra padding for safety
             scenarioYOffset = scenarioHeight
         else
             hostFrame._tpLockAnchors = false
             RestoreHijackedParent(self, hostFrame, self.scenarioFrame, ObjectiveTrackerFrame or UIParent, "_scenarioOriginalParent")
             if hasManualScenarioData then
                 -- Blizzard scenario frame exists but did not render visible rows; use manual fallback.
                 forceManualScenario = true
             end
                ResetAnchorState(self, "_scenarioContentsAnchored", "_scenarioContentsWidth")
             self._lastScenarioBlizzardHeight = nil
         end

    else
        if scenarioTracker and scenarioTracker.ContentsFrame then
            local hostFrame = scenarioTracker
            RestoreHijackedParent(self, hostFrame, self.scenarioFrame, ObjectiveTrackerFrame or UIParent, "_scenarioOriginalParent")
        end
           ResetAnchorState(self, "_scenarioContentsAnchored", "_scenarioContentsWidth")
           self._lastScenarioBlizzardHeight = nil
        if self.scenarioFrame and self.scenarioFrame.bgMask then
             self.scenarioFrame.bgMask:Hide()
        end
    end

    ---------------------------------------------------------------------------
    -- Manual scenario fallback
    ---------------------------------------------------------------------------
    if ((not useBlizzardScenario) or forceManualScenario) and hasManualScenarioData then
        -- Manual rendering fallback
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

    return scenarioYOffset
end
