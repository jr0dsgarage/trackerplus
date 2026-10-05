---@diagnostic disable: undefined-global
local _, addon = ...

-- Localize hot-path globals to avoid repeated global lookups
local pairs, ipairs, next, tostring = pairs, ipairs, next, tostring
local wipe = wipe
local format = string.format
local max, min = math.max, math.min
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local C_Scenario = C_Scenario
local C_Timer = C_Timer
-- NOTE: GetQuestDifficultyColor is deliberately *not* localized; see
-- GetDifficultyColorForLevel in QuestColors.lua.

-- Core addon initialization and event handling
local frame = CreateFrame("Frame")

local updateTimer = 0
local requestedUpdate = false
local pendingUpdate = false
local lastRenderedDataVersion = -1
local lastLayoutSignature = ""

-- Dirty section tracking + cached buckets (high-impact perf)
local dirtySections = { full = true }
local sectionCache = {
    quests = {},
    achievements = {},
    scenarios = {},
    autoQuests = {},
    superTracked = {},
    professions = {},
    monthly = {},
    endeavors = {},
}

local function MarkDirty(section)
    if not section or section == "full" then
        dirtySections.full = true
    else
        dirtySections[section] = true
    end
end

local function ClearDirty()
    for k in pairs(dirtySections) do
        dirtySections[k] = nil
    end
end

local function RefreshBucket(name, collector, owner)
    local bucket = sectionCache[name]
    wipe(bucket)
    collector(owner, bucket)
end

