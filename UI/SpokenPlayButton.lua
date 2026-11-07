---@diagnostic disable: undefined-global
local addonName, addon = ...

-------------------------------------------------------------------------------
-- Spoken Play buttons
--
-- When Spoken Quests is loaded, quest rows can carry the same square Play button
-- Spoken puts in the quest log and on the game's own tracker: a click reads the
-- quest's accept text aloud, a second click stops it.
--
-- Everything Spoken-specific lives here. Spoken's quest addon keeps its internals
-- on the global `VoiceOver` (its sound packs call in through that name, so it is
-- stable); the button's look comes from Spoken's public `Spoken:DressBoxButton`.
-- Clicks, stop/replay and the glyph following the queue are all Spoken's own code
-- (`QuestOverlayUI:BindPlayButton` / `FollowQueue`), so the button behaves exactly
-- like Spoken's.
--
-- Buttons hang off pooled tracker buttons (`host.spokenPlayButton`). GetOrCreateButton
-- hides it on reuse; a renderer re-shows it through ApplySpokenPlayButton.
-------------------------------------------------------------------------------

local ROW_SIZE = 14          -- Matches Spoken's own button on the game's tracker
local HEADER_SIZE = 16
-- The quest log's tracking checkbox, which Spoken's square button is drawn to match.
local BOX_ATLAS = "QuestLog-icon-ticksquare"

-- Spoken's quest-addon environment, or nil when it (or the pieces we use) isn't there.
local function GetVoiceOver()
    local vo = rawget(_G, "VoiceOver")
    local spoken = rawget(_G, "Spoken")
    if type(vo) ~= "table" or type(spoken) ~= "table" or not spoken.DressBoxButton then return nil end
    local ui = rawget(vo, "QuestOverlayUI")
    if type(ui) ~= "table" or not ui.BindPlayButton or not ui.SetPlayButtonState then return nil end
    return vo, ui, spoken
end

function addon:IsSpokenAvailable()
    return GetVoiceOver() ~= nil
end

-------------------------------------------------------------------------------
-- Whether a voice pack reads this quest. Asked per row per repaint, so answers
-- are cached until Spoken says its packs or its quest part changed.
-------------------------------------------------------------------------------
local voicedCache = {}

local function IsQuestVoiced(questID)
    local vo, ui = GetVoiceOver()
    if not vo or type(questID) ~= "number" or questID <= 0 then return false end

    -- Spoken's "Quests" part can be switched off from its own settings.
    local Addon = rawget(vo, "Addon")
    if Addon and Addon.IsPartOn and not Addon:IsPartOn() then return false end

    local cached = voicedCache[questID]
    if cached ~= nil then return cached end

    local voiced
    local DataModules, Enums = rawget(vo, "DataModules"), rawget(vo, "Enums")
    if DataModules and DataModules.PrepareSound and Enums and Enums.SoundEvent then
        -- The same check Spoken's own Play buttons make. Deliberately not
        -- ShowsTrackerButton: that also follows Spoken's setting for the game's
        -- tracker, which a TrackerPlus user may well have turned off.
        local ok, result = pcall(DataModules.PrepareSound, DataModules,
            { event = Enums.SoundEvent.QuestAccept, questID = questID })
        voiced = ok and result and true or false
    elseif ui.ShowsTrackerButton then
        local ok, result = pcall(ui.ShowsTrackerButton, ui, questID)
        voiced = ok and result and true or false
    else
        voiced = false
    end
    voicedCache[questID] = voiced
    return voiced
end

-------------------------------------------------------------------------------
-- Button creation and binding
-------------------------------------------------------------------------------
local dressFailed

local function CreatePlayButton(host, size)
    local _, ui, spoken = GetVoiceOver()
    -- Parented after creation, as Spoken does (see its Utils:CreateDetachedFrame):
    -- some clients hook CreateFrame for frames created inside open panels.
    local button = CreateFrame("Button", nil, nil)
    button:SetParent(host)
    button:SetSize(size, size)
    button:SetHitRectInsets(1, 1, 1, 1)

    local ok, err = pcall(spoken.DressBoxButton, spoken, button)
    if ok and button.SetBox then
        -- The atlas may not exist on every client; the dressed default is fine then.
        pcall(button.SetBox, button, BOX_ATLAS, size, size)
    end
    if not ok then
        if not dressFailed then
            dressFailed = true
            addon:LogAt("warn", "Spoken Play button could not be dressed: %s", tostring(err))
        end
        button:Hide()
        return nil
    end

    button.setPlayState = ui.FollowQueue
    -- Dark behind the box: the tracker can sit over the bright world.
    local back = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    back:SetPoint("TOPLEFT", 1, -1)
    back:SetPoint("BOTTOMRIGHT", -1, 1)
    back:SetColorTexture(0, 0, 0, 0.6)
    button._tpSize = size
    return button
end

-- The host's Play button for `questID`, bound and shown, or nil (and any old one
-- hidden) when Spoken isn't there or has no voice for this quest. The caller anchors it.
function addon:ApplySpokenPlayButton(host, questID, title, size)
    local button = host.spokenPlayButton
    if not IsQuestVoiced(questID) then
        if button then button:Hide() end
        return nil
    end
    local _, ui = GetVoiceOver()

    size = size or ROW_SIZE
    if not button then
        button = CreatePlayButton(host, size)
        if not button then return nil end
        host.spokenPlayButton = button
    elseif button._tpSize ~= size then
        if button.SetBox then pcall(button.SetBox, button, nil, size, size) end
        button:SetSize(size, size)
        button._tpSize = size
    end
    button:SetFrameLevel(host:GetFrameLevel() + 3)

    -- A pooled host moves between quests: drop a line queued for the last one.
    if button.questID ~= questID then button.soundData = nil end
    local soundTitle = (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID))
        or title or ""
    ui:BindPlayButton(button, questID, soundTitle, "TrackerPlus's Play button")
    button:ClearAllPoints()
    button:Show()
    ui:SetPlayButtonState(button)
    return button
end

addon.SPOKEN_ROW_BUTTON_SIZE = ROW_SIZE
addon.SPOKEN_HEADER_BUTTON_SIZE = HEADER_SIZE

-------------------------------------------------------------------------------
-- Follow Spoken: packs loading late, or its Quests part switched on/off, change
-- which quests have a voice.
-------------------------------------------------------------------------------
local function OnSpokenChanged()
    wipe(voicedCache)
    if addon.db then addon:RefreshDisplay() end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local _, _, spoken = GetVoiceOver()
    if not (spoken and spoken.RegisterCallback) then return end
    spoken:RegisterCallback("VOICE_PACKS_LOADED", OnSpokenChanged)
    spoken:RegisterCallback("PART_SWITCHED", function(key)
        if key == "quests" then OnSpokenChanged() end
    end)
end)
