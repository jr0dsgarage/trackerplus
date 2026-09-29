---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Settings panel using manual frame construction for maximum control
local panel = CreateFrame("Frame", "TrackerPlusOptionsPanel")
panel.name = "TrackerPlus"
local refreshDebugControlsUI = nil

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
        elseif dbKey == "matchBlizzardTracker" then
            -- Re-checking it should snap back onto the game's tracker immediately.
            if checked and addon.SyncWithBlizzardTracker then
                addon:SyncWithBlizzardTracker()
            end
        elseif dbKey == "colorMapPOIsByDifficulty" then
            -- Map pins are Blizzard's, outside our render pass entirely, so this only
            -- needs the outlines repainted.
            addon:RefreshMapPOIOutlines()
        elseif dbKey == "highlightQuestsInArea" then
            -- Starts or stops the area watcher; the stripe is an overlay on the
            -- existing rows, so no recollect or repaint is needed.
            addon:UpdateQuestAreaWatcher()
        elseif dbKey:find("show") or dbKey:find("fade") or dbKey:find("Group") or dbKey == "includeCampaignQuestInActiveQuest" or dbKey == "includeFTAQuests" or dbKey == "colorQuestsByDifficulty" then
            -- Colors (and quest inclusion/grouping) are computed in GetQuestData/
            -- CollectQuests at collection time, not at render time, so these need a
            -- full recollect rather than just a repaint.
            addon:RequestUpdate("full")
        elseif dbKey == "hideInInstance" or dbKey == "hideInCombat" then
            addon:RequestUpdate()
        elseif dbKey == "layoutDebug" then
            if addon.LogAt then
                addon:LogAt("info", "Layout debug %s", checked and "enabled" or "disabled")
            end
        elseif dbKey == "debugEnabled" then
            if addon.UpdateSectionDebugBoxes then
                addon:UpdateSectionDebugBoxes()
            end
            addon:RequestUpdate("full")
            if refreshDebugControlsUI then
                refreshDebugControlsUI()
            end
            print("|cff00ff00TrackerPlus:|r Debugging " .. (checked and "enabled" or "disabled") .. ".")
        elseif dbKey == "debugSectionBoxes" then
            if addon.UpdateSectionDebugBoxes then
                addon:UpdateSectionDebugBoxes()
            end
            addon:RequestUpdate("full")
        elseif dbKey == "showTooltips" then
            -- These take effect on next interaction
        end
    end)
    
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            local tooltipFrame = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
            tooltipFrame:SetText(text)
            tooltipFrame:AddLine(tooltip, nil, nil, nil, true)
            tooltipFrame:Show()
        end)
        cb:SetScript("OnLeave", function() addon:HideSharedTooltip() end)
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
        elseif dbKey == "mapPOIOutlineThickness" or dbKey == "mapPOIGlowOpacity" then
            -- Map pins are Blizzard's, outside our render pass entirely.
            addon:RefreshMapPOIOutlines()
        end
    end)
    
    if tooltip then
        slider:SetScript("OnEnter", function(self)
            local tooltipFrame = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
            tooltipFrame:SetText(text)
            tooltipFrame:AddLine(tooltip, nil, nil, nil, true)
            tooltipFrame:Show()
        end)
        slider:SetScript("OnLeave", function() addon:HideSharedTooltip() end)
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
                elseif dbKey == "sortMethod" then
                    -- Sorting happens in CollectTrackables, so this needs a full
                    -- recollect rather than just a repaint.
                    addon:RequestUpdate("full")
                elseif dbKey == "mapPOIOutlineStyle" then
                    -- Map pins are Blizzard's, outside our render pass entirely.
                    addon:RefreshMapPOIOutlines()
                elseif dbKey == "questAreaHighlightStyle" then
                    -- An overlay on the existing rows; restyle the lit ones in place.
                    addon:RefreshQuestAreaHighlights(true)
                elseif dbKey == "debugLevel" then
                    if addon.LogAt then
                        addon:LogAt("info", "Debug level set to %s", tostring(self.value))
                    end
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
               local tooltipFrame = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
               tooltipFrame:SetText(text)
               tooltipFrame:AddLine(tooltip, nil, nil, nil, true)
               tooltipFrame:Show()
        end)
           dropdown:SetScript("OnLeave", function() addon:HideSharedTooltip() end)
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
        addon:OpenColorPicker(addon.db[dbKey], function()
            UpdateSwatch()
            if callback then callback() end
        end)
    end)
    
    return yOffset - 30
end

-- Helper: Create Button
local function CreateButton(parent, text, width, onClick, yOffset)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 150, 25)
    btn:SetPoint("TOPLEFT", 16, yOffset)
    btn:SetText(text)
    btn:SetScript("OnClick", function()
        if onClick then onClick() end
    end)
    return yOffset - 35, btn
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
    
    -- Checkboxes that the addon can flip on its own (e.g. "Match Game Tracker"
    -- clears itself once the player drags or resizes the tracker).
    local function UpdateCheckbox(dbKey)
        local check = _G[addonName .. dbKey .. "Check"]
        if check then
            check:SetChecked(addon.db[dbKey] and true or false)
        end
    end

    UpdateSlider("frameWidth")
    UpdateSlider("frameHeight")
    UpdateSlider("frameScale")
    UpdateCheckbox("matchBlizzardTracker")
end

