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
-- and the best of them are watched, up to the game's watch cap less the player's quests.
--
-- Ownership: every watched quest is either auto-track's or the player's, and auto-track
-- only ever unwatches its own.
--   * Auto-track's (the ledger, charDB.autoTracked): quests it watched itself (true),
--     and quests the game watched on its own ("game"): on accepting a quest, on making
--     progress on one, or whenever else the game decides to.
--   * The player's (charDB.autoTrackLocked): quests locked with the padlock, and quests
--     the player tracked by hand from the quest log or map, before or after turning
--     auto-track on.
-- A watched quest that's neither is claimed on the next pass (see IsPlayersWatch). It
-- becomes the player's only on evidence that they tracked it themselves: a quest is
-- never locked just because auto-track didn't watch it. The focused (super-tracked)
-- quest is never unwatched either.
--
-- The player's own changes are noticed by comparing the watch list against both lists
-- on each pass (not from QUEST_WATCH_LIST_CHANGED, whose payload differs between
-- clients):
--   * one of auto-track's quests no longer watched was untracked by the player; it's
--     left alone ("declined") until they leave its area/zone.
--   * a declined quest watched again is auto-track's again, unless the player tracked
--     it by hand: then it's theirs.
--   * one of the player's quests no longer watched is nobody's, and declined the same
--     way.
--
-- Turning auto-track off unwatches the quests it watched itself and forgets the rest
-- of its list: quests the game watched stay watched.

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

-- Quests the player untracked: questID -> true until ranked, then "near" (tier 1 or 2)
-- or "far" as it was at the time. Auto-track leaves them alone (one of its own stays on
-- the ledger meanwhile) and lets a "near" one go once it no longer is.
local declined = {}
-- The real zone on the previous pass; changing zone forgets every declined quest.
local lastZone

-- Quests accepted while auto-track is on and not claimed yet: questID -> GetTime() of
-- the accept. Whenever the game gets round to watching one (on accept, or not until
-- the player makes progress on it), it's auto-track's.
local accepted = {}
-- A watch from Lua this soon after the accept is the game (or another addon) reacting
-- to it, not the player tracking the quest by hand.
local ACCEPT_GRACE_SECONDS = 5

-- Watches added from Lua since the last pass: questID -> GetTime() of the call. The
-- player tracking a quest by hand (quest log, map) goes through
-- C_QuestLog.AddQuestWatch, hooked below. The game mostly watches quests out of Lua's
-- sight, and where it doesn't, it does so from its QUEST_ACCEPTED or
-- QUEST_WATCH_UPDATE handlers, so a watch in the same frame as one of those events is
-- the game's. Our own watches are made during a pass, which empties this at its end,
-- and land on the ledger, so they're never asked about.
local luaWatches = {}
-- GetTime() of each frame that dispatched QUEST_ACCEPTED or QUEST_WATCH_UPDATE since
-- the last pass. GetTime() doesn't change within a frame.
local questEventFrames = {}

-- Clients that tell the two kinds of watch apart mark the ones the game makes on its
-- own as automatic, so an automatic watch is never the player's.
local WATCH_TYPES = Enum and Enum.QuestWatchType
local AUTOMATIC_WATCH = WATCH_TYPES and WATCH_TYPES.Automatic
local HAS_WATCH_TYPES = AUTOMATIC_WATCH ~= nil and WATCH_TYPES.Manual ~= nil
    and AUTOMATIC_WATCH ~= WATCH_TYPES.Manual

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

local function IsAutomaticWatch(questID)
    return HAS_WATCH_TYPES and C_QuestLog.GetQuestWatchType(questID) == AUTOMATIC_WATCH
end

local function InLog(questID)
    return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
end

local function GetFocusedQuestID()
    return (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()) or 0
end

local function Ledger()
    return addon.charDB and addon.charDB.autoTracked or EMPTY
end

local function Locked()
    return addon.charDB and addon.charDB.autoTrackLocked or EMPTY
end

-- The quests auto-track deals with: the log's ordinary quests. World quests, bonus
-- objectives and bounties are watched by the game's own rules.
local function IsOrdinaryQuest(info)
    local questID = info.questID
    return not info.isHeader and not info.isHidden
        and questID ~= nil and questID > 0
        and not info.isBounty
        and not C_QuestLog.IsWorldQuest(questID)
        and not C_QuestLog.IsQuestTask(questID)
