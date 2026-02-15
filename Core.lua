---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Core addon initialization and event handling
local frame = CreateFrame("Frame")

local updateTimer = 0
local requestedUpdate = false
local pendingUpdate = false

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

-- Print helper
local function Print(...)
    print("|cff00ff00TrackerPlus:|r", ...)
end

addon.Print = Print

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
    
    -- Initial update
    self:RequestUpdate()
    
    -- Manage default Blizzard tracker
    if ObjectiveTrackerFrame then
        -- Hook Show to control visibility based on our enabled state
        if not addon.hookedTracker then
            hooksecurefunc(ObjectiveTrackerFrame, "Show", function(self)
                if addon:GetSetting("enabled") then
                    -- Instead of Hide(), move it offscreen so we can still hijack its children (Bonus Frames)
                    -- If we Hide() it, its children (BonusObjectiveTracker) are also hidden and inactive.
                    self:ClearAllPoints()
                    self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 10000, 0)
                    self:SetAlpha(0) -- Visual hide
                    self:EnableMouse(false) -- No interaction
                end
            end)
            
            -- Prevent internal layout resets from moving it back
            hooksecurefunc(ObjectiveTrackerFrame, "SetPoint", function(self)
                 if addon:GetSetting("enabled") and not InCombatLockdown() then
                      -- If it tries to move back, force it away
                      local point, _, _, x, _ = self:GetPoint()
                      if x < 5000 then -- If it's on screen
                           self:ClearAllPoints()
                           self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 10000, 0)
                      end
                 end
            end)
            
            addon.hookedTracker = true
        end

        -- Initial visibility check
        self:UpdateDefaultTrackerVisibility()
    end
    
    Print("Loaded! Type /trackerplus or /tp for options.")
end

-- Update default tracker visibility based on enabled state
function addon:UpdateDefaultTrackerVisibility()
    if not ObjectiveTrackerFrame then return end
    
    if addon.Log then addon:Log("UpdateDefaultTrackerVisibility called. Enabled: %s", tostring(self:GetSetting("enabled"))) end
    
    if self:GetSetting("enabled") then
        -- Offscreen Mode
        ObjectiveTrackerFrame:ClearAllPoints()
        ObjectiveTrackerFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 10000, 0)
        ObjectiveTrackerFrame:SetAlpha(0)
        ObjectiveTrackerFrame:EnableMouse(false)
        if ObjectiveTrackerFrame.Show then ObjectiveTrackerFrame:Show() end
        if addon.Log then addon:Log("ObjectiveTrackerFrame Moved Offscreen (x=10000, Alpha=0)") end
    else
        -- Restore (This might need a ReloadUI to perfect, but we try)
        if ObjectiveTrackerFrame.Show then
            ObjectiveTrackerFrame:SetAlpha(1)
            ObjectiveTrackerFrame:EnableMouse(true)
            ObjectiveTrackerFrame:ClearAllPoints()
            -- Let Blizzard layout handle the rest or EditMode
            ObjectiveTrackerFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -180) 
            ObjectiveTrackerFrame:Show()
            if addon.Log then addon:Log("ObjectiveTrackerFrame Restored") end
        end
    end
end

-- Event registration
function addon:RegisterEvents()
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
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
        self:RequestUpdate("full")
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat
        if self:GetSetting("hideInCombat") then
            self:SetTrackerVisible(false)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat
        if self:GetSetting("hideInCombat") then
            self:SetTrackerVisible(true)
        end
        
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
            or event == "TRACKED_RECIPE_UPDATE" then
            self:RequestUpdate("professions")
        elseif event == "PERKS_PROGRAM_DATA_REFRESH" then
            self:RequestUpdate("monthly")
        elseif event == "INITIATIVE_TASKS_TRACKED_UPDATED"
            or event == "INITIATIVE_TASKS_TRACKED_LIST_CHANGED"
            or event == "NEIGHBORHOOD_INITIATIVE_TASKS_UPDATE"
            or event == "NEIGHBORHOOD_INITIATIVE_TRACKING_UPDATE"
            or event == "NEIGHBORHOOD_INITIATIVE_UPDATE" then
            self:RequestUpdate("endeavors")
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
    local updateInterval = self:GetSetting("updateInterval") or 0.1
    
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
end

