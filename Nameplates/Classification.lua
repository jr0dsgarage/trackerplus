---@diagnostic disable: undefined-global
local addonName, addon = ...

local wipeTable = addon.WipeTable
local strgsub = string.gsub
local strlower = string.lower

local questUtilsIsWorldQuest = rawget(_G, "QuestUtils_IsQuestWorldQuest")
local questUtilsIsBonusObjective = rawget(_G, "QuestUtils_IsQuestBonusObjective")
local getQuestLogSpecialItemInfo = rawget(_G, "GetQuestLogSpecialItemInfo")

local function safeGsub(value, pattern, replacement)
    if type(value) ~= "string" then
        return nil
    end
    local ok, result = pcall(strgsub, value, pattern, replacement)
    if ok and type(result) == "string" then
        return result
    end
    return nil
end

local function safeLower(value)
    if type(value) ~= "string" then
        return nil
    end
    local ok, result = pcall(strlower, value)
    if ok and type(result) == "string" then
        return result
    end
    return nil
end

local function safeMatch(value, pattern)
    if type(value) ~= "string" then
        return nil, nil
    end
    local ok, first, second = pcall(string.match, value, pattern)
    if ok then
        return first, second
    end
    return nil, nil
end

local function safeContains(value, needle)
    if type(value) ~= "string" then
        return false
    end
    local ok, found = pcall(string.find, value, needle, 1, true)
    return ok and found ~= nil
end

local function trim(value)
    if type(value) ~= "string" then
        return nil
    end

    local trimmed = safeGsub(value, "^%s+", "")
    if not trimmed then
        return nil
    end
    trimmed = safeGsub(trimmed, "%s+$", "")
    return trimmed
end

local function stripColorCodes(text)
    if type(text) ~= "string" then
        return nil
    end
    text = safeGsub(text, "|c%x%x%x%x%x%x%x%x", "")
    if not text then
        return nil
    end
    text = safeGsub(text, "|r", "")
    return text
end

local function normalizeText(text)
    if type(text) ~= "string" then
        return nil
    end

    text = stripColorCodes(text)
    if type(text) ~= "string" then
        return nil
    end

    -- Combine pattern replacements and normalize whitespace
    text = safeGsub(text, "[%[%]%p%c]", " ")  -- Remove brackets, punctuation, control chars
    if not text then
        return nil
    end
    text = safeLower(text)
    if not text then
        return nil
    end
    text = safeGsub(text, "%s+", " ")
    text = trim(text)

    return text
end

