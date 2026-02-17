local addonName, addon = ...

-- Pools
local trackableButtons = {}
local secureButtons = {}
local activeButtons = 0
local activeSecureButtons = 0

-- Helper to create or update border lines
function addon:CreateBorderLines(bar, size)
    size = tonumber(size) or 1
    if size < 0 then size = 0 end
    local pixelSize = math.floor(size + 0.5)
    
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

-- Organize trackables into Major/Minor hierarchy
function addon:OrganizeTrackables(trackables)
    self.knownMinorKeys = {} -- Reset cache
    local organized = {}
    -- Scenarios should already be extracted by ExtractScenarios, but just in case
    
    local buckets = {
        quest = {},
        achievement = {},
        profession = {},
        monthly = {},
        endeavor = {},
    }
    
    -- Bucketing
    for _, item in ipairs(trackables) do
        local type = item.type
        if type ~= "scenario" then
            if not buckets[type] then buckets[type] = {} end
            table.insert(buckets[type], item)
        end
    end
    
    -- Function to sort and add buckets
    local function AddBucket(type, title)
        local items = buckets[type]
        if items and #items > 0 then
            -- Major Header
            local majorKey = "MAJOR_" .. type
            self.knownMinorKeys[majorKey] = {} -- Init cache for this header
            local majorCollapsed = self.db.collapsedHeaders[majorKey]
            
            table.insert(organized, {
                isHeader = true,
                headerType = "major",
                title = title,
                key = majorKey,
                collapsed = majorCollapsed
            })
            
            if not majorCollapsed then
                -- Group by Minor (Zone or Category)
                local zones = {}
                for _, item in ipairs(items) do
                    local zone = item.zone or "General"
                    -- Simplify "World Quest" zones
                    if item.isWorldQuest then zone = "World Quests - " .. zone end
                    
                    if not zones[zone] then zones[zone] = {} end
                    table.insert(zones[zone], item)
                end
                
                -- Sort Zones
                local sortedZones = {}
                for zoneName, _ in pairs(zones) do table.insert(sortedZones, zoneName) end
                table.sort(sortedZones)
                
                for _, zoneName in ipairs(sortedZones) do
                    local zoneItems = zones[zoneName]
                    local minorKey = "MINOR_" .. type .. "_" .. zoneName
                    table.insert(self.knownMinorKeys[majorKey], minorKey) -- Cache minor key
                    local minorCollapsed = self.db.collapsedHeaders[minorKey]
                    
                    -- Minor Header
                    table.insert(organized, {
                        isHeader = true,
                        headerType = "minor",
                        title = zoneName,
                        key = minorKey,
                        collapsed = minorCollapsed
                    })
                    
                    if not minorCollapsed then
                        -- Sort items inside zone
                        -- (Uses existing sorting logic if previously sorted, otherwise re-sort)
                        -- For now, just add them
                        for _, item in ipairs(zoneItems) do
                            table.insert(organized, item)
                        end
                    end
                end
            end
        end
    end
    
    -- Add in desired order
    AddBucket("quest", "Quests")
    -- AddBucket("scenario", "Dungeons & Scenarios") -- Scenarios handled separately
    AddBucket("achievement", "Achievements")
    AddBucket("profession", "Professions")
    AddBucket("monthly", "Monthly Activities")
    AddBucket("endeavor", "Endeavors")
    
    return organized
end

function addon:ResetButtonPool()
    activeButtons = 0
    activeSecureButtons = 0
end

function addon:FinalizeButtonPool()
    -- Hide only unused regular pooled buttons.
    for i = activeButtons + 1, #trackableButtons do
        trackableButtons[i]:Hide()
    end

    -- Hide unused secure pooled buttons only when safe.
    if not InCombatLockdown() then
        for i = activeSecureButtons + 1, #secureButtons do
            secureButtons[i]:Hide()
        end
    end
end

