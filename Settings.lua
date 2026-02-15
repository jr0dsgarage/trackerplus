---@diagnostic disable: undefined-global
local addonName, addon = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

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
    _G[cb:GetName() .. "Text"]:SetText(text)
    
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
        elseif dbKey == "headerIconPosition" then
             if addon.UpdateMinMaxState then addon:UpdateMinMaxState() end
             addon:RefreshDisplay()
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
    
    local label = _G[slider:GetName() .. "Text"]
    local low = _G[slider:GetName() .. "Low"]
    local high = _G[slider:GetName() .. "High"]
    
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
        if dbKey == "frameWidth" or dbKey == "frameHeight" or dbKey == "frameScale" or dbKey == "barBorderSize" then
            addon:UpdateTrackerAppearance()
            if dbKey == "barBorderSize" then addon:RefreshDisplay() end
        elseif dbKey == "fontSize" or dbKey == "headerFontSize" or dbKey:find("^spacing") then
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

-- Helper: Create Dropdown
local function CreateDropdown(parent, text, dbKey, options, tooltip, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 16, yOffset - 5)
    label:SetText(text)
    
    local dropdown = CreateFrame("Frame", addonName .. dbKey .. "Dropdown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", 140, yOffset) -- Use fixed offset to align with others
    UIDropDownMenu_SetWidth(dropdown, 140)
    
    local function init(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, opt in ipairs(options) do
            info.text = opt.text
            info.value = opt.value
            info.func = function(self)
                addon:SetSetting(dbKey, self.value)
                UIDropDownMenu_SetSelectedValue(dropdown, self.value)
                
                -- Trigger updates
                if dbKey == "headerIconStyle" or dbKey == "headerIconPosition" or dbKey == "headerBackgroundStyle" then 
                    addon:RefreshDisplay() 
                end
            end
            info.checked = (addon.db[dbKey] == opt.value)
            UIDropDownMenu_AddButton(info, level)
        end
    end
    
    UIDropDownMenu_Initialize(dropdown, init)
    
    -- Set Initial Selection
    UIDropDownMenu_SetSelectedValue(dropdown, addon.db[dbKey])
    -- Force text update explicitly just in case
    local currentText = "Unknown"
    for _, opt in ipairs(options) do
        if opt.value == addon.db[dbKey] then currentText = opt.text break end
    end
    UIDropDownMenu_SetText(dropdown, currentText)
    
    if tooltip then
        dropdown:SetScript("OnEnter", function(self)
             GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
             GameTooltip:SetText(text, 1, 1, 1)
             GameTooltip:AddLine(tooltip, nil, nil, nil, true)
             GameTooltip:Show()
        end)
        dropdown:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    return yOffset - 35
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

-- Helper: Start a Boxed Section
local function StartSection(parent, title, yOffset)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset) -- Anchor relative to parent
    frame:SetPoint("RIGHT", parent, "RIGHT", -15, 0) -- Stretch to right
    
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.4)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    label:SetPoint("TOPLEFT", 10, -10)
    label:SetText(title)
    
    return frame, -35 -- Initial innerY for content inside
end

-- Helper: End a Boxed Section
local function EndSection(frame, innerY)
    local height = math.abs(innerY) + 5
    frame:SetHeight(height)
    return height + 15 -- Return total consumed height (height + margin)
end

-- External update function to sync UI with DB changes (e.g. from resizing)
function addon:UpdateSettingWidgets()
    -- Helpers to update specific types if needed
    local function UpdateSlider(dbKey)
        local slider = _G[addonName .. dbKey .. "Slider"]
        if slider and addon.db[dbKey] then
            -- Temporarily disable script to prevent feedback loop
            local oldScript = slider:GetScript("OnValueChanged")
            slider:SetScript("OnValueChanged", nil)
            slider:SetValue(addon.db[dbKey])
            slider:SetScript("OnValueChanged", oldScript)
            
            -- Update Text
            local label = _G[slider:GetName() .. "Text"]
            if label then
                local text = label:GetText() or ""
                -- Assuming text format "Name: Value"
                local name = text:match("^(.*):")
                if name then
                    -- Handle rounding if needed, but for frame dimension integers are fine.
                    -- If scale (float), might need formatting.
                    local msg = name .. ": " .. addon.db[dbKey]
                     if dbKey == "frameScale" then
                         msg = string.format("%s: %.2f", name, addon.db[dbKey])
                     end
                    label:SetText(msg)
                end
            end
        end
    end
    
    UpdateSlider("frameWidth")
    UpdateSlider("frameHeight")
    UpdateSlider("frameScale")
