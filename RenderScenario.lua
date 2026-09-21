local addonName, addon = ...

-- Localize hot-path globals
-- (LSM, bit_band, floor, match, and the DebugLayout alias were only used by the manual
-- scenario-mirror render branch removed above; dropped along with it.)
local ipairs, pcall, tostring = ipairs, pcall, tostring
local format = string.format
local max = math.max
local hooksecurefunc = hooksecurefunc

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

    -- SetAllPoints is a distinct Frame API from SetPoint/ClearAllPoints and was
    -- previously unguarded, so Blizzard layout code using it could drift the anchor
    -- undetected until the next periodic render.
    if borrowedFrame.SetAllPoints then
        hooksecurefunc(borrowedFrame, "SetAllPoints", function(frame)
            normalizeFromGuard(frame)
        end)
    end
end

local function InstallScenarioSizeObservers(owner, trackerFrame, contentsFrame)
    if not owner then
        return
    end

    local function install(frame)
        if not frame or frame._trackerPlusScenarioSizeObserverInstalled then
            return
        end

        frame._trackerPlusScenarioSizeObserverInstalled = true

        local function notifyIfChanged(observedFrame)
            if not observedFrame then
                return
            end

            local activeTracker = owner._activeScenarioBorrowedTracker
            if not activeTracker or (observedFrame ~= activeTracker and observedFrame:GetParent() ~= activeTracker) then
                return
            end

            local height = observedFrame.GetHeight and (observedFrame:GetHeight() or 0) or 0
            local shown = observedFrame.IsShown and observedFrame:IsShown() or false
            if observedFrame._trackerPlusObservedHeight == height and observedFrame._trackerPlusObservedShown == shown then
                return
            end

            observedFrame._trackerPlusObservedHeight = height
            observedFrame._trackerPlusObservedShown = shown

            owner._lastScenarioBorrowHeight = nil
            owner._layoutDirty = true
            owner._nextScenarioRefreshAt = 0
            owner:RequestUpdate("scenarios")
        end

        frame:HookScript("OnSizeChanged", function(observedFrame)
            notifyIfChanged(observedFrame)
        end)
        frame:HookScript("OnShow", function(observedFrame)
            notifyIfChanged(observedFrame)
        end)
        frame:HookScript("OnHide", function(observedFrame)
            notifyIfChanged(observedFrame)
        end)
    end

    install(trackerFrame)
    install(contentsFrame)
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
-- RenderScenarioSection — borrows the Blizzard scenario/delve/dungeon tracker frame
-- Returns: scenarioYOffset (total height consumed by scenario section)
--
-- NOTE: a "manual mirror rendering" fallback used to live here for when Blizzard-frame
-- detection below fails to find a shown tracker. It was removed because it was
-- permanently dead code: its only trigger, hasManualScenarioData, requires a scenario
-- trackable without isDummy=true, and Core.lua's CollectScenarioObjectives unconditionally
-- sets isDummy=true on the single item it ever produces. If Blizzard-frame detection is
-- ever observed to genuinely miss an active scenario in practice, a real fallback would
-- need CollectScenarioObjectives to emit real (non-dummy) data from
-- C_Scenario.GetStepInfo/criteria APIs, and a render branch rebuilt to consume it.
-------------------------------------------------------------------------------
function addon:RenderScenarioSection()
    local scenarioTracker = nil
    local scenarioTrackerName = nil

    -- C_Scenario.IsInScenario isn't present on every client this .toc targets, and
    -- gating solely on it meant the whole section silently never rendered there.
    -- addon:IsAnyScenarioTrackerActive() already falls back to inspecting the live
    -- tracker frames, which is the same evidence the borrow below relies on.
    local scenarioAPI = _G and _G.C_Scenario
    local inScenario = (scenarioAPI and scenarioAPI.IsInScenario and scenarioAPI.IsInScenario()) or false
    if not inScenario then
        inScenario = self:IsAnyScenarioTrackerActive()
    end

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
    
    if addon.LogAt then
        addon:LogAt("trace", "[SCN-BORROW] selected=%s inScenario=%s scenarioCount=%d",
            tostring(scenarioTrackerName), tostring(inScenario), tonumber((self.currentScenarios and #self.currentScenarios) or 0))
    end

    local scenarioYOffset = 0

    ---------------------------------------------------------------------------
    -- Scenario frame borrowing (borrow full tracker frame for stable lifetime)
    ---------------------------------------------------------------------------
    if scenarioTracker and scenarioTracker.ContentsFrame and inScenario then
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
            if trackerChanged and self._activeScenarioBorrowedTracker then
                -- addon:RestoreAllHijackedFrames (Core.lua) is the real restore
                -- implementation; it walks the same candidate tracker names and
                -- restores anything carrying the _trackerPlusOriginal* fields set
                -- below, which match its expectations exactly.
                self._activeScenarioBorrowedTracker._trackerPlusAnchorLockEnabled = nil
                self:RestoreAllHijackedFrames()
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
            InstallScenarioSizeObservers(self, borrowedFrame, contents)

            -- Keep anchor stable without forcing a full re-anchor every frame.
            EnsureScenarioBorrowAnchor(self, borrowedFrame)

            -- Assert visibility: Blizzard's own stage-complete/criteria fade
            -- animations can leave the borrowed frame's alpha at 0, which would
            -- otherwise make this section report a valid height while rendering
            -- nothing.
            --
            -- Only written when actually wrong. Every write to a Blizzard frame
            -- spreads TrackerPlus taint into it, which later surfaces as errors
            -- inside Blizzard's own tracker update (e.g. protected aura lookups in
            -- the scenario module), so don't re-assert this on every render tick.
            local function EnsureVisible(frame)
                if not frame then return end
                pcall(function()
                    if frame.GetAlpha and frame:GetAlpha() ~= 1 then
                        frame:SetAlpha(1)
                    end
                end)
                pcall(function()
                    if frame.SetIgnoreParentAlpha
                        and not (frame.IsIgnoringParentAlpha and frame:IsIgnoringParentAlpha()) then
                        frame:SetIgnoreParentAlpha(true)
                    end
                end)
            end

            EnsureVisible(borrowedFrame)
            EnsureVisible(contents)

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
    end

    if (not scenarioTracker or not inScenario) and self._activeScenarioBorrowedTracker then
        self._activeScenarioBorrowedTracker._trackerPlusAnchorLockEnabled = nil
        self:RestoreAllHijackedFrames()
        self._activeScenarioBorrowedTracker = nil
    end

    if not scenarioTracker and addon.LogAt then
        addon:LogAt("trace", "[SCN-BORROW] no-active-tracker")
    end

    -- Re-assert suppression of the default tracker, except while the game's Edit
    -- Mode is open: the player needs it visible and draggable there, and this runs
    -- every render tick so it would otherwise fight Edit Mode continuously.
    if (not scenarioTracker or not inScenario) and ObjectiveTrackerFrame and addon.db and addon.db.enabled
        and not addon._editModeActive and not InCombatLockdown() then
        ObjectiveTrackerFrame:SetAlpha(0)
        ObjectiveTrackerFrame:EnableMouse(false)
    end

    return scenarioYOffset
end
