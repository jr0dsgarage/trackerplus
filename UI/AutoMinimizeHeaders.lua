---@diagnostic disable: undefined-global
local _, addon = ...

-- Auto-minimize: while on, every quest zone header is collapsed except the zone the
-- player is in and any zone whose quest area (map blob) they are standing inside.
--
-- The collapse is written straight into db.collapsedHeaders by OrganizeTrackables, so
-- turning auto off leaves the headers exactly as they were. Toggling a quest zone
-- header by hand turns it off (see ToggleHeader).
--
-- Blob checks run over every quest in the Quests bucket, not just rendered rows:
-- quests under a collapsed header are never rendered, which is exactly the case this
-- has to catch.

local pairs, ipairs, wipe = pairs, ipairs, wipe

local TICK_SECONDS = 0.5

local IsInsideQuestBlob = C_Minimap and C_Minimap.IsInsideQuestBlob

-- Fills `out` with the set of zone names whose headers should stay open.
function addon:GetAutoExpandZones(questItems, out)
    wipe(out)

    local realZone = GetRealZoneText()
    if realZone and realZone ~= "" then out[realZone] = true end

    -- Fallback for when the quest log's header title differs from the real-zone text.
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        local info = mapID and C_Map.GetMapInfo(mapID)
        if info and info.name and info.name ~= "" then out[info.name] = true end
    end

    if IsInsideQuestBlob then
        for _, item in ipairs(questItems) do
            local zone = item.zone
            if zone and not out[zone] and item.id
                and IsInsideQuestBlob(item.id) == true then
                out[zone] = true
            end
        end
    end

    return out
end

-------------------------------------------------------------------------------
-- Watcher
-------------------------------------------------------------------------------
-- Zone changes already fire events that refresh the quests section; walking into or
-- out of a quest area fires nothing, so poll for that and repaint only on a change.
-- The zone set from the previous tick and the one being built; swapped each tick.
local lastZones, zoneSet = nil, {}

local function SameSet(a, b)
    for key in pairs(a) do
        if not b[key] then return false end
    end
    for key in pairs(b) do
        if not a[key] then return false end
    end
    return true
end

local function Tick()
    addon:GetAutoExpandZones(addon._organizeBuckets.quest, zoneSet)

    if not (lastZones and SameSet(zoneSet, lastZones)) then
        addon:RequestUpdate("quests")
    end
    lastZones, zoneSet = zoneSet, lastZones or {}
end

local ticker

function addon:UpdateAutoMinimizeWatcher()
    local enabled = self.db.autoMinimizeHeaders
    if enabled and not ticker then
        lastZones = nil
        ticker = C_Timer.NewTicker(TICK_SECONDS, Tick)
    elseif not enabled and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function addon:SetAutoMinimize(enabled)
    self.db.autoMinimizeHeaders = enabled and true or false
    local btn = self.trackerFrame and self.trackerFrame.autoMinBtn
    if btn and btn.UpdateColor then btn.UpdateColor() end
    self:UpdateAutoMinimizeWatcher()
    self:RequestUpdate("quests")
end
