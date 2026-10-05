---@diagnostic disable: undefined-global
local _, addon = ...

-- Ordering of trackables within their groups (Settings > Tracking > Sort Order).

-- Localize hot-path globals to avoid repeated global lookups
local type = type
local wipe = wipe
local huge = math.huge
local UnitLevel = UnitLevel
local C_QuestLog = C_QuestLog

-- Distance from the player to a trackable's objective, as a squared value (the
-- game returns squared distance; we never need the real distance, only an
-- ordering, so there's no point taking a square root). Unreachable or unknown
-- objectives return huge so they sort last.
function addon:GetTrackableSortDistance(item)
    local questID = item and (item.id or item.questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetDistanceSqToQuest then
        return huge
    end

    -- Documented as possibly returning nothing, so guard the call and the result.
    local ok, distanceSq, onContinent = pcall(C_QuestLog.GetDistanceSqToQuest, questID)
    if not ok or type(distanceSq) ~= "number" then
        return huge
    end

    -- A NaN would make the comparator inconsistent, which makes table.sort raise a
    -- hard error and take the whole render with it.
    if distanceSq ~= distanceSq then
        return huge
    end

    -- Objectives on another continent sort after anything we can walk to.
    if onContinent == false then
        return huge
    end

    return distanceSq
end

-- How hard a trackable is relative to the player, expressed as a level delta.
-- Higher means harder. This is the same quantity the game's difficulty colors are
-- thresholds on, so the sort order lines up with the colors shown on each row.
-- Trackables without a real level (achievements, professions, scaling quests) are
-- treated as being at the player's level.
function addon:GetTrackableSortDifficulty(item, playerLevel)
    -- difficultyLevel is the scaling-aware level, so prefer it; level is what the
    -- title displays and the two diverge on scaling quests.
    local level = item and (tonumber(item.difficultyLevel) or tonumber(item.level))
    if not level or level <= 0 then
        return 0
    end
    return level - (playerLevel or 0)
end

-- Sort trackables
function addon:SortTrackables(trackables)
    local sortMethod = self.db.sortMethod
    if sortMethod ~= "proximity" and sortMethod ~= "alphabetical" and sortMethod ~= "difficulty_desc" then
        -- Easiest-first difficulty is the default, and the fallback for any legacy
        -- or unrecognised value.
        sortMethod = "difficulty_asc"
    end

    local isProximity = (sortMethod == "proximity")
    local isAlphabetical = (sortMethod == "alphabetical")
    local isDifficulty = not isProximity and not isAlphabetical
    local difficultyDescending = (sortMethod == "difficulty_desc")

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

    -- Precompute each entry's sort key. table.sort calls the comparator O(n log n)
    -- times and these keys come from API calls, so computing them inside the
    -- comparator would hit the distance API dozens of times per quest.
    self._sortPriority = self._sortPriority or {}
    self._sortValue = self._sortValue or {}
    local priorities, values = self._sortPriority, self._sortValue
    wipe(priorities)
    wipe(values)

    local playerLevel = (UnitLevel and UnitLevel("player")) or 0

    for i = 1, #trackables do
        local item = trackables[i]
        priorities[item] = GetPriority(item)
        if isProximity then
            values[item] = self:GetTrackableSortDistance(item)
        elseif isDifficulty then
            values[item] = self:GetTrackableSortDifficulty(item, playerLevel)
        end
    end

    table.sort(trackables, function(a, b)
        local prioA = priorities[a] or 3
        local prioB = priorities[b] or 3

        if prioA ~= prioB then
            return prioA < prioB
        end

        if isProximity then
            -- Nearest first.
            local distA, distB = values[a] or huge, values[b] or huge
            if distA ~= distB then
                return distA < distB
            end
        elseif isDifficulty then
            local diffA, diffB = values[a] or 0, values[b] or 0
            if diffA ~= diffB then
                if difficultyDescending then
                    -- Hardest first; trivial/grey quests sink to the bottom.
                    return diffA > diffB
                end
                -- Easiest first, so the quickest quests to clear are at the top.
                return diffA < diffB
            end
        end

        -- Alphabetical, and the stable tiebreak for the other two orders.
        return (a.title or "") < (b.title or "")
    end)
end