-- Main update function
function addon:UpdateTracker()
    -- Defer updates if in combat to prevent taint issues with SecureFrames
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end

    if not self.trackerFrame then
        return
    end
    
    -- Check if we should hide
    local inInstance = IsInInstance()
    if self:GetSetting("hideInInstance") and inInstance then
        self:SetTrackerVisible(false)
        return
    end
    
    -- Collect all trackables (dirty-section aware)
    local trackables = self:CollectTrackables()
    
    -- Update the tracker frame with collected data
    self:UpdateTrackerDisplay(trackables)
    
    -- Handle fade when empty
    -- If unlocked, always show so user can move it
    if not self.db.locked then
        self:SetTrackerVisible(true)
        -- Add a visual indicator that it's empty but unlocked
        if #trackables == 0 and self.trackerFrame and self.trackerFrame.title then
             self.trackerFrame.title:SetText("Tracker Plus (Empty - Drag to Move)")
        end
    elseif self:GetSetting("fadeWhenEmpty") and #trackables == 0 then
        self:SetTrackerVisible(false)
    else
        if self.trackerFrame and self.trackerFrame.title then
             self.trackerFrame.title:SetText("Tracker Plus")
        end
        self:SetTrackerVisible(self:GetSetting("enabled"))
    end
end

-- Collect all trackables (quests, achievements, etc.)
function addon:CollectTrackables()
    local full = dirtySections.full
    local trackables = {}
    local db = self.db

    if full or dirtySections.quests then
        if db.showQuests then
            RefreshBucket("quests", addon.CollectQuests, self)
        else
            wipe(sectionCache.quests)
        end
    end

    if full or dirtySections.achievements then
        if db.showAchievements then
            RefreshBucket("achievements", addon.CollectAchievements, self)
        else
            wipe(sectionCache.achievements)
        end
    end

    if full or dirtySections.scenarios then
        if db.showScenarios or db.showDungeonObjectives then
            RefreshBucket("scenarios", addon.CollectScenarioObjectives, self)
        else
            wipe(sectionCache.scenarios)
        end
    end

    if full or dirtySections.autoQuests then
        RefreshBucket("autoQuests", addon.CollectAutoQuests, self)
    end

    if full or dirtySections.superTracked then
        RefreshBucket("superTracked", addon.CollectSuperTrackedQuest, self)
    end

    if full or dirtySections.professions then
        if db.showProfessions then
            RefreshBucket("professions", addon.CollectProfessionTracking, self)
        else
            wipe(sectionCache.professions)
        end
    end

    if full or dirtySections.monthly then
        if db.showMonthlyActivities then
            RefreshBucket("monthly", addon.CollectMonthlyActivities, self)
        else
            wipe(sectionCache.monthly)
        end
    end

    if full or dirtySections.endeavors then
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

    -- Done applying this dirty batch
    ClearDirty()
    
    return trackables
end

