---@diagnostic disable: undefined-global
local _, addon = ...

-- Quest title colors: difficulty coloring and the super-track override (also used by map pins).

-- Localize hot-path globals to avoid repeated global lookups
local next = next
local type = type
local band = bit.band
local UnitLevel = UnitLevel
local C_QuestLog = C_QuestLog
local C_SuperTrack = C_SuperTrack

-- The game's own relative-difficulty rating for a quest, as a QuestDifficultyColors
-- entry, or nil when this client can't supply one.
--
-- This is the source to prefer, and on this client it is the only one that works.
-- GetQuestDifficultyColor compares raw levels and reaches its green band only via
-- GetQuestGreenRange, which returns nil here -- so that function returns gold for
-- everything from four levels below the player up to two above, then drops straight
-- to grey, and can never return green at all. It is also level-based, so it cannot
-- rate a scaling quest correctly even in principle.
-- C_PlayerInfo.GetContentDifficultyQuestForPlayer instead asks the game how hard the
-- quest is *for this player*, scaling included, which is what the quest log shows.
--
-- The enum is mapped by member name rather than by number so that a client which
-- numbers or names these differently degrades to the fallback instead of mis-coloring.
local relativeDifficultyKeys

local function GetRelativeDifficultyKeys()
    if relativeDifficultyKeys ~= nil then
        return relativeDifficultyKeys
    end

    local ratings = Enum and Enum.RelativeContentDifficulty
    if not ratings then
        relativeDifficultyKeys = false
        return false
    end

    local keys = {}
    local function Map(member, colorKey)
        local rating = ratings[member]
        if rating ~= nil then
            keys[rating] = colorKey
        end
    end

    Map("Trivial", "trivial")
    Map("Easy", "standard")
    Map("Fair", "difficult")
    Map("Difficult", "verydifficult")
    Map("Impossible", "impossible")

    relativeDifficultyKeys = next(keys) and keys or false
    return relativeDifficultyKeys
end

local function GetRelativeDifficultyColor(questID)
    if not questID or questID == 0 then return nil end

    local rate = C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer
    if not rate then return nil end

    local keys = GetRelativeDifficultyKeys()
    if not keys then return nil end

    local ok, rating = pcall(rate, questID)
    if not ok or rating == nil then return nil end

    local colorKey = keys[rating]
    return colorKey and QuestDifficultyColors and QuestDifficultyColors[colorKey] or nil
end

-- The game's difficulty color for a quest level, or nil if it can't be determined.
--
-- GetQuestDifficultyColor is looked up on every call rather than localized at the top
-- of this file like the other globals. Localizing it there is what broke difficulty
-- coloring outright: the global is not guaranteed to exist by the time this file
-- loads, and the nil captured then stayed nil for the whole session, so the branch
-- guarding on it never ran and every quest title fell through to the flat quest
-- color. A per-call global lookup is a rounding error next to the render work.
--
-- When the client has no such global at all, the thresholds below reproduce what that
-- function does, reading the palette from the game's own QuestDifficultyColors table
-- and the green cutoff from its own GetQuestGreenRange -- so the colors and the
-- boundaries still come from the game, never from an addon-side palette.
local function GetDifficultyColorForLevel(level)
    local fromGame = GetQuestDifficultyColor
    if type(fromGame) == "function" then
        local ok, color = pcall(fromGame, level)
        if ok and color and color.r then
            return color
        end
    end

    local colors = QuestDifficultyColors
    if not colors then return nil end

    local levelDiff = level - (UnitLevel("player") or 0)
    if levelDiff >= 5 then
        return colors.impossible
    elseif levelDiff >= 3 then
        return colors.verydifficult
    elseif levelDiff >= -2 then
        return colors.difficult
    end

    -- How far below the player a quest can be and still count as green varies with
    -- level, so ask the game. Older clients take no argument, newer ones take a unit.
    local greenRange
    if GetQuestGreenRange then
        local ok, range = pcall(GetQuestGreenRange, "player")
        if not (ok and type(range) == "number") then
            ok, range = pcall(GetQuestGreenRange)
        end
        if ok and type(range) == "number" then
            greenRange = range
        end
    end

    -- Absent the API, the low-level band is the best single guess available.
    if -levelDiff <= (greenRange or 5) then
        return colors.standard
    end
    return colors.trivial
