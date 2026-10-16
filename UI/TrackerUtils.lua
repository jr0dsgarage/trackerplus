local addonName, addon = ...

-- Localize hot-path globals
local pairs, ipairs = pairs, ipairs
local floor = math.floor
local InCombatLockdown = InCombatLockdown
local wipe = wipe

-- Pools
local trackableButtons = {}
local secureButtons = {}
local activeButtons = 0
local activeSecureButtons = 0

-- Opens the game's color picker on `color` ({r, g, b, a}), editing it in place. onChange runs after
-- every change, including Cancel, which puts back the values the picker opened with.
function addon:OpenColorPicker(color, onChange)
    local original = { r = color.r, g = color.g, b = color.b, a = color.a }

    local function apply()
        color.r, color.g, color.b = ColorPickerFrame:GetColorRGB()
        color.a = ColorPickerFrame:GetColorAlpha()
        onChange()
    end

    ColorPickerFrame:SetupColorPickerAndShow({
        r = color.r or 1,
        g = color.g or 1,
        b = color.b or 1,
        opacity = color.a or 1,
        hasOpacity = true,
        swatchFunc = apply,
        opacityFunc = apply,
        cancelFunc = function()
            color.r, color.g, color.b, color.a = original.r, original.g, original.b, original.a
            onChange()
        end,
    })
end

-- Helper to create or update border lines
function addon:CreateBorderLines(bar, size)
    size = tonumber(size) or 1
    if size < 0 then size = 0 end
    local pixelSize = floor(size + 0.5)
    
    -- Create border frame if it doesn't exist
    if not bar.border then
        bar.border = CreateFrame("Frame", nil, bar)
        
        local function CreateLine(p) 
            local t = p:CreateTexture(nil, "BORDER") 
            t:SetColorTexture(1, 1, 1, 1) 
            return t 
        end
        
        bar.border.top = CreateLine(bar.border)
        bar.border.top:SetPoint("TOPLEFT")
        bar.border.top:SetPoint("TOPRIGHT")
        
        bar.border.bottom = CreateLine(bar.border)
        bar.border.bottom:SetPoint("BOTTOMLEFT")
        bar.border.bottom:SetPoint("BOTTOMRIGHT")
        
        bar.border.left = CreateLine(bar.border)
        bar.border.left:SetPoint("TOPLEFT")
        bar.border.left:SetPoint("BOTTOMLEFT")
        
        bar.border.right = CreateLine(bar.border)
        bar.border.right:SetPoint("TOPRIGHT")
        bar.border.right:SetPoint("BOTTOMRIGHT")
    end

    -- 0 means hidden border
    if pixelSize <= 0 then
        bar.border:Hide()
        return
    end
    bar.border:Show()
    
    -- Update Size & Anchors
    bar.border:ClearAllPoints()
    bar.border:SetPoint("TOPLEFT", -pixelSize, pixelSize)
    bar.border:SetPoint("BOTTOMRIGHT", pixelSize, -pixelSize)
    
    bar.border.top:SetHeight(pixelSize)
    bar.border.bottom:SetHeight(pixelSize)
    bar.border.left:SetWidth(pixelSize)
    bar.border.right:SetWidth(pixelSize)
end

-- Major header order and titles. Scenarios are rendered separately, and campaign
-- items are typed "quest" with questType="campaign", so they fall into Quests.
local ORGANIZE_ORDER = {
    { type = "quest", title = "Quests" },
    { type = "achievement", title = "Achievements" },
    { type = "profession", title = "Professions" },
    { type = "monthly", title = "Monthly Activities" },
    { type = "endeavor", title = "Endeavors" },
}

-- Reused across passes. Buckets are keyed by item type; types not listed in
-- ORGANIZE_ORDER have no bucket and are skipped.
local organized = {}
local zones, sortedZones, zoneTables = {}, {}, {}
local autoKeepZones = {}
local organizeBuckets = {}
for _, entry in ipairs(ORGANIZE_ORDER) do
    organizeBuckets[entry.type] = {}
end
-- AutoMinimizeHeaders.lua scans the Quests bucket between renders.
addon._organizeBuckets = organizeBuckets