end

-- True if the player tracked the quest by hand since the last pass: a watch from Lua
-- that wasn't the game reacting to an accept or to quest progress.
local function WasTrackedByHand(questID)
    local at = luaWatches[questID]
    if not at or questEventFrames[at] then return false end
    local acceptedAt = accepted[questID]
    return not (acceptedAt and at - acceptedAt <= ACCEPT_GRACE_SECONDS)
end

-- Who a watched quest that's on neither list belongs to: true for the player, false
-- for auto-track.
local function IsPlayersWatch(questID)
    if luaWatches[questID] then return WasTrackedByHand(questID) end
    -- Accepted while auto-track was on, or watched by the game on its own.
    if accepted[questID] or IsAutomaticWatch(questID) then return false end
    -- Nothing new to go on: a manual watch from before auto-track was turned on (or
    -- before this session), which only the player makes.
    return true
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
            elseif IsOrdinaryQuest(info) then
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

-- Untracks a quest we hold. Returns true if the watch list changed.
local function Release(questID, ledger)
    ledger[questID] = nil
    if IsWatched(questID) then
        C_QuestLog.RemoveQuestWatch(questID)
        return true
    end
    return false
end

-- Lets go of a declined quest: off the ledger too if it's still unwatched, so it's a
-- quest like any other again.
local function ForgetDeclined(questID, ledger)
    declined[questID] = nil
    if ledger[questID] and not IsWatched(questID) then
        ledger[questID] = nil
    end
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
    -- The log reads empty for a moment after login, before it arrives; every quest on
    -- our lists would look gone.
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    if numEntries == 0 then return end

    local ledger, locked = Ledger(), Locked()
    local changed = false
    local now = GetTime()

    -- Forget declined quests when the player changes zone: they left and came back.
    local realZone = GetRealZoneText()
    if realZone ~= lastZone then
        for questID in pairs(declined) do
            ForgetDeclined(questID, ledger)
        end
        lastZone = realZone
    end

    -- Notice what happened to our quests since the last pass.
    for questID in pairs(ledger) do
        if not InLog(questID) then
            ledger[questID] = nil -- completed, abandoned, or otherwise gone
            declined[questID] = nil
        elseif not IsWatched(questID) then
            -- Untracked out from under us; refined to near/far once ranked below.
            if not declined[questID] then declined[questID] = true end
        elseif declined[questID] then
            -- Watched again. Tracked by the player's hand, it's theirs now; otherwise
            -- (the game watched it) it's still ours.
            declined[questID] = nil
            if WasTrackedByHand(questID) then
                ledger[questID] = nil
                locked[questID] = true
                changed = true
            end
        end
    end
    -- One of the player's quests they untracked is nobody's now, though left alone
    -- like one of ours they untracked.
    for questID in pairs(locked) do
        if not InLog(questID) then
            locked[questID] = nil
        elseif not IsWatched(questID) then
            locked[questID] = nil
            declined[questID] = true
        end
    end
    for questID in pairs(declined) do
        if not InLog(questID) then declined[questID] = nil end
    end
    -- The log can lag the accept event, so give a new quest a moment to show up.
    for questID, acceptedAt in pairs(accepted) do
        if not InLog(questID) and now - acceptedAt > ACCEPT_GRACE_SECONDS then
            accepted[questID] = nil
        end
    end

    -- Claim every watched quest that's on neither list.
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and IsOrdinaryQuest(info) then
            local questID = info.questID
            if not ledger[questID] and not locked[questID] and IsWatched(questID) then
                if IsPlayersWatch(questID) then
                    locked[questID] = true
                else
                    ledger[questID] = "game"
                end
                declined[questID] = nil
                changed = true
            end
        end
    end
    -- An accepted quest is done with once claimed, or once we watch it ourselves below.
    for questID in pairs(accepted) do
        if ledger[questID] or locked[questID] then
            accepted[questID] = nil
        end
    end

    CollectCandidates(self.db.autoTrackFill, ledger, headers)
    sort(candidates, CompareCandidates)

    -- Slots: the cap less everything watched that isn't ours. Every ledger quest
    -- that isn't declined is watched.
    local ownWatched = 0
    for questID in pairs(ledger) do
        if not declined[questID] then ownWatched = ownWatched + 1 end
    end
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
            ForgetDeclined(questID, ledger)
        end
    end

    -- Untrack first so the new quests have room under the cap.
    local focused = GetFocusedQuestID()
    for questID in pairs(ledger) do
        if not desired[questID] and not declined[questID] and questID ~= focused then
            changed = Release(questID, ledger) or changed
        end
    end
    for questID in pairs(desired) do
        if not IsWatched(questID) then
            C_QuestLog.AddQuestWatch(questID)
            if IsWatched(questID) then
                ledger[questID] = true
                changed = true
            end
        end
    end

    ReleaseCandidates()
    wipe(luaWatches)
    wipe(questEventFrames)

    if changed then
        self:RequestUpdate("quests")
    end
