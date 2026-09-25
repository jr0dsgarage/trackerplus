---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Database version for future migrations
local DB_VERSION = 6

-- Default settings
local DEFAULTS = {
    enabled = true,
    locked = false,
    
    -- Frame Position & Size
    framePosition = nil,  -- {point, x, y}
    frameWidth = 250,
    frameHeight = 400,
    frameScale = 1.0,
    -- While true, the tracker mirrors the game's own objective tracker position and
    -- size (including changes made in the game's Edit Mode). Automatically cleared
    -- the first time the player drags or resizes the tracker themselves.
    matchBlizzardTracker = true,
    
    -- Appearance
    backgroundColor = {r = 0, g = 0, b = 0, a = 0.7},
    borderEnabled = false,
    borderColor = {r = 1, g = 1, b = 1, a = 1},
    borderSize = 1,
    headerIconStyle = "standard", -- "none", "standard", "square", "text_brackets", "questlog"
    headerIconPosition = "right", -- "left", "right"
    headerBackgroundStyle = "questlog", -- "none", "questlog", "tracker"
    
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
    colorQuestsByDifficulty = true, -- Color quest text using the client's own GetQuestDifficultyColor(level)
    colorMapPOIsByDifficulty = true, -- Outline the game's own world map quest pins in that same difficulty color
    mapPOIOutlineStyle = "glow", -- "glow" (the game's soft ring) or "circle" (hard ring)
    mapPOIOutlineThickness = 2, -- How far the circle/glow reaches past the pin, in pixels (1-10)
    mapPOIGlowOpacity = 1.0, -- Glow style only; 0-1, where 1 is as solid as it draws
    highlightQuestsInArea = true, -- Highlight a quest while standing inside its shaded map area
    questAreaHighlightStyle = "stripe", -- See STYLES in QuestAreaHighlight.lua
    questAreaHighlightColor = {r = 0.30, g = 0.58, b = 1, a = 1}, -- Sampled from the map's quest-area edge glow
    showZoneHeaders = true,
    includeCampaignQuestInActiveQuest = false,
    includeFTAQuests = false,
    
    -- Grouping & Sorting
    groupByZone = true,
    groupByCategory = true,
    sortMethod = "difficulty_asc",  -- "difficulty_asc", "difficulty_desc", "proximity", "alphabetical"
    
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
    showTooltips = true,
    
    -- Performance
    updateInterval = 0.15,

    -- Debug
    debugEnabled = false,
    debugLevel = "error", -- off | error | warn | info | trace
    layoutDebug = false,
    debugSectionBoxes = false,
    
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

    -- Capture the stored version before stamping the current one, so migrations
    -- below can tell which upgrades still need to run.
    local previousVersion = tonumber(TrackerPlusDB.version) or 1

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

        -- Migration (v2): "Match Game Tracker" mirrors the game's own tracker
        -- position/size and ships enabled, which is what a brand-new profile wants.
        -- A profile that already has a saved position deliberately chose it, so keep
        -- it rather than moving the tracker out from under the player on next login.
        if previousVersion < 2 and TrackerPlusDB.settings.framePosition then
            TrackerPlusDB.settings.matchBlizzardTracker = false
        end

        -- Migration (v4): sort options are now Difficulty (easiest or hardest
        -- first), Proximity and Alphabetical, and are exposed in Settings. The older
        -- values ("name", "level", "manual", "distance") were never selectable in the
        -- UI, so any stored one is a previous default rather than a deliberate
        -- choice; plain "difficulty" predates the direction option. Normalise
        -- anything unrecognised to the new default.
        if previousVersion < 4 then
            local method = TrackerPlusDB.settings.sortMethod
            if method ~= "difficulty_asc" and method ~= "difficulty_desc"
                and method ~= "proximity" and method ~= "alphabetical" then
                TrackerPlusDB.settings.sortMethod = "difficulty_asc"
            end
        end

        -- Migration (v5): header expand/collapse icons now default to the right.
        -- This moves profiles still holding the old "left" default; a profile that
        -- deliberately picked left will be moved too, since the two are stored
        -- identically and can't be told apart.
        if previousVersion < 5 and TrackerPlusDB.settings.headerIconPosition == "left" then
            TrackerPlusDB.settings.headerIconPosition = "right"
        end

        -- Migration (v6): section headers now default to the quest log background.
        -- Same caveat as the icon-position move above: a profile that deliberately
        -- chose the old "tracker" background is indistinguishable from one still
        -- carrying it as the default, so both are moved.
        if previousVersion < 6 and TrackerPlusDB.settings.headerBackgroundStyle == "tracker" then
            TrackerPlusDB.settings.headerBackgroundStyle = "questlog"
        end

        -- Migration: distance tracking removed
        TrackerPlusDB.settings.showDistance = nil

        -- Migration (v5): drop settings nothing reads any more, so they stop being
        -- written back out to SavedVariables.
        TrackerPlusDB.settings.collapseCompleted = nil
        TrackerPlusDB.settings.autoTrackQuests = nil
        TrackerPlusDB.settings.maxTrackedQuests = nil
        TrackerPlusDB.settings.clickToTrack = nil

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
        
        -- Migration: map POI glow opacity is a 0..1 fraction. It briefly ran 0..3,
        -- with the whole numbers counting stacked draw passes; that pass count moved
        -- behind the setting, so rescale anything still stored on the old range
        -- rather than clamping it and silently turning a middling choice into the
        -- maximum. Keyed on the value being out of range rather than on a version,
        -- since the old range never shipped.
        local glowOpacity = tonumber(TrackerPlusDB.settings.mapPOIGlowOpacity)
        if glowOpacity and glowOpacity > 1 then
            TrackerPlusDB.settings.mapPOIGlowOpacity = math.min(glowOpacity / 3, 1)
        end

        -- Migration: settings from an unreleased letter-glow version of the quest
        -- area highlight, superseded by highlightQuestsInArea/questAreaHighlightColor.
        TrackerPlusDB.settings.glowQuestsInArea = nil
        TrackerPlusDB.settings.questAreaGlowColor = nil

        -- Migration: quest area styles dropped after trying them in game.
        local areaStyle = TrackerPlusDB.settings.questAreaHighlightStyle
        if areaStyle == "stripePulse" or areaStyle == "backgroundPulse" or areaStyle == "underline"
            or areaStyle == "checker" or areaStyle == "checkerLeft" or areaStyle == "checkerRight"
            or areaStyle == "checkerEdgeLeft" or areaStyle == "checkerEdgeRight" or areaStyle == "glow" then
            TrackerPlusDB.settings.questAreaHighlightStyle = DEFAULTS.questAreaHighlightStyle
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