local function normalizeLines(lines)
    if not lines or #lines == 0 then
        return nil
    end

    local normalized = {}
    for _, line in ipairs(lines) do
        local normalizedLine = normalizeText(line)
        if normalizedLine then
            normalized[#normalized + 1] = normalizedLine
        end
    end

    if #normalized == 0 then
        return nil
    end

    return normalized
end

local QUEST_CACHE_SECONDS = 5 -- fallback TTL in case quest change events are missed
local UNIT_CACHE_SECONDS = 1.25
local UNIT_CACHE_PENDING_OBJECTIVE_SECONDS = 0.1

local questCache = { timestamp = 0, entries = {} }
local unitCache = {}
local tooltipTextCache = {}

local function resetCaches()
    questCache.timestamp = 0
    if wipeTable then
        wipeTable(questCache.entries)
        wipeTable(tooltipTextCache)
    else
        questCache.entries = {}
        tooltipTextCache = {}
    end
    unitCache = {}
end







local function getCachedTooltipText(text)
    if type(text) ~= "string" then
        return nil
    end

    local sanitized = stripColorCodes(text)
    if sanitized then
        sanitized = safeGsub(sanitized, "%s+", " ")
        sanitized = trim(sanitized)
    end

    if sanitized then
        return sanitized
    end

    return nil
end

local function parseTooltip(unit)
    local info = {
        hasQuestObjective = false,
        hasCompletedObjective = false,
        hasEnemyForcesLine = false,
        lines = {},
        normalizedLines = nil,
    }

    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = C_TooltipInfo.GetUnit(unit)
        if data then
            for _, line in ipairs(data.lines) do
                local text = line.leftText
                if type(text) == "string" then
                    local sanitized = getCachedTooltipText(text)
                    if sanitized then
                        info.lines[#info.lines + 1] = sanitized

                        local lower = safeLower(sanitized)
                        local isEnemyForcesLine = safeContains(lower, "enemy forces")
                        if isEnemyForcesLine then
                            info.hasEnemyForcesLine = true
                        end

                        local current, total = safeMatch(sanitized, "(%d+)%s*/%s*(%d+)")
                        if current and total and not isEnemyForcesLine then
                            local currentNum = tonumber(current)
                            local totalNum = tonumber(total)
                            if currentNum and totalNum then
                                if currentNum >= totalNum then
                                    info.hasCompletedObjective = true
                                else
                                    info.hasQuestObjective = true
                                end
                            end
                        end

                        local percentValue = safeMatch(sanitized, "(%d?%d?%d)%%")
                        if percentValue then
                            local isThreatLine = safeContains(lower, "threat")
                            if not isThreatLine and not isEnemyForcesLine then
                                local percentNum = tonumber(percentValue)
                                if percentNum then
                                    if percentNum >= 100 then
                                        info.hasCompletedObjective = true
                                    else
                                        info.hasQuestObjective = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    info.normalizedLines = normalizeLines(info.lines)
    return info
end

local function hasQuestItemIcon(unit)
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
        return false
    end

    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then
        return false
    end
    
    -- Try multiple possible locations for the SoftTargetFrame
    local softTargetFrame = nil
    if nameplate.UnitFrame then
        softTargetFrame = nameplate.UnitFrame.SoftTargetFrame
                      or nameplate.UnitFrame.softTargetFrame
    end
    
    -- Also check direct child of nameplate
    if not softTargetFrame then
        softTargetFrame = nameplate.SoftTargetFrame or nameplate.softTargetFrame
    end
    
    if softTargetFrame and softTargetFrame:IsShown() then
        -- Only return true if icon exists and is shown
        if softTargetFrame.Icon and softTargetFrame.Icon:IsShown() then
            return true
        end
    end

    return false
end

local function refreshQuestCache()
    local now = GetTime()
    if now - questCache.timestamp < QUEST_CACHE_SECONDS then
        return questCache.entries
    end

    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then
        return questCache.entries
    end

    -- Build new cache in local table to prevent race conditions
    local newEntries = {}
    local addedQuestIDs = {}

    local function determineWorldQuestFlag(questID, seedFlag)
        if seedFlag then
            return true
        end

        if not questID then
            return false
        end

        if C_QuestLog and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
            return true
        end

        if questUtilsIsWorldQuest and questUtilsIsWorldQuest(questID) then
            return true
        end

        return false
    end

    local function addEntry(entry)
        if not entry or not entry.questID then
            return
        end
        addedQuestIDs[entry.questID] = true
        newEntries[#newEntries + 1] = entry
    end

    local function buildQuestEntry(questID, seed)
        seed = seed or {}
        if not questID or addedQuestIDs[questID] then
            return nil
        end

        if C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then
            addedQuestIDs[questID] = true
            return nil
        end

        local entry = {
            questID = questID,
            questName = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or "Unknown Quest",
            isWorldQuest = false,
            isBonusObjective = false,
            normalizedQuestName = nil,
            hasQuestItem = seed.hasQuestItem,
        }

        entry.isWorldQuest = determineWorldQuestFlag(questID, seed.isWorldQuest)

        entry.normalizedQuestName = normalizeText(entry.questName)

        if seed.isBonusObjective then
            entry.isBonusObjective = true
        end

        if questUtilsIsBonusObjective and questUtilsIsBonusObjective(questID) then
            entry.isBonusObjective = true
        end

        if not entry.isBonusObjective and C_QuestLog and C_QuestLog.IsBonusObjective then
            local ok, isBonus = pcall(C_QuestLog.IsBonusObjective, questID)
            if ok and isBonus then
                entry.isBonusObjective = true
            end
        end

        if not entry.isBonusObjective and C_QuestLog and C_QuestLog.GetInfo then
            local questInfo = seed.questInfo
            if not questInfo then
                local infoIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
                if infoIndex then
                    questInfo = C_QuestLog.GetInfo(infoIndex)
                end
            end
            if questInfo and questInfo.isBonusObjective then
                entry.isBonusObjective = true
            end
        end

        if not entry.isBonusObjective and C_QuestLog and C_QuestLog.GetQuestTagInfo and Enum and Enum.QuestTagType and Enum.QuestTagType.BonusObjective then
            local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
            local tagID = nil
            if type(tagInfo) == "table" then
                tagID = tagInfo.tagID or tagInfo.tagId
            else
                tagID = tagInfo
            end
            if tagID and tagID == Enum.QuestTagType.BonusObjective then
                entry.isBonusObjective = true
            end
        end

        if not entry.isBonusObjective and entry.questName then
            local nameLower = safeLower(entry.questName)
            if safeContains(nameLower, "bonus objective") then
                entry.isBonusObjective = true
            end
        end

        addedQuestIDs[questID] = true
        return entry
    end

    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    for index = 1, numEntries do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            local questID = info.questID

            local hasQuestItem = false
            if getQuestLogSpecialItemInfo then
                local itemID = getQuestLogSpecialItemInfo(index)
                if itemID then
                    hasQuestItem = true
                end
            end

            local entry = buildQuestEntry(questID, {
                questInfo = info,
                isBonusObjective = info and info.isBonusObjective,
                isWorldQuest = info and info.isWorldQuest,
                hasQuestItem = hasQuestItem,
            })
            addEntry(entry)
        end
    end

    if C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID and C_Map and C_Map.GetBestMapForUnit then
        local processedMaps = {}

        local function addWorldQuest(questID, seed)
            local entry = buildQuestEntry(questID, seed)
            addEntry(entry)
        end

        local function processMap(mapID)
            if not mapID or processedMaps[mapID] then
                return
            end
            processedMaps[mapID] = true

            local tasks = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
            if tasks then
                for _, taskInfo in ipairs(tasks) do
                    local questID = taskInfo and taskInfo.questId
                    if questID then
                        local isActive
                        if C_TaskQuest.IsActive then
                            isActive = C_TaskQuest.IsActive(questID)
                        else
                            isActive = taskInfo.inProgress ~= false
                        end
                        if isActive then
                            local seed = { isWorldQuest = true }
                            if taskInfo and taskInfo.isBonusObjective then
                                seed.isBonusObjective = true
                            end
                            addWorldQuest(questID, seed)
                        end
                    end
                end
            end

            if C_Map.GetMapChildrenInfo and Enum and Enum.UIMapType then
                local children = C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone, false)
                if children then
                    for _, child in ipairs(children) do
                        if child and child.mapID then
                            processMap(child.mapID)
                        end
                    end
                end
            end
        end

        local currentMap = C_Map.GetBestMapForUnit("player")
        local depth = 0
        while currentMap and depth < 6 do
            processMap(currentMap)
            local mapInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(currentMap)
            if mapInfo and mapInfo.parentMapID then
                currentMap = mapInfo.parentMapID
            else
                currentMap = nil
            end
            depth = depth + 1
        end
    end

    -- Atomic update: assign new entries and timestamp together
    questCache.entries = newEntries
    questCache.timestamp = now
    
    return questCache.entries
end

local function matchQuestFromTooltip(unit, tooltipInfo, questEntries)
    if not questEntries or #questEntries == 0 then
        return nil, nil
    end

    local unitIsRelatedToQuest = C_QuestLog and C_QuestLog.UnitIsRelatedToQuest
    if unit and unitIsRelatedToQuest then
        for _, entry in ipairs(questEntries) do
            if entry.questID then
                local related = unitIsRelatedToQuest(unit, entry.questID)
                if related then
                    return entry, "unit-related"
                end
            end
        end
    end

    if not tooltipInfo then
        return nil, nil
    end

    local normalizedTooltipLines = tooltipInfo.normalizedLines
    if not normalizedTooltipLines and tooltipInfo.lines then
        normalizedTooltipLines = normalizeLines(tooltipInfo.lines)
    end

    if normalizedTooltipLines then
        for _, entry in ipairs(questEntries) do
            local normalizedQuestName = entry.normalizedQuestName
            if normalizedQuestName then
                for _, line in ipairs(normalizedTooltipLines) do
                    if safeContains(line, normalizedQuestName) or safeContains(normalizedQuestName, line) then
                        return entry, "tooltip-name"
                    end
                end
            end
        end
    end

    return nil, nil
end

local function classifyUnit(unitData)
    local cacheKey = unitData.frame or unitData.unit
    if not cacheKey then
        return nil
    end

    local now = GetTime()
    local questTimestamp = questCache.timestamp or 0
    local questDataExpired = (now - questTimestamp) >= QUEST_CACHE_SECONDS
    local cached = unitCache[cacheKey]
    if cached then
        local expires = cached.expires or (cached.time and (cached.time + UNIT_CACHE_SECONDS)) or 0
        local cacheValid = not questDataExpired and now < expires
        local questStampMatch = not cached.questTimestamp or cached.questTimestamp == questTimestamp
        if cacheValid and questStampMatch then
            return cached.result
        end
    end

    local unit = unitData.unit
    local unitName = UnitName(unit)
    if type(unitName) ~= "string" then
        unitCache[cacheKey] = {
            result = nil,
            expires = now + UNIT_CACHE_SECONDS,
            questTimestamp = questCache.timestamp,
        }
        return nil
    end

    local tooltipInfo = parseTooltip(unit)
    local questEntries = refreshQuestCache()
    local questMatch, questMatchSource = matchQuestFromTooltip(unit, tooltipInfo, questEntries)
    local questName = questMatch and questMatch.questName or nil
    local questID = questMatch and questMatch.questID or nil
    local isWorldQuest = questMatch and questMatch.isWorldQuest or false
    local isBonusObjective = questMatch and questMatch.isBonusObjective or false
    local hasQuestItem = questMatch and questMatch.hasQuestItem or false
    local questType = nil
    if questMatch then
        if isBonusObjective then
            questType = "Bonus"
        elseif isWorldQuest then
            questType = "World"
        else
            questType = "Regular"
        end
    end
    local hasSoftTarget = hasQuestItemIcon(unit)
    local isQuestBoss = UnitIsQuestBoss and UnitIsQuestBoss(unit)
    local isBossUnit = UnitIsBossMob and UnitIsBossMob(unit)
    local unitNameNormalized = normalizeText(unitName)

    local classification = UnitClassification and UnitClassification(unit)
    local isRare = classification == "rare" or classification == "rareelite" or classification == "elite"

    local reason
    local isMythicBoss = false
    local isMythicEnemyForces = false
    local mythicBossName
    if hasSoftTarget or hasQuestItem then
        reason = "Has Quest Item"
    elseif tooltipInfo.hasQuestObjective then
        if isBonusObjective then
            reason = "Bonus Objective"
        elseif isWorldQuest then
            reason = "World Quest"
        else
            reason = "Quest Objective"
        end
    end

    if not reason and inChallengeMode then
        local isNpc = not UnitIsPlayer(unit)
        local matchedBoss
        if isNpc and mythicStatus and mythicStatus.bosses and unitNameNormalized then
            for _, boss in ipairs(mythicStatus.bosses) do
                if boss and not boss.completed and boss.normalized then
                    if safeContains(boss.normalized, unitNameNormalized) or safeContains(unitNameNormalized, boss.normalized) then
                        matchedBoss = boss
                        break
                    end
                end
            end
        end

        if not matchedBoss and isNpc and isBossUnit then
            matchedBoss = { description = unitName, normalized = unitNameNormalized, completed = false }
        end

        if matchedBoss then
            reason = "Mythic Objective"
            isMythicBoss = true
            mythicBossName = matchedBoss.description or unitName
        else
            local reactionToPlayer = UnitReaction and UnitReaction(unit, "player")
            local hostile = not reactionToPlayer or reactionToPlayer <= 4
            local enemyForcesAvailable = mythicStatus and mythicStatus.hasEnemyForces and not mythicStatus.enemyForcesComplete
            if not enemyForcesAvailable and tooltipInfo.hasEnemyForcesLine then
                enemyForcesAvailable = not tooltipInfo.hasCompletedObjective
            end
            if isNpc and hostile and enemyForcesAvailable then
                reason = "Mythic Objective"
                isMythicEnemyForces = true
            end
        end
    end

    local result = {
        unit = unit,
        frame = unitData.frame,
        name = unitName,
        reason = reason,
        questName = questName,
        questID = questID,
        questType = questType,
        questMatchSource = questMatchSource,
        tooltipLines = tooltipInfo.lines,
        isWorldQuest = isWorldQuest,
        isBonusObjective = isBonusObjective,
        hasSoftTarget = hasSoftTarget,
        isQuestBoss = isQuestBoss,
        hasQuestObjectiveMatch = questMatch ~= nil,
        hasTooltipObjective = tooltipInfo.hasQuestObjective,
        hasCompletedObjective = tooltipInfo.hasCompletedObjective,
        isRare = isRare,
    }

    if not reason then
        if tooltipInfo.hasCompletedObjective then
            result.note = "Quest objective already complete"
        elseif tooltipInfo.hasQuestObjective then
            result.note = "Tooltip indicates quest objective, but filtered"
        elseif questMatch then
            result.note = "Quest match found, but no tooltip objective"
        elseif isQuestBoss then
            result.note = "Quest boss for unavailable quest"
        elseif isRare then
            result.note = "Rare/Elite (quest highlighting only)"
        end
    end

    local cacheDuration = UNIT_CACHE_SECONDS
    if result.hasQuestObjectiveMatch and not result.hasTooltipObjective then
        cacheDuration = UNIT_CACHE_PENDING_OBJECTIVE_SECONDS
    end

    unitCache[cacheKey] = {
        result = result,
        expires = now + cacheDuration,
        questTimestamp = questCache.timestamp,
    }
    return result
end

local function addUnit(target, unitToken, frame)
    if not unitToken or not UnitExists(unitToken) then
        return
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unitToken) then
        return
    end

    local reaction = UnitReaction and UnitReaction(unitToken, "player")
    if reaction and reaction > 4 then
        return
    end

    target[#target + 1] = {
        unit = unitToken,
        frame = frame,
    }
end

local function getRelevantUnits()
    local units = {}

    addUnit(units, "target")
    addUnit(units, "focus")
    addUnit(units, "mouseover")

    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.displayedUnit)
            addUnit(units, token, plate)
        end
    end

    return units
end

function addon:GetRelevantUnits()
    return getRelevantUnits()
end

function addon:ClassifyUnit(unitData)
    return classifyUnit(unitData)
end

function addon:ResetCaches()
    resetCaches()
end