-- Helper to gather quest data
function addon:GetQuestData(logIndex, typeOverride, zoneOverride)
    local info = C_QuestLog.GetInfo(logIndex)
    if not info then return nil end
    
    local questID = info.questID
    
    local isWorldQuest = C_QuestLog.IsWorldQuest(questID)
    local isBonusObjective = C_QuestLog.IsQuestTask(questID) and not isWorldQuest
    local type = typeOverride
    if not type then
         if isBonusObjective then
             type = "bonus"
         elseif isWorldQuest then
             type = "worldquest"
         else
             type = "quest"
         end
    end

    local questInfo = {
        type = type,
        id = questID,
        logIndex = logIndex,
        title = info.title,
        level = info.level,
        questType = self:GetQuestTypeName(questID),
        isComplete = C_QuestLog.IsComplete(questID),
        isFailed = info.isFailed,
        isWorldQuest = C_QuestLog.IsWorldQuest(questID),
        zone = zoneOverride or GetRealZoneText() or "Unknown Zone",
        objectives = {},
        color = self:GetQuestColor(info),
    }

    -- Get Quest Item Info
    local itemLink, itemTexture = GetQuestLogSpecialItemInfo(logIndex)
    if itemLink then
        questInfo.item = {
            link = itemLink,
            texture = itemTexture,
        }
    end
    
    -- Get objectives
    local objectives = C_QuestLog.GetQuestObjectives(questID) or {}
    local hasObjectives = false

    -- Check for Task/Bonus Objective Progress Bar
    if C_TaskQuest and C_TaskQuest.GetQuestProgressBarInfo then
        local progress = C_TaskQuest.GetQuestProgressBarInfo(questID)
        
        -- DEBUG: Log progress bar info
        if addon.Log and (isBonusObjective or type == "bonus" or type == "supertrack" or type == "quest") then
             local isTask = C_QuestLog.IsQuestTask(questID)
             addon:Log("Quest [%d] '%s' IsTask=%s IsBonus=%s Progress=%s", questID, info.title, tostring(isTask), tostring(isBonusObjective), tostring(progress))
        end
        
        if progress then
             hasObjectives = true
             table.insert(questInfo.objectives, {
                 text = "Progress",
                 type = "progressbar",
                 finished = (progress >= 100),
                 numFulfilled = progress,
                 numRequired = 100,
             })

        end
    end

    if objectives then
        for _, obj in ipairs(objectives) do
            -- Dont add redundant "0/1" objectives if we have a progress bar for the whole quest
            -- But usually tasks have "Assault X" as text and the bar is separate. 
            -- Keeping the text is useful for context.
            hasObjectives = true
            table.insert(questInfo.objectives, {
                text = obj.text,
                type = obj.type,
                finished = obj.finished,
                numFulfilled = obj.numFulfilled,
                numRequired = obj.numRequired,
            })
        end
    end
    
    if not hasObjectives then
        local numLeaderBoards = GetNumQuestLeaderBoards(logIndex)
        for j=1, numLeaderBoards do
             local text, type, finished = GetQuestLogLeaderBoard(j, logIndex)
             if text then
                 table.insert(questInfo.objectives, {
                     text = text,
                     type = type,
                     finished = finished,
                     numFulfilled = 0,
                     numRequired = 0,
                 })
             end
        end
    end
    
    return questInfo
end

-- Collect tracked quests
function addon:CollectQuests(trackables)
    local numQuests = C_QuestLog.GetNumQuestLogEntries()
    local currentZone = GetRealZoneText() or "Unknown Zone"
    
    for i = 1, numQuests do
        local info = C_QuestLog.GetInfo(i)
        
        if info then
            if info.isHeader then
                currentZone = info.title
            else
                local isWatched = (C_QuestLog.GetQuestWatchType(info.questID) ~= nil)
                local isTask = C_QuestLog.IsQuestTask(info.questID)
                
                -- Allow hidden quests IF they are Tasks (Bonus Objectives)
                local allowHidden = info.isHidden and isTask
                
                if (not info.isHidden or allowHidden) and isWatched then
                    local questInfo = self:GetQuestData(i, nil, currentZone)
                    if questInfo then
                        table.insert(trackables, questInfo)
                    end
                end
            end
        end
    end
end