-- Initialize the Settings UI
local function InitUI()
    -- Title info
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("TrackerPlus")
    
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
    -- Read from the .toc rather than hardcoding, so it can't drift out of date.
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local addonVersion = getMetadata and getMetadata(addonName, "Version")
    version:SetText(addonVersion and ("v" .. addonVersion) or "")

    -- Global Settings (Parent page)
    local globalFrame, gY = StartSection(panel, "Global Settings", -45)
    gY = CreateCheckbox(globalFrame, "Enable TrackerPlus", "enabled", "Enable or disable the tracker", gY)
    gY = CreateCheckbox(globalFrame, "Lock Panel", "locked", "Lock the tracker frame position", gY)
    EndSection(globalFrame, gY)

    local overview = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    overview:SetPoint("TOPLEFT", globalFrame, "BOTTOMLEFT", 8, -8)
    overview:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    overview:SetJustifyH("LEFT")
    overview:SetText("Expand TrackerPlus in the Settings list to open General, Tracking, Nameplates, Appearance, Layout, and Debug pages.")

    local orderedPages = {}

    local function CreateSettingsPage(id, pageTitle, pageDescription)
        local page = CreateFrame("Frame", "TrackerPlusOptionsPage" .. id)
        page.name = pageTitle
        page.parent = panel.name

        local titleText = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        titleText:SetPoint("TOPLEFT", 16, -16)
        titleText:SetText(pageTitle)

        local descText = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        descText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -8)
        descText:SetPoint("RIGHT", page, "RIGHT", -16, 0)
        descText:SetJustifyH("LEFT")
        descText:SetText(pageDescription or "")

        local scrollFrame = CreateFrame("ScrollFrame", addonName .. "SettingsScrollFrame" .. id, page, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 5, -55)
        scrollFrame:SetPoint("BOTTOMRIGHT", -27, 4)

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(600, 100)
        scrollFrame:SetScrollChild(content)

        scrollFrame:SetScript("OnShow", function(self)
            self:SetVerticalScroll(0)
        end)

        local pageInfo = {
            id = id,
            name = pageTitle,
            frame = page,
            content = content,
        }

        table.insert(orderedPages, pageInfo)
        return pageInfo
    end
    
    -- Page: General (Advanced)
    local generalPageInfo = CreateSettingsPage("General", "General", "Visibility and baseline behavior options.")
    local p1 = generalPageInfo.content
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
    
    p1:SetHeight(math.abs(y) + 20)
    
    -- Page: Appearance
    local appearancePageInfo = CreateSettingsPage("Appearance", "Appearance", "Frame dimensions, styling, fonts, and colors.")
    local p2 = appearancePageInfo.content
    y = -5
    
    s, sy = StartSection(p2, "Dimensions", y)
    sy = CreateCheckbox(s, "Match Game Tracker", "matchBlizzardTracker", "Place and size the tracker exactly over the game's own objective tracker, following any changes you make to it in the game's Edit Mode. Turns itself off as soon as you drag or resize TrackerPlus yourself; re-check it to snap back.", sy)
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

    sy = CreateSlider(s, "Border Size", "barBorderSize", 0, 10, 1, "Thickness of the progress bar border in pixels (0 hides border)", sy)

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
            local tooltipFrame = addon:AcquireTooltip(frame, "ANCHOR_RIGHT")
            tooltipFrame:SetText(description)
            tooltipFrame:Show()
        end)
        hitRect:SetScript("OnLeave", function() addon:HideSharedTooltip() end)
        
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
    
    p2:SetHeight(math.abs(y) + 20)
    
    -- Page: Layout & Spacing
    local layoutPageInfo = CreateSettingsPage("Layout", "Layout", "Fine-tune horizontal and vertical spacing rules.")
    local p3 = layoutPageInfo.content
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
    
    p3:SetHeight(math.abs(y) + 20)
    
    -- Page: Tracking
    local trackingPageInfo = CreateSettingsPage("Tracking", "Tracking", "Choose which content types are tracked and how they are grouped.")
    local p4 = trackingPageInfo.content
    y = -5
    
    s, sy = StartSection(p4, "Display Options", y)
    sy = CreateCheckbox(s, "Show Quest Level", "showQuestLevel", "Show the level of the quest", sy)
    sy = CreateCheckbox(s, "Color Quests by Difficulty", "colorQuestsByDifficulty", "Color quest name/level using the same difficulty colors as the default quest log (gray/green/yellow/orange/red based on your level vs. the quest's level), via the game's own GetQuestDifficultyColor. Disable to use the flat 'Quest Text' color below instead.", sy)
    sy = CreateCheckbox(s, "Color Map POIs by Difficulty", "colorMapPOIsByDifficulty", "Mark the game's quest pins on the world map with the same color that quest's name has in the tracker.", sy)
    sy = CreateDropdown(s, "Map POI Style", "mapPOIOutlineStyle", {
        {text = "Glow", value = "glow"},
        {text = "Circle", value = "circle"}
    }, "Glow uses the game's own soft ring art, fading outwards. Circle draws a hard-edged ring of an exact pixel thickness instead.", sy)
    sy = CreateSlider(s, "Map POI Thickness", "mapPOIOutlineThickness", 1, 10, 1, "How far past the pin the circle or glow reaches, in pixels.", sy)
    sy = CreateSlider(s, "Map POI Glow Opacity", "mapPOIGlowOpacity", 0.05, 1, 0.05, "How solid the glow is, where 1 is as solid as it can be drawn. Only applies to the Glow style; the circle is always drawn opaque.", sy)
    sy = CreateCheckbox(s, "Mark Quests You're Standing In", "highlightQuestsInArea", "Highlight a quest while you are inside the area the map shades for it.", sy)
    sy = CreateDropdown(s, "Quest Area Style", "questAreaHighlightStyle", addon.QuestAreaHighlightStyles, "How a quest you're standing in is marked in the tracker. Background and Gradient styles use a faded version of the color below so the text stays readable.", sy)
    sy = CreateColorPicker(s, "Quest Area Highlight Color", "questAreaHighlightColor", function()
        addon:RefreshQuestAreaHighlights(true)
    end, sy)
    sy = CreateCheckbox(s, "Show Zone Headers", "showZoneHeaders", "Group quests under zone headers", sy)
    sy = CreateCheckbox(s, "Include Campaign Quest in Active Quest", "includeCampaignQuestInActiveQuest", "When enabled, a pinned campaign quest also appears in the Active Quest section instead of only in Campaign Quests.", sy)
    sy = CreateCheckbox(s, "Group by Zone", "groupByZone", "Sort quests into zone groups", sy)
    sy = CreateDropdown(s, "Sort Order", "sortMethod", {
        {text = "Difficulty (Easiest First)", value = "difficulty_asc"},
        {text = "Difficulty (Hardest First)", value = "difficulty_desc"},
        {text = "Proximity", value = "proximity"},
        {text = "Alphabetical", value = "alphabetical"}
    }, "Order entries within each group. Difficulty compares each quest's level to yours: Easiest First puts trivial quests at the top, Hardest First puts them at the bottom. Proximity puts the closest objective first. Alphabetical sorts by name.", sy)
    sy = CreateCheckbox(s, "Include FollowTheArrow Quests", "includeFTAQuests", "Show a Follow the Arrow guide section between Active Quest and Campaign Quests. Requires the FollowTheArrow addon.", sy)
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
    
    p4:SetHeight(math.abs(y) + 20)

    -- Page: Nameplates. Built by Nameplates/Settings.lua; added here so it registers with the rest.
    local nameplatesPanel = addon.Nameplates and addon.Nameplates.settingsPanel
    if nameplatesPanel then
        table.insert(orderedPages, { id = "Nameplates", name = "Nameplates", frame = nameplatesPanel })
    end

    -- Page: Debug
    local debugPageInfo = CreateSettingsPage("Debug", "Debug", "Diagnostic logging and debug overlay controls.")
    local p5 = debugPageInfo.content
    y = -5

    s, sy = StartSection(p5, "Debug Options", y)
    sy = CreateCheckbox(s, "Enable Debugging", "debugEnabled", "Master switch for all TrackerPlus debugging features.", sy)
    local debugEnabledCheck = _G[addonName .. "debugEnabledCheck"]

    sy = CreateDropdown(s, "Debug Log Level", "debugLevel", {
        {text = "Off", value = "off"},
        {text = "Errors", value = "error"},
        {text = "Warnings", value = "warn"},
        {text = "Info", value = "info"},
        {text = "Trace", value = "trace"},
    }, "Controls verbosity for TrackerPlus debug logging.", sy)
    local debugLevelDropdown = _G[addonName .. "debugLevelDropdown"]

    sy = CreateCheckbox(s, "Layout Debug Logging", "layoutDebug", "Logs detailed layout snapshots (use with Trace level).", sy)
    local layoutDebugCheck = _G[addonName .. "layoutDebugCheck"]
    sy = CreateCheckbox(s, "Section Box Overlays", "debugSectionBoxes", "Draw labeled rectangles around tracker sections.", sy)
    local sectionBoxesCheck = _G[addonName .. "debugSectionBoxesCheck"]

    local openDebugBtn
    sy, openDebugBtn = CreateButton(s, "Open Debug Window", 170, function()
        if addon.ShowDebug then
            addon:ShowDebug()
        else
            print("|cff00ff00TrackerPlus:|r Debug window is not available yet.")
        end
    end, sy)

    local clearDebugBtn
    sy, clearDebugBtn = CreateButton(s, "Clear Debug Log", 170, function()
        if addon.ClearDebug then
            addon:ClearDebug()
            print("|cff00ff00TrackerPlus:|r Debug log cleared.")
        end
    end, sy)

    local function SetCheckEnabled(check, enabled)
        if not check then return end
        if enabled then
            check:Enable()
        else
            check:Disable()
        end
        local text = _G[check:GetName() .. "Text"]
        if text then
            if enabled then
                text:SetTextColor(1, 1, 1, 1)
            else
                text:SetTextColor(0.55, 0.55, 0.55, 1)
            end
        end
    end

    refreshDebugControlsUI = function()
        local enabled = addon.db and addon.db.debugEnabled == true

        if debugLevelDropdown then
            if enabled then
                UIDropDownMenu_EnableDropDown(debugLevelDropdown)
            else
                UIDropDownMenu_DisableDropDown(debugLevelDropdown)
            end
        end

        SetCheckEnabled(layoutDebugCheck, enabled)
        SetCheckEnabled(sectionBoxesCheck, enabled)

        if openDebugBtn then
            if enabled then openDebugBtn:Enable() else openDebugBtn:Disable() end
        end
        if clearDebugBtn then
            if enabled then clearDebugBtn:Enable() else clearDebugBtn:Disable() end
        end

        -- Master toggle remains enabled.
        SetCheckEnabled(debugEnabledCheck, true)
    end

    refreshDebugControlsUI()

    y = y - EndSection(s, sy)
    p5:SetHeight(math.abs(y) + 20)

    -- The order pages appear under TrackerPlus in the Settings list, independent of build order.
    local PAGE_ORDER = { General = 1, Tracking = 2, Nameplates = 3, Appearance = 4, Layout = 5, Debug = 6 }
    table.sort(orderedPages, function(a, b)
        return (PAGE_ORDER[a.id] or 99) < (PAGE_ORDER[b.id] or 99)
    end)

    addon.settingsPageOrder = orderedPages
    addon.settingsPages = {}
    for _, page in ipairs(orderedPages) do
        addon.settingsPages[page.id] = page
    end
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
addon.settingsCategory = nil
addon.settingsSubcategories = addon.settingsSubcategories or {}
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
        
        -- Register with modern Settings API (parent + subpages)
        if Settings and Settings.RegisterCanvasLayoutCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, "TrackerPlus")
            Settings.RegisterAddOnCategory(category)
            addon.settingsCategory = category

            for _, page in ipairs(addon.settingsPageOrder or {}) do
                local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, page.frame, page.name)
                addon.settingsSubcategories[page.id] = subcategory
            end
        else
            InterfaceOptions_AddCategory(panel)
            for _, page in ipairs(addon.settingsPageOrder or {}) do
                page.frame.parent = panel.name
                page.frame.name = page.name
                InterfaceOptions_AddCategory(page.frame)
            end
        end
        
        -- Opens a settings page by id (default "General"); used by /tp and /tp nameplates.
        addon.OpenSettings = function(pageID)
            pageID = pageID or "General"

            if Settings and Settings.OpenToCategory then
                local targetCategory = addon.settingsSubcategories and addon.settingsSubcategories[pageID]
                if not targetCategory then
                    targetCategory = addon.settingsCategory
                end

                local id = targetCategory and targetCategory:GetID()
                if id then
                    Settings.OpenToCategory(id)
                end
            elseif InterfaceOptionsFrame_OpenToCategory then
                local targetPanel = (addon.settingsPages and addon.settingsPages[pageID] and addon.settingsPages[pageID].frame) or panel
                InterfaceOptionsFrame_OpenToCategory(targetPanel)
                InterfaceOptionsFrame_OpenToCategory(targetPanel)
            end
        end
    end
