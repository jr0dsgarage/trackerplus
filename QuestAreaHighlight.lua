---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Marks a quest's tracker row while the player stands inside the area the map shades
-- for that quest (the "quest blob"). How it's marked is the questAreaHighlightStyle
-- setting; see STYLES below.
--
-- C_Minimap.IsInsideQuestBlob(questID) answers that directly, from the same data the
-- minimap draws its shading from, for any quest in the log -- not just the focused
-- one -- and without the world map ever having been opened. (The world map's own blob
-- pin can hit-test too, but only after the map has been shown once in the session,
-- and nothing short of a real show wakes it; don't go down that road again.)
--
-- The highlight is an overlay on rows the renderer already laid out, so a change in
-- which areas the player is standing in toggles it in place and never repaints.

local pairs, ipairs, wipe = pairs, ipairs, wipe

local TICK_SECONDS = 0.5

-- Left of the row, clear of the POI button (anchored at -4 on a 0.75-scaled child, so
-- its left edge lands near -3). Spans the row's full height, title and objectives.
local STRIPE_X = -8
local STRIPE_WIDTH = 2
local LINE_WIDTH = 1
local BRACKET_CAP = 6

-- Fill styles scale the chosen color's alpha down so the row's text stays readable.
local FILL_ALPHA = 0.25
local GRADIENT_ALPHA = 0.45

-- Box styles (outline and fills) reach out to the stripe's spot on the left and up
-- past the row's top, so they take in the POI button, whose art spills a few pixels
-- outside its own frame.
local BOX_LEFT = STRIPE_X
local BOX_TOP = 4

local DEFAULT_STYLE = "stripe"

local IsInsideQuestBlob = C_Minimap and C_Minimap.IsInsideQuestBlob

-- Quests the player is standing in, by questID. Read by the renderer on every paint
-- (via ApplyQuestAreaHighlight), written only by the watcher below.
local inArea = {}

-------------------------------------------------------------------------------
-- Styles
-------------------------------------------------------------------------------
-- Each style builds its own textures on the button once (so switching styles never
-- has to undo another style's texture, blend or gradient state), then colors them on
-- every show.

local function Line(button)
    return button:CreateTexture(nil, "ARTWORK")
end

local function Fill(button)
    -- Above the row's own bg (BACKGROUND, sublevel 0), below all text.
    local tex = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    tex:SetPoint("TOPLEFT", button, "TOPLEFT", BOX_LEFT, BOX_TOP)
    tex:SetPoint("BOTTOMRIGHT")
    return tex
end

local function LeftStripe(button)
    local tex = Line(button)
    tex:SetPoint("TOPLEFT", button, "TOPLEFT", STRIPE_X, 0)
    tex:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", STRIPE_X, 0)
    tex:SetWidth(STRIPE_WIDTH)
    return tex
end

local function SolidColor(textures, r, g, b, a)
    for _, tex in ipairs(textures) do tex:SetColorTexture(r, g, b, a) end
end

-- Horizontal fade of a flat wash; `strongRight` flips which end carries the color.
local function WashGradient(strongRight)
    return function(textures, r, g, b, a)
        local tex = textures[1]
        local strong, clear = CreateColor(r, g, b, a * GRADIENT_ALPHA), CreateColor(r, g, b, 0)
        tex:SetColorTexture(1, 1, 1, 1)
        if strongRight then
            tex:SetGradient("HORIZONTAL", clear, strong)
        else
            tex:SetGradient("HORIZONTAL", strong, clear)
        end
    end
end

local STYLES = {
    stripe = {
        text = "Stripe (Left)",
        build = function(button) return {LeftStripe(button)} end,
        color = SolidColor,
    },
    stripeRight = {
        text = "Stripe (Right)",
        build = function(button)
            local tex = Line(button)
            tex:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            tex:SetWidth(STRIPE_WIDTH)
            return {tex}
        end,
        color = SolidColor,
    },
    bracket = {
        text = "Bracket",
        build = function(button)
            local bar = LeftStripe(button)
            local top = Line(button)
            top:SetPoint("TOPLEFT", bar, "TOPLEFT")
            top:SetSize(BRACKET_CAP, STRIPE_WIDTH)
            local bottom = Line(button)
            bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
            bottom:SetSize(BRACKET_CAP, STRIPE_WIDTH)
            return {bar, top, bottom}
        end,
        color = SolidColor,
    },
    outline = {
        text = "Outline",
        build = function(button)
            local top, bottom, left, right = Line(button), Line(button), Line(button), Line(button)
            top:SetPoint("TOPLEFT", button, "TOPLEFT", BOX_LEFT, BOX_TOP)
            top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, BOX_TOP)
            top:SetHeight(LINE_WIDTH)
            bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", BOX_LEFT, 0)
            bottom:SetPoint("BOTTOMRIGHT")
            bottom:SetHeight(LINE_WIDTH)
            left:SetPoint("TOPLEFT", top, "TOPLEFT")
            left:SetPoint("BOTTOMLEFT", bottom, "BOTTOMLEFT")
            left:SetWidth(LINE_WIDTH)
            right:SetPoint("TOPRIGHT", top, "TOPRIGHT")
            right:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT")
            right:SetWidth(LINE_WIDTH)
            return {top, bottom, left, right}
        end,
        color = SolidColor,
    },
    background = {
        text = "Background Tint",
        build = function(button) return {Fill(button)} end,
        color = function(textures, r, g, b, a) SolidColor(textures, r, g, b, a * FILL_ALPHA) end,
    },
    gradient = {
        text = "Gradient Fade (Left)",
        build = function(button) return {Fill(button)} end,
        color = WashGradient(false),
    },
    gradientRight = {
        text = "Gradient Fade (Right)",
        build = function(button) return {Fill(button)} end,
        color = WashGradient(true),
    },
}

-- Dropdown order for Settings.lua.
addon.QuestAreaHighlightStyles = {}
for _, key in ipairs({
    "stripe", "stripeRight", "bracket", "outline",
    "background", "gradient", "gradientRight",
}) do
    table.insert(addon.QuestAreaHighlightStyles, {text = STYLES[key].text, value = key})
end

local function HideParts(textures)
    for _, tex in ipairs(textures) do tex:Hide() end
end

-------------------------------------------------------------------------------
-- Highlight
-------------------------------------------------------------------------------
local function HideHighlight(button)
    if button.areaParts then
        for _, textures in pairs(button.areaParts) do HideParts(textures) end
    end
    button._areaLit = nil
end

local function ShowHighlight(button)
    local db = addon.db
    local styleKey = STYLES[db.questAreaHighlightStyle] and db.questAreaHighlightStyle or DEFAULT_STYLE
    local style = STYLES[styleKey]

    -- Hide whatever another style left lit (the style may have just changed).
    local parts = button.areaParts
    if not parts then
        parts = {}
        button.areaParts = parts
    end
    for key, textures in pairs(parts) do
        if key ~= styleKey then HideParts(textures) end
    end

    local textures = parts[styleKey]
    if not textures then
        textures = style.build(button)
        parts[styleKey] = textures
    end

    local c = db.questAreaHighlightColor
    style.color(textures, c and c.r or 0.30, c and c.g or 0.58, c and c.b or 1, c and c.a or 1)
    for _, tex in ipairs(textures) do tex:Show() end

    button._areaLit = true
end

-- Binds a row to a quest (nil for rows that aren't quests) and shows or hides its
-- highlight to match. Called by the renderer for every quest row, and by the pool
-- when a button is recycled.
function addon:ApplyQuestAreaHighlight(button, questID)
    button._areaQuestID = questID
    if questID and self.db and self.db.highlightQuestsInArea and inArea[questID] then
        ShowHighlight(button)
    elseif button._areaLit then
        HideHighlight(button)
    end
end

-- Re-applies every visible row's highlight from the current inArea set. Only touches
-- rows whose state changed, unless forced (a color or style change has to reach lit
-- rows too).
function addon:RefreshQuestAreaHighlights(force)
    self:ForEachActiveButton(function(button)
        local questID = button._areaQuestID
        if questID then
            if force or (button._areaLit == true) ~= (inArea[questID] == true) then
                self:ApplyQuestAreaHighlight(button, questID)
            end
        end
    end)
end

-------------------------------------------------------------------------------
-- Watcher
-------------------------------------------------------------------------------
local newInArea = {}

local function Tick()
    local tracker = addon.trackerFrame
    wipe(newInArea)

    if tracker and tracker:IsShown() then
        addon:ForEachActiveButton(function(button)
            local questID = button._areaQuestID
            if questID and newInArea[questID] == nil then
                newInArea[questID] = IsInsideQuestBlob(questID) == true
            end
        end)
        -- Only the hits matter below; drop the misses so the set compares cleanly.
        for questID, inside in pairs(newInArea) do
            if not inside then newInArea[questID] = nil end
        end
    end

    -- Swap in the new set only if it differs, and only then touch the rows.
    local changed = false
    for questID in pairs(newInArea) do
        if not inArea[questID] then changed = true break end
    end
    if not changed then
        for questID in pairs(inArea) do
            if not newInArea[questID] then changed = true break end
        end
    end
    if changed then
        inArea, newInArea = newInArea, inArea
        addon:RefreshQuestAreaHighlights()
    end
end

local ticker

-- Starts or stops the watcher to match the setting. Off means no ticker at all, and
-- any highlight already showing is cleared. A client without the minimap API never
-- starts it.
function addon:UpdateQuestAreaWatcher()
    local enabled = self.db and self.db.highlightQuestsInArea and IsInsideQuestBlob
    if enabled and not ticker then
        ticker = C_Timer.NewTicker(TICK_SECONDS, Tick)
        Tick()
    elseif not enabled and ticker then
        ticker:Cancel()
        ticker = nil
        wipe(inArea)
        self:RefreshQuestAreaHighlights()
    end
end
