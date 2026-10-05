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

local pairs, ipairs, wipe, sort, concat = pairs, ipairs, wipe, table.sort, table.concat

local TICK_SECONDS = 0.5

local IsInsideQuestBlob = C_Minimap and C_Minimap.IsInsideQuestBlob

-- Fills `out` with the set of zone names whose headers should stay open.
function addon:GetAutoExpandZones(questItems, out)
    wipe(out)

    local realZone = GetRealZoneText and GetRealZoneText()
    if realZone and realZone ~= "" then out[realZone] = true end

    -- Fallback for when the quest log's header title differs from the real-zone text.
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        local info = mapID and C_Map.GetMapInfo(mapID)
        if info and info.name and info.name ~= "" then out[info.name] = true end
    end

    if IsInsideQuestBlob and questItems then
        for _, item in ipairs(questItems) do
            local zone = item.zone
            if zone and not out[zone] and item.id and not item.isWorldQuest
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
local zoneSet, zoneList = {}, {}
local lastSignature

local function Tick()
    local buckets = addon._organizeBuckets
    addon:GetAutoExpandZones(buckets and buckets.quest, zoneSet)

    wipe(zoneList)
    for zone in pairs(zoneSet) do zoneList[#zoneList + 1] = zone end
    sort(zoneList)
    local signature = concat(zoneList, "\n")

    if signature ~= lastSignature then
        lastSignature = signature
        addon:RequestUpdate("quests")
    end
end

local ticker

function addon:UpdateAutoMinimizeWatcher()
    local enabled = self.db and self.db.autoMinimizeHeaders
    if enabled and not ticker then
        lastSignature = nil
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
