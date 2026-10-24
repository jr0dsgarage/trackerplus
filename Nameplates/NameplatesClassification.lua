---@diagnostic disable: undefined-global
local _, TrackerPlus = ...
TrackerPlus.Nameplates = TrackerPlus.Nameplates or {}
local Nameplates = TrackerPlus.Nameplates

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

-- Quests a unit can be matched against, gathered from two sources with different costs:
--   logCache   - the quest log. Cheap; rebuilt after any quest log change.
--   worldCache - active world quests/tasks on the player's map, its parents and their
--                child zones. Many map queries, so rebuilt only when the player's map
--                changes, a quest is accepted/removed/turned in, or the TTL lapses.
-- questCache holds the two merged; its timestamp is the version unit results are
-- checked against.
local logCache = { timestamp = 0, entries = {}, added = {} }
local worldCache = { timestamp = 0, entries = {}, added = {}, mapID = nil }
local questCache = { timestamp = 0, entries = {} }
local unitCache = {}

-- includeWorldQuests: also drop the world quest scan (quest accepted/removed/turned in).
local function resetCaches(includeWorldQuests)
    logCache.timestamp = 0
    if includeWorldQuests then
        worldCache.timestamp = 0
    end
    questCache.timestamp = 0
    wipe(unitCache)
end

-- Tooltip line without color codes and with whitespace collapsed; nil if it can't be read.
local function sanitizeTooltipText(text)
    local sanitized = stripColorCodes(text)
    if sanitized then
        sanitized = safeGsub(sanitized, "%s+", " ")
        sanitized = trim(sanitized)
    end
    return sanitized
end

local function recordObjective(info, completed)
    if completed then
        info.hasCompletedObjective = true
    else
        info.hasQuestObjective = true
    end
end

-- Records "x/y" or "n%" progress found in a line's text; for tooltips without line types.
local function readObjectiveProgress(info, sanitized)
    local lower = safeLower(sanitized)
    -- Dungeon "Enemy Forces" progress isn't a quest objective.
    if safeContains(lower, "enemy forces") then
        return
    end

    local current, total = safeMatch(sanitized, "(%d+)%s*/%s*(%d+)")
    local currentNum, totalNum = tonumber(current), tonumber(total)
    if currentNum and totalNum then
        recordObjective(info, currentNum >= totalNum)
    end

    local percentNum = tonumber((safeMatch(sanitized, "(%d?%d?%d)%%")))
    if percentNum and not safeContains(lower, "threat") then
        recordObjective(info, percentNum >= 100)
    end
end

local isSecretValue = rawget(_G, "issecretvalue") or function() return false end

-- nil in place of a secret, so the value can be tested and compared safely.
local function readable(value)
    if isSecretValue(value) then
        return nil
    end
    return value
end

local lineTypes = Enum and Enum.TooltipDataLineType
local QUEST_TITLE_LINE = lineTypes and lineTypes.QuestTitle
local QUEST_OBJECTIVE_LINE = lineTypes and lineTypes.QuestObjective

-- Whether a typed objective line is finished, from the fields Blizzard's own check icon uses.
-- On restricted maps (dungeons) all of them are hidden: it's still an objective, so it counts as unfinished.
local function isObjectiveLineCompleted(line)
    local completed = readable(line.completed)
    if type(completed) == "boolean" then
        return completed
    end
    local fulfilled, required = readable(line.numFulfilled), readable(line.numRequired)
    if type(fulfilled) == "number" and type(required) == "number" and required > 0 then
        return fulfilled >= required
    end
    return false
end

