-- Options panel for next
---@diagnostic disable: undefined-global
local addonName, addon = ...

local panel = CreateFrame("Frame")
panel.name = "next"

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

local scrollFrame = CreateFrame("ScrollFrame", addonName .. "SettingsScrollFrame", bgFrame, "UIPanelScrollFrameTemplate")
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

local highlightOptionsByKey = {}
for _, option in ipairs(highlightOptions) do
    highlightOptionsByKey[option.key] = option
end

local WHITE_TEXTURE = "Interface\\BUTTONS\\WHITE8X8"
local previewClickSound = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON

local updatePreview
local selectPreviewOption

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

    addon:RenderBarHighlight(healthBar, style)

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
    local option = highlightOptionsByKey[optionKey]
    if not option then
        return nil
    end

    local colorKey = option.key .. "Color"
    local thicknessKey = option.key .. "Thickness"
    local offsetKey = option.key .. "Offset"
    local styleKey = option.key .. "Style"
    local enabledKey = option.key .. "Enabled"

    local color = NextTargetDB[colorKey]
    if not color then
        color = addon:GetDefault(colorKey)
        NextTargetDB[colorKey] = color
    end
    color = color or { r = 1, g = 1, b = 1, a = 1 }

    local thicknessValue = NextTargetDB[thicknessKey] or addon:GetDefault(thicknessKey) or 1
    local offsetValue = NextTargetDB[offsetKey] or addon:GetDefault(offsetKey) or 0
    local styleValue = NextTargetDB[styleKey] or addon:GetDefault(styleKey) or "outline"
    NextTargetDB[styleKey] = styleValue

    return {
        option = option,
        color = color,
        thickness = thicknessValue,
        offset = offsetValue,
        mode = styleValue,
        enabled = NextTargetDB[enabledKey] ~= false,
    }
end

local function updatePreviewButtonStates(selectedKey)
    for key, row in pairs(ui.highlightRows) do
        local button = row.previewButton
        local indicator = row.previewIndicator
        if button then
            local enabled = NextTargetDB[key .. "Enabled"] ~= false
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

updatePreview = function(optionKey)
    if not ui.preview or not ui.preview.frame then
        return
    end

    optionKey = optionKey or ui.preview.activeKey
    if not optionKey then
        return
    end

    local style = buildStyleData(optionKey)
    if not style then
        return
    end

    ui.preview.activeKey = optionKey

    applyPreviewHighlight(style)
    updatePreviewButtonStates(optionKey)
end

selectPreviewOption = function(optionKey)
    updatePreview(optionKey)
end

local function accentuate()
    if addon.ClearHighlights then
        addon:ClearHighlights()
    end
    if addon.UpdateHighlight then
        addon:UpdateHighlight()
    end
end