-- Collect tracked achievements
function addon:CollectAchievements(trackables)
    local trackedAchievements = {}
    
    -- Try C_ContentTracking first (Modern API)
    if C_ContentTracking and C_ContentTracking.GetTrackedIDs then
        trackedAchievements = C_ContentTracking.GetTrackedIDs(Enum.ContentTrackingType.Achievement)
    elseif GetTrackedAchievements then
        trackedAchievements = {GetTrackedAchievements()}
    end
    
    for _, achievementID in ipairs(trackedAchievements) do
        local id, name, points, completed, icon, isGuild
        
        -- Try C_AchievementInfo (Modern API)
        if C_AchievementInfo and C_AchievementInfo.GetInfo then
            local info = C_AchievementInfo.GetInfo(achievementID)
            if info then
                id = info.id
                name = info.title
                points = info.points
                completed = info.completed
                icon = info.icon
                isGuild = info.isGuild
            end
        elseif GetAchievementInfo then
            local _
            id, name, points, completed, _, _, _, _, _, icon, _, isGuild = GetAchievementInfo(achievementID)
        end
        
        if id then
            -- Determine Category (Minor Zone)
            local categoryName = "General"
            local categoryID
            if C_AchievementInfo and C_AchievementInfo.GetCategory then
                 categoryID = C_AchievementInfo.GetCategory(achievementID)
            elseif GetAchievementCategory then
                 categoryID = GetAchievementCategory(achievementID)
            end
            
            if categoryID then
                local catName
                if C_AchievementInfo and C_AchievementInfo.GetCategoryInfo then
                     catName = C_AchievementInfo.GetCategoryInfo(categoryID)
                elseif GetCategoryInfo then
                     catName = GetCategoryInfo(categoryID)
                end
                if catName then categoryName = catName end
            end

            local achievementInfo = {
                type = "achievement",
                id = achievementID,
                title = name,
                isComplete = completed,
                icon = icon,
                points = points,
                objectives = {},
                zone = categoryName,
                color = self.db.achievementColor,
            }
            
            -- Get criteria
            local numCriteria = 0
            if C_AchievementInfo and C_AchievementInfo.GetNumCriteria then
                numCriteria = C_AchievementInfo.GetNumCriteria(achievementID)
            elseif GetAchievementNumCriteria then
                numCriteria = GetAchievementNumCriteria(achievementID)
            end
            
            for i = 1, numCriteria do
                local criteriaString, criteriaCompleted, quantity, reqQuantity
                
                if C_AchievementInfo and C_AchievementInfo.GetCriteriaInfo then
                    local criteriaInfo = C_AchievementInfo.GetCriteriaInfo(achievementID, i)
                    if criteriaInfo then
                        criteriaString = criteriaInfo.description
                        criteriaCompleted = criteriaInfo.completed
                        quantity = criteriaInfo.quantity
                        reqQuantity = criteriaInfo.requiredQuantity
                    end
                elseif GetAchievementCriteriaInfo then
                    criteriaString, _, criteriaCompleted, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, i)
                end
                
                if criteriaString then
                    table.insert(achievementInfo.objectives, {
                        text = criteriaString,
                        finished = criteriaCompleted,
                        numFulfilled = quantity,
                        numRequired = reqQuantity,
                    })
                end
            end
            
            table.insert(trackables, achievementInfo)
        end
    end
end

-- Collect Auto Quest PopUps
function addon:CollectAutoQuests(trackables)
    if not GetNumAutoQuestPopUps then return end
    
    for i = 1, GetNumAutoQuestPopUps() do
        local questID, popUpType = GetAutoQuestPopUp(i)
        if questID then
             -- Only check if we have a title
             local title = C_QuestLog.GetTitleForQuestID(questID)
             if title then
                 table.insert(trackables, {
                     type = "autoquest",
                     questID = questID, -- Needed for interactions
                     title = title,
                     popUpType = popUpType, -- "OFFER", "COMPLETE"
                     isComplete = (popUpType == "COMPLETE"),
                     color = {r=1, g=0.8, b=0, a=1}, -- Orange/Goldish title
                     -- Use a specific structure for objectives to show the message
                     objectives = {{
                         text = (popUpType == "COMPLETE" and "Click to Complete" or "New Quest Available"), 
                         finished = false
                     }}
                 })
             end
        end
    end
end