end)

-- ============================================================================
-- Nameplates: settings subpage (registered with the pages above)
-- ============================================================================
do
    local _, TrackerPlus = ...
    local Nameplates = TrackerPlus.Nameplates

    local panel = CreateFrame("Frame")
    panel.name = "Nameplates"
    -- Frames start shown; the UI is built in OnShow, so start hidden or the first visit never fires it.
    panel:Hide()

    local bgFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    bgFrame:SetPoint("TOPLEFT", 4, -4)
    bgFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    bgFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    bgFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    bgFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local scrollFrame = CreateFrame("ScrollFrame", "TrackerPlusNameplatesScrollFrame", bgFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(620, 640)
    scrollFrame:SetScrollChild(content)

    local ui = {
        built = false,
        highlightRows = {},
        preview = {},
    }

    local highlightOptions = {
        { key = "currentTarget", label = "Current Target" },
        { key = "questObjective", label = "Quest Objective Target" },
        { key = "questItem", label = "Quest Item Target" },
        { key = "worldQuest", label = "World Quest Objective Target" },
        { key = "bonusObjective", label = "Bonus Objective Target" },
    }

    local highlightStyleChoices = {
        { value = "outline", label = "Outline" },
        { value = "blizzard", label = "Blizzard" },
        { value = "glow", label = "Glow" },
        { value = "rounded", label = "Rounded" },
    }

    local function styleLabelFor(value)
        for _, choice in ipairs(highlightStyleChoices) do
            if choice.value == value then
                return choice.label
            end
        end
        return value or "Outline"
    end

    local WHITE_TEXTURE = "Interface\\BUTTONS\\WHITE8X8"
    local previewClickSound = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON

    -- Uses the same renderer as live nameplates; disabled highlights preview dimmed.
    local function applyPreviewHighlight(style)
        local healthBar = ui.preview and ui.preview.healthBar
        if not healthBar then
            return
        end

        if style then
            local color = style.color or {}
            style.color = {
                r = color.r or 1,
                g = color.g or 1,
                b = color.b or 1,
                a = (color.a or 1) * (style.enabled and 1 or 0.35),
            }
        end

        Nameplates:RenderBarHighlight(healthBar, style)

        -- On the real nameplate preview, mirror what a live plate shows: our style replaces Blizzard's
        -- border, and only the current target is left undimmed (Blizzard darkens other plates).
        if ui.preview.plate then
            if healthBar.selectedBorder then
                healthBar.selectedBorder:Hide()
            end
            if healthBar.deselectedOverlay then
                healthBar.deselectedOverlay:SetShown(ui.preview.activeKey ~= "currentTarget")
            end
        end
    end

    local function buildStyleData(optionKey)
        local db = Nameplates.db
        return {
            color = db[optionKey .. "Color"],
            thickness = db[optionKey .. "Thickness"],
            offset = db[optionKey .. "Offset"],
            mode = db[optionKey .. "Style"],
            enabled = db[optionKey .. "Enabled"] ~= false,
        }
    end

    local function updatePreviewButtonStates(selectedKey)
        for key, row in pairs(ui.highlightRows) do
            local button = row.previewButton
            local indicator = row.previewIndicator
            if button then
                local enabled = Nameplates.db[key .. "Enabled"] ~= false
                local isSelected = (key == selectedKey)

                if isSelected then
                    button:Hide()
                    if indicator then
                        indicator:Show()
                        indicator:SetAlpha(enabled and 1 or 0.6)
                    end
                else
                    button:SetAlpha(enabled and 1 or 0.6)
                    button:SetEnabled(enabled)
                    button:Show()
                    if indicator then
                        indicator:Hide()
                    end
                end
            end
        end
    end

    local function updatePreview(optionKey)
        ui.preview.activeKey = optionKey
        applyPreviewHighlight(buildStyleData(optionKey))
        updatePreviewButtonStates(optionKey)
    end

    -- Re-applies highlights to live nameplates after a setting changes (debounced, so slider drags are cheap).
    local function applySettings()
        Nameplates:RequestUpdate()
    end

    -- Only the outline style has a thickness.
    local function setThicknessEnabled(row, enabled)
        local slider = row.thickness
        local shade = enabled and 1 or 0.5
        slider:SetEnabled(enabled)
        slider.Text:SetTextColor(shade, shade, shade)
        slider.Low:SetTextColor(shade, shade, shade)
        slider.High:SetTextColor(shade, shade, shade)
    end

    local function updateSwatch(button, color)
        button.swatch:SetColorTexture(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
    end

    local function createHighlightRow(anchor, option, index)
        local rowOffset = -12 - (index - 1) * 68  -- Increased spacing for two-line layout

        -- Label on first line
        local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, rowOffset)
        label:SetWidth(600)
        label:SetJustifyH("LEFT")
        label:SetText(option.label)

        -- All controls on second line, below the label
        local controlY = rowOffset - 18

        local checkbox = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, controlY)
        checkbox.Text:SetText("")  -- Remove text, label is above

        local dropdown = CreateFrame("Frame", nil, content, "UIDropDownMenuTemplate")
        dropdown:SetPoint("LEFT", checkbox, "RIGHT", -12, -2)
        UIDropDownMenu_SetWidth(dropdown, 120)
        UIDropDownMenu_JustifyText(dropdown, "LEFT")

        local colorButton = CreateFrame("Button", nil, content)
        colorButton:SetPoint("LEFT", dropdown, "RIGHT", 4, 0)
        colorButton:SetSize(24, 24)

        local border = colorButton:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints()
        border:SetColorTexture(0, 0, 0, 0.8)

        local swatch = colorButton:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("TOPLEFT", 1, -1)
        swatch:SetPoint("BOTTOMRIGHT", -1, 1)
        colorButton.swatch = swatch

        local thickness = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
        thickness:SetPoint("LEFT", colorButton, "RIGHT", 12, 0)
        thickness:SetMinMaxValues(1, 5)
        thickness:SetValueStep(1)
        thickness:SetObeyStepOnDrag(true)
        thickness:SetWidth(100)
        thickness.Low:SetText("1")
        thickness.High:SetText("5")
        thickness.Text:ClearAllPoints()
        thickness.Text:SetPoint("BOTTOM", thickness, "TOP", 0, 2)
        thickness.Text:SetJustifyH("CENTER")

        local offset = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
        offset:SetPoint("LEFT", thickness, "RIGHT", 12, 0)
        offset:SetMinMaxValues(0, 5)
        offset:SetValueStep(1)
        offset:SetObeyStepOnDrag(true)
        offset:SetWidth(100)
        offset.Low:SetText("0")
        offset.High:SetText("5")
        offset.Text:ClearAllPoints()
        offset.Text:SetPoint("BOTTOM", offset, "TOP", 0, 2)
        offset.Text:SetJustifyH("CENTER")

        local previewButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        previewButton:SetPoint("LEFT", offset, "RIGHT", 12, 0)
        previewButton:SetSize(24, 22)
        previewButton:SetMotionScriptsWhileDisabled(true)
        previewButton:SetText("i")
        previewButton:SetNormalFontObject(GameFontHighlightSmall)
        previewButton:SetHighlightFontObject(GameFontHighlightSmall)
        previewButton:SetDisabledFontObject(GameFontDisableSmall)

        local function tintButtonTextures(button, normal, highlight, disabled)
            local normalTexture = button:GetNormalTexture()
            if normalTexture then
                normalTexture:SetVertexColor(normal.r, normal.g, normal.b, normal.a or 1)
            end
            local highlightTexture = button:GetHighlightTexture()
            if highlightTexture then
                highlightTexture:SetVertexColor(highlight.r, highlight.g, highlight.b, highlight.a or 1)
            end
            local disabledTexture = button:GetDisabledTexture()
            if disabledTexture then
                disabledTexture:SetVertexColor(disabled.r, disabled.g, disabled.b, disabled.a or 1)
            end
        end

        tintButtonTextures(previewButton, { r = 0.7, g = 0.1, b = 0.1 }, { r = 1, g = 0.2, b = 0.2 }, { r = 0.3, g = 0.06, b = 0.06 })

        local indicator = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        indicator:SetPoint("CENTER", previewButton, "CENTER", 0, 0)
        indicator:SetSize(24, 22)
        indicator:SetText("i")
        indicator:SetNormalFontObject(GameFontHighlightSmall)
        indicator:SetDisabledFontObject(GameFontDisableSmall)
        indicator:Disable()
        indicator:EnableMouse(false)
        indicator:Hide()
        tintButtonTextures(indicator, { r = 0.65, g = 0.1, b = 0.1 }, { r = 0.9, g = 0.2, b = 0.2 }, { r = 0.35, g = 0.08, b = 0.08 })

        return {
            label = label,
            checkbox = checkbox,
            dropdown = dropdown,
            colorButton = colorButton,
            thickness = thickness,
            offset = offset,
            previewButton = previewButton,
            previewIndicator = indicator,
        }
    end

    local function bindHighlightRow(option, row)
        local enabledKey = option.key .. "Enabled"
        local colorKey = option.key .. "Color"
        local thicknessKey = option.key .. "Thickness"
        local offsetKey = option.key .. "Offset"
        local styleKey = option.key .. "Style"

        row.checkbox:SetScript("OnClick", function(self)
            Nameplates.db[enabledKey] = self:GetChecked()
            applySettings()
            if ui.preview.activeKey == option.key then
                updatePreview(option.key)
            else
                updatePreviewButtonStates(ui.preview.activeKey or option.key)
            end
        end)

        row.colorButton:SetScript("OnClick", function()
            local color = Nameplates.db[colorKey]
            TrackerPlus:OpenColorPicker(color, function()
                updateSwatch(row.colorButton, color)
                applySettings()
                if ui.preview.activeKey == option.key then
                    updatePreview(option.key)
                end
            end)
        end)

        row.thickness:SetScript("OnValueChanged", function(self, value)
            if self.isUpdating then
                return
            end
            local rounded = math.floor(value + 0.5)
            Nameplates.db[thicknessKey] = rounded
            self.Text:SetText(string.format("Thickness: %d", rounded))
            applySettings()
            if ui.preview.activeKey == option.key then
                updatePreview(option.key)
            end
        end)

        row.offset:SetScript("OnValueChanged", function(self, value)
            if self.isUpdating then
                return
            end
            local rounded = math.floor(value + 0.5)
            Nameplates.db[offsetKey] = rounded
            self.Text:SetText(string.format("Offset: %d", rounded))
            applySettings()
            if ui.preview.activeKey == option.key then
                updatePreview(option.key)
            end
        end)

        UIDropDownMenu_Initialize(row.dropdown, function(_, level)
            if level ~= 1 then
                return
            end
            local current = Nameplates.db[styleKey]
            for _, choice in ipairs(highlightStyleChoices) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = choice.label
                info.value = choice.value
                info.func = function()
                    Nameplates.db[styleKey] = choice.value
                    UIDropDownMenu_SetSelectedValue(row.dropdown, choice.value)
                    UIDropDownMenu_SetText(row.dropdown, choice.label)
                    setThicknessEnabled(row, choice.value == "outline")
                    applySettings()
                    if ui.preview.activeKey == option.key then
                        updatePreview(option.key)
                    end
                end
                info.checked = (current == choice.value)
                UIDropDownMenu_AddButton(info, level)
            end
        end)

        row.previewButton:SetScript("OnClick", function()
            if PlaySound and previewClickSound then
                PlaySound(previewClickSound)
            end
            updatePreview(option.key)
        end)
        row.previewButton:SetScript("OnEnter", function(self)
            local tooltip = TrackerPlus:AcquireTooltip(self, "ANCHOR_RIGHT")
            tooltip:SetText(option.label)
            tooltip:AddLine("Click to preview this highlight.", 1, 1, 1)
            tooltip:Show()
        end)
        row.previewButton:SetScript("OnLeave", function() TrackerPlus:HideSharedTooltip() end)
    end

    local function refreshHighlightRow(option, row)
        local style = buildStyleData(option.key)

        row.checkbox:SetChecked(style.enabled)
        updateSwatch(row.colorButton, style.color)

        row.thickness.isUpdating = true
        row.thickness:SetValue(style.thickness)
        row.thickness.Text:SetText(string.format("Thickness: %d", style.thickness))
        row.thickness.isUpdating = false

        row.offset.isUpdating = true
        row.offset:SetValue(style.offset)
        row.offset.Text:SetText(string.format("Offset: %d", style.offset))
        row.offset.isUpdating = false

        UIDropDownMenu_SetSelectedValue(row.dropdown, style.mode)
        UIDropDownMenu_SetText(row.dropdown, styleLabelFor(style.mode))
        setThicknessEnabled(row, style.mode == "outline")
    end

    -- Stops every event handler in a frame tree, so no Blizzard code ever runs on the preview again.
    local function silenceFrameTree(frame)
        if frame.UnregisterAllEvents then
            frame:UnregisterAllEvents()
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            silenceFrameTree(child)
        end
    end

    -- A nameplate built from Blizzard's templates, laid out with the live nameplate options so it looks
    -- like the game's own Nameplates settings preview. It is purely visual: it never gets a unit, because
    -- Blizzard's unit frame code run from an addon errors on unit health (secret values while tainted),
    -- and it never registers with NamePlateDriverFrame or its pool, so live nameplates are never touched.
    -- Returns the plate, or nil if this client lacks the pieces.
    local function createBlizzardPreviewPlate(parent)
        local hasTemplate = C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("NamePlateUnitFrameTemplate")
            and C_XMLUtil.GetTemplateInfo("NamePlateScriptBaseTemplate")
        if not (hasTemplate and NamePlateBaseMixin and NamePlateSetupOptions and NamePlateEnemyFrameOptions) then
            return nil
        end

        local plate = CreateFrame("Button", nil, parent, "NamePlateScriptBaseTemplate")
        Mixin(plate, NamePlateBaseMixin)

        -- Stand-in for NamePlateDriverFrame: hands out our own unit frame instead of a pooled one.
        local driver = {
            AcquireUnitFrame = function(_, namePlate)
                return CreateFrame("Button", nil, namePlate, "NamePlateUnitFrameTemplate")
            end,
            ReleaseUnitFrame = function() end,
            OnNamePlateResized = function() end,
        }
        plate:Init("NamePlateUnitFrameTemplate", driver)

        local width, height = NamePlateConstants and NamePlateConstants.NAMEPLATE_WIDTH or 230, 60
        if NamePlateDriverFrame and NamePlateDriverFrame.GetNamePlateScale and GetCVarNumberOrDefault then
            local ok, w, h = pcall(function()
                local style = GetCVarNumberOrDefault(NamePlateConstants.STYLE_CVAR)
                local scale = NamePlateDriverFrame:GetNamePlateScale(style)
                return NamePlateDriverFrame:GetNamePlateWidth(style, scale), NamePlateDriverFrame:GetNamePlateHeight(style, scale)
            end)
            if ok and w and h then
                width, height = w, h
            end
        end
        plate:SetSize(width, height)

        plate:AcquireUnitFrame()
        local unitFrame = plate.UnitFrame
        silenceFrameTree(plate)

        -- Size and style the pieces like a live enemy plate. No unit is set, so nothing reads unit data.
        pcall(unitFrame.ApplyFrameOptions, unitFrame, NamePlateSetupOptions, NamePlateEnemyFrameOptions)
        pcall(unitFrame.UpdateAnchors, unitFrame)

        -- Fixed stand-in values (our own, never secret).
        local healthBar = unitFrame.HealthBarsContainer.healthBar
        healthBar:SetMinMaxValues(0, 100)
        healthBar:SetValue(100)
        healthBar:SetStatusBarColor(0.78, 0.06, 0.1)
        unitFrame.name:SetText(UNIT_NAMEPLATES_TARGET_NAME_PREVIEW or "Target Name")
        unitFrame.name:SetVertexColor(1, 1, 1)
        unitFrame.name:Show()

        -- Everything in the template starts visible; Blizzard's unit updates (which never run here) are what
        -- normally hide the pieces that don't apply. Hide those a plain enemy plate wouldn't show.
        local hiddenKeys = {
            "AurasFrame", "CastBarsContainer", "RaidTargetFrame", "ClassificationFrame", "SoftTargetFrame",
            "LevelFrame", "WidgetContainer", "behindCameraIcon", "selectionHighlight", "aggroHighlight", "aggroFlash",
        }
        for _, key in ipairs(hiddenKeys) do
            local region = unitFrame[key]
            if region and region.Hide then
                region:Hide()
            end
        end
        for _, texture in ipairs(unitFrame.aggroHighlightTextures or {}) do
            texture:Hide()
        end

        -- The level badge, as Blizzard's preview shows it.
        local badge = unitFrame.PlayerLevelDiffFrame
        if badge and badge.playerLevelDiffText then
            badge.playerLevelDiffText:SetText(UnitLevel("player"))
            badge:Show()
        end
        return plate
    end

    -- Simple stand-in used when the client has no nameplate templates to build a real preview from.
    local function createFallbackPreviewBar(parent)
        local borderFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        borderFrame:SetPoint("CENTER", parent, "CENTER", 0, 0)
        borderFrame:SetSize(132, 7)
        borderFrame:SetBackdrop({
            bgFile = WHITE_TEXTURE,
            edgeFile = WHITE_TEXTURE,
            edgeSize = 2,
        })
        borderFrame:SetBackdropColor(0.08, 0.02, 0.02, 1)
        borderFrame:SetBackdropBorderColor(0, 0, 0, 1)

        local healthFill = CreateFrame("StatusBar", nil, borderFrame)
        healthFill:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 2, -1)
        healthFill:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", -2, 1)
        healthFill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        healthFill:SetStatusBarColor(0.78, 0.06, 0.1, 1)
        healthFill:SetMinMaxValues(0, 100)
        healthFill:SetValue(100)

        local background = healthFill:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        background:SetVertexColor(0.25, 0, 0, 0.8)

        return healthFill
    end

    local function buildPreviewSection()
        -- Framed like the game's Nameplates settings preview (NamePlatePreviewTemplate).
        local frame = CreateFrame("Frame", nil, content)
        frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, -16)
        frame:SetSize(280, 120)
        ui.preview.frame = frame

        local border = frame:CreateTexture(nil, "BACKGROUND")
        border:SetAtlas("options_frame_child")
        border:SetAllPoints()

        local previewHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        previewHeader:SetPoint("TOPLEFT", border, "TOPLEFT", 10, -10)
        previewHeader:SetText(PREVIEW or "Preview")

        local plate = createBlizzardPreviewPlate(frame)
        if plate then
            plate:SetPoint("CENTER", frame, "CENTER", 0, -6)
            ui.preview.plate = plate
            ui.preview.healthBar = plate.UnitFrame.HealthBarsContainer.healthBar
        else
            ui.preview.healthBar = createFallbackPreviewBar(frame)
        end
    end

    local function buildSettingsUI()
        if ui.built then
            return
        end
        ui.built = true

        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Nameplates")

        local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        subtitle:SetText("Highlight nameplates of quest targets")

        local enable = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        enable:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
        enable.Text:SetText("Enable Nameplate Highlights")
        enable:SetScript("OnClick", function(self)
            Nameplates.db.enabled = self:GetChecked() and true or false
            applySettings()
        end)
        ui.enable = enable

        local function addTooltip(button, heading, text)
            button:SetMotionScriptsWhileDisabled(true)
            button:SetScript("OnEnter", function(self)
                local tooltip = TrackerPlus:AcquireTooltip(self, "ANCHOR_RIGHT")
                tooltip:SetText(heading)
                tooltip:AddLine(text, 1, 1, 1, true)
                tooltip:Show()
            end)
            button:SetScript("OnLeave", function() TrackerPlus:HideSharedTooltip() end)
        end

        -- Each option checkbox stacks below the previous one.
        local lastOption = enable
        local function addOption(label, tooltip, onClick)
            local checkbox = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
            checkbox:SetPoint("TOPLEFT", lastOption, "BOTTOMLEFT", 0, -4)
            checkbox.Text:SetText(label)
            checkbox:SetScript("OnClick", function(self)
                onClick(self:GetChecked() and true or false)
                applySettings()
            end)
            addTooltip(checkbox, label, tooltip)
            lastOption = checkbox
            return checkbox
        end

        ui.fixDefaultBorder = addOption("Fix Default border offset",
            "Redraws Blizzard's own target/focus border (and the level badge's) so it sits evenly around the health bar, keeping Blizzard's color. Applies on nameplates that aren't already highlighted. Doesn't affect the highlight styles below; use their Offset sliders.",
            function(checked)
                Nameplates.db.fixDefaultBorderOffset = checked
            end)

        ui.hideDefaultBorder = addOption("Disable Default Health Bar border",
            "Hides Blizzard's target/focus border on the health bar of nameplates that aren't already highlighted.",
            function(checked)
                Nameplates.db.hideDefaultBorder = checked
            end)

        ui.hideLevelBadgeBorder = addOption("Disable Default Level Badge border",
            "Hides Blizzard's target/focus border around the level badge. When unchecked, the level badge keeps Blizzard's border (redrawn by \"Fix Default border offset\" if that's on); the highlight styles below are never drawn on it.",
            function(checked)
                Nameplates.db.hideLevelBadgeBorder = checked
            end)

        buildPreviewSection()

        local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", lastOption, "BOTTOMLEFT", 0, -18)
        header:SetText("Highlight Styles")

        for index, option in ipairs(highlightOptions) do
            local row = createHighlightRow(header, option, index)
            bindHighlightRow(option, row)
            ui.highlightRows[option.key] = row
            ui.lastRow = row
        end
    end

    -- Size the scroll child to exactly fit its contents (measured once the panel has a layout),
    -- so the scroll bar only appears when the panel is actually too short.
    local CONTENT_BOTTOM_PADDING = 16

    local function fitContentHeight()
        local row = ui.lastRow
        local top = content:GetTop()
        if not row or not top then
            return
        end

        local bottom
        for _, region in ipairs({ row.checkbox, row.dropdown, row.thickness.Low, row.offset.Low, row.previewButton }) do
            local regionBottom = region:GetBottom()
            if regionBottom and (not bottom or regionBottom < bottom) then
                bottom = regionBottom
            end
        end
        if bottom then
            content:SetHeight(math.ceil(top - bottom) + CONTENT_BOTTOM_PADDING)
        end
    end

    panel:SetScript("OnShow", function()
        buildSettingsUI()
        panel.refresh()
        fitContentHeight()
        -- Anchors may not be resolved until the first frame after the panel is shown.
        C_Timer.After(0, fitContentHeight)
    end)

    function panel.refresh()
        if not ui.built then
            return
        end
        ui.enable:SetChecked(Nameplates.db.enabled ~= false)
        ui.hideLevelBadgeBorder:SetChecked(Nameplates.db.hideLevelBadgeBorder ~= false)
        ui.fixDefaultBorder:SetChecked(Nameplates.db.fixDefaultBorderOffset == true)
        ui.hideDefaultBorder:SetChecked(Nameplates.db.hideDefaultBorder == true)

        for _, option in ipairs(highlightOptions) do
            refreshHighlightRow(option, ui.highlightRows[option.key])
        end

        updatePreview(ui.preview.activeKey or highlightOptions[1].key)
    end

    panel.default = function()
        Nameplates:ResetDB()
        Nameplates:HideDebugFrame()
        panel.refresh()
        applySettings()
    end

    -- TrackerPlus's Settings.lua registers this panel as its "Nameplates" subpage.
    panel.parent = "TrackerPlus"
    Nameplates.settingsPanel = panel

    function Nameplates:OpenSettings()
        if TrackerPlus.OpenSettings then
            TrackerPlus.OpenSettings("Nameplates")
        end
    end
end