-- Keeps a line's text for title matching and the debug window; returns it sanitized, or nil if unreadable.
local function addTextLine(info, text)
    if isSecretValue(text) then
        info.hiddenLineCount = info.hiddenLineCount + 1
        return nil
    end
    local sanitized = type(text) == "string" and sanitizeTooltipText(text)
    if sanitized then
        info.lines[#info.lines + 1] = sanitized
        return sanitized
    end
    return nil
end

local function parseTooltip(unit)
    local info = {
        hasQuestObjective = false,
        hasCompletedObjective = false,
        questIDs = {},
        lines = {},
        normalizedLines = nil,
        hiddenLineCount = 0,
    }

    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = C_TooltipInfo.GetUnit(unit)
        if data then
            for _, line in ipairs(data.lines) do
                local lineType = line.type
                -- Restricted tooltips can hide everything from addons; nothing after this is readable either.
                if isSecretValue(lineType) then
                    break
                end

                if QUEST_OBJECTIVE_LINE then
                    if lineType == QUEST_TITLE_LINE then
                        local questID = readable(line.id)
                        if type(questID) == "number" then
                            info.questIDs[#info.questIDs + 1] = questID
                        end
                        addTextLine(info, line.leftText)
                    elseif lineType == QUEST_OBJECTIVE_LINE then
                        recordObjective(info, isObjectiveLineCompleted(line))
                        addTextLine(info, line.leftText)
                    end
                else
                    -- Untyped tooltips: every line is a candidate title, and its text the only progress source.
                    local sanitized = addTextLine(info, line.leftText)
                    if sanitized then
                        readObjectiveProgress(info, sanitized)
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

-- State for the cache rebuilds below; module-level so their helpers aren't recreated
-- per rebuild. `building`/`buildingAdded` point at the cache currently being filled.
local building, buildingAdded, processedMaps = nil, nil, {}

local function determineWorldQuestFlag(questID, seedFlag)
    if seedFlag then
        return true
    end
    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
        return true
    end
    if questUtilsIsWorldQuest and questUtilsIsWorldQuest(questID) then
        return true
    end
    return false
end

-- seedQuestInfo: the quest's C_QuestLog.GetInfo table when the caller has it.
local function buildQuestEntry(questID, seedQuestInfo, seedIsWorldQuest, seedIsBonusObjective, seedHasQuestItem)
    if not questID or buildingAdded[questID] then
        return nil
    end

    if C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then
        buildingAdded[questID] = true
        return nil
    end

    local entry = {
        questID = questID,
        questName = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or "Unknown Quest",
        isWorldQuest = determineWorldQuestFlag(questID, seedIsWorldQuest),
        isBonusObjective = seedIsBonusObjective and true or false,
        normalizedQuestName = nil,
        hasQuestItem = seedHasQuestItem,
    }

    entry.normalizedQuestName = normalizeText(entry.questName)

    if questUtilsIsBonusObjective and questUtilsIsBonusObjective(questID) then
        entry.isBonusObjective = true
    end

    if not entry.isBonusObjective and C_QuestLog.IsBonusObjective then
        local ok, isBonus = pcall(C_QuestLog.IsBonusObjective, questID)
        if ok and isBonus then
            entry.isBonusObjective = true
        end
    end

    if not entry.isBonusObjective then
        local questInfo = seedQuestInfo
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

    if not entry.isBonusObjective and C_QuestLog.GetQuestTagInfo and Enum and Enum.QuestTagType and Enum.QuestTagType.BonusObjective then
        local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
        local tagID
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
        if safeContains(safeLower(entry.questName), "bonus objective") then
            entry.isBonusObjective = true
        end
    end

    buildingAdded[questID] = true
    return entry
end

local function addEntry(entry)
    if entry then
        buildingAdded[entry.questID] = true
        building[#building + 1] = entry
    end
end

-- Active world quests/tasks on a map and, recursively, its child zones.
local function processMap(mapID)
    if not mapID or processedMaps[mapID] then
        return
    end
    processedMaps[mapID] = true

    local tasks = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
    if tasks then
        for _, taskInfo in ipairs(tasks) do
            local questID = taskInfo.questId
            if questID then
                local isActive
                if C_TaskQuest.IsActive then
                    isActive = C_TaskQuest.IsActive(questID)
                else
                    isActive = taskInfo.inProgress ~= false
                end
                if isActive then
                    addEntry(buildQuestEntry(questID, nil, true, taskInfo.isBonusObjective, nil))
                end
            end
        end
    end

    if C_Map.GetMapChildrenInfo and Enum and Enum.UIMapType then
        local children = C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone, false)
        if children then
            for _, child in ipairs(children) do
                if child.mapID then
                    processMap(child.mapID)
                end
            end
        end
    end
end

local function rebuildLogCache(now)
    building, buildingAdded = {}, logCache.added
    wipe(buildingAdded)

    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            local hasQuestItem = getQuestLogSpecialItemInfo and getQuestLogSpecialItemInfo(index) ~= nil or false
            addEntry(buildQuestEntry(info.questID, info, info.isWorldQuest, info.isBonusObjective, hasQuestItem))
        end
    end

    logCache.entries = building
    logCache.timestamp = now
    building, buildingAdded = nil, nil
end

local function rebuildWorldCache(now, mapID)
    building, buildingAdded = {}, worldCache.added
    wipe(buildingAdded)
    wipe(processedMaps)

    if C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
        -- The player's map and its parents (up to 6 levels), each with its child zones.
        local currentMap = mapID
        local depth = 0
        while currentMap and depth < 6 do
            processMap(currentMap)
            local mapInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(currentMap)
            currentMap = mapInfo and mapInfo.parentMapID or nil
            depth = depth + 1
        end
    end

    worldCache.entries = building
    worldCache.timestamp = now
    worldCache.mapID = mapID
    building, buildingAdded = nil, nil
end

local function refreshQuestCache()
    if not C_QuestLog.GetNumQuestLogEntries then
        return questCache.entries
    end

    local now = GetTime()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local logStale = now - logCache.timestamp >= QUEST_CACHE_SECONDS
    local worldStale = now - worldCache.timestamp >= QUEST_CACHE_SECONDS or worldCache.mapID ~= mapID
    if not (logStale or worldStale) then
        return questCache.entries
    end

    if logStale then
        rebuildLogCache(now)
    end
    if worldStale then
        rebuildWorldCache(now, mapID)
    end

    -- Log entries first; a world quest also in the log (including a completed one,
    -- which the log pass records but leaves out) keeps its log entry.
    local merged = {}
    for _, entry in ipairs(logCache.entries) do
        merged[#merged + 1] = entry
    end
    for _, entry in ipairs(worldCache.entries) do
        if not logCache.added[entry.questID] then
            merged[#merged + 1] = entry
        end
    end

    questCache.entries = merged
    questCache.timestamp = now
    return merged
end

local function matchQuestFromTooltip(unit, tooltipInfo, questEntries)
    if not questEntries or #questEntries == 0 then
        return nil, nil
    end

    local unitIsRelatedToQuest = C_QuestLog.UnitIsRelatedToQuest
    if unit and unitIsRelatedToQuest then
        for _, entry in ipairs(questEntries) do
            if entry.questID then
                local related = readable(unitIsRelatedToQuest(unit, entry.questID))
                if related then
                    return entry, "unit-related"
                end
            end
        end
    end

    if not tooltipInfo then
        return nil, nil
    end

    -- Quest title lines carry the quest's ID, an exact match where the title text is only a fuzzy one.
    for _, questID in ipairs(tooltipInfo.questIDs) do
        for _, entry in ipairs(questEntries) do
            if entry.questID == questID then
                return entry, "tooltip-id"
            end
        end
    end

    local normalizedTooltipLines = tooltipInfo.normalizedLines

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
    if isSecretValue(unitName) then
        -- Identity hidden on restricted maps; the tooltip's line types can still mark a quest target.
        unitName = "<hidden by game>"
    elseif type(unitName) ~= "string" then
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
    local isQuestBoss = UnitIsQuestBoss and readable(UnitIsQuestBoss(unit))

    local classification = UnitClassification and readable(UnitClassification(unit))
    local isRare = classification == "rare" or classification == "rareelite" or classification == "elite"

    local reason
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
        hiddenTooltipLines = tooltipInfo.hiddenLineCount,
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

-- Reused every pass; entries are only read during that pass.
local units = {}

local function isRelevantUnit(unitToken)
    if not unitToken or not UnitExists(unitToken) then
        return false
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unitToken) then
        return false
    end
    local reaction = UnitReaction and UnitReaction(unitToken, "player")
    return not (reaction and reaction > 4)
end

local function getRelevantUnits()
    -- Only units with a nameplate: without one there is no health bar to highlight.
    local count = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.displayedUnit)
            if isRelevantUnit(token) then
                count = count + 1
                local entry = units[count]
                if not entry then
                    entry = {}
                    units[count] = entry
                end
                entry.unit, entry.frame = token, plate
            end
        end
    end
    for i = count + 1, #units do
        units[i] = nil
    end

    return units
end

function Nameplates:GetRelevantUnits()
    return getRelevantUnits()
end

function Nameplates:ClassifyUnit(unitData)
    return classifyUnit(unitData)
end

-- includeWorldQuests: also rescan world quests (see resetCaches).
function Nameplates:ResetCaches(includeWorldQuests)
    resetCaches(includeWorldQuests)
end
