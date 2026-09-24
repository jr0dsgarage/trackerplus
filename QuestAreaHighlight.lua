---@diagnostic disable: undefined-global
local addonName, addon = ...

-- A colored stripe beside a quest's tracker row while the player stands inside the
-- area the map shades for that quest (the "quest blob").
--
-- C_Minimap.IsInsideQuestBlob(questID) answers that directly, from the same data the
-- minimap draws its shading from, for any quest in the log -- not just the focused
-- one -- and without the world map ever having been opened. (The world map's own blob
-- pin can hit-test too, but only after the map has been shown once in the session,
-- and nothing short of a real show wakes it; don't go down that road again.)
--
-- The stripe is an overlay on rows the renderer already laid out, so a change in
-- which areas the player is standing in toggles it in place and never repaints.

local pairs, wipe = pairs, wipe

local TICK_SECONDS = 0.5

-- Left of the row, clear of the POI button (anchored at -4 on a 0.75-scaled child, so
-- its left edge lands near -3). Spans the row's full height, title and objectives.
local STRIPE_X = -8
local STRIPE_WIDTH = 2

local IsInsideQuestBlob = C_Minimap and C_Minimap.IsInsideQuestBlob

-- Quests the player is standing in, by questID. Read by the renderer on every paint
-- (via ApplyQuestAreaHighlight), written only by the watcher below.
local inArea = {}

-------------------------------------------------------------------------------
-- Stripe
-------------------------------------------------------------------------------
local function ShowStripe(button)
    local stripe = button.areaStripe
    if not stripe then
        stripe = button:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("TOPLEFT", button, "TOPLEFT", STRIPE_X, 0)
        stripe:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", STRIPE_X, 0)
        stripe:SetWidth(STRIPE_WIDTH)
        button.areaStripe = stripe
    end

    local c = addon.db.questAreaHighlightColor
    stripe:SetColorTexture(c and c.r or 0.30, c and c.g or 0.58, c and c.b or 1, c and c.a or 1)
    stripe:Show()
end

-- Binds a row to a quest (nil for rows that aren't quests) and shows or hides its
-- stripe to match. Called by the renderer for every quest row, and by the pool when a
-- button is recycled.
function addon:ApplyQuestAreaHighlight(button, questID)
    button._areaQuestID = questID
    if questID and self.db and self.db.highlightQuestsInArea and inArea[questID] then
        ShowStripe(button)
    elseif button.areaStripe then
        button.areaStripe:Hide()
    end
end

-- Re-applies every visible row's stripe from the current inArea set. Only touches
-- rows whose state changed, unless forced (a color change has to reach lit rows too).
function addon:RefreshQuestAreaHighlights(force)
    self:ForEachActiveButton(function(button)
        local questID = button._areaQuestID
        if questID then
            local shown = button.areaStripe and button.areaStripe:IsShown() or false
            if force or shown ~= (inArea[questID] == true) then
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
-- any stripe already showing is cleared. A client without the minimap API never
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