local function updateSwatch(button, color)
    button.swatch:SetColorTexture(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
end

local function useColorPicker(color, onChanged)
    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
        return
    end

    local function apply()
        color.r, color.g, color.b = ColorPickerFrame:GetColorRGB()
        color.a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
        onChanged()
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
            local previous = ColorPickerFrame.previousValues
            if previous then
                color.r = previous.r
                color.g = previous.g
                color.b = previous.b
                color.a = previous.opacity
                onChanged()
            end
        end,
    })
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
        NextTargetDB[enabledKey] = self:GetChecked()
        accentuate()
        if ui.preview.activeKey == option.key then
            updatePreview(option.key)
        else
            updatePreviewButtonStates(ui.preview.activeKey or option.key)
        end
    end)

    row.colorButton:SetScript("OnClick", function()
        local color = NextTargetDB[colorKey]
        if not color then
            color = addon:GetDefault(colorKey)
            NextTargetDB[colorKey] = color
        end
        useColorPicker(color, function()
            updateSwatch(row.colorButton, color)
            accentuate()
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
        NextTargetDB[thicknessKey] = rounded
        self.Text:SetText(string.format("Thickness: %d", rounded))
        accentuate()
        if ui.preview.activeKey == option.key then
            updatePreview(option.key)
        end
    end)

    row.offset:SetScript("OnValueChanged", function(self, value)
        if self.isUpdating then
            return
        end
        local rounded = math.floor(value + 0.5)
        NextTargetDB[offsetKey] = rounded
        self.Text:SetText(string.format("Offset: %d", rounded))
        accentuate()
        if ui.preview.activeKey == option.key then
            updatePreview(option.key)
        end
    end)

    UIDropDownMenu_Initialize(row.dropdown, function(_, level)
        if level ~= 1 then
            return
        end
        local current = NextTargetDB[styleKey] or addon:GetDefault(styleKey) or "outline"
        for _, choice in ipairs(highlightStyleChoices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = choice.label
            info.value = choice.value
            info.func = function()
                NextTargetDB[styleKey] = choice.value
                UIDropDownMenu_SetSelectedValue(row.dropdown, choice.value)
                UIDropDownMenu_SetText(row.dropdown, choice.label)
                
                -- Enable/disable thickness slider based on style
                local usesThickness = (choice.value == "outline")
                if usesThickness then
                    row.thickness:Enable()
                    row.thickness.Text:SetTextColor(1, 1, 1)
                    row.thickness.Low:SetTextColor(1, 1, 1)
                    row.thickness.High:SetTextColor(1, 1, 1)
                else
                    row.thickness:Disable()
                    row.thickness.Text:SetTextColor(0.5, 0.5, 0.5)
                    row.thickness.Low:SetTextColor(0.5, 0.5, 0.5)
                    row.thickness.High:SetTextColor(0.5, 0.5, 0.5)
                end
                
                accentuate()
                if ui.preview.activeKey == option.key then
                    updatePreview(option.key)
                end
            end
            info.checked = (current == choice.value)
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    if row.previewButton then
        row.previewButton.optionKey = option.key
        row.previewButton:SetScript("OnClick", function()
            if PlaySound and previewClickSound then
                PlaySound(previewClickSound)
            end
            selectPreviewOption(option.key)
        end)
        row.previewButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(option.label)
            GameTooltip:AddLine("Click to preview this highlight.", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.previewButton:SetScript("OnLeave", GameTooltip_Hide)
    end
end

local function refreshHighlightRow(option, row)
    local colorKey = option.key .. "Color"
    local thicknessKey = option.key .. "Thickness"
    local offsetKey = option.key .. "Offset"
    local enabledKey = option.key .. "Enabled"
    local styleKey = option.key .. "Style"

    row.checkbox:SetChecked(NextTargetDB[enabledKey] ~= false)

    local color = NextTargetDB[colorKey]
    if not color then
        color = addon:GetDefault(colorKey)
        NextTargetDB[colorKey] = color
    end
    updateSwatch(row.colorButton, color)

    local thicknessValue = NextTargetDB[thicknessKey] or addon:GetDefault(thicknessKey) or 1
    row.thickness.isUpdating = true
    row.thickness:SetValue(thicknessValue)
    row.thickness.Text:SetText(string.format("Thickness: %d", thicknessValue))
    row.thickness.isUpdating = false

    local offsetValue = NextTargetDB[offsetKey] or addon:GetDefault(offsetKey) or 0
    row.offset.isUpdating = true
    row.offset:SetValue(offsetValue)
    row.offset.Text:SetText(string.format("Offset: %d", offsetValue))
    row.offset.isUpdating = false

    local styleValue = NextTargetDB[styleKey] or addon:GetDefault(styleKey) or "outline"
    NextTargetDB[styleKey] = styleValue
    UIDropDownMenu_SetSelectedValue(row.dropdown, styleValue)
    UIDropDownMenu_SetText(row.dropdown, styleLabelFor(styleValue))
    
    -- Enable/disable thickness slider based on style
    local usesThickness = (styleValue == "outline")
    if usesThickness then
        row.thickness:Enable()
        row.thickness.Text:SetTextColor(1, 1, 1)
        row.thickness.Low:SetTextColor(1, 1, 1)
        row.thickness.High:SetTextColor(1, 1, 1)
    else
        row.thickness:Disable()
        row.thickness.Text:SetTextColor(0.5, 0.5, 0.5)
        row.thickness.Low:SetTextColor(0.5, 0.5, 0.5)
        row.thickness.High:SetTextColor(0.5, 0.5, 0.5)
    end
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
    if ui.preview.sectionBuilt then
        return
    end
    ui.preview.sectionBuilt = true

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
    title:SetText("next")

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText("Highlight potential next targets")

    local enable = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    enable:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
    enable.Text:SetText("Enable next")
    enable:SetScript("OnClick", function(self)
        NextTargetDB.enabled = self:GetChecked() and true or false
        if NextTargetDB.enabled then
            accentuate()
        elseif addon.ClearHighlights then
            addon:ClearHighlights()
        end
    end)
    ui.enable = enable

    local function addTooltip(button, heading, text)
        button:SetMotionScriptsWhileDisabled(true)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(heading)
            GameTooltip:AddLine(text, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
    end

    -- Each option checkbox stacks below the previous one.
    local lastOption = enable
    local function addOption(label, tooltip, onClick)
        local checkbox = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", lastOption, "BOTTOMLEFT", 0, -4)
        checkbox.Text:SetText(label)
        checkbox:SetScript("OnClick", function(self)
            onClick(self:GetChecked() and true or false)
            accentuate()
        end)
        addTooltip(checkbox, label, tooltip)
        lastOption = checkbox
        return checkbox
    end

    ui.fixDefaultBorder = addOption("Fix Default border offset",
        "Redraws Blizzard's own target/focus border (and the level badge's) so it sits evenly around the health bar, keeping Blizzard's color. Applies on nameplates next isn't already highlighting. Doesn't affect next's highlight styles; use their Offset sliders.",
        function(checked)
            NextTargetDB.fixDefaultBorderOffset = checked
        end)

    ui.hideDefaultBorder = addOption("Disable Default Health Bar border",
        "Hides Blizzard's target/focus border on the health bar of nameplates next isn't already highlighting.",
        function(checked)
            NextTargetDB.hideDefaultBorder = checked
        end)

    ui.hideLevelBadgeBorder = addOption("Disable Default Level Badge border",
        "Hides Blizzard's target/focus border around the level badge. When unchecked, the level badge keeps Blizzard's border (redrawn by \"Fix Default border offset\" if that's on); next's highlight styles are never drawn on it.",
        function(checked)
            NextTargetDB.hideLevelBadgeBorder = checked
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
    buildSettingsUI()

    ui.enable:SetChecked(NextTargetDB.enabled ~= false)
    ui.hideLevelBadgeBorder:SetChecked(NextTargetDB.hideLevelBadgeBorder ~= false)
    ui.fixDefaultBorder:SetChecked(NextTargetDB.fixDefaultBorderOffset == true)
    ui.hideDefaultBorder:SetChecked(NextTargetDB.hideDefaultBorder == true)

    for _, option in ipairs(highlightOptions) do
        refreshHighlightRow(option, ui.highlightRows[option.key])
    end

    if ui.preview.frame then
        if ui.preview.activeKey then
            updatePreview(ui.preview.activeKey)
        elseif highlightOptions[1] then
            selectPreviewOption(highlightOptions[1].key)
        end
    end
end

panel.okay = function()
    panel.refresh()
    if NextTargetDB.debugMode then
        addon:ShowDebugFrame()
    else
        addon:HideDebugFrame()
    end
    accentuate()
end

panel.cancel = function()
    panel.refresh()
end

panel.default = function()
    NextTargetDB.enabled = addon:GetDefault("enabled")
    NextTargetDB.debugMode = addon:GetDefault("debugMode")
    NextTargetDB.hideLevelBadgeBorder = addon:GetDefault("hideLevelBadgeBorder")
    NextTargetDB.fixDefaultBorderOffset = addon:GetDefault("fixDefaultBorderOffset")
    NextTargetDB.hideDefaultBorder = addon:GetDefault("hideDefaultBorder")

    for _, option in ipairs(highlightOptions) do
        NextTargetDB[option.key .. "Enabled"] = addon:GetDefault(option.key .. "Enabled")
        NextTargetDB[option.key .. "Color"] = addon:GetDefault(option.key .. "Color")
        NextTargetDB[option.key .. "Thickness"] = addon:GetDefault(option.key .. "Thickness")
        NextTargetDB[option.key .. "Offset"] = addon:GetDefault(option.key .. "Offset")
        NextTargetDB[option.key .. "Style"] = addon:GetDefault(option.key .. "Style")
    end

    panel.refresh()
    if NextTargetDB.debugMode then
        addon:ShowDebugFrame()
    else
        addon:HideDebugFrame()
    end
    accentuate()
end

if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
elseif Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    addon.settingsCategory = category
end

addon.settingsPanel = panel

function addon:OpenSettings()
    if Settings and Settings.OpenToCategory then
        if not self.settingsCategory and self.settingsPanel then
            local category = Settings.RegisterCanvasLayoutCategory(self.settingsPanel, self.settingsPanel.name or "next")
            Settings.RegisterAddOnCategory(category)
            self.settingsCategory = category
        end
        if self.settingsCategory and self.settingsCategory.GetID then
            Settings.OpenToCategory(self.settingsCategory:GetID())
            return
        end
    end

    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end