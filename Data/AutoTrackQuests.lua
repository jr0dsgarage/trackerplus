---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Auto-track: keeps the game's watched-quest list on the quests around the player.
--
-- While on (title bar button, or Settings > Quest Tracking), every TICK_SECONDS the
-- quest log is ranked:
--   1. quests whose shaded map area (quest blob) the player is standing in, and in a
--      dungeon or raid, the quests filed under that instance's quest log header (many
--      instances have no map, so their quests can't be placed by pin)
--   2. quests whose map pin (objectives, or the turn-in NPC once the quest is ready
--      to hand in) is in the player's current zone. Outside instances the quest log's
--      zone headers are deliberately ignored: a quest is filed under the zone it came
--      from, which says nothing about where it's done.
--   3. with "Auto fill the quest log" on: every other quest with a location, nearest first
-- and the best of them are watched, up to the game's watch cap less the quests the
-- player tracked by hand.
--
-- Ownership: only quests on the ledger (charDB.autoTracked) are ever unwatched by
-- it: the ones it watched itself, plus quests accepted while it's on (the game
-- watches those on accept, but the player didn't choose to track them). Quests the
-- player tracked by hand, or locked with the padlock, are never touched, and
-- neither is the focused (super-tracked) quest.
--
-- The player's own changes are noticed by comparing the watch list against our
-- ledger on each pass (not from QUEST_WATCH_LIST_CHANGED, whose payload differs
-- between clients):
--   * a ledger quest no longer watched was untracked by the player; it's left alone
--     ("declined") until they leave its area/zone, or track it again themselves.
--   * a declined quest that's watched again was re-tracked by the player; it's
--     theirs now.
--
-- Turning auto-track off unwatches every quest on the ledger and forgets it.

local pairs, ipairs, wipe, sort = pairs, ipairs, wipe, table.sort
local huge = math.huge

local TICK_SECONDS = 1

-- A distance-ranked (tier 3) quest must be this much closer than a quest we already
-- track to push it out, so two quests at nearly the same range don't swap back and
-- forth as the player moves. Compared on squared distances, hence squared.
local INCUMBENT_FACTOR = 0.75 * 0.75

local IsInsideQuestBlob = C_Minimap and C_Minimap.IsInsideQuestBlob

local EMPTY = {}

-- Instance types whose quests are tracked by quest log header: dungeons and raids.
local HEADER_INSTANCE_TYPES = { party = true, raid = true }
local instanceHeaders = {}

