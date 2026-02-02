---@diagnostic disable: undefined-global
local addonName, addon = ... -- Version: ForceUpdate1

-- Settings panel using manual frame construction for maximum control
local panel = CreateFrame("Frame", "TrackerPlusOptionsPanel")
panel.name = "TrackerPlus"

-- Modern scroll frame setup
local scrollFrame = CreateFrame("ScrollFrame", addonName .. "SettingsScrollFrame", panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 5, -35) -- Adjusted for Tabs
scrollFrame:SetPoint("BOTTOMRIGHT", -27, 4)

-- Content frame (this will hold all our controls)
local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(600, 1000) -- Initial height, will be adjusted dynamically
scrollFrame:SetScrollChild(content)

-- Helper: Create Header
local function CreateHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, yOffset)
    header:SetText(text)
    return yOffset - 30  -- Return updated offset
end

-- Helper: Create Checkbox
local function CreateCheckbox(parent, text, dbKey, tooltip, yOffset)
    local cb = CreateFrame("CheckButton", addonName .. dbKey .. "Check", parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, yOffset)
    getglobal(cb:GetName() .. "Text"):SetText(text)
    
    -- Load saved state
    cb:SetChecked(addon.db[dbKey])
    
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        addon:SetSetting(dbKey, checked)
        
        -- Trigger immediate updates based on setting
        if dbKey == "enabled" then
            addon:SetTrackerVisible(checked)
        elseif dbKey == "locked" then
            addon:UpdateTrackerLock()
        elseif dbKey == "borderEnabled" then
            addon:UpdateTrackerAppearance()
        elseif dbKey:find("show") or dbKey:find("fade") or dbKey:find("Group") then
            addon:RefreshDisplay()
        elseif dbKey == "hideInInstance" or dbKey == "hideInCombat" then
            addon:RequestUpdate()
        elseif dbKey == "showTooltips" then
            -- These take effect on next interaction
        end
    end)
    
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    return yOffset - 30
end

-- Helper: Create Slider
local function CreateSlider(parent, text, dbKey, minVal, maxVal, step, tooltip, yOffset)
    local slider = CreateFrame("Slider", addonName .. dbKey .. "Slider", parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 20, yOffset - 10) -- Give some room for label
    slider:SetWidth(200)
    slider:SetHeight(17)
    slider:SetOrientation("HORIZONTAL")
    
    local label = getglobal(slider:GetName() .. "Text")
    local low = getglobal(slider:GetName() .. "Low")
    local high = getglobal(slider:GetName() .. "High")
    
    local val = addon.db[dbKey] or minVal
    label:SetText(text .. ": " .. val)
    low:SetText(minVal)
    high:SetText(maxVal)
    
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(val)
    
    slider:SetScript("OnValueChanged", function(self, value)
        -- Round value if step >= 1
        if step >= 1 then
            value = math.floor(value + 0.5)
        else
            value = math.floor(value * 100) / 100
        end
        
        addon:SetSetting(dbKey, value)
        label:SetText(text .. ": " .. value)
        
        -- Immediate updates
        if dbKey == "frameWidth" or dbKey == "frameHeight" or dbKey == "frameScale" then
            addon:UpdateTrackerAppearance()
        elseif dbKey == "fontSize" or dbKey == "headerFontSize" then
            addon:RefreshDisplay()
        end
    end)
    
    if tooltip then
        slider:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    return yOffset - 50 -- Sliders need more vertical space
end

