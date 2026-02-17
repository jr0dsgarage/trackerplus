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
    
    -- Trackable Type Colors
    achievementColor = {r = 1, g = 0.82, b = 0, a = 1},     -- Gold/Yellow
    scenarioColor = {r = 1, g = 1, b = 1, a = 1},           -- White
    bonusColor = {r = 1, g = 1, b = 1, a = 1},              -- White
    professionColor = {r = 0.5, g = 1, b = 0.5, a = 1},     -- Greenish
    monthlyColor = {r = 0.4, g = 0.6, b = 1, a = 1},        -- Blue
    endeavorColor = {r = 1, g = 0.4, b = 0.8, a = 1},       -- Pink
    
    -- Display Options
    showQuestLevel = true,
    showZoneHeaders = true,
    collapseCompleted = false,
    
    -- Grouping & Sorting
    groupByZone = true,
    groupByCategory = true,
    sortMethod = "name",  -- "level", "name", "manual"
    
    -- State
    collapsedHeaders = {},
    collapsedSections = {},
    
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
    updateInterval = 0.15,
    
    -- Cache
    endeavorCache = {}, -- Stores last known tracked endeavors {id=true}
    
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
    spacingProgressBarPadding = 5,     -- Vertical padding above progress bars (below text)
    
    -- Progress Bar Styling
    barTexture = "Blizzard",          -- Texture for progress bars
    barBorderSize = 1,                -- Border thickness in pixels (0 hides border)
    barBackgroundColor = {r = 0, g = 0, b = 0, a = 0.5}, -- Background color of progress bars
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

        -- Migration: distance sort removed
        if TrackerPlusDB.settings.sortMethod == "distance" then
            TrackerPlusDB.settings.sortMethod = "name"
        end

        -- Migration: distance tracking removed
        TrackerPlusDB.settings.showDistance = nil

        -- Migration: quest type toggle removed
        TrackerPlusDB.settings.showQuestType = nil

        -- Migration: clamp bar border size to new 0..10 range
        if TrackerPlusDB.settings.barBorderSize == nil then
            TrackerPlusDB.settings.barBorderSize = DEFAULTS.barBorderSize
        elseif TrackerPlusDB.settings.barBorderSize < 0 then
            TrackerPlusDB.settings.barBorderSize = 0
        elseif TrackerPlusDB.settings.barBorderSize > 10 then
            TrackerPlusDB.settings.barBorderSize = 10
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