end

-- Initialize the Settings UI
local function InitUI()
    -- Title info
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("TrackerPlus")
    
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
    version:SetText("v1.0.0") -- Should ideally pull from TOC

    -- Global Settings (Outside Tabs)
    local globalFrame, gY = StartSection(panel, "Global Settings", -45)
    gY = CreateCheckbox(globalFrame, "Enable TrackerPlus", "enabled", "Enable or disable the tracker", gY)
    gY = CreateCheckbox(globalFrame, "Lock Panel", "locked", "Lock the tracker frame position", gY)
    local globalHeight = EndSection(globalFrame, gY)

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
        local tabNames = {"General", "Appearance", "Layout", "Tracking"}
        local prevTab
        
        for i, name in ipairs(tabNames) do
            local tab = CreateFrame("Button", addonName.."Tab"..i, parent, "PanelTopTabButtonTemplate")
            tab:SetID(i)
            tab:SetText(name)
            tab:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
            
            if i == 1 then
                -- Anchor tabs below global settings
                tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -(45 + globalHeight + 10)) 
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
        return -(45 + globalHeight + 40) -- Return Y start for scrollframe
    end

    local startY = CreateTabs(panel)

    -- Adjust ScrollFrame to be below tabs
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", 5, startY) 
    scrollFrame:SetPoint("BOTTOMRIGHT", -27, 4)

    
    local function CreatePage()
        local page = CreateFrame("Frame", nil, content)
        page:SetSize(600, 100)
        page:SetPoint("TOPLEFT")
        page:SetPoint("TOPRIGHT")
        page:Hide()
        table.insert(pages, page)
        return page
    end
    
    -- Page 1: General (Advanced)
    local p1 = CreatePage()
    local y = -5
    local s, sy
    
    s, sy = StartSection(p1, "Visibility & Behavior", y)
    sy = CreateCheckbox(s, "Hide in Instance", "hideInInstance", "Hide tracker when inside a dungeon/raid", sy)
    sy = CreateCheckbox(s, "Hide in Combat", "hideInCombat", "Hide tracker during combat", sy)
    sy = CreateCheckbox(s, "Fade When Empty", "fadeWhenEmpty", "Hide frame if no quests tracked", sy)
    sy = CreateCheckbox(s, "Show Tooltips", "showTooltips", "Show quest details on hover", sy)
    y = y - EndSection(s, sy)

    s, sy = StartSection(p1, "Data Management", y)
    -- Manual reset button creation since helper is specific
    local resetBtn = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    resetBtn:SetSize(150, 25)
    resetBtn:SetPoint("TOPLEFT", 16, sy)
    resetBtn:SetText("Reset All Settings")
    resetBtn:SetScript("OnClick", function() StaticPopup_Show("TRACKERPLUS_RESET_CONFIRM") end)
    sy = sy - 35
    y = y - EndSection(s, sy)
    
    p1.finalHeight = math.abs(y) + 20
    
    -- Page 2: Appearance
    local p2 = CreatePage()
    y = -5
    
    s, sy = StartSection(p2, "Dimensions", y)
    sy = CreateSlider(s, "Frame Width", "frameWidth", 150, 500, 1, "Width of the tracker frame", sy)
    sy = CreateSlider(s, "Frame Height", "frameHeight", 200, 800, 1, "Height of the tracker frame", sy)
    sy = CreateSlider(s, "Frame Scale", "frameScale", 0.5, 2.0, 0.1, "Scale of the tracker frame", sy)
    y = y - EndSection(s, sy)
    
    s, sy = StartSection(p2, "Styling", y)
    sy = CreateCheckbox(s, "Show Border", "borderEnabled", "Show a border around the tracker", sy)
    sy = CreateDropdown(s, "Expand/Collapse Icon", "headerIconStyle", {
        {text = "None", value = "none"},
        {text = "Standard (Gold)", value = "standard"},
        {text = "Square (Check)", value = "square"},
        {text = "Text [+/-]", value = "text_brackets"},
        {text = "Quest Log (+/-)", value = "questlog"}
    }, "Style of the expand/collapse header icons", sy)
    
    sy = CreateDropdown(s, "Icon Position", "headerIconPosition", {
        {text = "Left (Start)", value = "left"},
        {text = "Right (End)", value = "right"}
    }, "Position of the expand/collapse icon on the header", sy)

    sy = CreateDropdown(s, "Header Background", "headerBackgroundStyle", {
        {text = "None", value = "none"},
        {text = "Quest Log Background", value = "questlog"},
        {text = "Tracker Background (Custom)", value = "tracker"}
    }, "Style of the header background", sy)

    -- Progress Bar Settings
    local barHeader = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    barHeader:SetPoint("TOPLEFT", 16, sy - 10)
    barHeader:SetText("Progress Bars")
    sy = sy - 30

    sy = CreateSlider(s, "Border Size", "barBorderSize", 1, 5, 1, "Thickness of the progress bar border", sy)

    -- Media Dropdown for Bar Texture
    local function CreateMediaDropdown(section, label, key, description, y)
        local frame = CreateFrame("Frame", nil, section, "UIDropDownMenuTemplate")
        frame:SetPoint("TOPLEFT", 0, y - 20)
        
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 16, 5)
        text:SetText(label)
        
        -- Tooltip
        local hitRect = CreateFrame("Frame", nil, frame)
        hitRect:SetAllPoints(text)
        hitRect:SetScript("OnEnter", function()
            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
            GameTooltip:SetText(description, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        hitRect:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        UIDropDownMenu_SetWidth(frame, 150)
        
        local function Initialize(self, level)
            local selected = addon.db[key]
            
            -- Get textures from LSM
            local lsmRef = LibStub and LibStub("LibSharedMedia-3.0", true)
            local textureList = lsmRef and lsmRef:List("statusbar") or {}
            
            -- Sort textures
            table.sort(textureList)
            
            -- Add Blizzard default if missing
            local found = false
            for _, v in ipairs(textureList) do if v == "Blizzard" then found = true break end end
            if not found then table.insert(textureList, 1, "Blizzard") end
            
            for _, name in ipairs(textureList) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = name
                info.value = name
                info.checked = (name == selected)
                info.func = function(self)
                    addon.db[key] = self.value
                    UIDropDownMenu_SetText(frame, self.value)
                    addon:UpdateTrackerAppearance()
                    addon:RefreshDisplay()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
        
        UIDropDownMenu_Initialize(frame, Initialize)
        -- Set initial text safely
        if addon.db[key] then
            UIDropDownMenu_SetText(frame, addon.db[key])
        else
            UIDropDownMenu_SetText(frame, "Blizzard")
        end
        
        return y - 50
    end
    
    sy = CreateMediaDropdown(s, "Bar Texture", "barTexture", "Texture used for progress bars", sy)

    y = y - EndSection(s, sy)
    
    s, sy = StartSection(p2, "Fonts", y)
    sy = CreateSlider(s, "Font Size", "fontSize", 8, 24, 1, "Size of the quest text", sy)
    sy = CreateSlider(s, "Header Size", "headerFontSize", 10, 28, 1, "Size of the headers", sy)
    y = y - EndSection(s, sy)
    
    s, sy = StartSection(p2, "Colors", y)
    local updateAppearance = function() addon:UpdateTrackerAppearance() end
    local updateDisplay = function() addon:RefreshDisplay() end
    sy = CreateColorPicker(s, "Background Color", "backgroundColor", updateAppearance, sy)
    sy = CreateColorPicker(s, "Border Color", "borderColor", updateAppearance, sy)
    sy = CreateColorPicker(s, "Header Text", "headerColor", updateDisplay, sy)
    sy = CreateColorPicker(s, "Quest Text", "questColor", updateDisplay, sy)
    
    sy = CreateColorPicker(s, "Bar Background", "barBackgroundColor", updateDisplay, sy)
    
    sy = CreateColorPicker(s, "Achievements", "achievementColor", updateDisplay, sy)
    sy = CreateColorPicker(s, "Professions", "professionColor", updateDisplay, sy)
    sy = CreateColorPicker(s, "Monthly Activities", "monthlyColor", updateDisplay, sy)
    sy = CreateColorPicker(s, "Endeavors", "endeavorColor", updateDisplay, sy)
    sy = CreateColorPicker(s, "Scenarios", "scenarioColor", updateDisplay, sy)
    sy = CreateColorPicker(s, "Bonus Objectives", "bonusColor", updateDisplay, sy)
    
    sy = CreateColorPicker(s, "Objective Text", "objectiveColor", updateDisplay, sy)
    sy = CreateColorPicker(s, "Completed Color", "completeColor", updateDisplay, sy)
    sy = CreateColorPicker(s, "Failed Color", "failedColor", updateDisplay, sy)
    y = y - EndSection(s, sy)
    
    p2.finalHeight = math.abs(y) + 20
    
    -- Page 3: Layout & Spacing
    local p3 = CreatePage()
    y = -5
    
    s, sy = StartSection(p3, "Horizontal Spacing", y)
    sy = CreateSlider(s, "Major Header Indent", "spacingMajorHeaderIndent", 0, 50, 1, "Left indent for major category headers (Quests, Achievements)", sy)
    sy = CreateSlider(s, "Minor Header Indent", "spacingMinorHeaderIndent", 0, 50, 1, "Left indent for zone/subgroup headers", sy)
    sy = CreateSlider(s, "Quest/Item Indent", "spacingTrackableIndent", 0, 50, 1, "Left indent for individual quests and trackables", sy)
    sy = CreateSlider(s, "POI Button Padding", "spacingPOIButton", 0, 50, 1, "Left padding for text when POI button is shown", sy)
    sy = CreateSlider(s, "Item Button Spacing", "spacingItemButton", 0, 50, 1, "Additional space when item/action button exists", sy)
    sy = CreateSlider(s, "Objective Indent", "spacingObjectiveIndent", 0, 50, 1, "Extra indent for objective lines (relative to quest)", sy)
    sy = CreateSlider(s, "Progress Bar Inset", "spacingProgressBarInset", 0, 50, 1, "Horizontal margin for progress bars from edges", sy)
    sy = CreateSlider(s, "Progress Bar Padding", "spacingProgressBarPadding", 0, 20, 1, "Vertical padding between text and progress bar", sy)
    y = y - EndSection(s, sy)
    
    s, sy = StartSection(p3, "Vertical Spacing", y)
    sy = CreateSlider(s, "Item Spacing", "spacingItemVertical", 0, 20, 1, "Vertical gap between trackable items", sy)
    sy = CreateSlider(s, "Major Header Gap", "spacingMajorHeaderAfter", 10, 50, 1, "Vertical space after major category headers", sy)
    sy = CreateSlider(s, "Minor Header Gap", "spacingMinorHeaderAfter", 10, 50, 1, "Vertical space after zone/subgroup headers", sy)
    y = y - EndSection(s, sy)
    
    p3.finalHeight = math.abs(y) + 20
    
    -- Page 4: Tracking
    local p4 = CreatePage()
    y = -5
    
    s, sy = StartSection(p4, "Display Options", y)
    sy = CreateCheckbox(s, "Show Quest Level", "showQuestLevel", "Show the level of the quest", sy)
    sy = CreateCheckbox(s, "Show Quest Type", "showQuestType", "Show type (Daily, Elite, etc.)", sy)
    sy = CreateCheckbox(s, "Show Distance", "showDistance", "Show distance to objective in yards", sy)
    sy = CreateCheckbox(s, "Show Zone Headers", "showZoneHeaders", "Group quests under zone headers", sy)
    sy = CreateCheckbox(s, "Group by Zone", "groupByZone", "Sort quests into zone groups", sy)
    y = y - EndSection(s, sy)
    
    s, sy = StartSection(p4, "Trackable Types", y)
    sy = CreateCheckbox(s, "Quests", "showQuests", "Track regular quests", sy)
    sy = CreateCheckbox(s, "World Quests", "showWorldQuests", "Track world quests", sy)
    sy = CreateCheckbox(s, "Achievements", "showAchievements", "Track achievements", sy)
    sy = CreateCheckbox(s, "Bonus Objectives", "showBonusObjectives", "Track bonus objectives", sy)
    sy = CreateCheckbox(s, "Scenarios", "showScenarios", "Track scenarios and dungeons", sy)
    sy = CreateCheckbox(s, "Professions", "showProfessions", "Track profession recipes/quests", sy)
    sy = CreateCheckbox(s, "Monthly Activities", "showMonthlyActivities", "Track Trading Post / Traveler's Log activities", sy)
    sy = CreateCheckbox(s, "Endeavors", "showEndeavors", "Track housing endeavors", sy)
    y = y - EndSection(s, sy)
    
    p4.finalHeight = math.abs(y) + 20

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