-- Get or create a button from the pool
function addon:GetOrCreateButton(parent)
    activeButtons = activeButtons + 1
    
    local btn
    if trackableButtons[activeButtons] then
        btn = trackableButtons[activeButtons]
        -- Re-parent if necessary
        if parent and btn:GetParent() ~= parent then
             btn:SetParent(parent)
        end
        btn:ClearAllPoints()
    else
        -- Create new button
        -- Note: If parent is nil here, it might be an issue, but usually parent is passed.
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
    
    -- Reset Custom Elements (Cleanup from potentially being used as a Popup/AutoQuest)
    if btn.popupBackdrop then btn.popupBackdrop:Hide() end
    if btn.largeIcon then btn.largeIcon:Hide() end
    if btn.stageBox then btn.stageBox:Hide() end
    if btn.subText then btn.subText:Hide() end
    
    -- IMPORTANT: Clear points on reuse to prevent anchor conflicts
    btn:ClearAllPoints()
    btn:Show()
    
    -- Nuclear option: Ensure any lingering children like ProgressBars are hidden
    if btn.progressBars then
        for _, bar in pairs(btn.progressBars) do
            bar:Hide()
        end
    end
    if btn.objectives then
        for _, obj in pairs(btn.objectives) do
            obj:Hide()
        end
    end
    if btn.distance then btn.distance:Hide() end
    if btn.stageBox then btn.stageBox:Hide() end
    if btn.styledBackdrop then btn.styledBackdrop:Hide() end
    if btn.SetBackdrop then btn:SetBackdrop(nil) end
    
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
    
    -- Re-parenting secure frames in combat is restricted, so we ensure this is only called out of combat.
    -- If we are in combat, we can't reparent securely, but this function is likely called during update which is combat-protected usually?
    -- Actually, render updates might be delayed until after combat.
    if not InCombatLockdown() then
        button:SetParent(parent)
    end
    
    return button
end

-- Handle trackable click
function addon:OnTrackableClick(trackable, mouseButton)
    if not trackable then return end
    
    if mouseButton == "LeftButton" then
        if IsShiftKeyDown() then
             -- Shift+Left: Stop Tracking
            if trackable.type == "quest" then
                C_QuestLog.RemoveQuestWatch(trackable.id)
            elseif trackable.type == "achievement" then
                if C_ContentTracking and C_ContentTracking.StopTracking then
                    C_ContentTracking.StopTracking(Enum.ContentTrackingType.Achievement, trackable.id, Enum.ContentTrackingStopType.Manual)
                elseif RemoveTrackedAchievement then
                    RemoveTrackedAchievement(trackable.id)
                end
            elseif trackable.type == "profession" then
                C_TradeSkillUI.SetRecipeTracked(trackable.id, false, trackable.isRecraft)
            elseif trackable.type == "monthly" then
                C_PerksProgram.RemoveTrackedPerksActivity(trackable.id)
            elseif trackable.type == "endeavor" then
                if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RemoveTrackedInitiativeTask then
                     C_NeighborhoodInitiative.RemoveTrackedInitiativeTask(trackable.id)
                else
                    print("Shift-click to remove Endeavors not supported.")
                end
            end
            self:RequestUpdate()
        else
            -- Left click: Focus/navigate to quest
            if trackable.type == "autoquest" then
                if trackable.popUpType == "COMPLETE" then
                     if ShowQuestComplete then ShowQuestComplete(trackable.questID) end
                elseif trackable.popUpType == "OFFER" then
                     if ShowQuestOffer then ShowQuestOffer(trackable.questID) end
                end
            elseif trackable.type == "quest" then
                local questID = trackable.id
                if questID then
                    -- Show on map
                    if QuestMapFrame and QuestMapFrame.GetDetailQuestID and QuestMapFrame:GetDetailQuestID() == questID and QuestMapFrame:IsVisible() then
                        -- Already shown, do nothing or toggle? Standard behavior is just show.
                    else
                        -- Ensure map is open
                        if not WorldMapFrame or not WorldMapFrame:IsShown() then
                             ToggleWorldMap()
                        end
                        -- Select quest
                        if QuestMapFrame then
                             QuestMapFrame_ShowQuestDetails(questID)
                        end
                    end
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
                if C_TradeSkillUI.OpenRecipe then
                    C_TradeSkillUI.OpenRecipe(trackable.id)
                else
                    local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(trackable.id)
                    if info and info.professionID then
                        C_TradeSkillUI.OpenTradeSkill(info.professionID)
                    end
                end
            elseif trackable.type == "monthly" then
                if not EncounterJournal then EncounterJournal_LoadUI() end
                if not EncounterJournal:IsShown() then ToggleEncounterJournal() end
                -- Try to switch to Monthly Activities tab if possible (Tab 3 usually)
                -- Specific API to open directly to activity?
                -- EncounterJournal_DisplayMonthlyActivities() is standard if available
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
        if trackable.type == "quest" then
            MenuUtil.CreateContextMenu(UIParent, function(owner, rootDescription)
                rootDescription:CreateTitle(trackable.title)
                
                -- Focus (Super Track)
                rootDescription:CreateButton("Focus Quest", function()
                    C_SuperTrack.SetSuperTrackedQuestID(trackable.id)
                end)
                
                -- Stop Tracking
                rootDescription:CreateButton("Stop Tracking", function()
                    C_QuestLog.RemoveQuestWatch(trackable.id)
                    addon:RequestUpdate()
                end)
                
                -- Open Quest Log (Show in Map)
                rootDescription:CreateButton("Show in Quest Log", function()
                     if not WorldMapFrame or not WorldMapFrame:IsShown() then ToggleWorldMap() end
                     QuestMapFrame_ShowQuestDetails(trackable.id)
                end)
                
                -- Share
                if IsInGroup() then
                    rootDescription:CreateButton("Share Quest", function()
                        C_QuestLog.SetSelectedQuest(trackable.id)
                        QuestLogPushQuest()
                    end)
                end
                
                -- Link to Chat
                rootDescription:CreateButton("Link to Chat", function()
                    local link = GetQuestLink(trackable.id)
                    if link then
                        ChatEdit_InsertLink(link)
                    end
                end)
                
                -- Abandon (Cautious)
                rootDescription:CreateButton("Abandon Quest", function()
                    C_QuestLog.SetSelectedQuest(trackable.id)
                    C_QuestLog.SetAbandonQuest()
                    local title = C_QuestLog.GetTitleForQuestID(trackable.id)
                    StaticPopup_Show("ABANDON_QUEST", title)
                end)
            end)
        end
    end
