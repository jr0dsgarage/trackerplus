---@diagnostic disable: undefined-global
local _, addon = ...

-------------------------------------------------------------------------------
-- Border and background textures for the tracker panel: the game's own (the
-- set LibSharedMedia ships, plus a few more), and anything other addons have
-- registered with LibSharedMedia. Settings stores the name; these resolve it.
-------------------------------------------------------------------------------

local SOLID_FILE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_NAME = "Solid"

-- { name, file, edge size that suits it, where its art's inner edge is }. Picking a border sets
-- Border Size to its edge size. The last value is how far in from the outside of each edge
-- piece the visible art stops, as a fraction of the edge size (the rest is transparent);
-- taken from the background insets the game pairs with each border. The tracker pushes the
-- border out by that much, so the art's inner edge sits on the panel's edge at any size.
local BUILTIN_BORDERS = {
    { "Solid", SOLID_FILE, 1, 1 },
    { "Blizzard Tooltip", "Interface\\Tooltips\\UI-Tooltip-Border", 16, 0.25 },
    { "Blizzard Dialog", "Interface\\DialogFrame\\UI-DialogBox-Border", 32, 0.34 },
    { "Blizzard Dialog Gold", "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", 32, 0.34 },
    { "Blizzard Achievement Wood", "Interface\\AchievementFrame\\UI-Achievement-WoodBorder", 32, 0.3 },
    { "Blizzard Chat Bubble", "Interface\\Tooltips\\ChatBubble-Backdrop", 32, 0.3 },
    { "Blizzard Party", "Interface\\CHARACTERFRAME\\UI-Party-Border", 16, 0.3 },
    { "Blizzard Toast", "Interface\\FriendsFrame\\UI-Toast-Border", 12, 0.35 },
    { "Blizzard Slider", "Interface\\Buttons\\UI-SliderBar-Border", 8, 0.375 },
    { "Blizzard Glues Panel", "Interface\\Glues\\Common\\TextPanel-Border", 32, 0.3 },
}

local BUILTIN_BACKGROUNDS = {
    { "Solid", SOLID_FILE },
    { "Blizzard Tooltip", "Interface\\Tooltips\\UI-Tooltip-Background" },
    { "Blizzard Dialog Background", "Interface\\DialogFrame\\UI-DialogBox-Background" },
    { "Blizzard Dialog Background Dark", "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" },
    { "Blizzard Dialog Background Gold", "Interface\\DialogFrame\\UI-DialogBox-Gold-Background" },
    { "Blizzard Collections Background", "Interface\\Collections\\CollectionsBackgroundTile" },
    { "Blizzard Garrison Background", "Interface\\Garrison\\GarrisonUIBackground" },
    { "Blizzard Garrison Background 2", "Interface\\Garrison\\GarrisonUIBackground2" },
    { "Blizzard Garrison Background 3", "Interface\\Garrison\\GarrisonMissionUIInfoBoxBackgroundTile" },
    { "Blizzard Marble", "Interface\\FrameGeneral\\UI-Background-Marble" },
    { "Blizzard Rock", "Interface\\FrameGeneral\\UI-Background-Rock" },
    { "Blizzard Parchment", "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal" },
    { "Blizzard Parchment 2", "Interface\\AchievementFrame\\UI-GuildAchievement-Parchment-Horizontal" },
    { "Blizzard Tabard Background", "Interface\\TabardFrame\\TabardFrameBackground" },
    { "Blizzard Low Health", "Interface\\FullScreenTextures\\LowHealth" },
    { "Blizzard Out of Control", "Interface\\FullScreenTextures\\OutOfControl" },
}
local BUILTINS = { border = BUILTIN_BORDERS, background = BUILTIN_BACKGROUNDS }

-- For borders other addons registered, whose size and art we don't know.
local FALLBACK_EDGE_SIZE = 16
local FALLBACK_INNER_EDGE = 0.3

local function NormalizePath(path)
    return (path:lower():gsub("/", "\\"))
end

-- Leaves out game files this client doesn't have (Forever lacks the garrison art, for
-- one). Addon files can't be checked this way, so they're always kept.
local function FileExists(path)
    if not GetFileIDFromPath or NormalizePath(path):find("^interface\\addons\\") then
        return true
    end
    return GetFileIDFromPath(path) ~= nil
end

-- Every available texture of `kind` ("border" or "background"), as a list of
-- { name, path, edgeSize }: Solid first, then the rest by name. Built on demand so
-- media registered by addons that loaded after us is included.
function addon:GetPanelMediaList(kind)
    local list, seen = {}, {}
    local function add(name, path, edgeSize)
        if type(path) ~= "string" or path == "" then return end -- LibSharedMedia's "None"
        local key = NormalizePath(path)
        if seen[key] or not FileExists(path) then return end
        seen[key] = true
        list[#list + 1] = { name = name, path = path, edgeSize = edgeSize }
    end

    for _, entry in ipairs(BUILTINS[kind]) do
        add(entry[1], entry[2], entry[3])
    end
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if lsm then
        for _, name in ipairs(lsm:List(kind)) do
            add(name, lsm:Fetch(kind, name, true))
        end
    end

    table.sort(list, function(a, b)
        if (a.name == DEFAULT_NAME) ~= (b.name == DEFAULT_NAME) then
            return a.name == DEFAULT_NAME
        end
        return a.name:lower() < b.name:lower()
    end)
    return list
end

-- The file for a saved name, plus (for borders) its suggested edge size and inner edge
-- fraction (see BUILTIN_BORDERS). Falls back to Solid when the texture is gone (say, the
-- addon that registered it was removed).
function addon:ResolvePanelMedia(kind, name)
    for _, entry in ipairs(BUILTINS[kind]) do
        if entry[1] == name and FileExists(entry[2]) then
            return entry[2], entry[3] or FALLBACK_EDGE_SIZE, entry[4] or FALLBACK_INNER_EDGE
        end
    end
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = lsm and name and lsm:Fetch(kind, name, true)
    if type(path) == "string" and path ~= "" then
        if NormalizePath(path) == NormalizePath(SOLID_FILE) then
            return path, 1, 1 -- e.g. Details' "1 Pixel"
        end
        return path, FALLBACK_EDGE_SIZE, FALLBACK_INNER_EDGE
    end
    return SOLID_FILE, 1, 1
end

function addon:IsSolidPanelMedia(path)
    return NormalizePath(path) == NormalizePath(SOLID_FILE)
end
