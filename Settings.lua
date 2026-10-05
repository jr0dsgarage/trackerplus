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
-- withInput: show the value in an editable box ("Frame Width: [ 250 ]") instead of
-- baked into the label, so an exact number can be typed.
local function CreateSlider(parent, text, dbKey, minVal, maxVal, step, tooltip, yOffset, withInput)
    local slider = CreateFrame("Slider", addonName .. dbKey .. "Slider", parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 20, yOffset - 10) -- Give some room for label
    slider:SetWidth(200)
    slider:SetHeight(17)
    slider:SetOrientation("HORIZONTAL")

    local label = _G[slider:GetName() .. "Text"]
    local low = _G[slider:GetName() .. "Low"]
    local high = _G[slider:GetName() .. "High"]

    local function FormatValue(v)
        if step >= 1 then return tostring(v) end
        return string.format("%.2f", v)
    end

    local input
    if withInput then
        label:SetText(text .. ":")

        input = CreateFrame("EditBox", addonName .. dbKey .. "Input", slider, "InputBoxTemplate")
        input:SetSize(50, 20)
        input:SetPoint("LEFT", label, "RIGHT", 10, 0)
        input:SetAutoFocus(false)
        input:SetJustifyH("CENTER")
        input:SetMaxLetters(6)
        slider.valueInput = input
        slider.formatValue = FormatValue

        local function Commit(self)
            local num = tonumber(self:GetText())
            if num then
                num = math.max(minVal, math.min(maxVal, num))
                slider:SetValue(num)
            end
            -- Re-show the stored value: covers invalid input, clamping, and rounding.
            self:SetText(FormatValue(addon.db[dbKey] or minVal))
        end

        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self)
            self:SetText(FormatValue(addon.db[dbKey] or minVal))
            self:ClearFocus()
        end)
        input:SetScript("OnEditFocusLost", Commit)
    end

    local val = addon.db[dbKey] or minVal
    if input then
        input:SetText(FormatValue(val))
        input:SetCursorPosition(0)
    else
        label:SetText(text .. ": " .. val)
    end
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
            value = math.floor(value * 100 + 0.5) / 100
        end

        addon:SetSetting(dbKey, value)
        if input then
            if not input:HasFocus() then
                input:SetText(FormatValue(value))
            end
        else
            label:SetText(text .. ": " .. value)
        end
        
        -- Immediate updates
        if dbKey == "frameWidth" or dbKey == "frameHeight" or dbKey == "frameScale" or dbKey == "barBorderSize" then
            addon:UpdateTrackerAppearance()
            if dbKey == "barBorderSize" then addon:RefreshDisplay() end
        elseif dbKey == "headerFontSize" then
            -- The tracker's own title uses the header font too.
            addon:UpdateTrackerAppearance()
            addon:RefreshDisplay()
        elseif dbKey == "fontSize" or dbKey == "objectiveFontSize" or dbKey:find("^spacing") then
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

    -- Sits under its label. The template has ~16px of padding on its left, so x=0
    -- lines its box up with the label text.
    local dropdown = CreateFrame("Frame", addonName .. dbKey .. "Dropdown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", 0, yOffset - 20)
    UIDropDownMenu_SetWidth(dropdown, 180)
    
    local function init(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, opt in ipairs(options) do
            info.text = opt.text
            info.value = opt.value
            info.func = function(self)
                addon:SetSetting(dbKey, self.value)
                UIDropDownMenu_SetSelectedValue(dropdown, self.value)
                
                -- Trigger updates
                if dbKey == "frameAnchor" then
                    -- Only changes which point is pinned; the frame doesn't move.
                    addon:ApplyTrackerAnchor()
                elseif dbKey == "headerIconStyle" or dbKey == "headerIconPosition" or dbKey == "headerBackgroundStyle" then
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
    
    return yOffset - 55
end

-- Fonts every client ships, so the list is never empty without LibSharedMedia.
local BUILTIN_FONTS = {
    { "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" },
    { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\SKURRI.TTF" },
    { "Morpheus", "Fonts\\MORPHEUS.TTF" },
}

local function NormalizeFontPath(path)
    return (path:lower():gsub("/", "\\"))
end

-- Font objects used to draw each menu entry in its own font, one per file. Also
-- doubles as a load test: false means the file wouldn't load, and such fonts are
-- left out of the list, since picking one makes the tracker text vanish.
local fontPreviewObjects = {}
local fontPreviewCount = 0
local function GetFontPreviewObject(path)
    local key = NormalizeFontPath(path)
    local obj = fontPreviewObjects[key]
    if obj == nil then
        fontPreviewCount = fontPreviewCount + 1
        obj = CreateFont(addonName .. "FontPreview" .. fontPreviewCount)
        -- Only an explicit false is a failure; a client that returns nothing
        -- from SetFont shouldn't lose every font.
        if obj:SetFont(path, 12, "") == false then obj = false end
        fontPreviewObjects[key] = obj
    end
    return obj or nil
end

-- Every font we can find, as a sorted { {name, path}, ... } list, deduplicated by
-- file. Built on demand so fonts registered by addons that loaded after us count:
--   * LibSharedMedia (if any addon loaded it): fonts other addons registered by name
--   * the built-in game fonts above
--   * every Font object in the UI (GetFonts), which picks up font files that
--     addons use without registering them; these are named after their file
local function GetAvailableFonts()
    local list, seen = {}, {}
    local function add(name, path)
        if type(path) ~= "string" or path == "" then return end
        local key = NormalizeFontPath(path)
        if seen[key] then return end
        seen[key] = true
        if not GetFontPreviewObject(path) then return end
        list[#list + 1] = { name = name, path = path }
    end

    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if lsm then
        for _, name in ipairs(lsm:List("font")) do
            add(name, lsm:Fetch("font", name, true))
        end
    end

    for _, font in ipairs(BUILTIN_FONTS) do
        add(font[1], font[2])
    end

    if GetFonts then
        local ok, fontNames = pcall(GetFonts)
        if ok and type(fontNames) == "table" then
            for _, entry in ipairs(fontNames) do
                local obj = type(entry) == "string" and _G[entry] or entry
                if type(obj) == "table" and obj.GetFont then
                    local path = obj:GetFont()
                    if type(path) == "string" then
                        add(path:match("([^\\/]+)%.%w+$") or path, path)
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

local function GetFontDisplayName(path, fonts)
    if type(path) ~= "string" then return "Unknown" end
    local key = NormalizeFontPath(path)
    for _, font in ipairs(fonts or GetAvailableFonts()) do
        if NormalizeFontPath(font.path) == key then return font.name end
    end
    return path:match("([^\\/]+)%.%w+$") or path
end

-- Long lists are split into alphabetical submenus so the menu stays on screen.
local FONT_MENU_FLAT_LIMIT = 25
local FONT_MENU_CHUNK = 20

local function ApplyFontChange(dbKey)
    if dbKey == "headerFontFace" then
        -- The tracker's own title uses the header font too.
        addon:UpdateTrackerAppearance()
    end
    addon:RefreshDisplay()
end

-- One per font dropdown; run when the menu closes so a hover preview never outlives it.
local fontPreviewEnders = {}
local fontMenuHooked = false

-- Helper: Create Font Dropdown (lists every available font, shown in that font).
-- Hovering an entry previews it on the tracker; leaving or closing puts it back.
local function CreateFontDropdown(parent, text, dbKey, tooltip, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 16, yOffset - 5)
    label:SetText(text)

    local dropdown = CreateFrame("Frame", addonName .. dbKey .. "Dropdown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", 0, yOffset - 20)
    UIDropDownMenu_SetWidth(dropdown, 180)

    local fonts -- rebuilt each time the menu opens

    -- The saved font while a hovered one is temporarily in the db; nil when not previewing.
    local previewOriginal
    local function EndPreview()
        if previewOriginal == nil then return end
        addon.db[dbKey] = previewOriginal
        previewOriginal = nil
        ApplyFontChange(dbKey)
    end
    table.insert(fontPreviewEnders, EndPreview)
    if not fontMenuHooked and DropDownList1 then
        fontMenuHooked = true
        DropDownList1:HookScript("OnHide", function()
            for _, endPreview in ipairs(fontPreviewEnders) do endPreview() end
        end)
    end

    local function AddFontButton(font, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = font.name
        info.value = font.path
        info.fontObject = GetFontPreviewObject(font.path)
        -- Checked against the saved font, not one being previewed.
        local current = previewOriginal or addon.db[dbKey]
        info.checked = type(current) == "string"
            and NormalizeFontPath(current) == NormalizeFontPath(font.path)
        info.funcOnEnter = function()
            if previewOriginal == nil then previewOriginal = addon.db[dbKey] end
            addon.db[dbKey] = font.path
            ApplyFontChange(dbKey)
        end
        info.funcOnLeave = EndPreview
        info.func = function()
            previewOriginal = nil -- keep it: this is now the saved font
            addon:SetSetting(dbKey, font.path)
            UIDropDownMenu_SetText(dropdown, font.name)
            CloseDropDownMenus()
            ApplyFontChange(dbKey)
        end
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(dropdown, function(self, level, menuList)
        level = level or 1
        if level == 1 then
            fonts = GetAvailableFonts()
            if #fonts <= FONT_MENU_FLAT_LIMIT then
                for _, font in ipairs(fonts) do AddFontButton(font, level) end
                return
            end
            for first = 1, #fonts, FONT_MENU_CHUNK do
                local last = math.min(first + FONT_MENU_CHUNK - 1, #fonts)
                local info = UIDropDownMenu_CreateInfo()
                info.text = fonts[first].name .. "  -  " .. fonts[last].name
                info.hasArrow = true
                info.notCheckable = true
                info.menuList = first
                UIDropDownMenu_AddButton(info, level)
            end
        elseif menuList and fonts then
            for i = menuList, math.min(menuList + FONT_MENU_CHUNK - 1, #fonts) do
                AddFontButton(fonts[i], level)
            end
        end
    end)

    UIDropDownMenu_SetText(dropdown, GetFontDisplayName(addon.db[dbKey]))

    if tooltip then
        dropdown:SetScript("OnEnter", function(self)
            local tooltipFrame = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
            tooltipFrame:SetText(text)
            tooltipFrame:AddLine(tooltip, nil, nil, nil, true)
            tooltipFrame:Show()
        end)
        dropdown:SetScript("OnLeave", function() addon:HideSharedTooltip() end)
    end

    return yOffset - 55
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

-- Helper: Start a Boxed Section in one of two side-by-side columns (1 = left,
-- 2 = right), each half of the page's 600px. Finish the pair with EndColumnRow.
local function StartColumnSection(parent, title, yOffset, column)
    local frame, innerY = StartSection(parent, title, yOffset)
    frame:ClearAllPoints()
    if column == 1 then
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
        frame:SetPoint("RIGHT", parent, "LEFT", 295, 0)
    else
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 305, yOffset)
        frame:SetPoint("RIGHT", parent, "RIGHT", -15, 0)
    end
    return frame, innerY
end

-- Helper: End a pair of column sections, matching their heights so the boxes line up
local function EndColumnRow(left, leftInnerY, right, rightInnerY)
    local consumed = math.max(EndSection(left, leftInnerY), EndSection(right, rightInnerY))
    left:SetHeight(consumed - 15)
    right:SetHeight(consumed - 15)
    return consumed
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

            if slider.valueInput then
                if not slider.valueInput:HasFocus() then
                    slider.valueInput:SetText(slider.formatValue(addon.db[dbKey]))
                end
                return
            end

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
    
    -- Dimensions | Styling side by side
    local dimSection, dimY = StartColumnSection(p2, "Dimensions", y, 1)
    dimY = CreateCheckbox(dimSection, "Match Game Tracker", "matchBlizzardTracker", "Place and size the tracker exactly over the game's own objective tracker, following any changes you make to it in the game's Edit Mode. Turns itself off as soon as you drag or resize TrackerPlus yourself; re-check it to snap back.", dimY)
    dimY = CreateDropdown(dimSection, "Anchor", "frameAnchor", {
        {text = "Top Left", value = "TOPLEFT"},
        {text = "Top", value = "TOP"},
        {text = "Top Right", value = "TOPRIGHT"},
        {text = "Left", value = "LEFT"},
        {text = "Center", value = "CENTER"},
        {text = "Right", value = "RIGHT"},
        {text = "Bottom Left", value = "BOTTOMLEFT"},
        {text = "Bottom", value = "BOTTOM"},
        {text = "Bottom Right", value = "BOTTOMRIGHT"},
    }, "The point of the tracker that stays in place when it's resized. Top Right grows down and to the left; Bottom Left grows up and to the right.", dimY)
    dimY = CreateSlider(dimSection, "Frame Width", "frameWidth", 150, 500, 1, "Width of the tracker frame", dimY, true)
    dimY = CreateSlider(dimSection, "Frame Height", "frameHeight", 200, 800, 1, "Height of the tracker frame", dimY, true)
    dimY = CreateSlider(dimSection, "Frame Scale", "frameScale", 0.5, 2.0, 0.1, "Scale of the tracker frame", dimY, true)

    s, sy = StartColumnSection(p2, "Styling", y, 2)
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

    y = y - EndColumnRow(dimSection, dimY, s, sy)
    
    -- Fonts: one row per text type, font picker on the left and its size on the right
    s, sy = StartSection(p2, "Fonts", y)
    local fontLeft = CreateFrame("Frame", nil, s)
    fontLeft:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
    fontLeft:SetSize(290, 1)
    local fontRight = CreateFrame("Frame", nil, s)
    fontRight:SetPoint("TOPLEFT", s, "TOPLEFT", 295, 0)
    fontRight:SetSize(290, 1)

    local FONT_ROWS = {
        { "Header Font", "headerFontFace", "Header Font Size", "headerFontSize", 10, 28, "the tracker title and section/zone headers" },
        { "Quest Name Font", "fontFace", "Quest Name Font Size", "fontSize", 8, 24, "quest and other trackable names" },
        { "Objective Font", "objectiveFontFace", "Objective Font Size", "objectiveFontSize", 8, 24, "objective lines under each quest" },
    }
    for _, row in ipairs(FONT_ROWS) do
        CreateFontDropdown(fontLeft, row[1], row[2], "Font used for " .. row[7] .. ". Lists every font available, including ones installed by other addons.", sy)
        -- Nudged down so the slider's label lines up with the dropdown's label.
        CreateSlider(fontRight, row[3], row[4], row[5], row[6], 1, "Size of " .. row[7], sy - 8, true)
        sy = sy - 60
    end
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
    
    -- Horizontal | Vertical side by side
    local hSection, hY = StartColumnSection(p3, "Horizontal Spacing", y, 1)
    s, sy = hSection, hY
    sy = CreateSlider(s, "Major Header Indent", "spacingMajorHeaderIndent", 0, 50, 1, "Left indent for major category headers (Quests, Achievements)", sy)
    sy = CreateSlider(s, "Minor Header Indent", "spacingMinorHeaderIndent", 0, 50, 1, "Left indent for zone/subgroup headers", sy)
    sy = CreateSlider(s, "Quest/Item Indent", "spacingTrackableIndent", 0, 50, 1, "Left indent for individual quests and trackables", sy)
    sy = CreateSlider(s, "POI Button Padding", "spacingPOIButton", 0, 50, 1, "Left padding for text when POI button is shown", sy)
    sy = CreateSlider(s, "Item Button Spacing", "spacingItemButton", 0, 50, 1, "Additional space when item/action button exists", sy)
    sy = CreateSlider(s, "Objective Indent", "spacingObjectiveIndent", 0, 50, 1, "Extra indent for objective lines (relative to quest)", sy)
    sy = CreateSlider(s, "Progress Bar Inset", "spacingProgressBarInset", 0, 50, 1, "Horizontal margin for progress bars from edges", sy)
    sy = CreateSlider(s, "Progress Bar Padding", "spacingProgressBarPadding", 0, 20, 1, "Vertical padding between text and progress bar", sy)
    hY = sy

    s, sy = StartColumnSection(p3, "Vertical Spacing", y, 2)
    sy = CreateSlider(s, "Item Spacing", "spacingItemVertical", 0, 20, 1, "Vertical gap between trackable items", sy)
    sy = CreateSlider(s, "Major Header Gap", "spacingMajorHeaderAfter", 10, 50, 1, "Vertical space after major category headers", sy)
    sy = CreateSlider(s, "Minor Header Gap", "spacingMinorHeaderAfter", 10, 50, 1, "Vertical space after zone/subgroup headers", sy)
    y = y - EndColumnRow(hSection, hY, s, sy)
    
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