end

-- Get quest color based on type/status
--
-- Note there is deliberately no "quest is complete" branch here. A quest's title --
-- and, through GetQuestTitleColorByQuestID, its map pin -- keeps showing the level
-- difference right up to turn-in, because that is the thing the color is for.
-- db.completeColor stays green for what it actually describes: an objective line that
-- is done (see RenderItem.lua). Completion is already unmistakable from the POI icon,
-- which the game swaps to the turn-in mark on its own.
function addon:GetQuestColor(info)
    local db = self.db
    local questID = info.questID
    if info.isFailed then
        return db.failedColor
    elseif C_QuestLog.IsWorldQuest(questID) then
        return db.questTypeColors.worldQuest
    elseif C_QuestLog.IsQuestTask(questID) then
        return db.bonusColor
    elseif db.colorQuestsByDifficulty then
        -- Ask the game how hard this quest is for the player first; only fall back to
        -- comparing levels ourselves on a client that can't answer.
        local color = GetRelativeDifficultyColor(questID)
        if not color then
            local level = tonumber(info.level) or tonumber(info.difficultyLevel)
            if level and level > 0 then
                color = GetDifficultyColorForLevel(level)
            end
        end

        if color and color.r then
            return { r = color.r, g = color.g, b = color.b, a = 1 }
        end
        return db.questColor
    else
        return db.questColor
    end
end

-- Gold: what the tracker paints whichever quest is currently super-tracked, whatever
-- that quest's own difficulty or status color would otherwise be.
local SUPER_TRACKED_TITLE_COLOR = { r = 1, g = 0.82, b = 0, a = 1 }

-- Whichever quest is super-tracked right now, or 0.
function addon:GetSuperTrackedQuestID()
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        return C_SuperTrack.GetSuperTrackedQuestID() or 0
    end
    return self._cachedSuperTrackedQuestID or 0
end

-- The color a quest's title is *actually* painted with: GetQuestColor's answer, with
-- the super-track gold laid over the top.
--
-- This last step belongs here rather than in the row renderer because the map pins
-- need the same final color. While the override lived inline in RenderTrackableItem,
-- super-tracking a completed quest painted the tracker title gold but left the pin
-- the green GetQuestColor returns for completed quests -- which is the very same
-- db.completeColor that finished objective lines use, so the pin looked like it was
-- picking up an objective's color rather than the title's.
--
-- Pass superTrackedQuestID when the caller already has it (the row renderer caches it
-- once per pass) to keep it out of per-row work.
function addon:ApplySuperTrackedTitleColor(questID, color, superTrackedQuestID)
    if not questID or questID == 0 then return color end

    superTrackedQuestID = superTrackedQuestID or self:GetSuperTrackedQuestID()
    if questID == superTrackedQuestID then
        return SUPER_TRACKED_TITLE_COLOR
    end

    return color
end

-- The same color, for a quest known only by its ID.
--
-- GetQuestColor works from the C_QuestLog.GetInfo table the collection pass already
-- holds. Callers outside that pass -- the world map pins -- only have a questID, so
-- rebuild that input rather than duplicating the color rules and letting the two
-- drift apart. A quest the map pins but the log no longer lists falls back to the
-- client's own difficulty level for it.
function addon:GetQuestColorByQuestID(questID)
    if not questID then return nil end

    local logIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
    if logIndex then
        local info = C_QuestLog.GetInfo(logIndex)
        if info and info.questID == questID then
            return self:GetQuestColor(info)
        end
    end

    local level = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(questID)
    level = tonumber(level) or 0
    return self:GetQuestColor({ questID = questID, level = level, difficultyLevel = level })
end

-- Same, but carrying the super-track override, so callers outside the render pass end
-- up with the color the tracker row is showing rather than the one underneath it.
function addon:GetQuestTitleColorByQuestID(questID)
    return self:ApplySuperTrackedTitleColor(questID, self:GetQuestColorByQuestID(questID))
end
