-- Options panel for Nameplates (a TrackerPlus settings subpage)
---@diagnostic disable: undefined-global
local _, TrackerPlus = ...
TrackerPlus.Nameplates = TrackerPlus.Nameplates or {}
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

local scrollFrame = TrackerPlus.SettingsWidgets.CreateScrollFrame(bgFrame, "TrackerPlusNameplatesScrollFrame")
scrollFrame:SetPoint("TOPLEFT", 0, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", -18, 4)

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
    { key = "activeQuest", label = "Active Quest Target",
      tooltip = "Objectives of your Active (super-tracked) quest. Replaces the other quest highlights on those"
          .. " mobs, but never the Current Target highlight.\n\nThis highlight doesn't show inside instances." },
    { key = "questObjective", label = "Quest Objective Target" },
    { key = "questItem", label = "Quest Item Target" },
    { key = "worldQuest", label = "World Quest Objective Target", retailOnly = true },
    { key = "bonusObjective", label = "Bonus Objective Target", retailOnly = true },
}
-- Forever has no world quests or bonus objectives (see RETAIL_ONLY_KEYS in NameplatesDatabase.lua).
if not TrackerPlus.IsRetail then
    for i = #highlightOptions, 1, -1 do
        if highlightOptions[i].retailOnly then
            table.remove(highlightOptions, i)
        end
    end
end

local highlightStyleChoices = {
    { value = "outline", text = "Outline" },
    { value = "blizzard", text = "Blizzard" },
    { value = "glow", text = "Glow" },
    { value = "rounded", text = "Rounded" },
}

local WHITE_TEXTURE = "Interface\\BUTTONS\\WHITE8X8"
-- The search box's magnifying glass, on each highlight's preview button.
local PREVIEW_ICON = "Interface\\Common\\UI-Searchbox-Icon"
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
        -- The level badge follows the "Disable Default Level Badge border" / "Fix Default border offset" options.
        local badge = ui.preview.plate.UnitFrame.PlayerLevelDiffFrame
        if badge and badge.selectedBorder then
            badge.selectedBorder:Show()
            Nameplates:RenderPreviewBadgeBorder(badge)
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

-- Only the outline style has a thickness, so the slider is hidden for the others.
local function setThicknessShown(row, shown)
    row.thickness:SetShown(shown)
end

local function updateSwatch(button, color)
    button.swatch:SetColorTexture(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
end

local function refreshPreviewFor(option)
    if ui.preview.activeKey == option.key then
        updatePreview(option.key)
    end
end

-- A highlight row's style dropdown picked `value`.
local function onStyleSelected(option, value)
    Nameplates.db[option.key .. "Style"] = value
    setThicknessShown(ui.highlightRows[option.key], value == "outline")
    applySettings()
    refreshPreviewFor(option)
end

-- A highlight row's Offset or Thickness slider moved.
local function onRowSliderChanged(option, dbKey, value)
    Nameplates.db[dbKey] = value
    applySettings()
    refreshPreviewFor(option)
end

-- Highlight row spacing: between rows, between the small controls, and around the sliders.
local ROW_SPACING = 76
local CONTROL_GAP = 8
local SLIDER_GAP = 16
-- Kept clear on the right of the rows, matching the page's left margin.
local CONTENT_RIGHT_MARGIN = 16

local function createHighlightRow(anchor, option, index)
    local rowOffset = -12 - (index - 1) * ROW_SPACING -- two lines: label, then controls

    -- Label on first line
    local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Starts one preview button in: that button leads the line (anchored below).
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 26, rowOffset)
    label:SetJustifyH("LEFT")
    label:SetText(option.label)

    -- All controls on second line, below the label
    local controlY = rowOffset - 18

    local checkbox = TrackerPlus.SettingsWidgets.CreateCheckbox(content) -- no text, label is above
    checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, controlY)

    local styleKey = option.key .. "Style"
    local dropdown = TrackerPlus.SettingsWidgets.CreateChoiceDropdown(content, 100, highlightStyleChoices,
        function() return Nameplates.db[styleKey] end,
        function(value) onStyleSelected(option, value) end)
    dropdown:SetPoint("LEFT", checkbox, "RIGHT", CONTROL_GAP, 0)

    local colorButton = CreateFrame("Button", nil, content)
    colorButton:SetPoint("LEFT", dropdown, "RIGHT", CONTROL_GAP, 0)
    colorButton:SetSize(24, 24)

    local border = colorButton:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 0.8)

    local swatch = colorButton:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 1, -1)
    swatch:SetPoint("BOTTOMRIGHT", -1, 1)
    colorButton.swatch = swatch

    -- The value is shown in each slider's label, so no value beside the arrows. The width
    -- here is a starting point: fitRowWidths stretches both sliders to fill the row.
    local function createRowSlider(labelText, dbKey, minVal, maxVal)
        return TrackerPlus.SettingsWidgets.CreateSlider(content, {
            min = minVal, max = maxVal, step = 1, width = 70, showValue = false,
            value = Nameplates.db[dbKey],
            labelFormat = function(value) return string.format("%s: %d", labelText, value) end,
            onChange = function(value) onRowSliderChanged(option, dbKey, value) end,
        })
    end

    local offset = createRowSlider("Offset", option.key .. "Offset", 0, 5)
    offset:SetPoint("LEFT", colorButton, "RIGHT", SLIDER_GAP, 0)

    local thickness = createRowSlider("Thickness", option.key .. "Thickness", 1, 5)
    thickness:SetPoint("LEFT", offset, "RIGHT", SLIDER_GAP, 0)

    -- Marks the end of the row for the hover tooltip. Thickness can be hidden, and a
    -- hidden owner would hide the tooltip, so it can't be the anchor itself.
    local rowEnd = CreateFrame("Frame", nil, content)
    rowEnd:SetSize(1, 1)
    rowEnd:SetPoint("LEFT", thickness, "RIGHT", 0, 0)

    -- Preview button: a magnifying glass at the start of the label's line.
    local function addMagnifierIcon(button)
        local icon = button:CreateTexture(nil, "OVERLAY")
        icon:SetTexture(PREVIEW_ICON)
        icon:SetSize(12, 12)
        icon:SetPoint("CENTER", 0, 0)
        return icon
    end

    local previewButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    previewButton:SetPoint("RIGHT", label, "LEFT", -6, 0)
    previewButton:SetSize(20, 18)
    previewButton:SetMotionScriptsWhileDisabled(true)
    addMagnifierIcon(previewButton)

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
    indicator:SetSize(20, 18)
    addMagnifierIcon(indicator)
    indicator:Disable()
    indicator:EnableMouse(false)
    indicator:Hide()
    tintButtonTextures(indicator, { r = 0.65, g = 0.1, b = 0.1 }, { r = 0.9, g = 0.2, b = 0.2 }, { r = 0.35, g = 0.08, b = 0.08 })

    -- One hover row for the label and every control on the line below it; the optional
    -- explanation shows past the end of the row. (The preview button keeps its own tooltip.)
    TrackerPlus.SettingsWidgets.AttachHover(checkbox, {
        title = option.label, body = option.tooltip, top = label, anchor = rowEnd,
        frames = {
            dropdown.Dropdown, dropdown.DecrementButton, dropdown.IncrementButton, colorButton,
            offset.Slider, offset.Back, offset.Forward,
            thickness.Slider, thickness.Back, thickness.Forward,
        },
    })

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

    row.thickness:SetValue(style.thickness, true)
    row.offset:SetValue(style.offset, true)

    row.dropdown:Refresh()
    setThicknessShown(row, style.mode == "outline")
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

