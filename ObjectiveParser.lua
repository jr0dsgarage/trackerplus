local addonName, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Localize hot-path globals
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local format, match = string.format, string.match
local max, floor = math.max, math.floor

-------------------------------------------------------------------------------
-- Objective parse cache
-------------------------------------------------------------------------------
local objectiveParseCache = {}
local objectiveParseCacheCount = 0

local function GetObjectiveParseKey(item, obj, objIndex)
    -- Use only safe, immutable values (id, objIndex, numbers) to avoid tainting.
    -- Never include obj.text or obj.quantityString as they come from protected frames.
    return table.concat({
        tostring(item.id or 0),
        tostring(objIndex),
        tostring(obj.type or ""),
        tostring(obj.numFulfilled or 0),
        tostring(obj.numRequired or 0),
    }, "\31")
end

-------------------------------------------------------------------------------
-- ParseObjectiveDisplay  (exposed as addon.ParseObjectiveDisplay)
-------------------------------------------------------------------------------
function addon.ParseObjectiveDisplay(item, obj, objIndex)
    local useCache = (obj and obj.type ~= "progressbar")
    local cacheKey
    if useCache then
        cacheKey = GetObjectiveParseKey(item, obj, objIndex)
        local cached = objectiveParseCache[cacheKey]
        if cached then
            return cached
        end
    end

    local parsed = {
        prefixText = "",
        bodyText = "",
        isProgressBar = false,
        progressValue = 0,
        progressMax = 100,
    }

    local required = tonumber(obj.numRequired)
    local fulfilled = tonumber(obj.numFulfilled)

    if obj.type == "progressbar" then
        parsed.isProgressBar = true

        -- Follow Blizzard's task progress source when available.
        if C_TaskQuest and C_TaskQuest.GetQuestProgressBarInfo and item and item.id then
            local taskProgress = C_TaskQuest.GetQuestProgressBarInfo(item.id)
            if taskProgress ~= nil then
                parsed.progressValue = tonumber(taskProgress) or 0
                parsed.progressMax = 100
            else
                -- Fallback to explicit objective percentage if provided by Blizzard objective text.
                local percentMatch = string.match(obj.quantityString or "", "(%d+)%%")
                if not percentMatch then
                    percentMatch = string.match(obj.text or "", "(%d+)%%")
                end
                if percentMatch then
                    parsed.progressValue = tonumber(percentMatch) or 0
                    parsed.progressMax = 100
                elseif required and required > 0 then
                    parsed.progressValue = fulfilled or 0
                    parsed.progressMax = required
                else
                    local ratioFulfilled, ratioRequired = string.match(obj.quantityString or "", "(%d+)%s*/%s*(%d+)")
                    if not ratioFulfilled then
                        ratioFulfilled, ratioRequired = string.match(obj.text or "", "(%d+)%s*/%s*(%d+)")
                    end
                    if ratioFulfilled and ratioRequired then
                        parsed.progressValue = tonumber(ratioFulfilled) or 0
                        parsed.progressMax = tonumber(ratioRequired) or 100
                    else
                        parsed.progressValue = fulfilled or 0
                        parsed.progressMax = 100
                    end
                end
            end
        elseif required and required > 0 then
            parsed.progressValue = fulfilled or 0
            parsed.progressMax = required
        else
            local percentMatch = string.match(obj.quantityString or "", "(%d+)%%")
            if not percentMatch then
                percentMatch = string.match(obj.text or "", "(%d+)%%")
            end

            if percentMatch then
                parsed.progressValue = tonumber(percentMatch) or 0
                parsed.progressMax = 100
            else
                local ratioFulfilled, ratioRequired = string.match(obj.quantityString or "", "(%d+)%s*/%s*(%d+)")
                if not ratioFulfilled then
                    ratioFulfilled, ratioRequired = string.match(obj.text or "", "(%d+)%s*/%s*(%d+)")
                end

                if ratioFulfilled and ratioRequired then
                    parsed.progressValue = tonumber(ratioFulfilled) or 0
                    parsed.progressMax = tonumber(ratioRequired) or 100
                else
                    parsed.progressValue = fulfilled or 0
                    parsed.progressMax = 100
                end
            end
        end

        if parsed.progressMax <= 0 then parsed.progressMax = 100 end
        if parsed.progressValue < 0 then parsed.progressValue = 0 end
        if parsed.progressValue > parsed.progressMax then parsed.progressValue = parsed.progressMax end

        -- Follow Blizzard completion state for visibility, not just computed percentage.
        -- If Blizzard marks objective or quest complete, hide the progress bar row.
        local objectiveFinished = (obj.finished == true)
        local questFinished = (item and (item.isComplete == true or item.isFinished == true))
        if objectiveFinished or questFinished then
            parsed.isProgressBar = false
        end

        local cleanText = obj.text or ""
        cleanText = cleanText:gsub("%s*%(%d+%%%)", "")
        cleanText = cleanText:gsub("%s*%d+%%", "")
        cleanText = cleanText:gsub("^%d+/%d+%s*", "")
        cleanText = cleanText:gsub(":%s*$", "")
        cleanText = cleanText:gsub("^%s+", ""):gsub("%s+$", "")
        if cleanText == "" and obj.text then
            cleanText = obj.text:gsub("%s*%(%d+%%%)", "")
        end
        parsed.bodyText = (cleanText or "Progress")
    elseif obj.quantityString and obj.quantityString ~= "" then
        parsed.bodyText = (obj.text or ""):gsub("^%d+/%d+%s*", ""):gsub("^%s+", "")
        parsed.prefixText = obj.quantityString
    elseif obj.numRequired and obj.numRequired > 0 then
        parsed.bodyText = (obj.text or ""):gsub("^%d+/%d+%s*", ""):gsub("^%s+", "")
        parsed.prefixText = format("%d/%d", obj.numFulfilled or 0, obj.numRequired)
    else
        local p, b = (obj.text or ""):match("^%s*([%d]+/[%d]+)%s+(.*)$")
        if p then
            parsed.prefixText = p
            parsed.bodyText = b
        else
            parsed.bodyText = (obj.text or "")
        end
    end

    if parsed.prefixText ~= "" and (not parsed.bodyText or parsed.bodyText == "") then
        parsed.bodyText = " "
    end

    if useCache then
        objectiveParseCache[cacheKey] = parsed
        objectiveParseCacheCount = objectiveParseCacheCount + 1
        if objectiveParseCacheCount > 2000 then
            wipe(objectiveParseCache)
            objectiveParseCacheCount = 0
        end
    end

    return parsed
end

-------------------------------------------------------------------------------
-- ResolveTrackableItemData  (exposed as addon.ResolveTrackableItemData)
-------------------------------------------------------------------------------
function addon.ResolveTrackableItemData(item)
    if not item then return nil end

    local itemData = item.item
    if itemData and (itemData.link or itemData.texture) then
        return itemData
    end

    local logIndex = item.logIndex
    if (not logIndex or logIndex <= 0) and item.id and C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        logIndex = C_QuestLog.GetLogIndexForQuestID(item.id)
        if logIndex and logIndex > 0 then
            item.logIndex = logIndex
        end
    end

    if logIndex and logIndex > 0 then
        local itemLink, itemTexture = GetQuestLogSpecialItemInfo(logIndex)
        if itemLink or itemTexture then
            itemData = itemData or {}
            itemData.link = itemLink or itemData.link
            itemData.texture = itemTexture or itemData.texture
            item.item = itemData
        end
    end

    return item.item
end
