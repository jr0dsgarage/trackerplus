---@diagnostic disable: undefined-global
local _, addon = ...

-- Quest log collectors: quest rows, auto-quest popups and the super-tracked quest.

-- Localize hot-path globals to avoid repeated global lookups
local ipairs = ipairs
local type = type
local tostring = tostring
local band = bit.band
local GetRealZoneText = GetRealZoneText
local C_QuestLog = C_QuestLog
local C_SuperTrack = C_SuperTrack

local function ShouldForceObjectiveIncomplete(objectiveText)
    if type(objectiveText) ~= "string" then
        return false
    end

    local text = objectiveText:gsub("^%s+", "")
    if text == "" then
        return false
    end

    local lowered = text:lower()
    if lowered:find("ready to turn-in", 1, true) then
        return false
    end

    local hasLeadingNumericPrefix =
        text:match("^%d+%s*/%s*%d+")
        or text:match("^%(%s*%d+%s*/%s*%d+%s*%)")
        or text:match("^%d+%%")
        or text:match("^%(%s*%d+%%%s*%)")

    return not hasLeadingNumericPrefix
end

-- Helper to gather quest data
function addon:GetQuestData(logIndex, typeOverride, zoneOverride)
    local info = C_QuestLog.GetInfo(logIndex)
    if not info then return nil end
    
    local questID = info.questID
    
    local isWorldQuest = C_QuestLog.IsWorldQuest(questID)
    local isBonusObjective = C_QuestLog.IsQuestTask(questID) and not isWorldQuest
    local isComplete = C_QuestLog.IsComplete(questID)
    local itemType = typeOverride
    if not itemType then
         if isBonusObjective then
             itemType = "bonus"
         elseif isWorldQuest then
             itemType = "worldquest"
         else
             itemType = "quest"
         end
    end

    local questInfo = {
        type = itemType,
        id = questID,
        logIndex = logIndex,
        title = info.title,
        level = info.level,
        -- Distinct from level: QuestInfo carries both, and this is the one the game
        -- compares against the player for difficulty. They diverge on scaling quests,
        -- where level is what gets shown in brackets but difficultyLevel is what
        -- decides green/yellow/orange. Carried so colouring and difficulty sorting can
        -- use it while the title keeps displaying level.
        difficultyLevel = info.difficultyLevel,
        questType = self:GetQuestTypeName(questID),
        -- Drives the "+" in "[28+]", matching the default quest log's marker for
        -- elite / group quests.
        isGroupQuest = self:IsGroupQuest(questID, info),
        isComplete = isComplete,
        isFailed = info.isFailed,
        isWorldQuest = isWorldQuest,
        zone = zoneOverride or GetRealZoneText() or "Unknown Zone",
        objectives = {},
        color = self:GetQuestColor(info),
    }

    -- Get Quest Item Info
    local itemLink, itemTexture = GetQuestLogSpecialItemInfo(logIndex)
    if itemLink or itemTexture then
        questInfo.item = {
            link = itemLink,
            texture = itemTexture,
        }
    end
    
    -- Get objectives
    local objectives = C_QuestLog.GetQuestObjectives(questID) or {}
    local hasObjectives = false
    local hasProgressBarObj = false

    if objectives then
        for _, obj in ipairs(objectives) do
            -- Dont add redundant "0/1" objectives if we have a progress bar for the whole quest
            -- But usually tasks have "Assault X" as text and the bar is separate.
            -- Keeping the text is useful for context.
            hasObjectives = true
            
            local flags = obj.flags or 0
            local isFlagged = band(flags, 1) == 1
            if obj.type == "progressbar" or isFlagged or (obj.text and string.match(obj.text, "%%")) then
                hasProgressBarObj = true
            end

            local objectiveFinished = (obj.finished == true)
            -- Blizzard can flag text-only objectives as finished before they flip to Ready to Turn-in.
            if objectiveFinished and ShouldForceObjectiveIncomplete(obj.text) then
                objectiveFinished = false
            end
            
            questInfo.objectives[#questInfo.objectives + 1] = {
                text = obj.text,
                type = obj.type,
                finished = objectiveFinished,
                numFulfilled = obj.numFulfilled,
                numRequired = obj.numRequired,
                flags = obj.flags,
            }
        end
    end

    -- Check for Task/Bonus/World Quest progress bars only if we lack a native one
    local canUseTaskProgress = C_QuestLog.IsQuestTask(questID) or isWorldQuest or isBonusObjective
    if not hasProgressBarObj and canUseTaskProgress and C_TaskQuest and C_TaskQuest.GetQuestProgressBarInfo then
        local progress = C_TaskQuest.GetQuestProgressBarInfo(questID)

        if progress then
             hasObjectives = true
             questInfo.objectives[#questInfo.objectives + 1] = {
                 text = "Progress",
                 type = "progressbar",
                 finished = (progress >= 100),
                 numFulfilled = progress,
                 numRequired = 100,
             }
        end
    end
    
    -- Legacy leaderboard fallback, only reached when C_QuestLog.GetQuestObjectives
    -- returned nothing. Both globals are absent on clients that have moved on, and
    -- this runs during every collection pass, so guard rather than risk erroring
    -- out of quest collection entirely.
    if not hasObjectives and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local numLeaderBoards = GetNumQuestLeaderBoards(logIndex) or 0
        for j=1, numLeaderBoards do
             local text, type, finished = GetQuestLogLeaderBoard(j, logIndex)
             if text then
                 local objectiveFinished = (finished == true)
                 if objectiveFinished and ShouldForceObjectiveIncomplete(text) then
                     objectiveFinished = false
                 end
                 questInfo.objectives[#questInfo.objectives + 1] = {
                     text = text,
                     type = type,
                     finished = objectiveFinished,
                     numFulfilled = 0,
                     numRequired = 0,
                 }
             end
        end
    end
    
    return questInfo