-- Collect scenario objectives
function addon:CollectScenarioObjectives(trackables)
    -- If we are using the Blizzard frame (which is the plan now), we don't need to manually collect items
    -- However, we still need to detect attendance so the core loop knows we have "scenarios" to trigger the layout logic.
    if not C_Scenario.IsInScenario() then
        return
    end
    
    -- Insert a dummy item so TrackerFrame knows to activate the Scenario section
    -- The actual rendering will now look for the Blizzard Frame instead of this data 
    -- (See TrackerFrame.lua changes)
    local scenarioInfo = {
            type = "scenario",
            id = 0,
            title = "Blizzard Scenario Frame",
            level = 0,
            zone = "Scenario",
            objectives = {},
            color = self.db.scenarioColor,
            isDummy = true
    }
    table.insert(trackables, scenarioInfo)
end

-- Collect profession tracking
function addon:CollectProfessionTracking(trackables)
    -- Helper to add recipes
    local function AddRecipes(isRecraft)
        local trackedRecipes = C_TradeSkillUI.GetRecipesTracked(isRecraft)
        
        for _, recipeID in ipairs(trackedRecipes) do
            local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)
            if schematic then
                local professionInfo = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
                local professionName = professionInfo and professionInfo.professionName or "Professions"
                
                table.insert(trackables, {
                    type = "profession",
                    id = recipeID,
                    title = schematic.name,
                    level = 0, -- Recipes don't really have levels like quests
                    zone = professionName,
                    isRecraft = isRecraft,
                    objectives = {}, -- Could list reagents here if we wanted
                    color = self.db.professionColor
                })
            end
        end
    end

    AddRecipes(false)
    AddRecipes(true)
end

-- Collect monthly activities (Trading Post / Perks Program)
function addon:CollectMonthlyActivities(trackables)
    if not C_PerksProgram then return end
    
    local trackedIDs
    if C_PerksProgram.GetTrackedPerksActivities then
        trackedIDs = C_PerksProgram.GetTrackedPerksActivities()
    elseif C_ContentTracking and C_ContentTracking.GetTrackedIDs and Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.PerksActivity then
        trackedIDs = C_ContentTracking.GetTrackedIDs(Enum.ContentTrackingType.PerksActivity)
    end
    
    if not trackedIDs then return end
    
    for _, activityID in ipairs(trackedIDs) do
        local info = C_PerksProgram.GetPerksActivityInfo(activityID)
        if info then
            local objectives = {}
            local isComplete = info.completed
            
            -- If not complete, show progress
            if not isComplete then
                local progress = info.progress or 0
                local required = info.threshold or 1
                
                table.insert(objectives, {
                    text = info.activityName,
                    finished = isComplete,
                    numFulfilled = progress,
                    numRequired = required,
                    flags = 0 -- Default
                })
            end
            
            table.insert(trackables, {
                type = "monthly",
                id = activityID,
                title = info.activityName,
                level = 0,
                zone = "Traveler's Log",
                isComplete = isComplete,
                objectives = objectives,
                color = self.db.monthlyColor -- Cyan-ish
            })
        end
    end
end

-- Get quest type name
function addon:GetQuestTypeName(questID)
    local questInfo = C_QuestLog.GetQuestTagInfo(questID)
    
    if C_QuestLog.IsWorldQuest(questID) then
        return "World Quest"
    elseif questInfo then
        return questInfo.tagName
    end
    
    return nil
end