-- Organize trackables into Major/Minor hierarchy
function addon:OrganizeTrackables(trackables)
    local db = self.db
    local collapsedHeaders = db.collapsedHeaders
    self.knownMinorKeys = self.knownMinorKeys or {}
    local knownMinorKeys = self.knownMinorKeys
    wipe(knownMinorKeys)
    wipe(organized)

    for _, bucket in pairs(organizeBuckets) do
        wipe(bucket)
    end
    for _, item in ipairs(trackables) do
        local bucket = organizeBuckets[item.type]
        if bucket then
            bucket[#bucket + 1] = item
        end
    end

    for _, entry in ipairs(ORGANIZE_ORDER) do
        local bucketType = entry.type
        local items = organizeBuckets[bucketType]
        if #items > 0 then
            -- Major Header
            local majorKey = "MAJOR_" .. bucketType
            local minorKeys = {}
            knownMinorKeys[majorKey] = minorKeys
            local majorCollapsed = collapsedHeaders[majorKey]

            organized[#organized + 1] = {
                isHeader = true,
                headerType = "major",
                title = entry.title,
                key = majorKey,
                collapsed = majorCollapsed
            }

            if not majorCollapsed then
                -- Group by Minor (Zone or Category)
                wipe(zones)
                for _, item in ipairs(items) do
                    local zone = item.zone or "General"
                    local zoneItems = zones[zone]
                    if not zoneItems then
                        zoneItems = zoneTables[zone]
                        if not zoneItems then
                            zoneItems = {}
                            zoneTables[zone] = zoneItems
                        end
                        wipe(zoneItems)
                        zones[zone] = zoneItems
                    end
                    zoneItems[#zoneItems + 1] = item
                end

                wipe(sortedZones)
                for zoneName in pairs(zones) do sortedZones[#sortedZones + 1] = zoneName end
                table.sort(sortedZones)

                -- Auto-minimize (header "A"): only the current zone and zones whose
                -- quest area we're standing in stay open. See AutoMinimizeHeaders.lua.
                local autoKeep
                if bucketType == "quest" and db.autoMinimizeHeaders then
                    autoKeep = self:GetAutoExpandZones(items, autoKeepZones)
                end

                for _, zoneName in ipairs(sortedZones) do
                    local minorKey = "MINOR_" .. bucketType .. "_" .. zoneName
                    minorKeys[#minorKeys + 1] = minorKey
                    if autoKeep then
                        collapsedHeaders[minorKey] = not autoKeep[zoneName]
                    end
                    local minorCollapsed = collapsedHeaders[minorKey]

                    -- Minor Header
                    organized[#organized + 1] = {
                        isHeader = true,
                        headerType = "minor",
                        title = zoneName,
                        key = minorKey,
                        collapsed = minorCollapsed
                    }

                    if not minorCollapsed then
                        for _, item in ipairs(zones[zoneName]) do
                            organized[#organized + 1] = item
                        end
                    end
                end
            end
        end
    end

    return organized
end

function addon:ResetButtonPool()
    activeButtons = 0
    activeSecureButtons = 0
end

function addon:FinalizeButtonPool()
    -- Regular pooled buttons routinely parent a secure item button (see
    -- GetOrCreateSecureButton). Hiding a regular button also changes the effective
    -- shown state of any secure child it houses, so gate this the same way as the
    -- secure-button loop below rather than hiding unconditionally.
    if not InCombatLockdown() then
        for i = activeButtons + 1, #trackableButtons do
            trackableButtons[i]:Hide()
        end

        -- Hide unused secure pooled buttons only when safe.
        for i = activeSecureButtons + 1, #secureButtons do
            secureButtons[i]:Hide()
        end
    end
end

-- Calls fn(button) for every pooled button in use by the current render, so overlays
-- (see QuestAreaHighlight.lua) can update rows in place without a repaint.
function addon:ForEachActiveButton(fn)
    for i = 1, activeButtons do
        fn(trackableButtons[i])
    end
end

local OBJECTIVE_PART_KEYS = { "objectiveBullets", "objectivePrefixes", "objectives", "objectiveProgresses" }

-- Get or create a button from the pool. Returns it shown, unanchored and with every
-- part another renderer might have added hidden or reset.
function addon:GetOrCreateButton(parent)
    activeButtons = activeButtons + 1
    
    local btn
    if trackableButtons[activeButtons] then
        btn = trackableButtons[activeButtons]
        -- Re-parent if necessary
        if parent and btn:GetParent() ~= parent then
             btn:SetParent(parent)
        end
    else
        btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(20)
        
        -- Background
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0, 0, 0, 0)
        
        -- Text
        btn.text = btn:CreateFontString(nil, "OVERLAY")
        btn.text:SetPoint("TOPLEFT", 2, -2)
        btn.text:SetPoint("TOPRIGHT", -2, -2)
        btn.text:SetJustifyH("LEFT")
        btn.text:SetWordWrap(true)
        
        -- Enable mouse
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        table.insert(trackableButtons, btn)
    end
    
    -- Reset parts other renderers add to pooled buttons
    if btn._ftaCounter then btn._ftaCounter:Hide() end
    -- The quest-area highlight belongs to whichever quest last used this button; the
    -- quest renderer re-applies it, every other renderer must not inherit it.
    if btn._areaLit or btn._areaQuestID then addon:ApplyQuestAreaHighlight(btn, nil) end
    
    -- IMPORTANT: Clear points on reuse to prevent anchor conflicts
    btn:ClearAllPoints()
    btn:Show()
    
    -- Hide any lingering children like progress bars
    if btn.progressBars then
        for _, frame in pairs(btn.progressBars) do
            frame:Hide()
        end
    end
    -- Objective lines a previous row left behind (RenderTrackableItem re-shows
    -- the ones it uses).
    for _, key in ipairs(OBJECTIVE_PART_KEYS) do
        local arr = btn[key]
        if arr then
            for i = 1, #arr do arr[i]:Hide() end
        end
    end
    if btn.styledBackdrop then btn.styledBackdrop:Hide() end

    -- Reset quest-specific child controls so pooled buttons don't leak icons
    if btn.poiButton then
        btn.poiButton.questID = nil
        -- Drop any stale super-track highlight, so a recycled row can't inherit the
        -- previous occupant's selected state if this render doesn't repaint it.
        if btn.poiButton.ClearSelected then
            btn.poiButton:ClearSelected()
        end
        btn.poiButton:Hide()
    end
    if btn.itemButton then
        btn.itemButton.itemLink = nil
        btn.itemButton:Hide()
        -- Clear the reference itself, not just its state: the secure-button pool is
        -- indexed by a flat per-render counter, so a stale (but non-nil) reference here
        -- can alias a different pooled secure button that a *different* row legitimately
        -- claims later in the same or a later render pass, and this reset would then
        -- hide that other row's active item button out from under it.
        btn.itemButton = nil
    end
    if btn.groupButton then
        btn.groupButton.questID = nil
        btn.groupButton:Hide()
        btn.groupButton:ClearAllPoints()
    end
    
    return btn
end

-- Get or create a secure button for Queue/Item use
function addon:GetOrCreateSecureButton(parent)
    activeSecureButtons = activeSecureButtons + 1
    
    local button
    if secureButtons[activeSecureButtons] then
        button = secureButtons[activeSecureButtons]
    else
        -- Create new secure button
        button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
        button:SetSize(20, 20)
        
        -- Icon
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        
        -- Cooldown
        button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        button.cooldown:SetAllPoints()
        button.cooldown:SetHideCountdownNumbers(false)
        
        -- Hover
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        
        -- Register
        button:RegisterForClicks("AnyUp", "AnyDown")
        
        table.insert(secureButtons, button)
    end
    
    -- Secure frames can't be reparented in combat; renders then reuse the old parent.
    if not InCombatLockdown() then
        button:SetParent(parent)
    end
    
    return button
end

-- Insert a link into the active chat box, opening chat first if none is active.
-- ChatFrameUtil replaces the ChatEdit_* globals on newer clients.
local function InsertChatLink(link)
    if not link then return end

    local insertLink = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if insertLink and insertLink(link) then return end

    local openChat = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if openChat then openChat(link) end
end

function addon:LinkQuestToChat(questID)
    if not questID then return end
    InsertChatLink(GetQuestLink(questID))
end

-- Same link calls Blizzard's own tracker modules make on a CHATLINK click.
local function GetTrackableLink(trackable)
    local t, id = trackable.type, trackable.id
    if t == "achievement" then
        return GetAchievementLink and GetAchievementLink(id)
    elseif t == "profession" then
        return C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink and C_TradeSkillUI.GetRecipeLink(id)
    elseif t == "monthly" then
        return C_PerksActivities and C_PerksActivities.GetPerksActivityChatLink
            and C_PerksActivities.GetPerksActivityChatLink(id)
    elseif t == "endeavor" then
        return C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetInitiativeTaskChatLink
            and C_NeighborhoodInitiative.GetInitiativeTaskChatLink(id)
    end
    local questID = trackable.questID or id
    return questID and GetQuestLink(questID)
end

function addon:LinkTrackableToChat(trackable)
    if not trackable then return end
    InsertChatLink(GetTrackableLink(trackable))
end

-- Untrack a non-quest trackable. Returns true when the type supports it.
function addon:StopTrackingTrackable(trackable)
    local t, id = trackable.type, trackable.id
    if t == "achievement" then
        if C_ContentTracking and C_ContentTracking.StopTracking then
            C_ContentTracking.StopTracking(Enum.ContentTrackingType.Achievement, id, Enum.ContentTrackingStopType.Manual)
        elseif RemoveTrackedAchievement then
            RemoveTrackedAchievement(id)
        end
    elseif t == "profession" then
        C_TradeSkillUI.SetRecipeTracked(id, false, trackable.isRecraft)
    elseif t == "monthly" then
        -- C_PerksActivities, not C_PerksProgram: the latter is the vendor
        -- side of the feature and has no tracking functions.
        if not (C_PerksActivities and C_PerksActivities.RemoveTrackedPerksActivity) then return false end
        C_PerksActivities.RemoveTrackedPerksActivity(id)
    elseif t == "endeavor" then
        if not (C_NeighborhoodInitiative and C_NeighborhoodInitiative.RemoveTrackedInitiativeTask) then return false end
        C_NeighborhoodInitiative.RemoveTrackedInitiativeTask(id)
    else
        return false
    end
    self:RequestUpdate()
    return true
end

-- Open the world map on a quest's zone. Super-tracking is left to the quest's POI
-- button, so a plain click never changes which quest is focused.
--
-- Deliberately does not open the quest's details pane. Any map work done from addon
-- code taints it, and the map's quest pins then hit a blocked SetPassThroughButtons
-- call when Blizzard refreshes them:
--   * ToggleWorldMap() acquires pins under our taint, and Blizzard reuses them later
--     even on a plain M-key open.
--   * QuestMapFrame_ShowQuestDetails() stores the quest in DetailsFrame.questID, which
--     every quest-pin refresh reads (QuestMapFrame_GetFocusedQuestID), so even a
--     secure QUEST_LOG_UPDATE refresh turns tainted while that pane is up.
-- C_Map.OpenWorldMap fires WORLD_MAP_OPEN for Blizzard's own handler to answer, so
-- the map opens without running any map code as us.
--
-- In place of the details pane, the clicked quest is scrolled into view in the map's
-- quest list and given a glow (see the quest list focus section below). Both stay
-- clear of anything the pins read.
function addon:OpenMapToQuest(questID)
    if not questID then return end

    self:SetQuestLogFocus(questID)

    if WorldMapFrame and WorldMapFrame:IsShown() then
        -- The list is already built, so no rebuild is coming to apply the focus.
        self:ApplyQuestLogFocus()
        return
    end

    if C_Map and C_Map.OpenWorldMap then
        local mapID = GetQuestUiMapID and GetQuestUiMapID(questID)
        C_Map.OpenWorldMap(mapID and mapID > 0 and mapID or nil)
    else
        -- No taint-free route on this client; opening the map is still worth it.
        ToggleWorldMap()
    end

    -- The list's rows can be laid out without final screen positions until the next
    -- frame, which would leave the first scroll attempt short.
    C_Timer.After(0, function() addon:ApplyQuestLogFocus() end)
end

-------------------------------------------------------------------------------
-- Quest list focus: the quest last clicked in the tracker, highlighted in the map's
-- quest list until the map closes.
--
-- Blizzard rebuilds the list from its row pools on every QuestLogQuests_Update, so
-- the glow is re-applied from a post-hook each time. Only our own textures are added
-- to the rows, kept in a weak table rather than as fields on Blizzard's pooled
-- buttons, and scrolling goes through ScrollToQuest, which only reads row positions
-- and moves the scroll frame. Nothing that the map's pin refresh reads is written.
-------------------------------------------------------------------------------
local QUEST_LOG_FOCUS_ATLAS = "questlog-quest-glow-yellow"
local QUEST_LOG_FOCUS_ALPHA = 0.6

local focusGlows = setmetatable({}, { __mode = "k" })
local questLogFocusID = nil
-- Scrolling happens once per click, not on every rebuild, or each quest update would
-- yank the list back while the player scrolls it.
local questLogFocusScrollPending = false

local function FindQuestLogTitle(questID)
    local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not (questID and pool) then return nil end
    for titleFrame in pool:EnumerateActive() do
        if titleFrame.questID == questID then
            return titleFrame
        end
    end
end

function addon:SetQuestLogFocus(questID)
    questLogFocusID = questID
    questLogFocusScrollPending = questID ~= nil

    -- The list leaves out quests under collapsed headers, so open the quest's header.
    -- ExpandQuestHeader is C-side; the resulting QUEST_LOG_UPDATE rebuilds the list
    -- securely and the hook below then finishes the scroll.
    if questID and ExpandQuestHeader and C_QuestLog.GetHeaderIndexForQuest then
        local headerIndex = C_QuestLog.GetHeaderIndexForQuest(questID)
        local info = headerIndex and C_QuestLog.GetInfo(headerIndex)
        if info and info.isCollapsed then
            ExpandQuestHeader(headerIndex)
        end
    end
end

function addon:ApplyQuestLogFocus()
    for _, glow in pairs(focusGlows) do
        glow:Hide()
    end

    local titleFrame = FindQuestLogTitle(questLogFocusID)
    if not titleFrame then return end

    local glow = focusGlows[titleFrame]
    if not glow then
        glow = titleFrame:CreateTexture(nil, "BACKGROUND")
        glow:SetAtlas(QUEST_LOG_FOCUS_ATLAS)
        glow:SetAllPoints(titleFrame)
        glow:SetAlpha(QUEST_LOG_FOCUS_ALPHA)
        focusGlows[titleFrame] = glow
    end
    glow:Show()

    -- ScrollToQuest compares screen positions, which a freshly laid-out row may not
    -- have yet; the pending flag then carries the scroll to the next attempt.
    if questLogFocusScrollPending and QuestScrollFrame.ScrollToQuest
        and titleFrame:GetTop() and QuestScrollFrame:GetTop() then
        questLogFocusScrollPending = false
        QuestScrollFrame:ScrollToQuest(questLogFocusID)
    end
end

-- Called from Initialize, and again from MapPOIColor.lua if Blizzard_WorldMap loads
-- later (or earlier, before Initialize), so it must only hook once.
local questLogFocusHooked = false

function addon:InitQuestLogFocus()
    if questLogFocusHooked then return end
    if not (QuestLogQuests_Update and WorldMapFrame) then return end
    questLogFocusHooked = true

    hooksecurefunc("QuestLogQuests_Update", function()
        if questLogFocusID then
            addon:ApplyQuestLogFocus()
        end
    end)

    WorldMapFrame:HookScript("OnHide", function()
        addon:SetQuestLogFocus(nil)
        addon:ApplyQuestLogFocus()
    end)
end

-- Handle trackable click
function addon:OnTrackableClick(trackable, mouseButton)
    if not trackable then return end
    
    if mouseButton == "LeftButton" then
        if IsShiftKeyDown() then
            -- Shift+Left: Link to Chat (untracking lives in the right-click menu)
            self:LinkTrackableToChat(trackable)
        else
            -- Left click: Focus/navigate to quest
            if trackable.type == "autoquest" then
                if trackable.popUpType == "COMPLETE" then
                     if ShowQuestComplete then ShowQuestComplete(trackable.questID) end
                elseif trackable.popUpType == "OFFER" then
                     if ShowQuestOffer then ShowQuestOffer(trackable.questID) end
                end
            elseif trackable.type == "quest" or trackable.type == "campaign" or trackable.type == "supertrack" then
                local questID = trackable.id or trackable.questID
                -- Show on map, unless its details are already open there.
                local alreadyShown = QuestMapFrame and QuestMapFrame.GetDetailQuestID
                    and QuestMapFrame:GetDetailQuestID() == questID and QuestMapFrame:IsVisible()
                if questID and not alreadyShown then
                    self:OpenMapToQuest(questID)
                end
            elseif trackable.type == "achievement" then
                -- Open achievement UI
                if not AchievementFrame then
                    AchievementFrame_LoadUI()
                end
                if AchievementFrame then
                    ShowUIPanel(AchievementFrame)
                    AchievementFrame_SelectAchievement(trackable.id)
                end
            elseif trackable.type == "profession" then
                local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(trackable.id)
                if info and info.professionID and C_TradeSkillUI.OpenTradeSkill then
                    C_TradeSkillUI.OpenTradeSkill(info.professionID)
                end

                if C_TradeSkillUI.OpenRecipe then
                    local function TryOpenRecipe()
                        C_TradeSkillUI.OpenRecipe(trackable.id)
                    end

                    -- The profession frame may still be loading; retry as it settles.
                    TryOpenRecipe()
                    C_Timer.After(0, TryOpenRecipe)
                    C_Timer.After(0.2, TryOpenRecipe)
                    C_Timer.After(0.5, TryOpenRecipe)
                end
            elseif trackable.type == "monthly" then
                if not EncounterJournal then EncounterJournal_LoadUI() end
                if not EncounterJournal:IsShown() then ToggleEncounterJournal() end
                -- Switch to the Traveler's Log tab where the client supports it.
                if EncounterJournal_DisplayMonthlyActivities then
                    EncounterJournal_DisplayMonthlyActivities()
                end
            elseif trackable.type == "endeavor" then
                if HousingFramesUtil and HousingFramesUtil.OpenFrameToTaskID then
                    HousingFramesUtil.OpenFrameToTaskID(trackable.id)
                end
            end
        end
    elseif mouseButton == "RightButton" then
        -- Right click: Context Menu
        if trackable.type == "quest" or trackable.type == "campaign" or trackable.type == "supertrack" then
            local questID = trackable.id or trackable.questID
            if not questID then return end
            MenuUtil.CreateContextMenu(UIParent, function(owner, rootDescription)
                rootDescription:CreateTitle(trackable.title)
                
                -- Focus (Super Track)
                rootDescription:CreateButton("Focus Quest", function()
                    C_SuperTrack.SetSuperTrackedQuestID(questID)
                end)
                
                -- Stop Tracking
                rootDescription:CreateButton("Stop Tracking", function()
                    C_QuestLog.RemoveQuestWatch(questID)
                    addon:RequestUpdate()
                end)
                
                -- Open Quest Log (Show in Map)
                rootDescription:CreateButton("Show in Quest Log", function()
                    addon:OpenMapToQuest(questID)
                end)
                
                -- Share
                if IsInGroup() then
                    rootDescription:CreateButton("Share Quest", function()
                        C_QuestLog.SetSelectedQuest(questID)
                        QuestLogPushQuest()
                    end)
                end
                
                -- Link to Chat
                rootDescription:CreateButton("Link to Chat", function()
                    addon:LinkQuestToChat(questID)
                end)
                
                -- Abandon (Cautious)
                rootDescription:CreateButton("Abandon Quest", function()
                    C_QuestLog.SetSelectedQuest(questID)
                    C_QuestLog.SetAbandonQuest()
                    local title = C_QuestLog.GetTitleForQuestID(questID)
                    StaticPopup_Show("ABANDON_QUEST", title)
                end)
            end)
        elseif trackable.type == "achievement" or trackable.type == "profession"
            or trackable.type == "monthly" or trackable.type == "endeavor" then
            MenuUtil.CreateContextMenu(UIParent, function(owner, rootDescription)
                rootDescription:CreateTitle(trackable.title)

                rootDescription:CreateButton("Link to Chat", function()
                    addon:LinkTrackableToChat(trackable)
                end)

                rootDescription:CreateButton("Stop Tracking", function()
                    addon:StopTrackingTrackable(trackable)
                end)
            end)
        end
    end
end

-- Sets every stored MINOR_<type>_* header under a major key to `value`.
local function SetChildHeaders(collapsedHeaders, majorKey, value)
    local prefix = "MINOR_" .. majorKey:sub(#"MAJOR_" + 1) .. "_"
    for k in pairs(collapsedHeaders) do
        if k:sub(1, #prefix) == prefix then
            collapsedHeaders[k] = value
        end
    end
end

-- Toggle header collapse state
function addon:ToggleHeader(key, recursive)
    local collapsedHeaders = self.db.collapsedHeaders

    -- Toggling a quest zone header by hand overrides auto-minimize, which would
    -- otherwise undo the click on the next paint. Turn it off until re-enabled.
    if self.db.autoMinimizeHeaders and key
        and (key:find("^MINOR_quest_") or (recursive and key == "MAJOR_quest")) then
        self:SetAutoMinimize(false)
    end

    if recursive and key:find("^MAJOR_") then
        -- Shift+Click: the major header stays expanded either way.
        if not collapsedHeaders[key] then
            -- Currently expanded: collapse every child, both the ones rendered last
            -- pass and any stored ones.
            collapsedHeaders[key] = false
            for _, minorKey in ipairs(self.knownMinorKeys and self.knownMinorKeys[key] or {}) do
                collapsedHeaders[minorKey] = true
            end
            SetChildHeaders(collapsedHeaders, key, true)
        else
            -- Currently collapsed: expand it and all children (nil = expanded).
            collapsedHeaders[key] = false
            SetChildHeaders(collapsedHeaders, key, nil)
        end
    else
        collapsedHeaders[key] = not collapsedHeaders[key]
    end
    
    self:RequestUpdate()
end