end

function addon:IsCampaignQuestLogEntry(logIndex, info)
    if not logIndex or logIndex <= 0 then return false end

    info = info or C_QuestLog.GetInfo(logIndex)
    if not info or info.isHeader then return false end

    if (info.campaignID and info.campaignID ~= 0) or info.isCampaign or info.isStory then
        return true
    end

    for i = logIndex - 1, 1, -1 do
        local headerInfo = C_QuestLog.GetInfo(i)
        if headerInfo and headerInfo.isHeader then
            return (headerInfo.campaignID and headerInfo.campaignID ~= 0) or headerInfo.isCampaign or headerInfo.isStory or false
        end
    end

    return false
end

function addon:GetQuestShortDescription(questID, logIndex)
    if not GetQuestLogQuestText then return nil end

    -- GetQuestLogQuestText reads whichever quest is currently *selected*, so the
    -- quest has to be selected first. The legacy SelectQuestLogEntry(logIndex) no
    -- longer does that on this client, which is why every quest's tooltip showed
    -- the same description: whatever quest happened to be selected already.
    -- C_QuestLog.SetSelectedQuest(questID) is the current way to do it.
    --
    -- This runs on hover (user interaction) rather than during background
    -- collection, and the previous selection is restored afterwards so the
    -- player's own quest log selection isn't moved out from under them.
    local previousQuestID
    if C_QuestLog and C_QuestLog.GetSelectedQuest then
        local ok, selected = pcall(C_QuestLog.GetSelectedQuest)
        if ok then previousQuestID = selected end
    end

    local selected = false
    if questID and C_QuestLog and C_QuestLog.SetSelectedQuest then
        selected = pcall(C_QuestLog.SetSelectedQuest, questID)
    end

    if not selected and SelectQuestLogEntry then
        -- Legacy fallback: select by log index instead.
        local idx = logIndex
        if not idx and questID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
            idx = C_QuestLog.GetLogIndexForQuestID(questID)
        end
        if idx and idx > 0 then
            selected = pcall(SelectQuestLogEntry, idx)
        end
    end

    if not selected then return nil end

    local desc
    local ok, questText = pcall(GetQuestLogQuestText)
    if ok then desc = questText end

    -- Put the player's selection back.
    if previousQuestID and previousQuestID ~= 0 and previousQuestID ~= questID
        and C_QuestLog and C_QuestLog.SetSelectedQuest then
        pcall(C_QuestLog.SetSelectedQuest, previousQuestID)
    end

    if desc and desc ~= "" then
        -- Truncate to keep tooltip concise
        if #desc > 220 then
            desc = desc:sub(1, 220) .. "..."
        end
        return desc
    end

    return nil
end

