---@diagnostic disable: undefined-global
local _, TrackerPlus = ...
TrackerPlus.Nameplates = TrackerPlus.Nameplates or {}
local Nameplates = TrackerPlus.Nameplates

local DEFAULTS = {
    enabled = true,
    debugMode = false,
    hideLevelBadgeBorder = true,
    -- Blizzard's target/focus health bar border on nameplates this module isn't styling:
    fixDefaultBorderOffset = false, -- redraw it (and the level badge's) with its top edge 1px lower
    hideDefaultBorder = false,      -- hide the health bar's
    currentTargetEnabled = true,
    currentTargetColor = { r = 0, g = 1, b = 0, a = 0.8 },
    currentTargetThickness = 2,
    currentTargetOffset = 0,
    currentTargetStyle = "rounded",
    -- Objectives of the Active (super-tracked) quest; overrides the other quest styles, but never the current target.
    activeQuestEnabled = true,
    -- The tracker's quest-area highlight blue (questAreaHighlightColor in Database.lua).
    activeQuestColor = { r = 0.30, g = 0.58, b = 1, a = 1 },
    activeQuestThickness = 3,
    activeQuestOffset = 0,
    activeQuestStyle = "rounded",
    questObjectiveEnabled = true,
    questObjectiveColor = { r = 1, g = 1, b = 0, a = 0.9 },
    questObjectiveThickness = 3,
    questObjectiveOffset = 0,
    questObjectiveStyle = "rounded",
    questItemEnabled = true,
    questItemColor = { r = 0, g = 1, b = 1, a = 0.9 },  -- Cyan
    questItemThickness = 3,
    questItemOffset = 0,
    questItemStyle = "rounded",
    worldQuestEnabled = true,
    worldQuestColor = { r = 0.3, g = 0.7, b = 1, a = 0.9 },
    worldQuestThickness = 3,
    worldQuestOffset = 0,
    worldQuestStyle = "rounded",
    bonusObjectiveEnabled = true,
    bonusObjectiveColor = { r = 1, g = 0.41, b = 0.71, a = 0.9 },
    bonusObjectiveThickness = 3,
    bonusObjectiveOffset = 0,
    bonusObjectiveStyle = "rounded",
}

-- Highlights for features Forever doesn't have; turned off there (and their rows left
-- out of the Nameplates page), like RETAIL_ONLY_SETTINGS in Database.lua.
local RETAIL_ONLY_KEYS = {
    "worldQuestEnabled",
    "bonusObjectiveEnabled",
}

local deepCopy = TrackerPlus.DeepCopy

local function mergeDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = deepCopy(value)
            else
                mergeDefaults(target[key], value)
            end
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function Nameplates:InitializeDB()
    -- Stored beside TrackerPlus's own settings, which InitDatabase keeps under TrackerPlusDB.settings.
    TrackerPlusDB = TrackerPlusDB or {}

    TrackerPlusDB.nameplates = TrackerPlusDB.nameplates or {}
    Nameplates.db = TrackerPlusDB.nameplates

    -- Always merge in any new defaults (doesn't overwrite existing values)
    mergeDefaults(Nameplates.db, DEFAULTS)

    if not TrackerPlus.IsRetail then
        for _, key in ipairs(RETAIL_ONLY_KEYS) do
            Nameplates.db[key] = false
        end
    end
end

-- Replaces the settings with a fresh copy of the defaults.
function Nameplates:ResetDB()
    TrackerPlusDB.nameplates = nil
    self:InitializeDB()
end