local function AppendBucket(dest, source)
    for i = 1, #source do
        dest[#dest + 1] = source[i]
    end
end

function addon:IsAnyScenarioTrackerActive()
    if C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario() then
        return true
    end
    -- In War Within/Dragonflight, delves and some other scenarios might not return true above.
    -- Check if the actual UI modules are active.
    local trackers = { "DelvesObjectiveTracker", "DelveObjectiveTracker", "ScenarioObjectiveTracker" }
    for _, name in ipairs(trackers) do
        local t = _G[name]
        -- If it exists, is shown, and has an active UI inside it
        if t and t:IsShown() and t.ContentsFrame then
            local hasContent = false
            -- Check if any children are actually visible (GetNumChildren > 0 alone is unreliable)
            for _, child in pairs({t.ContentsFrame:GetChildren()}) do
                if child:IsShown() and child:GetHeight() > 5 then
                    hasContent = true
                    break
                end
            end
            local hasHeight = max(t:GetHeight() or 0, t.ContentsFrame:GetHeight() or 0) > 10
            if hasContent or hasHeight then
                return true
            end
        end
    end
    return false
end

-- Print helper
local function Print(...)
    print("|cff00ff00TrackerPlus:|r", ...)
end

addon.Print = Print
addon.disableObjectiveTrackerHooks = false

function addon:GetSharedTooltip()
    return GameTooltip
end

function addon:AcquireTooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    return GameTooltip
end

function addon:HideSharedTooltip()
    GameTooltip:Hide()
end

-- Initialize addon
function addon:Initialize()
    -- Initialize database
    self:InitDatabase()
    
    -- Create tracker frame
    self:CreateTrackerFrame()
    
    -- Register events
    self:RegisterEvents()
    
    -- Register slash commands
    self:RegisterSlashCommands()

    -- Difficulty-colored outlines on the game's own world map quest pins
    self:InitMapPOIColors()

    -- Glow on the clicked quest in the map's quest list
    self:InitQuestLogFocus()

    -- Stripe beside quests whose shaded map area the player is standing in
    self:UpdateQuestAreaWatcher()

    -- Collapse quest zone headers we are not in (header "A" toggle)
    self:UpdateAutoMinimizeWatcher()

    -- Initial update
    self:RequestUpdate()
    self._layoutDirty = true
    
    -- Manage default Blizzard tracker
    if ObjectiveTrackerFrame then
        -- Hook Show to control visibility based on our enabled state
        if not addon.hookedTracker and not addon.disableObjectiveTrackerHooks then
            hooksecurefunc(ObjectiveTrackerFrame, "Show", function(self)
                -- While Edit Mode is open the player needs to see and drag the
                -- real tracker, so suppression is suspended (see OnEditModeEnter).
                if addon.db.enabled and not addon._editModeActive then
                    self:EnableMouse(false)
                    if not InCombatLockdown() then
                        self:SetAlpha(0)
                    end
                end
            end)
            addon.hookedTracker = true
        end

        -- If any code path flips ObjectiveTracker mouse back on while TrackerPlus is enabled,
        -- immediately turn it back off to prevent click-through behavior.
        if not addon.hookedTrackerMouse and not addon.disableObjectiveTrackerHooks then
            hooksecurefunc(ObjectiveTrackerFrame, "EnableMouse", function(self, enabled)
                if addon.db.enabled and enabled and not addon._editModeActive then
                    self:EnableMouse(false)
                end
            end)
            addon.hookedTrackerMouse = true
        end

        -- Initial visibility check
        self:UpdateDefaultTrackerVisibility()
    end

    -- Edit Mode enter/exit (clients without Edit Mode simply have no EventRegistry
    -- callbacks for it, so this is a no-op there).
    if not addon.hookedEditMode and EventRegistry and EventRegistry.RegisterCallback then
        pcall(function()
            EventRegistry:RegisterCallback("EditMode.Enter", function()
                addon:OnEditModeEnter()
            end, addon)
            EventRegistry:RegisterCallback("EditMode.Exit", function()
                addon:OnEditModeExit()
            end, addon)
        end)
        addon.hookedEditMode = true
    end

    Print("Loaded! Type /trackerplus or /tp for options.")
end

function addon:RestoreAllHijackedFrames()
    -- Restore borrowed frames to their original parents.
    --
    -- Only frames carrying our _trackerPlusOriginalParent marker are touched, and
    -- RenderScenario only ever marks the top-level tracker. Every write to (and
    -- even broad traversal of) a Blizzard frame spreads TrackerPlus taint into it,
    -- which later surfaces as errors inside Blizzard's own tracker update, so this
    -- deliberately checks a few known fields instead of walking GetChildren().
    local function RestoreFrame(frameToRestore)
        if not (frameToRestore and frameToRestore._trackerPlusOriginalParent) then
            return
        end

        frameToRestore:SetParent(frameToRestore._trackerPlusOriginalParent)
        frameToRestore:ClearAllPoints()
        if frameToRestore._trackerPlusOriginalPoint1 then
            frameToRestore:SetPoint(
                frameToRestore._trackerPlusOriginalPoint1,
                frameToRestore._trackerPlusOriginalRelTo,
                frameToRestore._trackerPlusOriginalPoint2,
                frameToRestore._trackerPlusOriginalX or 0,
                frameToRestore._trackerPlusOriginalY or 0
            )
        end
        frameToRestore._trackerPlusOriginalParent = nil
        frameToRestore._trackerPlusOriginalPoint1 = nil
        frameToRestore._trackerPlusOriginalRelTo = nil
        frameToRestore._trackerPlusOriginalPoint2 = nil
        frameToRestore._trackerPlusOriginalX = nil
        frameToRestore._trackerPlusOriginalY = nil
    end

    if not InCombatLockdown() then
        local candidates = {
            "DelvesObjectiveTracker",
            "DelveObjectiveTracker",
            "ScenarioObjectiveTracker",
        }
        for _, name in ipairs(candidates) do
            local tracker = _G and _G[name]
            if tracker then
                pcall(function()
                    RestoreFrame(tracker)
                    local contents = tracker.ContentsFrame
                    if contents then
                        RestoreFrame(contents)
                        RestoreFrame(contents.WidgetContainer)
                    end
                end)
            end
        end
    end

    -- Clear cached metadata
    if addon.scenarioFrame then
        addon.scenarioFrame.borrowedFrame = nil
    end
    addon.scenarioHostOriginalParent = nil
end

-- Edit Mode integration
--
-- The game's Edit Mode is how the player positions and sizes its own tracker, and
-- TrackerPlus mirrors that geometry while "Match Game Tracker" is on. That only
-- works if the real tracker is visible and draggable while Edit Mode is open, so
-- suppression is suspended for the duration and re-applied on exit.
function addon:OnEditModeEnter()
    self._editModeActive = true

    -- Let the player see/grab the real tracker again.
    if ObjectiveTrackerFrame and not InCombatLockdown() then
        pcall(function()
            ObjectiveTrackerFrame:SetAlpha(1)
            ObjectiveTrackerFrame:EnableMouse(true)
            ObjectiveTrackerFrame:Show()
        end)
    end

    -- Our own frame sits exactly on top of it while matching, which would cover it
    -- and swallow the drag, so stand aside until Edit Mode closes.
    if self.db.matchBlizzardTracker then
        self._hideForEditMode = true
        self:SetTrackerVisible(false)
    end
end

function addon:OnEditModeExit()
    self._editModeActive = nil
    self._hideForEditMode = nil

    -- Re-hide the default tracker, then adopt whatever geometry was just set.
    self:UpdateDefaultTrackerVisibility()

    if self.SyncWithBlizzardTracker then
        self:SyncWithBlizzardTracker()
    end

    self:RequestUpdate("full")
end

-- Update default tracker visibility based on enabled state
function addon:UpdateDefaultTrackerVisibility()
    if not ObjectiveTrackerFrame then return end

    -- Edit Mode owns the tracker's visibility while it is open.
    if self._editModeActive then return end

    if addon.LogAt then addon:LogAt("trace", "UpdateDefaultTrackerVisibility called. enabled=%s", tostring(self.db.enabled)) end

    if self.db.enabled then
        ObjectiveTrackerFrame:EnableMouse(false)
        if not InCombatLockdown() then
            ObjectiveTrackerFrame:SetAlpha(0)
            if addon.LogAt then addon:LogAt("trace", "ObjectiveTrackerFrame hidden") end
        end
    else
        -- Restore default Blizzard tracker visibility
        if ObjectiveTrackerFrame.Show and not InCombatLockdown() then
            ObjectiveTrackerFrame:SetAlpha(1)
            ObjectiveTrackerFrame:EnableMouse(true)
            ObjectiveTrackerFrame:Show()
            if addon.LogAt then addon:LogAt("trace", "ObjectiveTrackerFrame restored") end
        end
    end
end

-- Event registration
function addon:RegisterEvents()
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    
    -- Quest events
    frame:RegisterEvent("QUEST_ACCEPTED")
    frame:RegisterEvent("QUEST_REMOVED")
    frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    frame:RegisterEvent("SUPER_TRACKING_CHANGED")
    frame:RegisterEvent("QUEST_AUTOCOMPLETE")
    
    -- World quest events
    frame:RegisterEvent("QUEST_WATCH_UPDATE")
    frame:RegisterEvent("WORLD_QUEST_COMPLETED_BY_SPELL")
    
    -- Bonus objective / Task quest events
    pcall(function() frame:RegisterEvent("QUEST_POI_UPDATE") end)
    pcall(function() frame:RegisterEvent("TASK_PROGRESS_UPDATE") end)
    pcall(function() frame:RegisterEvent("QUEST_PROGRESS_UPDATE") end)
    pcall(function() frame:RegisterEvent("QUEST_LOG_CRITERIA_UPDATE") end)
    
    -- Achievement events
    frame:RegisterEvent("TRACKED_ACHIEVEMENT_LIST_CHANGED")
    frame:RegisterEvent("ACHIEVEMENT_EARNED")
    frame:RegisterEvent("CRITERIA_UPDATE")
    
    -- Scenario/Dungeon events
    frame:RegisterEvent("SCENARIO_UPDATE")
    frame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
    frame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    
    -- Zone change events
    frame:RegisterEvent("ZONE_CHANGED")
    frame:RegisterEvent("ZONE_CHANGED_INDOORS")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    
    -- Combat events
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    
    -- Profession events
    frame:RegisterEvent("SKILL_LINES_CHANGED")
    frame:RegisterEvent("TRADE_SKILL_SHOW")
    frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    frame:RegisterEvent("TRACKED_RECIPE_UPDATE")
    pcall(function() frame:RegisterEvent("ITEM_COUNT_CHANGED") end)
    pcall(function() frame:RegisterEvent("BAG_UPDATE_DELAYED") end)
    pcall(function() frame:RegisterEvent("CURRENCY_DISPLAY_UPDATE") end)
    pcall(function() frame:RegisterEvent("BANKFRAME_OPENED") end)
    pcall(function() frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED") end)
    pcall(function() frame:RegisterEvent("BANK_TABS_CHANGED") end)
    pcall(function() frame:RegisterEvent("BANK_TAB_SETTINGS_UPDATED") end)

    -- Monthly Activities (Trading Post)
    if C_PerksProgram then
        -- Safe registration for valid events only
        pcall(function() frame:RegisterEvent("PERKS_PROGRAM_DATA_REFRESH") end)
    end
    
    -- Endeavors (Housing)
    if C_NeighborhoodInitiative then
        -- Register accurate events for Endeavors
        pcall(function() frame:RegisterEvent("INITIATIVE_TASKS_TRACKED_UPDATED") end)
        pcall(function() frame:RegisterEvent("INITIATIVE_TASKS_TRACKED_LIST_CHANGED") end)
        -- Keep these just in case older/internal names are used
        pcall(function() frame:RegisterEvent("NEIGHBORHOOD_INITIATIVE_TASKS_UPDATE") end)
        pcall(function() frame:RegisterEvent("NEIGHBORHOOD_INITIATIVE_TRACKING_UPDATE") end)
        pcall(function() frame:RegisterEvent("NEIGHBORHOOD_INITIATIVE_UPDATE") end)
    end
    
    -- General Content Tracking (Modern API)
    pcall(function() frame:RegisterEvent("CONTENT_TRACKING_UPDATE") end)
    pcall(function() frame:RegisterEvent("TRACKABLE_INFO_UPDATE") end)

    -- Edit Mode: the game's tracker can be moved/resized there, and we mirror it
    -- until the player positions TrackerPlus themselves. Safe registration; the
    -- event does not exist on clients without Edit Mode.
    pcall(function() frame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED") end)

    -- FollowTheArrow addon events (safe registration; events may not exist)
    pcall(function() frame:RegisterEvent("FTA_GUIDE_CHANGED") end)
    pcall(function() frame:RegisterEvent("FTA_STEP_CHANGED") end)
    pcall(function() frame:RegisterEvent("FTA_PROGRESS_UPDATED") end)

    frame:SetScript("OnEvent", function(_, event, ...)
        addon:OnEvent(event, ...)
    end)
    
    frame:SetScript("OnUpdate", function(_, elapsed)
        addon:OnUpdate(elapsed)
    end)
end

-- Event handler
function addon:OnEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if self.RestorePosition then self.RestorePosition() end
        self:UpdateDefaultTrackerVisibility()
        self:RequestUpdate("full")

        -- The game's tracker may not have its final Edit Mode geometry yet at this
        -- point, so take one more reading shortly after login/zone-in.
        if self.SyncWithBlizzardTracker and C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                addon:SyncWithBlizzardTracker()
            end)
        end
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        -- The player moved/resized the game's tracker in Edit Mode; follow it
        -- unless they've already positioned TrackerPlus themselves.
        if self.SyncWithBlizzardTracker then
            self:SyncWithBlizzardTracker()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat
        if self.db.hideInCombat then
            self:SetTrackerVisible(false)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat
        if self.db.hideInCombat then
            self:SetTrackerVisible(true)
        end

        -- Re-assert suppression now that combat restrictions are lifted.
        self:UpdateDefaultTrackerVisibility()
        
        -- Process pending updates
        if pendingUpdate then
            pendingUpdate = false
            self:RequestUpdate()
        end
    else
        -- Route events to minimal dirty sections
        if event == "QUEST_ACCEPTED"
            or event == "QUEST_REMOVED"
            or event == "QUEST_WATCH_LIST_CHANGED"
            or event == "QUEST_LOG_UPDATE"
            or event == "QUEST_TURNED_IN"
            or event == "UNIT_QUEST_LOG_CHANGED"
            or event == "SUPER_TRACKING_CHANGED"
            or event == "QUEST_AUTOCOMPLETE"
            or event == "QUEST_WATCH_UPDATE"
            or event == "WORLD_QUEST_COMPLETED_BY_SPELL"
            or event == "QUEST_POI_UPDATE"
            or event == "TASK_PROGRESS_UPDATE"
            or event == "QUEST_PROGRESS_UPDATE"
            or event == "QUEST_LOG_CRITERIA_UPDATE"
            or event == "ZONE_CHANGED"
            or event == "ZONE_CHANGED_INDOORS"
            or event == "ZONE_CHANGED_NEW_AREA" then
            self:RequestUpdate("quests")
            self:RequestUpdate("autoQuests")
            self:RequestUpdate("superTracked")
            self:RequestUpdate("scenarios")
        elseif event == "TRACKED_ACHIEVEMENT_LIST_CHANGED"
            or event == "ACHIEVEMENT_EARNED"
            or event == "CRITERIA_UPDATE" then
            self:RequestUpdate("achievements")
        elseif event == "SCENARIO_UPDATE"
            or event == "SCENARIO_CRITERIA_UPDATE"
            or event == "PLAYER_DIFFICULTY_CHANGED" then
            self:RequestUpdate("scenarios")
        elseif event == "SKILL_LINES_CHANGED"
            or event == "TRADE_SKILL_SHOW"
            or event == "TRADE_SKILL_LIST_UPDATE"
            or event == "TRACKED_RECIPE_UPDATE"
            or event == "GET_ITEM_INFO_RECEIVED"
            or event == "ITEM_COUNT_CHANGED"
            or event == "BAG_UPDATE_DELAYED"
            or event == "CURRENCY_DISPLAY_UPDATE"
            or event == "BANKFRAME_OPENED"
            or event == "PLAYERBANKSLOTS_CHANGED"
            or event == "BANK_TABS_CHANGED"
            or event == "BANK_TAB_SETTINGS_UPDATED" then
            self:RequestUpdate("professions")
        elseif event == "PERKS_PROGRAM_DATA_REFRESH" then
            self:RequestUpdate("monthly")
        elseif event == "INITIATIVE_TASKS_TRACKED_UPDATED"
            or event == "INITIATIVE_TASKS_TRACKED_LIST_CHANGED"
            or event == "NEIGHBORHOOD_INITIATIVE_TASKS_UPDATE"
            or event == "NEIGHBORHOOD_INITIATIVE_TRACKING_UPDATE"
            or event == "NEIGHBORHOOD_INITIATIVE_UPDATE" then
            self:RequestUpdate("endeavors")
            elseif event == "FTA_GUIDE_CHANGED"
            or event == "FTA_STEP_CHANGED"
            or event == "FTA_PROGRESS_UPDATED" then
            self:RequestUpdate("fta")
        elseif event == "CONTENT_TRACKING_UPDATE" or event == "TRACKABLE_INFO_UPDATE" then
            -- Broad content tracking changes can affect multiple sections.
            self:RequestUpdate("full")
        else
            self:RequestUpdate("full")
        end
    end
end

-- Update timer with debounce
function addon:OnUpdate(elapsed)
    if not requestedUpdate then
        return
    end
    
    updateTimer = updateTimer + elapsed
    local db = self.db
    local updateInterval = db.updateInterval or 0.1
    local now = GetTime()

    -- Adaptive cadence: fast during active objective churn, slower when idle/minimized/hidden
    if db.minimized then
        updateInterval = max(updateInterval, 0.25)
    elseif self._updateBurstUntil and now < self._updateBurstUntil then
        updateInterval = min(updateInterval, 0.05)
    else
        updateInterval = max(updateInterval, 0.15)
    end

    if self.trackerFrame and not self.trackerFrame:IsShown() then
        updateInterval = max(updateInterval, 0.25)
    end
    
    if updateTimer >= updateInterval then
        updateTimer = 0
        requestedUpdate = false
        self:UpdateTracker()
    end
end

-- Request a tracker update (debounced)
function addon:RequestUpdate(section)
    if section then
        MarkDirty(section)
    elseif next(dirtySections) == nil then
        MarkDirty("full")
    end
    requestedUpdate = true

    if section == "quests"
        or section == "autoQuests"
        or section == "superTracked"
        or section == "scenarios"
        or section == "achievements" then
        self._updateBurstUntil = GetTime() + 1.0
    end
end

-- Main update function
function addon:UpdateTracker()
    -- In combat, run a minimal layout-only refresh to avoid protected UI mutations.
    if InCombatLockdown() then
        pendingUpdate = true
        self:UpdateCombatFrameVisibility()
        return
    end

    if not self.trackerFrame then
        return
    end

    local db = self.db

    -- Check if we should hide
    local inInstance = IsInInstance()
    if db.hideInInstance and inInstance then
        self:SetTrackerVisible(false)
        return
    end
    
    -- Track layout changes independently from data changes
    local layoutSignature = format("%d|%d|%s|%s|%s", 
        db.frameWidth or 0,
        db.frameHeight or 0,
        tostring(db.groupByZone),
        tostring(db.groupByCategory),
        tostring(db.frameScale or 1)
    )
    if layoutSignature ~= lastLayoutSignature then
        lastLayoutSignature = layoutSignature
        self._layoutDirty = true
    end

    -- Collect all trackables (dirty-section aware)
    local trackables = self:CollectTrackables()

    -- Paint when data/layout changed, and always refresh while in scenarios.
    -- Scenario/Delve visuals are hijacked from Blizzard frames and may change without
    -- mutating our collected dataVersion, so skipping paint can leave stale/empty UI.
    local forceDisplayRefresh = false
    if addon:IsAnyScenarioTrackerActive() then
        local now = GetTime()
        if self._nextScenarioRefreshAt == nil or now >= self._nextScenarioRefreshAt then
            forceDisplayRefresh = true
            self._nextScenarioRefreshAt = now + 0.2
        end
    else
        self._nextScenarioRefreshAt = nil
    end

    -- Paint only when data/layout changed (or forced refresh)
    local dataVersion = self._dataVersion or 0
    if forceDisplayRefresh or self._layoutDirty or dataVersion ~= lastRenderedDataVersion then
        local ok, err = xpcall(function()
            self:UpdateTrackerDisplay(trackables)
        end, function(message)
            if debugstack then
                return string.format("%s\n%s", tostring(message), tostring(debugstack()))
            end
            return tostring(message)
        end)

        if ok then
            lastRenderedDataVersion = dataVersion
            self._layoutDirty = false
        else
            if self.LogAt then
                self:LogAt("error", "Render error: %s", tostring(err))
            elseif self.Log then
                self:Log("Render error: %s", tostring(err))
            end

            local now = GetTime()
            if not self._lastRenderErrorPrintAt or (now - self._lastRenderErrorPrintAt) > 5 then
                self._lastRenderErrorPrintAt = now
                Print("Render error captured. Use /tpdebug to inspect details.")
            end
        end
    end
    
    -- Handle fade when empty
    -- If unlocked, always show so user can move it
    if not db.locked then
        self:SetTrackerVisible(true)
        -- Add a visual indicator that it's empty but unlocked
        if #trackables == 0 and self.trackerFrame and self.trackerFrame.title then
             self.trackerFrame.title:SetText("Tracker Plus (Empty - Drag to Move)")
        end
    elseif db.fadeWhenEmpty and #trackables == 0 then
        self:SetTrackerVisible(false)
    else
        if self.trackerFrame and self.trackerFrame.title then
             self.trackerFrame.title:SetText("Tracker Plus")
        end
        self:SetTrackerVisible(db.enabled)
    end
end

-- Combat-safe refresh: update top-level frame visibility/size and layout only.
function addon:UpdateCombatFrameVisibility()
    if not self.trackerFrame then return end

    local scenarioYOffset = 0
    if self.RenderScenarioSection then
        local ok, result = pcall(function()
            return self:RenderScenarioSection()
        end)
        if ok then
            scenarioYOffset = tonumber(result) or 0
        end
    end

    if self.scenarioFrame then
        if scenarioYOffset > 0 then
            self.scenarioFrame:SetHeight(scenarioYOffset)
            if self.db and self.db.minimized then
                self.scenarioFrame:Hide()
            else
                self.scenarioFrame:Show()
            end
        else
            self.scenarioFrame:SetHeight(1)
            self.scenarioFrame:Hide()
        end
    end

    self:UpdateLayoutAnchors()
    self:UpdateScrollShadows()
end

-- Collect all trackables (quests, achievements, etc.)
function addon:CollectTrackables()
    local full = dirtySections.full
    local trackables = {}
    local db = self.db
    local refreshedAny = false

    if full or dirtySections.quests then
        refreshedAny = true
        if db.showQuests or db.showWorldQuests then
            RefreshBucket("quests", addon.CollectQuests, self)
        else
            wipe(sectionCache.quests)
        end
    end

    if full or dirtySections.achievements then
        refreshedAny = true
        if db.showAchievements then
            RefreshBucket("achievements", addon.CollectAchievements, self)
        else
            wipe(sectionCache.achievements)
        end
    end

    if full or dirtySections.scenarios then
        refreshedAny = true
        if db.showScenarios or db.showDungeonObjectives then
            RefreshBucket("scenarios", addon.CollectScenarioObjectives, self)
        else
            wipe(sectionCache.scenarios)
        end
    end

    if full or dirtySections.autoQuests then
        refreshedAny = true
        RefreshBucket("autoQuests", addon.CollectAutoQuests, self)
    end

    if full or dirtySections.superTracked then
        refreshedAny = true
        RefreshBucket("superTracked", addon.CollectSuperTrackedQuest, self)
    end

    if full or dirtySections.professions then
        refreshedAny = true
        if db.showProfessions then
            RefreshBucket("professions", addon.CollectProfessionTracking, self)
        else
            wipe(sectionCache.professions)
        end
    end

    if full or dirtySections.monthly then
        refreshedAny = true
        if db.showMonthlyActivities then
            RefreshBucket("monthly", addon.CollectMonthlyActivities, self)
        else
            wipe(sectionCache.monthly)
        end
    end

    if full or dirtySections.endeavors then
        refreshedAny = true
        if db.showEndeavors then
            RefreshBucket("endeavors", addon.CollectEndeavors, self)
        else
            wipe(sectionCache.endeavors)
        end
    end

    AppendBucket(trackables, sectionCache.quests)
    AppendBucket(trackables, sectionCache.achievements)
    AppendBucket(trackables, sectionCache.scenarios)
    AppendBucket(trackables, sectionCache.autoQuests)
    AppendBucket(trackables, sectionCache.superTracked)
    AppendBucket(trackables, sectionCache.professions)
    AppendBucket(trackables, sectionCache.monthly)
    AppendBucket(trackables, sectionCache.endeavors)
    
    -- Sort trackables
    self:SortTrackables(trackables)

    if refreshedAny then
        self._dataVersion = (self._dataVersion or 0) + 1
    end

    -- Done applying this dirty batch
    ClearDirty()
    
    return trackables
end

-- Set tracker visibility
function addon:SetTrackerVisible(visible)
    if self.trackerFrame then
        -- While Edit Mode is open and we're mirroring the game's tracker, stay
        -- hidden regardless of what the regular update loop asks for.
        if visible and not self._hideForEditMode then
            self.trackerFrame:Show()
        else
            self.trackerFrame:Hide()
        end
    end
end

-- Slash commands
function addon:RegisterSlashCommands()
    SLASH_TRACKERPLUS1 = "/trackerplus"
    SLASH_TRACKERPLUS2 = "/tp"
    
    SlashCmdList["TRACKERPLUS"] = function(msg)
        msg = msg:lower():trim()
        
        if msg == "" or msg == "config" or msg == "settings" or msg == "options" then
            if addon.OpenSettings then
                addon.OpenSettings()
            else
                -- Fallback if Settings.lua hasn't loaded properly
                Print("Settings panel not loaded yet.")
            end
        elseif msg == "toggle" then
            local enabled = not addon.db.enabled
            addon:SetSetting("enabled", enabled)
            addon:SetTrackerVisible(enabled)
            addon:UpdateDefaultTrackerVisibility()
            Print(enabled and "Enabled" or "Disabled")
        elseif msg == "lock" then
            addon:SetSetting("locked", true)
            addon:UpdateTrackerLock()
            Print("Tracker locked")
        elseif msg == "unlock" then
            addon:SetSetting("locked", false)
            addon:UpdateTrackerLock()
            Print("Tracker unlocked")
        elseif msg == "reset" then
            addon:ResetDatabase()
            addon:RequestUpdate()
            Print("Settings reset to defaults")
        elseif (msg == "nameplates" or msg:find("^nameplates ")) and addon.Nameplates then
            addon.Nameplates:HandleCommand(msg:sub(#"nameplates" + 2))
        else
            Print("Commands:")
            Print("  /tp - Open settings")
            Print("  /tp toggle - Toggle tracker on/off")
            Print("  /tp lock/unlock - Lock/unlock frame position")
            Print("  /tp reset - Reset all settings")
            Print("  /tp nameplates - Nameplate highlight options (/tp nameplates help)")
        end
    end
end

-- Bootstrap
-- RegisterEvents (run from Initialize) replaces this OnEvent script with addon:OnEvent.
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Initialize with a slight delay to ensure other things are ready
    C_Timer.After(1, function()
         addon:Initialize()
    end)
end)