-- Lays the preview plate out for the game's current Nameplates options (Style, Size). Blizzard rebuilds
-- NamePlateSetupOptions/NamePlateEnemyFrameOptions whenever those change, so re-applying them is enough;
-- run when the plate is built and every time the panel opens, since the game's options may have changed.
local function layoutPreviewPlate(plate)
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

    -- Sizes, textures and anchors for the style (ApplyFrameOptions re-anchors too). No unit is set,
    -- so nothing reads unit data.
    local unitFrame = plate.UnitFrame
    pcall(unitFrame.ApplyFrameOptions, unitFrame, NamePlateSetupOptions, NamePlateEnemyFrameOptions)

    -- Styles with a level slot in the health bar border (Classic) show the level there, as
    -- CompactUnitFrame_UpdateLevel would for a mob of your own level.
    local levelFrame = unitFrame.LevelFrame
    if levelFrame then
        if NamePlateEnemyFrameOptions.showLevel and levelFrame.LevelText then
            local level = UnitLevel("player")
            levelFrame.LevelText:SetText(level)
            local color = GetRelativeDifficultyColor and GetRelativeDifficultyColor(level, level)
            if color then
                levelFrame.LevelText:SetVertexColor(color.r, color.g, color.b)
            end
            levelFrame.LevelText:Show()
            if levelFrame.HighLevelTexture then
                levelFrame.HighLevelTexture:Hide()
            end
            levelFrame:Show()
        else
            levelFrame:Hide()
        end
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

    plate:AcquireUnitFrame()
    local unitFrame = plate.UnitFrame
    silenceFrameTree(plate)

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
        "WidgetContainer", "behindCameraIcon", "selectionHighlight", "aggroHighlight", "aggroFlash",
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
    -- Heal prediction and absorb pieces on the health bar; the over-absorb glows otherwise show as a
    -- red sliver at the bar's left end and a blue one at its right.
    local hiddenBarKeys = {
        "myHealPrediction", "otherHealPrediction", "totalAbsorb", "totalAbsorbOverlay", "myHealAbsorb",
        "myHealAbsorbLeftShadow", "myHealAbsorbRightShadow", "overAbsorbGlow", "overHealAbsorbGlow",
    }
    for _, key in ipairs(hiddenBarKeys) do
        local region = healthBar[key]
        if region and region.Hide then
            region:Hide()
        end
    end

    -- The level badge, as Blizzard's preview shows it.
    local badge = unitFrame.PlayerLevelDiffFrame
    if badge and badge.playerLevelDiffText then
        local level = UnitLevel("player")
        -- Colored as for a mob of your own level, where the badge colors by difficulty (Forever).
        local color = badge.GetDifficultyColor and badge:GetDifficultyColor(0)
        badge.playerLevelDiffText:SetText(color and color:WrapTextInColorCode(level) or level)
        badge.playerLevelDiffText:Show()
        -- Forever's badge has a skull for unknown levels that starts visible; Blizzard
        -- (CompactUnitFrame_UpdatePlayerLevelDiff) hides it whenever the level is known.
        if badge.highLevelTexture then
            badge.highLevelTexture:Hide()
        end
        -- Forever's badge decides for itself whether it shows, and the health bar is shortened to
        -- make room for it. With no unit it would say no, so answer for it as a live mob's would.
        if badge.ShouldDisplay then
            badge.ShouldDisplay = function() return true end
        end
        badge:Show()
    end
    -- Sized and styled by layoutPreviewPlate, which the panel runs each time it opens.
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

    local W = TrackerPlus.SettingsWidgets

    -- Rows end at their label, clear of the preview box in the top right corner
    local function addHover(checkbox, body)
        W.AttachHover(checkbox, { body = body, right = checkbox.Text })
    end

    local enable = W.CreateCheckbox(content)
    enable:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
    enable.Text:SetText("Enable Nameplate Highlights")
    enable:SetScript("OnClick", function(self)
        Nameplates.db.enabled = self:GetChecked() and true or false
        applySettings()
    end)
    addHover(enable, "Outline the nameplates of your target and of quest targets, in the styles set below.")
    ui.enable = enable

    -- Each option checkbox stacks below the previous one.
    local lastOption = enable
    local function addOption(label, tooltip, onClick)
        local checkbox = W.CreateCheckbox(content)
        checkbox:SetPoint("TOPLEFT", lastOption, "BOTTOMLEFT", 0, -4)
        checkbox.Text:SetText(label)
        checkbox:SetScript("OnClick", function(self)
            onClick(self:GetChecked() and true or false)
            applySettings()
            if ui.preview.activeKey then
                updatePreview(ui.preview.activeKey)
            end
        end)
        addHover(checkbox, tooltip)
        lastOption = checkbox
        return checkbox
    end

    ui.fixDefaultBorder = addOption("Fix Default border offset",
        "Moves the top of Blizzard's own target/focus border on the health bar and level badge down 1px, keeping Blizzard's color. Applies on nameplates that aren't already highlighted. Doesn't affect the highlight styles below; use their Offset sliders.",
        function(checked)
            Nameplates.db.fixDefaultBorderOffset = checked
        end)

    ui.hideDefaultBorder = addOption("Disable Default Health Bar border",
        "Hides Blizzard's target/focus border on the health bar of nameplates that aren't already highlighted.",
        function(checked)
            Nameplates.db.hideDefaultBorder = checked
        end)

    ui.hideLevelBadgeBorder = addOption("Disable Default Level Badge border",
        "Hides Blizzard's target/focus border around the level badge. When unchecked, the level badge keeps Blizzard's border (adjusted by \"Fix Default border offset\" if that's on); the highlight styles below are never drawn on it.",
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
    for _, region in ipairs({ row.checkbox, row.dropdown, row.offset, row.previewButton }) do
        local regionBottom = region:GetBottom()
        if regionBottom and (not bottom or regionBottom < bottom) then
            bottom = regionBottom
        end
    end
    if bottom then
        content:SetHeight(math.ceil(top - bottom) + CONTENT_BOTTOM_PADDING)
    end
end

-- Widens the content to the scroll frame (keeping the preview box in its top right corner) and
-- stretches each row's two sliders so the row, with every control showing, reaches the right margin.
local MIN_SLIDER_WIDTH = 90 -- arrows included

local function fitRowWidths()
    local width = scrollFrame:GetWidth()
    local contentLeft = content:GetLeft()
    if not width or width <= 0 or not contentLeft then
        return
    end
    content:SetWidth(width)

    for _, row in pairs(ui.highlightRows) do
        local sliderLeft = row.offset:GetLeft()
        if sliderLeft then
            local available = width - CONTENT_RIGHT_MARGIN - (sliderLeft - contentLeft)
            local sliderWidth = math.max(MIN_SLIDER_WIDTH, math.floor((available - SLIDER_GAP) / 2))
            row.offset:SetWidth(sliderWidth)
            row.thickness:SetWidth(sliderWidth)
        end
    end
end

panel:SetScript("OnShow", function()
    buildSettingsUI()
    -- Pick up any change to the game's Nameplates Style or Size since the panel was last open.
    if ui.preview.plate then
        layoutPreviewPlate(ui.preview.plate)
    end
    panel.refresh()
    fitRowWidths()
    fitContentHeight()
    -- Anchors may not be resolved until the first frame after the panel is shown.
    C_Timer.After(0, function()
        fitRowWidths()
        fitContentHeight()
    end)
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
    TrackerPlus.OpenSettings("Nameplates")
end