-- Helper: Create Color Picker
local function CreateColorPicker(parent, text, dbKey, callback, yOffset)
    local container = CreateFrame("Button", nil, parent)
    container:SetSize(300, 24)
    container:SetPoint("TOPLEFT", 16, yOffset)
    
    -- Color swatch
    local swatch = CreateFrame("Frame", nil, container)
    swatch:SetSize(20, 20)
    swatch:SetPoint("LEFT", 0, 0)
    
    -- Swatch border
    local bg = swatch:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 1) -- White border check
    
    -- Swatch color
    local colorTex = swatch:CreateTexture(nil, "OVERLAY")
    colorTex:SetPoint("TOPLEFT", 1, -1)
    colorTex:SetPoint("BOTTOMRIGHT", -1, 1)
    
    -- Label
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", swatch, "RIGHT", 5, 0)
    label:SetText(text)
    
    -- Update function
    local function UpdateSwatch()
        local c = addon.db[dbKey]
        if c then
            colorTex:SetColorTexture(c.r, c.g, c.b, c.a or 1)
        end
    end
    UpdateSwatch()
    
    -- Click handler
    container:SetScript("OnClick", function()
        local c = addon.db[dbKey]
        
        local info = {
            r = c.r, g = c.g, b = c.b, opacity = c.a,
            hasOpacity = true,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = 1
                if ColorPickerFrame.GetColorAlpha then
                    a = ColorPickerFrame:GetColorAlpha()
                elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
                    a = OpacitySliderFrame:GetValue()
                end
                
                addon.db[dbKey] = {r = r, g = g, b = b, a = a}
                UpdateSwatch()
                if callback then callback() end
            end,
            opacityFunc = function()
                -- Called when opacity changes
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = 1
                if ColorPickerFrame.GetColorAlpha then
                     a = ColorPickerFrame:GetColorAlpha()
                elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
                     a = OpacitySliderFrame:GetValue()
                end
                
                addon.db[dbKey] = {r = r, g = g, b = b, a = a}
                UpdateSwatch()
                if callback then callback() end
            end,
            cancelFunc = function()
                -- Restore original
                addon.db[dbKey] = c
                UpdateSwatch()
                if callback then callback() end
            end,
        }
        
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    
    return yOffset - 30
end

-- Initialize the Settings UI
local function InitUI()
    local pages = {}
    local tabs = {}
    
    local function SelectTab(id)
        for i, tab in ipairs(tabs) do
            if i == id then
                if PanelTemplates_SelectTab then
                    PanelTemplates_SelectTab(tab)
                else
                    tab:Disable() -- Visual indication for selected
                end
                
                if pages[i] then 
                    pages[i]:Show() 
                    -- Update content height
                    if pages[i].finalHeight then
                         content:SetHeight(pages[i].finalHeight)
                    end
                end
            else
                if PanelTemplates_DeselectTab then
                    PanelTemplates_DeselectTab(tab)
                else
                    tab:Enable()
                end
                
                if pages[i] then pages[i]:Hide() end
            end
        end
        scrollFrame:SetVerticalScroll(0)
    end
    
    local function CreateTabs(parent)
        local tabNames = {"General", "Appearance", "Tracking"}
        local prevTab
        
        for i, name in ipairs(tabNames) do
            local tab = CreateFrame("Button", addonName.."Tab"..i, parent, "PanelTopTabButtonTemplate")
            tab:SetID(i)
            tab:SetText(name)
            tab:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
            
            if i == 1 then
                tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -5)
            else
                tab:SetPoint("LEFT", prevTab, "RIGHT", -5, 0)
            end
            
            if PanelTemplates_TabResize then
                PanelTemplates_TabResize(tab, 0)
            else
                 local textWidth = tab:GetFontString():GetStringWidth()
                 tab:SetWidth(textWidth + 20)
            end

            table.insert(tabs, tab)
            prevTab = tab
        end
    end

    CreateTabs(panel)
    
    local function CreatePage()
        local page = CreateFrame("Frame", nil, content)
        page:SetSize(600, 100)
        page:SetPoint("TOPLEFT")
        page:SetPoint("TOPRIGHT")
        page:Hide()
        table.insert(pages, page)
        return page
    end
    
    -- Page 1: General
    local p1 = CreatePage()
    local yOffset = -16
    yOffset = CreateHeader(p1, "General Settings", yOffset)
    yOffset = CreateCheckbox(p1, "Enable Tracker", "enabled", "Enable or disable the tracker", yOffset)
    yOffset = CreateCheckbox(p1, "Lock Frame", "locked", "Lock the tracker frame position", yOffset)
    
    yOffset = CreateHeader(p1, "Advanced Options", yOffset)
    yOffset = CreateCheckbox(p1, "Hide in Instance", "hideInInstance", "Hide tracker when inside a dungeon/raid", yOffset)
    yOffset = CreateCheckbox(p1, "Hide in Combat", "hideInCombat", "Hide tracker during combat", yOffset)
    yOffset = CreateCheckbox(p1, "Fade When Empty", "fadeWhenEmpty", "Hide frame if no quests tracked", yOffset)
    yOffset = CreateCheckbox(p1, "Show Tooltips", "showTooltips", "Show quest details on hover", yOffset)

    yOffset = yOffset - 20
    local resetBtn = CreateFrame("Button", nil, p1, "UIPanelButtonTemplate")
    resetBtn:SetSize(150, 25)
    resetBtn:SetPoint("TOPLEFT", 16, yOffset)
    resetBtn:SetText("Reset All Settings")
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("TRACKERPLUS_RESET_CONFIRM")
    end)
    p1.finalHeight = math.abs(yOffset - 40) + 20
    
    -- Page 2: Appearance
    local p2 = CreatePage()
    local y = -16
    y = CreateHeader(p2, "Appearance", y)
    y = CreateSlider(p2, "Frame Width", "frameWidth", 150, 500, 10, "Width of the tracker frame", y)
    y = CreateSlider(p2, "Frame Height", "frameHeight", 200, 800, 10, "Height of the tracker frame", y)
    y = CreateSlider(p2, "Frame Scale", "frameScale", 0.5, 2.0, 0.1, "Scale of the tracker frame", y)
    y = CreateCheckbox(p2, "Show Border", "borderEnabled", "Show a border around the tracker", y)
    
    y = CreateHeader(p2, "Font Settings", y)
    y = CreateSlider(p2, "Font Size", "fontSize", 8, 24, 1, "Size of the quest text", y)
    y = CreateSlider(p2, "Header Size", "headerFontSize", 10, 28, 1, "Size of the headers", y)
    
    y = CreateHeader(p2, "Colors", y)
    local updateAppearance = function() addon:UpdateTrackerAppearance() end
    local updateDisplay = function() addon:RefreshDisplay() end
    
    y = CreateColorPicker(p2, "Background Color", "backgroundColor", updateAppearance, y)
    y = CreateColorPicker(p2, "Border Color", "borderColor", updateAppearance, y)
    y = CreateColorPicker(p2, "Header Text", "headerColor", updateDisplay, y)
    y = CreateColorPicker(p2, "Quest Text", "questColor", updateDisplay, y)
    y = CreateColorPicker(p2, "Objective Text", "objectiveColor", updateDisplay, y)
    y = CreateColorPicker(p2, "Completed Color", "completeColor", updateDisplay, y)
    y = CreateColorPicker(p2, "Failed Color", "failedColor", updateDisplay, y)
    p2.finalHeight = math.abs(y) + 20
    
    -- Page 3: Tracking
    local p3 = CreatePage()
    y = -16
    y = CreateHeader(p3, "Display Options", y)
    y = CreateCheckbox(p3, "Show Quest Level", "showQuestLevel", "Show the level of the quest", y)
    y = CreateCheckbox(p3, "Show Quest Type", "showQuestType", "Show type (Daily, Elite, etc.)", y)
    y = CreateCheckbox(p3, "Show Distance", "showDistance", "Show distance to objective in yards", y)
    y = CreateCheckbox(p3, "Show Zone Headers", "showZoneHeaders", "Group quests under zone headers", y)
    y = CreateCheckbox(p3, "Group by Zone", "groupByZone", "Sort quests into zone groups", y)
    
    y = CreateHeader(p3, "Trackable Types", y)
    y = CreateCheckbox(p3, "Quests", "showQuests", "Track regular quests", y)
    y = CreateCheckbox(p3, "World Quests", "showWorldQuests", "Track world quests", y)
    y = CreateCheckbox(p3, "Achievements", "showAchievements", "Track achievements", y)
    y = CreateCheckbox(p3, "Bonus Objectives", "showBonusObjectives", "Track bonus objectives", y)
    y = CreateCheckbox(p3, "Scenarios", "showScenarios", "Track scenarios and dungeons", y)
    y = CreateCheckbox(p3, "Professions", "showProfessions", "Track profession recipes/quests", y)
    y = CreateCheckbox(p3, "Monthly Activities", "showMonthlyActivities", "Track Trading Post / Traveler's Log activities", y)
    p3.finalHeight = math.abs(y) + 20

    SelectTab(1)
end

-- Confirmation dialog
StaticPopupDialogs["TRACKERPLUS_RESET_CONFIRM"] = {
    text = "Are you sure you want to reset all TrackerPlus settings to default?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        addon:ResetDatabase()
        addon:UpdateTrackerAppearance()
        addon:RefreshDisplay()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Register settings
local settingsLoaded = false
local settingsFrame = CreateFrame("Frame")
settingsFrame:RegisterEvent("PLAYER_LOGIN")
settingsFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if settingsLoaded then return end
        settingsLoaded = true
        
        -- Ensure database is initialized before building UI
        if not addon.db and addon.InitDatabase then
            addon:InitDatabase()
        end
        
        -- Build the UI
        InitUI() 
        
        -- Register with modern Settings API
        local category = Settings.RegisterCanvasLayoutCategory(panel, "TrackerPlus")
        Settings.RegisterAddOnCategory(category)
        
        -- Add slash command shortcut
        addon.OpenSettings = function()
            Settings.OpenToCategory(category:GetID())
        end
    end
end)
