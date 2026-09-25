---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Localize hot-path globals
local ipairs, tonumber = ipairs, tonumber
local format = string.format
local floor, max, abs = math.floor, math.max, math.abs
local GetTime = GetTime

-------------------------------------------------------------------------------
-- Quest Timer section — "Quest Timer: MM:SS" rows pinned above the quest list
--
-- Self-managed rather than drawn by UpdateTrackerDisplay: the main render pass only
-- paints when collected quest data changes, which a ticking clock never does. This
-- section reads the timers on quest log events, counts down locally with OnUpdate,
-- and only asks for a re-layout when rows appear or disappear.
-------------------------------------------------------------------------------

local ROW_PAD = 6          -- vertical padding added to the font size per row
local TICK_INTERVAL = 0.1  -- how often the countdown text is checked
local JITTER = 1.5         -- keep the old expiry if a re-read lands within this

local timers = {}          -- { expiresAt = number, title = string|nil, questID = number|nil }
local rows = {}            -- pooled buttons, each with a .text font string
local tickElapsed = 0

-- Returns title, questID for a quest log index.
local function GetQuestInfoForLogIndex(logIndex)
    if not logIndex or logIndex <= 0 then return nil end
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(logIndex)
        if info then return info.title, info.questID end
        return nil
    end
    if GetQuestLogTitle then
        local title, _, _, _, _, _, _, questID = GetQuestLogTitle(logIndex)
        return title, questID
    end
end

-- Clicking a timer row makes its quest the Active (super-tracked) quest.
local function OnRowClick(self)
    local questID = self.questID
    if not questID or not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
    C_SuperTrack.SetSuperTrackedQuestID(questID)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

local function OnRowEnter(self)
    if not self.questID then return end
    local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
    tooltip:SetText(self.title or "Quest Timer")
    tooltip:AddLine("Click to make this the Active quest", 0.82, 0.82, 0.82)
    tooltip:Show()
end

local function OnRowLeave()
    addon:HideSharedTooltip()
end

-- Fill `out` with { seconds, title, questID } entries. Classic exposes the timers directly
-- through GetQuestTimers; the modern client only has a per-quest time allowance.
local function CollectTimers(out)
    local n = 0

    if GetQuestTimers then
        local values = { GetQuestTimers() }
        for i, value in ipairs(values) do
            local seconds = tonumber(value)
            if seconds and seconds > 0 then
                n = n + 1
                out[n] = out[n] or {}
                out[n].seconds = seconds
                out[n].title, out[n].questID = GetQuestInfoForLogIndex(GetQuestIndexForTimer and GetQuestIndexForTimer(i))
            end
        end
    end

    if n == 0 and C_QuestLog and C_QuestLog.GetTimeAllowed
        and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local total, elapsed = C_QuestLog.GetTimeAllowed(info.questID)
                local seconds = total and elapsed and (total - elapsed)
                if seconds and total > 0 and seconds > 0 then
                    n = n + 1
                    out[n] = out[n] or {}
                    out[n].seconds = seconds
                    out[n].title = info.title
                    out[n].questID = info.questID
                end
            end
        end
    end

    for i = n + 1, #out do out[i] = nil end
    return n
end

local function FormatTimeLeft(seconds)
    seconds = max(0, floor(seconds))
    return format("%02d:%02d", floor(seconds / 60), seconds % 60)
end

local function UpdateRowTexts(now)
    local showTitles = #timers > 1
    for i, timer in ipairs(timers) do
        local row = rows[i]
        local text = "Quest Timer: " .. FormatTimeLeft(timer.expiresAt - now)
        if showTitles and timer.title then
            text = text .. " |cffaaaaaa- " .. timer.title .. "|r"
        end
        if row._tpText ~= text then
            row.text:SetText(text)
            row._tpText = text
        end
    end
end

local scratch = {}

function addon:RefreshQuestTimers()
    local timerFrame = self.questTimerFrame
    if not timerFrame then return end

    local db = self.db
    local now = GetTime()
    local count = CollectTimers(scratch)

    -- Re-reads report whole seconds, so keep the running expiry unless it really
    -- moved; otherwise the display would jitter by a second on every quest update.
    for i = 1, count do
        local expiresAt = now + scratch[i].seconds
        local existing = timers[i]
        if existing and existing.title == scratch[i].title and abs(existing.expiresAt - expiresAt) < JITTER then
            expiresAt = existing.expiresAt
        end
        timers[i] = timers[i] or {}
        timers[i].expiresAt = expiresAt
        timers[i].title = scratch[i].title
        timers[i].questID = scratch[i].questID
    end
    for i = count + 1, #timers do timers[i] = nil end

    local fontFace = db.headerFontFace or "Fonts\\FRIZQT__.TTF"
    local fontSize = db.headerFontSize or 14
    local rowHeight = fontSize + ROW_PAD

    for i = 1, count do
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, timerFrame)
            row:RegisterForClicks("LeftButtonUp")
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row:SetScript("OnClick", OnRowClick)
            row:SetScript("OnEnter", OnRowEnter)
            row:SetScript("OnLeave", OnRowLeave)
            row.text = row:CreateFontString(nil, "OVERLAY")
            row.text:SetPoint("LEFT", 5, 0)
            row.text:SetPoint("RIGHT", -5, 0)
            row.text:SetJustifyH("CENTER")
            row.text:SetWordWrap(false)
            rows[i] = row
        end
        row.questID = timers[i].questID
        row.title = timers[i].title
        row.text:SetFont(fontFace, fontSize, db.headerFontOutline)
        row.text:SetTextColor(1, 0.82, 0, 1) -- Gold, matching section headers
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", timerFrame, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", timerFrame, "TOPRIGHT", 0, -(i - 1) * rowHeight)
        row:Show()
    end
    for i = count + 1, #rows do
        rows[i]:Hide()
        rows[i]._tpText = nil
        rows[i].questID = nil
    end

    UpdateRowTexts(now)

    if count > 0 then
        timerFrame:SetHeight(count * rowHeight)
        timerFrame:SetShown(not db.minimized)
    else
        timerFrame:SetHeight(1)
        timerFrame:Hide()
    end

    -- The layout signature includes this section's visibility and height, so this
    -- is a no-op unless a row was added or removed.
    self:UpdateLayoutAnchors()
    self:UpdateContentWidth()
end

function addon:InitQuestTimerSection()
    local timerFrame = self.questTimerFrame
    if not timerFrame or timerFrame._tpTimerInit then return end
    timerFrame._tpTimerInit = true

    -- OnUpdate only runs while the frame is shown, so this costs nothing without timers.
    timerFrame:SetScript("OnUpdate", function(_, elapsed)
        tickElapsed = tickElapsed + elapsed
        if tickElapsed < TICK_INTERVAL then return end
        tickElapsed = 0

        local now = GetTime()
        for _, timer in ipairs(timers) do
            if timer.expiresAt <= now then
                addon:RefreshQuestTimers()
                return
            end
        end
        UpdateRowTexts(now)
    end)

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("QUEST_LOG_UPDATE")
    events:RegisterEvent("QUEST_ACCEPTED")
    events:RegisterEvent("QUEST_REMOVED")
    events:SetScript("OnEvent", function()
        addon:RefreshQuestTimers()
    end)

    self:RefreshQuestTimers()
end
