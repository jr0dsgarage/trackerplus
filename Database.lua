---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Database version for future migrations
local DB_VERSION = 1

-- Default settings
local DEFAULTS = {
    enabled = true,
    locked = false,
    
    -- Frame Position & Size
    framePosition = nil,  -- {point, x, y}
    frameWidth = 250,
    frameHeight = 400,
    frameScale = 1.0,
    
    -- Appearance
    backgroundColor = {r = 0, g = 0, b = 0, a = 0.7},
    borderEnabled = false,
    borderColor = {r = 1, g = 1, b = 1, a = 1},
    borderSize = 1,
    headerIconStyle = "standard", -- "none", "standard", "square", "text_brackets", "questlog"
    headerIconPosition = "left", -- "left", "right"
    headerBackgroundStyle = "tracker", -- "none", "questlog", "tracker"
    
    -- Font Settings
    fontSize = 12,
    fontFace = "Fonts\\FRIZQT__.TTF",
    fontOutline = "OUTLINE",
    
    -- Header Font
    headerFontSize = 14,
    headerFontFace = "Fonts\\FRIZQT__.TTF",
    headerFontOutline = "OUTLINE",
    
    -- Colors
    headerColor = {r = 1, g = 0.82, b = 0, a = 1},  -- Gold
    questColor = {r = 1, g = 1, b = 1, a = 1},       -- White
    objectiveColor = {r = 0.9, g = 0.9, b = 0.9, a = 1},  -- Light gray
    completeColor = {r = 0, g = 1, b = 0, a = 1},    -- Green
    failedColor = {r = 1, g = 0, b = 0, a = 1},      -- Red
    
    -- Display Options
    showQuestLevel = true,
    showQuestType = true,
    showZoneHeaders = true,
    showDistance = true,
    collapseCompleted = false,
    
    -- Grouping & Sorting
    groupByZone = true,
    groupByCategory = true,
    sortMethod = "distance",  -- "distance", "level", "name", "manual"
    
    -- State
    collapsedHeaders = {},
    
    -- Trackable Types
    showQuests = true,
    showAchievements = true,
    showWorldQuests = true,
    showBonusObjectives = true,
    showProfessions = true,
    showScenarios = true,
    showDungeonObjectives = true,
    showMonthlyActivities = true,
    showEndeavors = true,
    
    -- Advanced Features
    autoTrackQuests = false,
    maxTrackedQuests = 25,
    hideInInstance = false,
    hideInCombat = false,
    fadeWhenEmpty = true,
    
    -- Quest Type Colors
    questTypeColors = {
        normal = {r = 1, g = 0.82, b = 0, a = 1},
        elite = {r = 1, g = 0.5, b = 0, a = 1},
        dungeon = {r = 0.5, g = 0.5, b = 1, a = 1},
        raid = {r = 1, g = 0, b = 1, a = 1},
        pvp = {r = 1, g = 0.1, b = 0.1, a = 1},
        legendary = {r = 1, g = 0.5, b = 0, a = 1},
        artifact = {r = 0.9, g = 0.8, b = 0.5, a = 1},
        worldQuest = {r = 0.25, g = 0.78, b = 0.92, a = 1},
        profession = {r = 0.5, g = 1, b = 0.5, a = 1},
    },
    
    -- Interaction
    clickToTrack = true,
    showTooltips = true,
    
    -- Performance
    updateInterval = 0.1,
    
    -- Spacing & Layout
    spacingMajorHeaderIndent = 0,      -- Indent for major category headers (Quests, Achievements, etc.)
    spacingMinorHeaderIndent = 5,      -- Indent for minor zone headers
    spacingTrackableIndent = 10,       -- Indent for quest/achievement items
    spacingPOIButton = 16,             -- Left padding when POI button is present
    spacingItemButton = 20,            -- Additional padding when item button exists
    spacingObjectiveIndent = 0,        -- Additional indent for objectives (relative to parent)
    spacingItemVertical = 4,           -- Vertical spacing between trackable items
    spacingMajorHeaderAfter = 26,      -- Vertical space after major headers
    spacingMinorHeaderAfter = 22,      -- Vertical space after minor headers
    spacingProgressBarInset = 20,      -- Horizontal inset for progress bars from edges
}

-- Deep copy helper
local function DeepCopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[DeepCopy(orig_key, copies)] = DeepCopy(orig_value, copies)
            end
            setmetatable(copy, DeepCopy(getmetatable(orig), copies))
        end
    else
        copy = orig
    end
    return copy
end

-- Initialize database
function addon:InitDatabase()
    -- Create saved variables table if it doesn't exist
    if not TrackerPlusDB then
        TrackerPlusDB = {}
    end
    
    -- Set database version
    TrackerPlusDB.version = DB_VERSION
    
    -- Initialize settings with defaults
    if not TrackerPlusDB.settings then
        TrackerPlusDB.settings = DeepCopy(DEFAULTS)
    else
        -- Merge any new defaults
        for key, value in pairs(DEFAULTS) do
            if TrackerPlusDB.settings[key] == nil then
                TrackerPlusDB.settings[key] = DeepCopy(value)
            end
        end
        
        -- Fix legacy font paths (Migration)
        if TrackerPlusDB.settings.fontFace == "Friz Quadrata TT" then
            TrackerPlusDB.settings.fontFace = "Fonts\\FRIZQT__.TTF"
        end
        if TrackerPlusDB.settings.headerFontFace == "Friz Quadrata TT" then
            TrackerPlusDB.settings.headerFontFace = "Fonts\\FRIZQT__.TTF"
        end
    end
    
    -- Create reference to settings
    addon.db = TrackerPlusDB.settings
    addon.DEFAULTS = DEFAULTS
end

-- Reset settings to defaults
function addon:ResetDatabase()
    TrackerPlusDB.settings = DeepCopy(DEFAULTS)
    addon.db = TrackerPlusDB.settings
end

-- Get a setting value
function addon:GetSetting(key)
    return addon.db[key]
end

-- Set a setting value
function addon:SetSetting(key, value)
    addon.db[key] = value
end

-- Table utilities
function addon:TableCount(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

function addon:TableContains(t, value)
    for _, v in pairs(t) do
        if v == value then
            return true
        end
    end
    return false
end

-- Color utilities
function addon:ColorToHex(r, g, b)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function addon:ColorText(text, r, g, b)
    return addon:ColorToHex(r, g, b) .. text .. "|r"
end