end

-- Toggle header collapse state
function addon:ToggleHeader(key, recursive)
    if not self.db.collapsedHeaders then self.db.collapsedHeaders = {} end
    
    if recursive and key:find("MAJOR_") then
        -- Recursive toggling logic (Shift+Click)
        local currentState = self.db.collapsedHeaders[key]
        
        if not currentState then 
            -- Currently Expanded ([-]) -> Minimize Children
            self.db.collapsedHeaders[key] = false -- Keep Parent Expanded
            
            -- Collapse known children (from Render Cache)
            if self.knownMinorKeys and self.knownMinorKeys[key] then
                for _, minorKey in ipairs(self.knownMinorKeys[key]) do
                    self.db.collapsedHeaders[minorKey] = true
                end
            end
            
            -- Also catch persistent entries
            local type = key:match("MAJOR_(.+)")
            local prefix = "MINOR_" .. type .. "_"
            for k, _ in pairs(self.db.collapsedHeaders) do
                if k:find("^" .. prefix) then
                    self.db.collapsedHeaders[k] = true
                end
            end
        else
            -- Currently Collapsed ([+]) -> Expand All
            self.db.collapsedHeaders[key] = false -- Expand Parent
            
            -- Expand all children (remove from DB so they default to nil/Expanded)
            local type = key:match("MAJOR_(.+)")
            local prefix = "MINOR_" .. type .. "_"
            for k, _ in pairs(self.db.collapsedHeaders) do
                if k:find("^" .. prefix) then
                    self.db.collapsedHeaders[k] = nil
                end
            end
        end
    else
        -- Standard Click
        local newState = not self.db.collapsedHeaders[key]
        self.db.collapsedHeaders[key] = newState
    end
    
    self:RequestUpdate()
end