-- In a dungeon or raid, the quest log header titles its quests are filed under (the
-- instance's name, and the zone text in case it differs); nil anywhere else.
local function GetInstanceHeaders()
    if not GetInstanceInfo then return nil end
    local name, instanceType = GetInstanceInfo()
    if not HEADER_INSTANCE_TYPES[instanceType] then return nil end
    wipe(instanceHeaders)
    if name and name ~= "" then instanceHeaders[name] = true end
    local zone = GetRealZoneText()
    if zone and zone ~= "" then instanceHeaders[zone] = true end
    if next(instanceHeaders) == nil then return nil end
    return instanceHeaders
end

-- The zone-level map a map belongs to: maps below zone level (a city district with
-- its own map, a cave, a building) count as the zone they sit in. Cached, since map
-- parents never change.
local ZONE_MAP_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
local zoneOfMap = {}

local function GetZoneMapID(mapID)
    if not mapID or mapID <= 0 then return nil end
    local cached = zoneOfMap[mapID]
    if cached ~= nil then return cached or nil end

    local zoneID, current = false, mapID
    for _ = 1, 10 do -- map trees are shallow; the cap only guards against a loop
        local info = C_Map.GetMapInfo(current)
        if not info then break end
        if info.mapType <= ZONE_MAP_TYPE then
            -- A zone, or a continent/world when the map has no zone above it.
            zoneID = current
            break
        end
        if not info.parentMapID or info.parentMapID == 0 then
            zoneID = current
            break
        end
        current = info.parentMapID
    end

    zoneOfMap[mapID] = zoneID
    return zoneID or nil
end

-- The zone-level map of where a quest's pin is right now: its objectives, or its
-- turn-in once it's ready to hand in. Asks for the pin's real map rather than the
-- waypoint (flight master, portal) the game routes cross-zone quests through.
local GetQuestUiMapID = GetQuestUiMapID
local function GetQuestZoneMapID(questID)
    if not GetQuestUiMapID then return nil end
    local ok, mapID = pcall(GetQuestUiMapID, questID, true)
    if not ok or type(mapID) ~= "number" then return nil end
    return GetZoneMapID(mapID)
end

-- Quests the player untracked out from under us: questID -> true if it was "near"
-- (tier 1 or 2) at the time, so it's let go again once it no longer is.
local declined = {}
-- The real zone on the previous pass; changing zone forgets every declined quest.
local lastZone

-- Quests accepted while auto-track is on: questID -> GetTime() of the accept. The
-- game watches a new quest from its own QUEST_ACCEPTED handler, which may run
-- before or after ours, so the next pass adopts it onto the ledger once it's
-- watched. One the game didn't watch is dropped after ACCEPT_GRACE_SECONDS, so a
-- later track by hand stays the player's.
local accepted = {}
local ACCEPT_GRACE_SECONDS = 5

-- Scratch tables reused each pass.
local candidates, desired, nearNow, pool = {}, {}, {}, {}

local function GetWatchCap()
    if C_QuestLog.GetMaxNumQuestsCanWatch then
        local cap = C_QuestLog.GetMaxNumQuestsCanWatch()
        if type(cap) == "number" and cap > 0 then return cap end
    end
    return (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES) or 25
end

local function IsWatched(questID)
    return C_QuestLog.GetQuestWatchType(questID) ~= nil
end

local function GetFocusedQuestID()
    return (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()) or 0
end

local function Ledger()
    return addon.charDB and addon.charDB.autoTracked or EMPTY
end

local function Acquire()
    local entry = pool[#pool]
    if entry then
        pool[#pool] = nil
        return entry
    end
    return {}
end

local function ReleaseCandidates()
    for i = #candidates, 1, -1 do
        pool[#pool + 1] = candidates[i]
        candidates[i] = nil
    end
end

local function CompareCandidates(a, b)
    if a.tier ~= b.tier then return a.tier < b.tier end
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.questID < b.questID -- stable, so equal ranks never trade places
end

-- Fills `candidates` with every quest in the log auto-track may watch, each with its
-- tier and a ranking distance. Quests on no tier are left out. `headers` is
-- GetInstanceHeaders()'s answer.
local function CollectCandidates(fill, ledger, headers)
    ReleaseCandidates()
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    local playerZoneMapID = GetZoneMapID(C_Map.GetBestMapForUnit("player"))
    local underInstanceHeader = false

    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                underInstanceHeader = headers ~= nil and info.title ~= nil and headers[info.title] == true
            elseif not info.isHidden and info.questID and info.questID > 0
                and not info.isBounty
                and not C_QuestLog.IsWorldQuest(info.questID)
                and not C_QuestLog.IsQuestTask(info.questID) then
                local questID = info.questID
                local tier
                if underInstanceHeader
                    or (IsInsideQuestBlob and IsInsideQuestBlob(questID) == true) then
                    tier = 1
                elseif playerZoneMapID and GetQuestZoneMapID(questID) == playerZoneMapID then
                    tier = 2
                end

                local distanceSq = addon.GetQuestDistanceSq(questID)
                if not tier and fill and distanceSq < huge then
                    tier = 3
                end

                if tier then
                    local entry = Acquire()
                    entry.questID = questID
                    entry.tier = tier
                    -- Quests we already hold get a head start (see INCUMBENT_FACTOR).
                    entry.rank = ledger[questID] and distanceSq * INCUMBENT_FACTOR or distanceSq
                    candidates[#candidates + 1] = entry
                end
            end
        end
    end
end

-- Untracks a quest we added. Returns true if the watch list changed.
local function Release(questID, ledger)
    ledger[questID] = nil
    if IsWatched(questID) then
        C_QuestLog.RemoveQuestWatch(questID)
        return true
    end
    return false
end

-- One ranking pass: works out which quests should be watched and makes it so.
function addon:RunAutoTrackPass()
    if not (self.db and self.db.autoTrackNearby and self.db.enabled) then return end
    -- Nothing reliable to rank against during a loading screen. Dungeons and raids
    -- often have no map at all, but their quests are found by header instead.
    local headers = GetInstanceHeaders()
    if not (headers or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))) then return end
    -- Leave the tracker alone mid-fight; the next tick after combat catches up.
    if InCombatLockdown() then return end

    local ledger = Ledger()
    local changed = false

    -- Forget declined quests when the player changes zone: they left and came back.
    local realZone = GetRealZoneText()
    if realZone ~= lastZone then
        wipe(declined)
        lastZone = realZone
    end

    -- Hand newly accepted quests the game watched to auto-track.
    local now = GetTime()
    for questID, acceptedAt in pairs(accepted) do
        if ledger[questID] or not C_QuestLog.GetLogIndexForQuestID(questID) then
            accepted[questID] = nil
        elseif IsWatched(questID) then
            ledger[questID] = true
            accepted[questID] = nil
            changed = true
        elseif now - acceptedAt > ACCEPT_GRACE_SECONDS then
            accepted[questID] = nil
        end
    end

    -- Notice what the player did to the watch list since the last pass.
    for questID in pairs(ledger) do
        if not C_QuestLog.GetLogIndexForQuestID(questID) then
            ledger[questID] = nil -- completed, abandoned, or otherwise gone
        elseif not IsWatched(questID) then
            ledger[questID] = nil
            declined[questID] = true -- refined to near/far once ranked below
        end
    end
    for questID in pairs(declined) do
        if not C_QuestLog.GetLogIndexForQuestID(questID) or IsWatched(questID) then
            declined[questID] = nil -- gone, or tracked again by hand (theirs now)
        end
    end

    CollectCandidates(self.db.autoTrackFill, ledger, headers)
    sort(candidates, CompareCandidates)

    -- Slots: the cap less everything watched that isn't ours.
    local ownWatched = 0
    for _ in pairs(ledger) do ownWatched = ownWatched + 1 end
    local slots = GetWatchCap() - (C_QuestLog.GetNumQuestWatches() - ownWatched)

    wipe(desired)
    wipe(nearNow)
    for _, entry in ipairs(candidates) do
        local questID = entry.questID
        if entry.tier <= 2 then nearNow[questID] = true end
        if declined[questID] then
            -- `true` means it hasn't been ranked since it was untracked.
            if declined[questID] == true then
                declined[questID] = entry.tier <= 2 and "near" or "far"
            end
        elseif slots > 0 and (ledger[questID] or not IsWatched(questID)) then
            desired[questID] = true
            slots = slots - 1
        end
    end
    -- A quest declined while near is let go once the player has left its area/zone.
    for questID, state in pairs(declined) do
        if state == true then
            declined[questID] = "far"
        elseif state == "near" and not nearNow[questID] then
            declined[questID] = nil
        end
    end

    -- Untrack first so the new quests have room under the cap.
    local focused = GetFocusedQuestID()
    for questID in pairs(ledger) do
        if not desired[questID] and questID ~= focused then
            changed = Release(questID, ledger) or changed
        end
    end
    for questID in pairs(desired) do
        if not ledger[questID] and not IsWatched(questID) then
            C_QuestLog.AddQuestWatch(questID)
            if IsWatched(questID) then
                ledger[questID] = true
                changed = true
            end
        end
    end

    ReleaseCandidates()

    if changed then
        self:RequestUpdate("quests")
    end
end

-- Unwatches every quest auto-track added (except the focused one, which simply
-- becomes the player's) and forgets them.
local function ReleaseAll()
    local ledger = Ledger()
    local focused = GetFocusedQuestID()
    local changed = false
    for questID in pairs(ledger) do
        if questID == focused then
            ledger[questID] = nil
        else
            changed = Release(questID, ledger) or changed
        end
    end
    wipe(declined)
    wipe(accepted)
    lastZone = nil
    if changed then
        addon:RequestUpdate("quests")
    end
end

local acceptFrame = CreateFrame("Frame")
acceptFrame:RegisterEvent("QUEST_ACCEPTED")
acceptFrame:SetScript("OnEvent", function(_, _, arg1, arg2)
    if not (addon.db and addon.db.autoTrackNearby and addon.db.enabled) then return end
    -- Older clients pass (questLogIndex, questID); newer ones just questID.
    local questID = arg2 or arg1
    if type(questID) ~= "number" or questID <= 0 then return end
    if Ledger()[questID] then return end
    accepted[questID] = GetTime()
end)

-------------------------------------------------------------------------------
-- On/off
-------------------------------------------------------------------------------
local ticker

local function Tick()
    addon:RunAutoTrackPass()
end

local function RefreshButtons()
    local frame = addon.trackerFrame
    if not frame then return end
    if frame.autoTrackBtn and frame.autoTrackBtn.UpdateColor then frame.autoTrackBtn.UpdateColor() end
    if frame.autoMinBtn and frame.autoMinBtn.UpdateColor then frame.autoMinBtn.UpdateColor() end
    -- The Settings checkbox, if the panel has been built (it re-reads on show anyway).
    local check = _G[addonName .. "autoTrackNearbyCheck"]
    if check then check:SetChecked(addon.db.autoTrackNearby and true or false) end
end

-- Starts or stops the timer to match the setting. Called once at login.
function addon:UpdateAutoTrackWatcher()
    local enabled = self.db.autoTrackNearby
    if enabled then
        -- Ledger entries the player untracked while we weren't looking (another
        -- addon, a reload with the feature off) are simply forgotten.
        local ledger = Ledger()
        for questID in pairs(ledger) do
            if not IsWatched(questID) then ledger[questID] = nil end
        end
        if not ticker then
            ticker = C_Timer.NewTicker(TICK_SECONDS, Tick)
        end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
    RefreshButtons()
end

-- Turns auto-track on (tracking every nearby quest straight away) or off (untracking
-- the quests it added, leaving the player's own).
function addon:SetAutoTrack(enabled)
    enabled = enabled and true or false
    self.db.autoTrackNearby = enabled

    if enabled then
        self:UpdateAutoTrackWatcher()
        self:RunAutoTrackPass()
    else
        self:UpdateAutoTrackWatcher()
        ReleaseAll()
    end
    self:RequestUpdate("quests")
end

-------------------------------------------------------------------------------
-- Per-quest lock (the padlock on quest rows while auto-track is on)
-------------------------------------------------------------------------------
-- Locked means the quest is the player's: auto-track won't untrack it. That's every
-- quest not on the ledger -- locked with the padlock, tracked by hand, or already
-- tracked before auto-track was turned on -- so those show locked without anything
-- being stored for them. A quest just accepted is auto-track's (see `accepted`).

function addon:IsQuestAutoTrackLocked(questID)
    return not (Ledger()[questID] or accepted[questID])
end

-- Locking hands a quest auto-track added to the player, as if they had tracked it by
-- hand. Unlocking hands a tracked quest to auto-track, which untracks it on the next
-- pass if it isn't nearby.
function addon:SetQuestAutoTrackLocked(questID, locked)
    if not questID or not self.charDB then return end
    local ledger = self.charDB.autoTracked
    if locked then
        ledger[questID] = nil
    elseif IsWatched(questID) then
        ledger[questID] = true
    end
    declined[questID] = nil
    accepted[questID] = nil

    self:RefreshDisplay()
    if not locked then
        self:RunAutoTrackPass()
    end
end
