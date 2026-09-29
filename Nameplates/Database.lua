---@diagnostic disable: undefined-global
local _, TrackerPlus = ...
TrackerPlus.Nameplates = TrackerPlus.Nameplates or {}
local Nameplates = TrackerPlus.Nameplates

-- Current database version - increment when migrations are added
local DB_VERSION = 2

local DEFAULTS = {
    enabled = true,
    debugMode = false,
    debugFramePosition = nil,
    hideLevelBadgeBorder = true,
    -- Blizzard's target/focus border on nameplates this module isn't styling:
    fixDefaultBorderOffset = false, -- redraw it evenly in Blizzard's color (our own styles are unaffected)
    hideDefaultBorder = false,      -- hide the health bar's (the level badge still gets the offset fix)
    currentTargetEnabled = true,
    currentTargetColor = { r = 0, g = 1, b = 0, a = 0.8 },
    currentTargetThickness = 2,
    currentTargetOffset = 0,
    currentTargetStyle = "blizzard",
    questObjectiveEnabled = true,
    questObjectiveColor = { r = 1, g = 1, b = 0, a = 0.9 },
    questObjectiveThickness = 3,
    questObjectiveOffset = 0,
    questObjectiveStyle = "blizzard",
    questItemEnabled = true,
    questItemColor = { r = 0, g = 1, b = 1, a = 0.9 },  -- Cyan
    questItemThickness = 3,
    questItemOffset = 0,
    questItemStyle = "blizzard",
    worldQuestEnabled = true,
    worldQuestColor = { r = 0.3, g = 0.7, b = 1, a = 0.9 },
    worldQuestThickness = 3,
    worldQuestOffset = 0,
    worldQuestStyle = "blizzard",
    bonusObjectiveEnabled = true,
    bonusObjectiveColor = { r = 1, g = 0.41, b = 0.71, a = 0.9 },
    bonusObjectiveThickness = 3,
    bonusObjectiveOffset = 0,
    bonusObjectiveStyle = "blizzard",
}

local MIGRATION_MAP = {
    showCurrentTarget = "currentTargetEnabled",
    showQuestObjective = "questObjectiveEnabled",
    showQuestItem = "questItemEnabled",
    showWorldQuestHighlight = "worldQuestEnabled",
    currentBorderThickness = "currentTargetThickness",
    currentBorderOffset = "currentTargetOffset",
    questObjectiveBorderThickness = "questObjectiveThickness",
    questObjectiveBorderOffset = "questObjectiveOffset",
    questItemBorderThickness = "questItemThickness",
    questItemBorderOffset = "questItemOffset",
    worldQuestBorderThickness = "worldQuestThickness",
    worldQuestBorderOffset = "worldQuestOffset",
}

local STYLE_KEYS = {
    "currentTargetStyle",
    "questObjectiveStyle",
    "questItemStyle",
    "worldQuestStyle",
    "bonusObjectiveStyle",
    "mythicObjectiveStyle",
}

local function cloneTable(source)
    if type(source) ~= "table" then
        return source
    end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = cloneTable(value)
    end
    return copy
end

local function mergeDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = cloneTable(value)
            else
                mergeDefaults(target[key], value)
            end
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function wipeTable(tbl)
    if table.wipe then
        table.wipe(tbl)
    elseif type(wipe) == "function" then
        wipe(tbl)
    else
        for key in pairs(tbl) do
            tbl[key] = nil
        end
    end
end
Nameplates.WipeTable = wipeTable

local function sanitizeCommand(text)
    if not text then
        return ""
    end
    return text:match("^%s*(.-)%s*$") or ""
end
Nameplates.SanitizeCommand = sanitizeCommand

function Nameplates:GetDefault(key)
    return cloneTable(DEFAULTS[key])
end

function Nameplates:InitializeDB()
    -- Stored beside TrackerPlus's own settings, which InitDatabase keeps under TrackerPlusDB.settings.
    TrackerPlusDB = TrackerPlusDB or {}

    -- One-time import from the standalone addon this module used to be. NextTargetDB is only loaded
    -- because TrackerPlus.toc lists it; drop it from ## SavedVariables once players have migrated.
    if TrackerPlusDB.nameplates == nil and type(NextTargetDB) == "table" then
        TrackerPlusDB.nameplates = NextTargetDB
    end
    NextTargetDB = nil

    TrackerPlusDB.nameplates = TrackerPlusDB.nameplates or {}
    Nameplates.db = TrackerPlusDB.nameplates

    -- Only run migrations if database version is outdated or missing
    local currentVersion = Nameplates.db.dbVersion or 0
    if currentVersion < DB_VERSION then
        -- Migration: Rename old keys to new keys
        for oldKey, newKey in pairs(MIGRATION_MAP) do
            if Nameplates.db[oldKey] ~= nil and Nameplates.db[newKey] == nil then
                Nameplates.db[newKey] = Nameplates.db[oldKey]
            end
            Nameplates.db[oldKey] = nil
        end

        -- Migration: Rename "border" style to "outline"
        for _, styleKey in ipairs(STYLE_KEYS) do
            if Nameplates.db[styleKey] == "border" then
                Nameplates.db[styleKey] = "outline"
            end
        end

        -- Migration: Remove deprecated settings
        Nameplates.db.rareEliteEnabled = nil
        Nameplates.db.rareEliteColor = nil
        Nameplates.db.rareEliteThickness = nil
        Nameplates.db.rareEliteOffset = nil
        Nameplates.db.onlyInCombat = nil
        Nameplates.db.currentTargetAlways = nil

        -- Migration: Fix old orange quest color to new yellow
        local questColor = Nameplates.db.questObjectiveColor
        if questColor and questColor.r == 1 and questColor.g == 0.5 and questColor.b == 0 then
            questColor.r = DEFAULTS.questObjectiveColor.r
            questColor.g = DEFAULTS.questObjectiveColor.g
            questColor.b = DEFAULTS.questObjectiveColor.b
            questColor.a = DEFAULTS.questObjectiveColor.a
        end

        -- Mark database as migrated
        Nameplates.db.dbVersion = DB_VERSION
    end

    -- Always merge in any new defaults (doesn't overwrite existing values)
    mergeDefaults(Nameplates.db, DEFAULTS)
end
