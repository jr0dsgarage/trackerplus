---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Stamped into TrackerPlusDB.version so future migrations can tell what they're upgrading from.
local DB_VERSION = 1

-- Which client we're running in. WoW Forever (vanilla content on the modern client)
-- reports 1.6x builds; retail reports 12.x.
local build = select(4, GetBuildInfo())
addon.IsForever = build >= 16000 and build < 20000
addon.IsRetail = not addon.IsForever

-- Settings for features Forever doesn't have (campaigns, world quests, achievements,
-- ...). There they are forced off and left out of the Settings panel.
local RETAIL_ONLY_SETTINGS = {
    includeCampaignQuestInActiveQuest = true,
    showWorldQuests = true,
    showBonusObjectives = true,
    showScenarios = true,
    showDungeonObjectives = true,
    showAchievements = true,
    showMonthlyActivities = true,
    showEndeavors = true,
    -- Colors for the trackable types above
    achievementColor = true,
    monthlyColor = true,
    endeavorColor = true,
    scenarioColor = true,
    bonusColor = true,
}

-- Whether a setting applies to this client.
function addon:IsSettingAvailable(key)
    return addon.IsRetail or not RETAIL_ONLY_SETTINGS[key]
end

-- Turns off every toggle this client can't use, whatever the profile says.
local function ApplyClientRestrictions(settings)
    if addon.IsRetail then return end
    for key in pairs(RETAIL_ONLY_SETTINGS) do
        if type(settings[key]) == "boolean" then
            settings[key] = false
        end
    end
end

-- Default settings
local DEFAULTS = {
    enabled = true,
    locked = false,
    
    -- Frame Position & Size
    framePosition = nil,  -- {point, x, y}
    frameWidth = 250,
    frameHeight = 400,
    frameScale = 1.0,
    -- The point of the tracker that stays put when it's resized (any SetPoint name).
    frameAnchor = "TOPRIGHT",
    -- While true, the tracker mirrors the game's own objective tracker position and
    -- size (including changes made in the game's Edit Mode). Automatically cleared
    -- the first time the player drags or resizes the tracker themselves.
    matchBlizzardTracker = true,
    
    -- Appearance
    backgroundColor = {r = 0, g = 0, b = 0, a = 0.7},
    borderEnabled = false,
    borderColor = {r = 1, g = 1, b = 1, a = 1},
    borderSize = 1,
    -- Panel textures, by name (see UI/PanelMedia.lua for the list)
    borderStyle = "Solid",
    backgroundStyle = "Solid",
    headerIconStyle = "standard", -- "none", "standard", "square", "text_brackets", "questlog"
    headerIconPosition = "right", -- "left", "right"
    headerBackgroundStyle = "questlog", -- "none", "questlog", "tracker"
    -- Trackable row background (see Render/RenderItem.lua for the styles)
    rowBackgroundEnabled = false,
    rowBackgroundStyle = "friends-card-default",
    rowBackgroundAlpha = 1,

    -- Font Settings (fontFace/fontSize are the quest name font)
    fontSize = 12,
    fontFace = "Fonts\\FRIZQT__.TTF",
    fontOutline = "OUTLINE",

    -- Objective Font (objective, task and note lines under a quest)
    objectiveFontSize = 11,
    objectiveFontFace = "Fonts\\FRIZQT__.TTF",

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
    showPartyMembersOnQuest = true, -- "(+N)" after the quest name; the names are in its tooltip
    colorQuestsByDifficulty = true, -- Color quest text using the client's own GetQuestDifficultyColor(level)
    colorMapPOIsByDifficulty = true, -- Outline the game's own world map quest pins in that same difficulty color
    mapPOIOutlineStyle = "glow", -- "glow" (the game's soft ring) or "circle" (hard ring)
    mapPOIOutlineThickness = 2, -- How far the circle/glow reaches past the pin, in pixels (1-10)
    mapPOIGlowOpacity = 1.0, -- Glow style only; 0-1, where 1 is as solid as it draws
    highlightQuestsInArea = true, -- Highlight a quest while standing inside its shaded map area
    questAreaHighlightStyle = "stripe", -- See STYLES in QuestAreaHighlight.lua
    questAreaHighlightColor = {r = 0.30, g = 0.58, b = 1, a = 1}, -- Sampled from the map's quest-area edge glow
    includeCampaignQuestInActiveQuest = false,
    includeFTAQuests = false,
    autoMinimizeHeaders = false, -- Collapse quest zone headers except the current zone and quest areas we stand in

    -- Spoken integration (only offered while Spoken Quests is loaded; see UI/SpokenPlayButton.lua)
    spokenPlayButton = true,             -- Play button on quest rows that a voice pack reads
    spokenPlayButtonPosition = "right",  -- "left" (under the POI button) or "right" (right edge of the title line)
    spokenPlayButtonActiveQuest = true,  -- Play button beside the Active Quest section's title (independent of the above)
    
    -- Sorting
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
        worldQuest = {r = 0.25, g = 0.78, b = 0.92, a = 1},
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
addon.DeepCopy = DeepCopy

-- Initialize database
function addon:InitDatabase()
    -- Create saved variables table if it doesn't exist
    if not TrackerPlusDB then
        TrackerPlusDB = {}
    end

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
    end
    
    ApplyClientRestrictions(TrackerPlusDB.settings)

    -- Create reference to settings
    addon.db = TrackerPlusDB.settings
end

-- Reset settings to defaults
function addon:ResetDatabase()
    TrackerPlusDB.settings = DeepCopy(DEFAULTS)
    ApplyClientRestrictions(TrackerPlusDB.settings)
    addon.db = TrackerPlusDB.settings

    -- Nameplates keeps its own settings table beside ours.
    addon.Nameplates:ResetDB()
    addon.Nameplates:RequestUpdate()
end

-- Set a setting value
function addon:SetSetting(key, value)
    addon.db[key] = value
end