-- Collect tracked quests
function addon:CollectQuests(trackables)
    local numQuests = C_QuestLog.GetNumQuestLogEntries()
    local currentZone = GetRealZoneText() or "Unknown Zone"
    local currentHeaderIsCampaign = false
    local worldQuestsHeader = (_G and rawget(_G, "WORLD_QUESTS")) or "World Quests"

    local function IsWorldQuestsHeaderTitle(title)
        if not title then return false end
        if title == worldQuestsHeader then return true end
        return tostring(title):lower() == tostring(worldQuestsHeader):lower()
    end

    for i = 1, numQuests do
        local info = C_QuestLog.GetInfo(i)

        if info then
            if info.isHeader then
                currentZone = info.title
                currentHeaderIsCampaign = (info.campaignID and info.campaignID ~= 0) or info.isCampaign or info.isStory
            else
                local isWorldQuest = C_QuestLog.IsWorldQuest(info.questID)
                local isWatched = (C_QuestLog.GetQuestWatchType(info.questID) ~= nil)
                local isTask = C_QuestLog.IsQuestTask(info.questID)
                local isComplete = C_QuestLog.IsComplete(info.questID)
                local isUnderWorldQuestHeader = IsWorldQuestsHeaderTitle(currentZone)
                local treatAsWorldQuest = isWorldQuest or isUnderWorldQuestHeader

                -- Allow hidden quests IF they are Tasks (Bonus Objectives)
                local allowHidden = info.isHidden and isTask

                local shouldInclude = false
                if treatAsWorldQuest then
                    -- World quests are rendered in their own pinned section.
                    -- Do not require the watch flag; quest-log tracking can be transient.
                    -- Hide completed/ended world quests immediately so stale headers disappear.
                    shouldInclude = self.db.showWorldQuests and not isComplete
                elseif isTask then
                    -- Bonus objectives are rendered in their own pinned section.
                    -- Do not require watch state; these are often hidden/unwatched in the quest log.
                    shouldInclude = self.db.showBonusObjectives
                else
                    shouldInclude = self.db.showQuests and isWatched
                end

                if (not info.isHidden or allowHidden) and shouldInclude then
                    local isCamp = currentHeaderIsCampaign or self:IsCampaignQuestLogEntry(i, info)
                    local questType = nil
                    if treatAsWorldQuest then
                        questType = "worldquest"
                    elseif isCamp and not isWorldQuest and not isTask then
                        questType = "campaign"
                    end
                    local questInfo = self:GetQuestData(i, questType, currentZone)
                    if questInfo then
                        trackables[#trackables + 1] = questInfo
                    end
                end
            end
        end
    end
end

-- Collect Auto Quest PopUps
function addon:CollectAutoQuests(trackables)
    if not GetNumAutoQuestPopUps then return end
    
    for i = 1, GetNumAutoQuestPopUps() do
        local questID, popUpType = GetAutoQuestPopUp(i)
        if questID then
             -- Skip stale popup entries after completion/turn-in.
             local alreadyDone = C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID)
             local inLog = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
             local isCompleteNow = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
             local isStaleCompletePopup = (popUpType == "COMPLETE") and (alreadyDone or not inLog or not isCompleteNow)

             local title = (not alreadyDone and not isStaleCompletePopup) and C_QuestLog.GetTitleForQuestID(questID)
             if title then
                 trackables[#trackables + 1] = {
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
                 }
             end
        end
    end
end

-- Get quest type name
function addon:IsGroupQuest(questID, info)
    if info and (tonumber(info.suggestedGroup) or 0) > 0 then
        return true
    end
    local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
    if not tagInfo then return false end
    if tagInfo.isElite then return true end
    return Enum.QuestTag and tagInfo.tagID == Enum.QuestTag.Group or false
end

function addon:GetQuestTypeName(questID)
    local questInfo = C_QuestLog.GetQuestTagInfo(questID)
    
    if C_QuestLog.IsWorldQuest(questID) then
        return "World Quest"
    elseif questInfo then
        return questInfo.tagName
    end
    
    return nil
end

-- Collect super tracked quest
function addon:CollectSuperTrackedQuest(trackables)
    local superTrackedQuestID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID()
    if not superTrackedQuestID or superTrackedQuestID == 0 then return end

    -- Check if it's a world quest logic here if needed...
    -- But assuming it's in the log for now:
    local logIndex = C_QuestLog.GetLogIndexForQuestID(superTrackedQuestID)
    if not logIndex then return end

    if not self.db.includeCampaignQuestInActiveQuest and self:IsCampaignQuestLogEntry(logIndex) then
        return
    end

    local questInfo = self:GetQuestData(logIndex, "supertrack", "Pinned")
    if questInfo then
         trackables[#trackables + 1] = questInfo
    end
end