-- Collect Endeavors (Housing)
function addon:CollectEndeavors(trackables)
     -- C_NeighborhoodInitiative (Housing API)
     if C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetTrackedInitiativeTasks then
          local trackerData = C_NeighborhoodInitiative.GetTrackedInitiativeTasks()
          local trackedIDs = {}
          local useCache = false
          
          -- Try to get live data
          if trackerData and trackerData.trackedIDs and #trackerData.trackedIDs > 0 then
               trackedIDs = trackerData.trackedIDs
               -- Update cache
               self.db.endeavorCache = {}
               for _, id in ipairs(trackedIDs) do
                   self.db.endeavorCache[id] = true
               end
          else
               -- Fallback to cache if live data missing (common on login)
               useCache = true
               if self.db.endeavorCache then
                   for id, _ in pairs(self.db.endeavorCache) do
                       table.insert(trackedIDs, id)
                   end
               end
          end
          
          for _, id in ipairs(trackedIDs) do
              local info = C_NeighborhoodInitiative.GetInitiativeTaskInfo(id)
              
              if info and not info.completed then
                  local objectives = {}
                  
                  if info.requirementsList then
                      for _, req in ipairs(info.requirementsList) do
                          local text = req.requirementText
                          if text then
                              -- Clean up text formatting
                              -- Remove leading dashes to prevent double dashes in tracker
                              text = text:gsub("^%s*-%s*", "")
                              text = string.gsub(text, " / ", "/") 
                              
                              local isFinished = req.completed
                              if not isFinished then
                                  table.insert(objectives, {
                                      text = text,
                                      finished = isFinished
                                  })
                              end
                          end
                      end
                  end
                  
                  table.insert(trackables, {
                       type = "endeavor",
                       id = info.ID or id,
                       title = info.taskName or ("Endeavor " .. id),
                       level = 0, 
                       zone = "Housing",
                       objectives = objectives,
                       color = self.db.endeavorColor -- Warm Pink
                  })
              end
          end
     end
end

-- Get quest color based on type/status
function addon:GetQuestColor(info)
    if info.isFailed then
        return self.db.failedColor
    elseif C_QuestLog.IsComplete(info.questID) then
        return self.db.completeColor
    elseif C_QuestLog.IsWorldQuest(info.questID) then
        return self.db.questTypeColors.worldQuest
    elseif C_QuestLog.IsQuestTask(info.questID) then
        return self.db.bonusColor
    else
        return self.db.questColor
    end
end

-- Sort trackables
function addon:SortTrackables(trackables)
    local sortMethod = self:GetSetting("sortMethod")
    
    local function GetPriority(trackable)
        -- Priority 1: Scenarios/Dungeons (always on top)
        if trackable.type == "scenario" then
            return 1
        end
        
        -- Priority 2: Super Tracked Quest (Pinned)
        if trackable.type == "supertrack" then
            return 2
        end
        
        -- Priority 3: Everything else
        return 3
    end
    
    table.sort(trackables, function(a, b)
        local prioA = GetPriority(a)
        local prioB = GetPriority(b)
        
        if prioA ~= prioB then
            return prioA < prioB
        end
    
        if sortMethod == "level" then
            return (a.level or 0) > (b.level or 0)
        elseif sortMethod == "name" then
            return (a.title or "") < (b.title or "")
        end
        
        return false
    end)
end

-- Collect super tracked quest
function addon:CollectSuperTrackedQuest(trackables)
    local superTrackedQuestID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID()
    if not superTrackedQuestID or superTrackedQuestID == 0 then return end

    -- Check if it's a world quest logic here if needed...
    -- But assuming it's in the log for now:
    local logIndex = C_QuestLog.GetLogIndexForQuestID(superTrackedQuestID)
    if not logIndex then return end

    local questInfo = self:GetQuestData(logIndex, "supertrack", "Pinned")
    if questInfo then
         table.insert(trackables, questInfo)
    end
end

-- Set tracker visibility
function addon:SetTrackerVisible(visible)
    if self.trackerFrame then
        if visible then
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
            local enabled = not addon:GetSetting("enabled")
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
        else
            Print("Commands:")
            Print("  /tp - Open settings")
            Print("  /tp toggle - Toggle tracker on/off")
            Print("  /tp lock/unlock - Lock/unlock frame position")
            Print("  /tp reset - Reset all settings")
        end
    end
end

-- Bootstrap
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- Initialize with a slight delay to ensure other things are ready
        C_Timer.After(1, function()
             addon:Initialize()
        end)
    else
        -- Forward other events to handler if initialized (handled by Re-registration in Initialize)
        -- But for now we just handle bootstrap here.
        -- Once Initialize is called, it overwrites the OnEvent script to addon:OnEvent
    end
end)