end

-- Unwatches every quest auto-track watched itself (except the focused one, which stays
-- watched) and forgets the rest of its list: quests the game watched stay watched.
local function ReleaseAll()
    local ledger = Ledger()
    local focused = GetFocusedQuestID()
    local changed = false
    for questID, source in pairs(ledger) do
        if source == true and questID ~= focused then
            changed = Release(questID, ledger) or changed
        else
            ledger[questID] = nil
        end
    end
    wipe(declined)
    wipe(accepted)
    wipe(luaWatches)
    wipe(questEventFrames)
    lastZone = nil
    if changed then
        addon:RequestUpdate("quests")
    end
end

local function IsAutoTrackOn()
    return addon.db and addon.db.autoTrackNearby and addon.db.enabled
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_WATCH_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not IsAutoTrackOn() then return end
    local now = GetTime()
    questEventFrames[now] = true
    if event ~= "QUEST_ACCEPTED" then return end

    -- Older clients pass (questLogIndex, questID); newer ones just questID.
    local questID = arg2 or arg1
    if type(questID) ~= "number" or questID <= 0 then return end
    if C_QuestLog.IsWorldQuest(questID) or C_QuestLog.IsQuestTask(questID) then return end
    -- A quest just accepted is nobody's yet, whatever was remembered about it before.
    Ledger()[questID] = nil
    Locked()[questID] = nil
    declined[questID] = nil
    accepted[questID] = now
end)

-- See luaWatches.
if C_QuestLog and C_QuestLog.AddQuestWatch then
    hooksecurefunc(C_QuestLog, "AddQuestWatch", function(questID)
        if type(questID) == "number" and questID > 0 and IsAutoTrackOn() then
            luaWatches[questID] = GetTime()
        end
    end)
end

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

-- Starts or stops the timer to match the setting. Called once at login. The lists are
-- left for the first pass to check: at login the watch list may not be filled in yet.
function addon:UpdateAutoTrackWatcher()
    if self.db.autoTrackNearby then
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
-- Locked means the quest is the player's: auto-track won't untrack it. That's a quest
-- locked with the padlock or tracked by hand (see the ownership notes at the top).

function addon:IsQuestAutoTrackLocked(questID)
    if Ledger()[questID] then return false end
    if Locked()[questID] then return true end
    -- Not claimed yet (the next pass will): show what it will be.
    return IsPlayersWatch(questID)
end

-- Locking hands a quest to the player, as if they had tracked it by hand. Unlocking
-- hands a tracked quest to auto-track, which untracks it on the next pass if it isn't
-- nearby.
function addon:SetQuestAutoTrackLocked(questID, locked)
    if not questID or not self.charDB then return end
    local ledger, lockedQuests = self.charDB.autoTracked, self.charDB.autoTrackLocked
    if locked then
        ledger[questID] = nil
        lockedQuests[questID] = true
    else
        lockedQuests[questID] = nil
        if IsWatched(questID) then
            ledger[questID] = true
        end
    end
    declined[questID] = nil
    accepted[questID] = nil
    luaWatches[questID] = nil

    self:RefreshDisplay()
    if not locked then
        self:RunAutoTrackPass()
    end
end
