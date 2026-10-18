---@diagnostic disable: undefined-global
local addonName, addon = ...
local W = addon.SettingsWidgets

-- Settings panel using manual frame construction for maximum control
local panel = CreateFrame("Frame", "TrackerPlusOptionsPanel")
panel.name = "TrackerPlus"

-------------------------------------------------------------------------------
-- What each setting needs refreshed when it changes. Settings not listed take
-- effect on their own (read on the next interaction or render).
-------------------------------------------------------------------------------
-- Collected data (colors, grouping, sorting, what's included) is built at collection
-- time, so these need a full recollect rather than just a repaint.
local function Recollect() addon:RequestUpdate("full") end
-- Style changes (fonts, sizes, spacing) only need the current data repainted.
local function Repaint() addon:RefreshDisplay() end
local function UpdateAppearance() addon:UpdateTrackerAppearance() end
-- The tracker's own title uses the header font, and bars are drawn by rows.
local function UpdateAppearanceAndRepaint()
    addon:UpdateTrackerAppearance()
    addon:RefreshDisplay()
end
-- Map pins are Blizzard's, outside our render pass entirely.
local function RefreshMapPins() addon:RefreshMapPOIOutlines() end
local function RefreshDebugBoxes()
    addon:UpdateSectionDebugBoxes()
    addon:RequestUpdate("full")
end

local SETTING_EFFECTS = {
    enabled = function(enabled)
        addon:SetTrackerVisible(enabled)
        addon:UpdateDefaultTrackerVisibility()
    end,
    locked = function() addon:UpdateTrackerLock() end,
    -- Re-checking it should snap back onto the game's tracker immediately.
    matchBlizzardTracker = function(enabled)
        if enabled then addon:SyncWithBlizzardTracker() end
    end,
    hideInInstance = function() addon:RequestUpdate() end,
    hideInCombat = function() addon:RequestUpdate() end,

    frameAnchor = function() addon:ApplyTrackerAnchor() end, -- the frame doesn't move
    frameWidth = UpdateAppearance,
    frameHeight = UpdateAppearance,
    frameScale = UpdateAppearance,
    borderEnabled = UpdateAppearance,
    borderSize = UpdateAppearance,
    backgroundStyle = UpdateAppearance,
    -- borderStyle is added below UpdateSlider, which it needs.
    barBorderSize = UpdateAppearanceAndRepaint,
    barTexture = UpdateAppearanceAndRepaint,
    headerFontSize = UpdateAppearanceAndRepaint,
    fontSize = Repaint,
    objectiveFontSize = Repaint,
    headerIconStyle = Repaint,
    headerIconPosition = Repaint,
    headerBackgroundStyle = Repaint,
    rowBackgroundEnabled = Repaint,
    rowBackgroundStyle = Repaint,
    rowBackgroundAlpha = Repaint,

    fadeWhenEmpty = Recollect,
    showQuestLevel = Recollect,
    sortMethod = Recollect,
    colorQuestsByDifficulty = Recollect,
    includeCampaignQuestInActiveQuest = Recollect,
    includeFTAQuests = Recollect,
    showQuests = Recollect,
    showWorldQuests = Recollect,
    showAchievements = Recollect,
    showBonusObjectives = Recollect,
    showScenarios = Recollect,
    showProfessions = Recollect,
    showMonthlyActivities = Recollect,
    showEndeavors = Recollect,

    colorMapPOIsByDifficulty = RefreshMapPins,
    mapPOIOutlineStyle = RefreshMapPins,
    mapPOIOutlineThickness = RefreshMapPins,
    mapPOIGlowOpacity = RefreshMapPins,
    -- Starts or stops the area watcher; the highlight is an overlay on existing rows.
    highlightQuestsInArea = function() addon:UpdateQuestAreaWatcher() end,
    questAreaHighlightStyle = function() addon:RefreshQuestAreaHighlights(true) end,

    debugEnabled = function(enabled)
        RefreshDebugBoxes()
        addon.Print("Debugging " .. (enabled and "enabled" or "disabled") .. ".")
    end,
    debugSectionBoxes = RefreshDebugBoxes,
    debugLevel = function(level) addon:LogAt("info", "Debug level set to %s", tostring(level)) end,
    layoutDebug = function(enabled) addon:LogAt("info", "Layout debug %s", enabled and "enabled" or "disabled") end,
}
for _, key in ipairs({
    "spacingMajorHeaderIndent", "spacingMinorHeaderIndent", "spacingTrackableIndent",
    "spacingPOIButton", "spacingObjectiveIndent",
    "spacingProgressBarInset", "spacingProgressBarPadding",
    "spacingItemVertical", "spacingMajorHeaderAfter", "spacingMinorHeaderAfter",
}) do
    SETTING_EFFECTS[key] = Repaint
end

-------------------------------------------------------------------------------
-- Dependent controls: greyed out while a setting they depend on makes them moot.
-------------------------------------------------------------------------------
local dependencies = {}

-- isEnabled(db) decides, on every settings change and whenever a page opens, whether
-- the given widgets (as returned by the Create* helpers) are usable.
local function AddDependency(isEnabled, ...)
    dependencies[#dependencies + 1] = { isEnabled = isEnabled, widgets = { ... } }
end

local DISABLED_SHADE = 0.5

local function SetWidgetEnabled(widget, enabled)
    local shade = enabled and 1 or DISABLED_SHADE
    local kind = widget.tpKind
    if kind == "slider" then
        widget:SetEnabled(enabled) -- greys its own label and value
        return
    elseif kind == "colorPicker" then
        widget:SetEnabled(enabled)
        widget:SetAlpha(enabled and 1 or DISABLED_SHADE)
    else -- checkbox, button, dropdown
        widget:SetEnabled(enabled)
    end
    if widget.tpLabel then
        widget.tpLabel:SetTextColor(shade, shade, shade)
    end
end

local function RefreshDependencies()
    local db = addon.db
    for _, dependency in ipairs(dependencies) do
        local enabled = dependency.isEnabled(db) and true or false
        for _, widget in ipairs(dependency.widgets) do
            SetWidgetEnabled(widget, enabled)
        end
    end
end

-- Saves a setting and applies whatever it needs refreshed.
local function ChangeSetting(dbKey, value)
    addon:SetSetting(dbKey, value)
    local effect = SETTING_EFFECTS[dbKey]
    if effect then effect(value) end
    RefreshDependencies()
end

-- Lights up `control`'s row while hovered and shows `title` and the wrapped `body`,
-- like a row of the game's Settings list. `top` is a label above the control, if any.
local function AttachTooltip(control, title, body, top)
    W.AttachHover(control, { title = title, body = body, top = top })
end

-------------------------------------------------------------------------------
-- Widgets. Each takes the running y offset inside its section and returns the
-- next offset plus the widget, so dependent controls can be wired up.
-------------------------------------------------------------------------------

-- Helper: Create Checkbox
local function CreateCheckbox(parent, text, dbKey, tooltip, yOffset)
    local cb = W.CreateCheckbox(parent, addonName .. dbKey .. "Check")
    cb:SetPoint("TOPLEFT", 16, yOffset)
    cb.tpKind = "checkbox"
    cb.tpLabel = cb.Text
    cb.tpLabel:SetText(text)
    
    -- Load saved state, and re-read it whenever the page opens: slash commands
    -- (/tpdebug, /tp lock, /tp toggle) change settings while the panel is closed.
    cb:SetChecked(addon.db[dbKey])
    cb:HookScript("OnShow", function(self)
        self:SetChecked(addon.db[dbKey] and true or false)
    end)

    cb:SetScript("OnClick", function(self)
        ChangeSetting(dbKey, self:GetChecked())
    end)
    AttachTooltip(cb, text, tooltip)
    
    return yOffset - 30, cb
end

-- Sliders by setting key, for syncing ones the addon changes itself (UpdateSlider).
local sliders = {}

-- Track length of every slider. Leaves room in a half-width column for the arrows
-- and the value beside them.
local SLIDER_WIDTH = 160

-- Helper: Create Slider, with the Settings panel's stepper arrows and the value to its
-- right; clicking the value lets an exact number be typed (see SettingsWidgets.lua).
local function CreateSlider(parent, text, dbKey, minVal, maxVal, step, tooltip, yOffset)
    local slider = W.CreateSlider(parent, {
        label = text, min = minVal, max = maxVal, step = step, width = SLIDER_WIDTH,
        decimals = step >= 1 and 0 or 2,
        value = addon.db[dbKey] or minVal,
        onChange = function(value) ChangeSetting(dbKey, value) end,
    })
    -- The label sits above, so this puts its top where a checkbox's would be
    slider:SetPoint("TOPLEFT", 16, yOffset - 18)
    slider.tpKind = "slider"
    sliders[dbKey] = slider
    AttachTooltip(slider, text, tooltip)

    return yOffset - 50, slider -- Sliders need more vertical space
end

-- Width of every dropdown's box; its previous / next buttons add ~60px around it.
local DROPDOWN_WIDTH = 180

-- The label above every dropdown. Returns the dropdown's y offset.
local function CreateDropdownLabel(parent, text, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 16, yOffset - 5)
    label:SetText(text)
    return label, yOffset - 20
end

local function FinishDropdown(dropdown, label, text, tooltip)
    dropdown.tpKind = "dropdown"
    dropdown.tpLabel = label
    AttachTooltip(dropdown, text, tooltip, label)
end

-- Helper: Create Dropdown. `options` is a list of { text, value }, or a function
-- returning one (re-read each time the menu opens).
local function CreateDropdown(parent, text, dbKey, options, tooltip, yOffset)
    local label, dropdownY = CreateDropdownLabel(parent, text, yOffset)
    local dropdown = W.CreateChoiceDropdown(parent, DROPDOWN_WIDTH, options,
        function() return addon.db[dbKey] end,
        function(value) ChangeSetting(dbKey, value) end)
    dropdown:SetPoint("TOPLEFT", 16, dropdownY)
    FinishDropdown(dropdown, label, text, tooltip)

    return yOffset - 55, dropdown
end

-- LibSharedMedia status bar textures, plus the built-in "Blizzard" one.
local function GetBarTextureOptions()
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    -- Copied: LSM hands out its own list, which must not be re-sorted or added to.
    local names = {}
    for _, name in ipairs(lsm and lsm:List("statusbar") or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    if not tContains(names, "Blizzard") then
        table.insert(names, 1, "Blizzard")
    end

    local options = {}
    for i, name in ipairs(names) do
        options[i] = { text = name, value = name }
    end
    return options
end

-- A small gold heading inside a section, for a group of controls.
local function CreateSubheader(parent, text, yOffset)
    local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 16, yOffset - 6)
    heading:SetText(text)
    return yOffset - 26
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

local function ApplyFontChange(dbKey)
    if dbKey == "headerFontFace" then
        -- The tracker's own title uses the header font too.
        addon:UpdateTrackerAppearance()
    end
    addon:RefreshDisplay()
end

-- Helper: Create Font Dropdown (lists every available font, shown in that font; long
-- lists scroll). Hovering an entry previews it on the tracker; leaving or closing puts it back.
local function CreateFontDropdown(parent, text, dbKey, tooltip, yOffset)
    local label, dropdownY = CreateDropdownLabel(parent, text, yOffset)

    -- The saved font while a hovered one is temporarily in the db; nil when not previewing.
    local previewOriginal
    local function EndPreview()
        if previewOriginal == nil then return end
        addon.db[dbKey] = previewOriginal
        previewOriginal = nil
        ApplyFontChange(dbKey)
    end

    local function StartPreview(path)
        if previewOriginal == nil then previewOriginal = addon.db[dbKey] end
        addon.db[dbKey] = path
        ApplyFontChange(dbKey)
    end

    -- Checked against the saved font, not one being previewed.
    local function IsSelected(path)
        local current = previewOriginal or addon.db[dbKey]
        return type(current) == "string" and NormalizeFontPath(current) == NormalizeFontPath(path)
    end

    local function SetSelected(path)
        previewOriginal = nil -- keep it: this is now the saved font
        addon:SetSetting(dbKey, path)
        ApplyFontChange(dbKey)
    end

    local dropdown = W.CreateDropdown(parent, DROPDOWN_WIDTH, function(owner, rootDescription)
        local fonts = GetAvailableFonts()
        -- Shown when the saved font isn't in the list
        owner:SetDefaultText(GetFontDisplayName(previewOriginal or addon.db[dbKey], fonts))
        for _, font in ipairs(fonts) do
            local radio = W.CreateFontRadio(rootDescription, font.name, GetFontPreviewObject(font.path), IsSelected, SetSelected, font.path)
            radio:SetOnEnter(function() StartPreview(font.path) end)
            radio:SetOnLeave(EndPreview)
        end
        W.LimitMenuHeight(rootDescription, #fonts)
    end)
    dropdown.Dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuClose, EndPreview, dropdown)
    dropdown:SetPoint("TOPLEFT", 16, dropdownY)
    FinishDropdown(dropdown, label, text, tooltip)

    return yOffset - 55, dropdown
end

-- Helper: Create Color Picker. `width` is the clickable area (swatch + label); keep it
-- inside the column so neighbouring pickers don't overlap.
local function CreateColorPicker(parent, text, dbKey, callback, yOffset, width)
    local container = CreateFrame("Button", nil, parent)
    container:SetSize(width or 300, 24)
    container:SetPoint("TOPLEFT", 16, yOffset)
    container.tpKind = "colorPicker"
    
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
    -- Reset or another source can change the color while the panel is closed.
    container:SetScript("OnShow", UpdateSwatch)
    W.AttachHover(container) -- after SetScript("OnShow"), which would drop its hook

    return yOffset - 30, container
end

-- Helper: Create Button
local function CreateButton(parent, text, width, onClick, yOffset)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 150, 25)
    btn:SetPoint("TOPLEFT", 16, yOffset)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    btn.tpKind = "button"
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

-- Settings widgets the addon can change while the panel is open.
local function UpdateSlider(dbKey)
    local slider = sliders[dbKey]
    if slider and addon.db[dbKey] then
        slider:SetValue(addon.db[dbKey], true) -- silent: the setting is already saved
    end
end

-- Picking a border also sets Border Size to the size that texture is drawn for.
SETTING_EFFECTS.borderStyle = function(name)
    local _, edgeSize = addon:ResolvePanelMedia("border", name)
    addon:SetSetting("borderSize", edgeSize)
    UpdateSlider("borderSize")
    addon:UpdateTrackerAppearance()
end

-- Dropdown options for a panel texture kind ("border" or "background").
local function GetPanelMediaOptions(kind)
    return function()
        local options = {}
        for i, entry in ipairs(addon:GetPanelMediaList(kind)) do
            options[i] = { text = entry.name, value = entry.name }
        end
        return options
    end
end

local function UpdateCheckbox(dbKey)
    local check = _G[addonName .. dbKey .. "Check"]
    if check then
        check:SetChecked(addon.db[dbKey] and true or false)
    end
end

-- Syncs the widgets with settings the addon changed itself: drag-resizing, and
-- "Match Game Tracker" clearing itself once the player moves the tracker.
function addon:UpdateSettingWidgets()
    UpdateSlider("frameWidth")
    UpdateSlider("frameHeight")
    UpdateSlider("frameScale")
    UpdateCheckbox("matchBlizzardTracker")
    RefreshDependencies()
end

-- Initialize the Settings UI
local function InitUI()
    local orderedPages = {}

    -- A subpage under TrackerPlus in the Settings list, with a scrolling content frame.
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

        local scrollFrame = W.CreateScrollFrame(page, addonName .. "SettingsScrollFrame" .. id)
        scrollFrame:SetPoint("TOPLEFT", 5, -55)
        scrollFrame:SetPoint("BOTTOMRIGHT", -18, 4)

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(600, 100)
        scrollFrame:SetScrollChild(content)

        scrollFrame:SetScript("OnShow", function(self)
            self:SetVerticalScroll(0)
        end)
        page:HookScript("OnShow", RefreshDependencies)

        orderedPages[#orderedPages + 1] = { id = id, name = pageTitle, frame = page, content = content }
        return content
    end

    local s, sy, left, leftY
    local y

    ---------------------------------------------------------------------------
    -- TrackerPlus (top-level page): general behavior
    ---------------------------------------------------------------------------
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("TrackerPlus")
    
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
    -- Read from the .toc rather than hardcoding, so it can't drift out of date.
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local addonVersion = getMetadata and getMetadata(addonName, "Version")
    version:SetText(addonVersion and ("v" .. addonVersion) or "")
    panel:HookScript("OnShow", RefreshDependencies)

    y = -45
    left, leftY = StartColumnSection(panel, "Tracker", y, 1)
    leftY = CreateCheckbox(left, "Enable TrackerPlus", "enabled", "Replace the game's objective tracker with TrackerPlus.", leftY)
    leftY = CreateCheckbox(left, "Lock Panel", "locked", "Stop the tracker from being dragged or resized.", leftY)
    leftY = CreateCheckbox(left, "Show Tooltips", "showTooltips", "Show quest details when hovering a tracker row.", leftY)

    s, sy = StartColumnSection(panel, "Visibility", y, 2)
    sy = CreateCheckbox(s, "Hide in Instances", "hideInInstance", "Hide the tracker inside dungeons and raids.", sy)
    sy = CreateCheckbox(s, "Hide in Combat", "hideInCombat", "Hide the tracker during combat.", sy)
    sy = CreateCheckbox(s, "Hide When Empty", "fadeWhenEmpty", "Hide the tracker while nothing is tracked (only while it's locked).", sy)
    y = y - EndColumnRow(left, leftY, s, sy)

    -- Built only from what applies here: campaigns are retail-only, and Follow the
    -- Arrow needs its addon. Left out entirely when neither does.
    local showCampaignPin = addon:IsSettingAvailable("includeCampaignQuestInActiveQuest")
    local showFTAPin = addon:IsFollowTheArrowAvailable()
    if showCampaignPin or showFTAPin then
        s, sy = StartSection(panel, "Pinned Sections", y)
        if showCampaignPin then
            sy = CreateCheckbox(s, "Campaign in Active Quest", "includeCampaignQuestInActiveQuest", "When a campaign quest is your Active (super-tracked) quest, also show it in the Active Quest section instead of only under Campaign Quests.", sy)
        end
        if showFTAPin then
            sy = CreateCheckbox(s, "Follow the Arrow", "includeFTAQuests", "Show a Follow the Arrow guide section between Active Quest and Campaign Quests.", sy)
        end
        y = y - EndSection(s, sy)
    end

    local overview = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    overview:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y)
    overview:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    overview:SetJustifyH("LEFT")
    overview:SetText("More settings are on the pages under TrackerPlus in the list on the left: Tracking Panel, Nameplates, Appearance, Layout, Map Pins and Debug.")
    y = y - 30

    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(150, 25)
    resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    resetBtn:SetText("Reset All Settings")
    resetBtn:SetScript("OnClick", function() StaticPopup_Show("TRACKERPLUS_RESET_CONFIRM") end)

    ---------------------------------------------------------------------------
    -- Tracking Panel
    ---------------------------------------------------------------------------
    local tracking = CreateSettingsPage("Tracking", "Tracking Panel", "What the tracker shows and how quests are colored and sorted.")
    y = -5

    left, leftY = StartSection(tracking, "Quest Display", y)
    leftY = CreateCheckbox(left, "Show Quest Level", "showQuestLevel", "Show each quest's level before its name, e.g. [28+] for a group quest.", leftY)
    leftY = CreateCheckbox(left, "Color by Difficulty", "colorQuestsByDifficulty", "Color quest names by how hard each quest is for you, matching the default quest log (grey, green, yellow, orange, red). Turn off to use the flat Quest Text color from Appearance instead.", leftY)
    leftY = CreateDropdown(left, "Sort Order", "sortMethod", {
        {text = "Difficulty (Easiest First)", value = "difficulty_asc"},
        {text = "Difficulty (Hardest First)", value = "difficulty_desc"},
        {text = "Proximity", value = "proximity"},
        {text = "Alphabetical", value = "alphabetical"}
    }, "Order entries within each zone. Difficulty compares each quest's level to yours: Easiest First puts trivial quests at the top, Hardest First puts them at the bottom. Proximity puts the closest objective first. Alphabetical sorts by name.", leftY)
    y = y - EndSection(left, leftY)

    -- Two columns of checkboxes inside one full-width section.
    s, sy = StartSection(tracking, "Trackable Types", y)
    local typesLeft = CreateFrame("Frame", nil, s)
    typesLeft:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
    typesLeft:SetSize(290, 1)
    local typesRight = CreateFrame("Frame", nil, s)
    typesRight:SetPoint("TOPLEFT", s, "TOPLEFT", 295, 0)
    typesRight:SetSize(290, 1)
    local TRACKABLE_TYPES = {}
    for _, entry in ipairs({
        { "Quests", "showQuests", "Track regular quests." },
        { "World Quests", "showWorldQuests", "Track world quests." },
        { "Bonus Objectives", "showBonusObjectives", "Track bonus objectives." },
        { "Scenarios", "showScenarios", "Track scenarios, delves and dungeons." },
        { "Achievements", "showAchievements", "Track achievements." },
        { "Professions", "showProfessions", "Track profession recipes." },
        { "Monthly Activities", "showMonthlyActivities", "Track Trading Post / Traveler's Log activities." },
        { "Endeavors", "showEndeavors", "Track housing endeavors." },
    }) do
        if addon:IsSettingAvailable(entry[2]) then
            TRACKABLE_TYPES[#TRACKABLE_TYPES + 1] = entry
        end
    end
    -- Left column fills first; the right takes the rest.
    local typesPerColumn = math.ceil(#TRACKABLE_TYPES / 2)
    local typesY = sy
    for i, entry in ipairs(TRACKABLE_TYPES) do
        local column = i <= typesPerColumn and typesLeft or typesRight
        CreateCheckbox(column, entry[1], entry[2], entry[3], typesY - ((i - 1) % typesPerColumn) * 30)
    end
    sy = sy - typesPerColumn * 30
    y = y - EndSection(s, sy)

    tracking:SetHeight(math.abs(y) + 20)

    ---------------------------------------------------------------------------
    -- Map Pins
    ---------------------------------------------------------------------------
    local mapPins = CreateSettingsPage("MapPins", "Map Pins", "How the game's quest pins on the world map are marked.")
    y = -5

    local mapPinsEnabled, mapPinStyle, mapPinThickness, mapPinOpacity
    left, leftY = StartSection(mapPins, "World Map Pins", y)
    leftY = CreateCheckbox(left, "Color by Difficulty", "colorMapPOIsByDifficulty", "Ring the game's quest pins on the world map in the same color that quest's name has in the tracker.", leftY)
    leftY, mapPinStyle = CreateDropdown(left, "Style", "mapPOIOutlineStyle", {
        {text = "Glow", value = "glow"},
        {text = "Circle", value = "circle"}
    }, "Glow uses the game's own soft ring art, fading outwards. Circle draws a hard-edged ring of an exact pixel thickness instead.", leftY)
    leftY, mapPinThickness = CreateSlider(left, "Thickness", "mapPOIOutlineThickness", 1, 10, 1, "How far past the pin the circle or glow reaches, in pixels.", leftY)
    leftY, mapPinOpacity = CreateSlider(left, "Glow Opacity", "mapPOIGlowOpacity", 0.05, 1, 0.05, "How solid the glow is, where 1 is as solid as it can be drawn. Only applies to the Glow style; the circle is always drawn opaque.", leftY)
    mapPinsEnabled = function(db) return db.colorMapPOIsByDifficulty end
    AddDependency(mapPinsEnabled, mapPinStyle, mapPinThickness)
    AddDependency(function(db) return db.colorMapPOIsByDifficulty and db.mapPOIOutlineStyle ~= "circle" end, mapPinOpacity)
    y = y - EndSection(left, leftY)

    mapPins:SetHeight(math.abs(y) + 20)

    -- Page: Nameplates. Built by NameplatesSettings.lua; added here so it registers with the rest.
    orderedPages[#orderedPages + 1] = { id = "Nameplates", name = "Nameplates", frame = addon.Nameplates.settingsPanel }

    ---------------------------------------------------------------------------
    -- Appearance
    ---------------------------------------------------------------------------
    local appearance = CreateSettingsPage("Appearance", "Appearance", "Frame size and position, styling, fonts and colors.")
    y = -5

    local frameWidthSlider, frameHeightSlider
    left, leftY = StartColumnSection(appearance, "Dimensions", y, 1)
    leftY = CreateCheckbox(left, "Match Game Tracker", "matchBlizzardTracker", "Place and size the tracker exactly over the game's own objective tracker, following any changes you make to it in the game's Edit Mode. Turns itself off as soon as you drag or resize TrackerPlus yourself; re-check it to snap back.", leftY)
    leftY = CreateDropdown(left, "Anchor", "frameAnchor", {
        {text = "Top Left", value = "TOPLEFT"},
        {text = "Top", value = "TOP"},
        {text = "Top Right", value = "TOPRIGHT"},
        {text = "Left", value = "LEFT"},
        {text = "Center", value = "CENTER"},
        {text = "Right", value = "RIGHT"},
        {text = "Bottom Left", value = "BOTTOMLEFT"},
        {text = "Bottom", value = "BOTTOM"},
        {text = "Bottom Right", value = "BOTTOMRIGHT"},
    }, "The point of the tracker that stays in place when it's resized. Top Right grows down and to the left; Bottom Left grows up and to the right.", leftY)
    leftY, frameWidthSlider = CreateSlider(left, "Width", "frameWidth", 150, 500, 1, "Width of the tracker frame. Set by the game's tracker while Match Game Tracker is on.", leftY)
    leftY, frameHeightSlider = CreateSlider(left, "Height", "frameHeight", 200, 800, 1, "Height of the tracker frame. Set by the game's tracker while Match Game Tracker is on.", leftY)
    leftY = CreateSlider(left, "Scale", "frameScale", 0.5, 2.0, 0.1, "Scale of the tracker frame.", leftY)
    AddDependency(function(db) return not db.matchBlizzardTracker end, frameWidthSlider, frameHeightSlider)

    -- The color pickers only apply to Solid; textures are drawn in their own colors.
    local function IsSolid(kind, name)
        return addon:IsSolidPanelMedia((addon:ResolvePanelMedia(kind, name)))
    end
    local borderStyleDropdown, borderSizeSlider, borderColorPicker, backgroundColorPicker
    s, sy = StartColumnSection(appearance, "Panel Styling", y, 2)
    sy = CreateDropdown(s, "Background", "backgroundStyle", GetPanelMediaOptions("background"), "The texture behind the tracker, stretched to fill it: Solid, the game's own backgrounds, or any other addons registered with LibSharedMedia.", sy)
    sy, backgroundColorPicker = CreateColorPicker(s, "Background Color", "backgroundColor", UpdateAppearance, sy, 250)
    sy = CreateCheckbox(s, "Show Border", "borderEnabled", "Show a border around the tracker.", sy)
    sy, borderStyleDropdown = CreateDropdown(s, "Border Style", "borderStyle", GetPanelMediaOptions("border"), "The border drawn around the outside of the tracker: the game's own borders, plus any other addons registered with LibSharedMedia. Picking one sets Border Size to suit it.", sy)
    sy, borderColorPicker = CreateColorPicker(s, "Border Color", "borderColor", UpdateAppearance, sy, 250)
    sy, borderSizeSlider = CreateSlider(s, "Border Size", "borderSize", 1, 32, 1, "How thick the border is, in pixels; it grows outwards from the tracker. Textured borders look best at the size picking them sets.", sy)
    AddDependency(function(db) return db.borderEnabled end, borderStyleDropdown, borderSizeSlider)
    AddDependency(function(db) return db.borderEnabled and IsSolid("border", db.borderStyle) end, borderColorPicker)
    AddDependency(function(db) return IsSolid("background", db.backgroundStyle) end, backgroundColorPicker)
    y = y - EndColumnRow(left, leftY, s, sy)

    left, leftY = StartColumnSection(appearance, "Header Styling", y, 1)
    leftY = CreateDropdown(left, "Expand/Collapse Icon", "headerIconStyle", {
        {text = "None", value = "none"},
        {text = "Standard (Gold)", value = "standard"},
        {text = "Square (Check)", value = "square"},
        {text = "Text (+/-)", value = "text_brackets"},
        {text = "Quest Log (+/-)", value = "questlog"}
    }, "Style of the expand/collapse icons on headers.", leftY)
    leftY = CreateDropdown(left, "Icon Position", "headerIconPosition", {
        {text = "Left (Start)", value = "left"},
        {text = "Right (End)", value = "right"}
    }, "Which side of the header the expand/collapse icon sits on.", leftY)
    leftY = CreateDropdown(left, "Header Background", "headerBackgroundStyle", {
        {text = "None", value = "none"},
        {text = "Quest Log Background", value = "questlog"},
        {text = "Tracker Background (Custom)", value = "tracker"}
    }, "Background behind section and zone headers.", leftY)

    local rowStyleDropdown, rowAlphaSlider
    s, sy = StartColumnSection(appearance, "Row Styling", y, 2)
    sy = CreateCheckbox(s, "Show Row Background", "rowBackgroundEnabled", "Draw a background behind each quest and trackable row (not those in the Active Quest panel).", sy)
    sy, rowStyleDropdown = CreateDropdown(s, "Row Background", "rowBackgroundStyle", addon.RowBackgroundStyles, "The background drawn behind each row, from the game's own Social window cards.", sy)
    sy, rowAlphaSlider = CreateSlider(s, "Opacity", "rowBackgroundAlpha", 0.05, 1, 0.05, "How solid the row background is.", sy)
    AddDependency(function(db) return db.rowBackgroundEnabled end, rowStyleDropdown, rowAlphaSlider)

    local areaStyle, areaColor
    sy = CreateSubheader(s, "Quest Area Highlight", sy)
    sy = CreateCheckbox(s, "Highlight quests in your current area", "highlightQuestsInArea", "Highlight a quest's tracker row while you are inside the area the map shades for it.", sy)
    sy, areaStyle = CreateDropdown(s, "Style", "questAreaHighlightStyle", addon.QuestAreaHighlightStyles, "How a quest you're standing in is marked in the tracker. Background and Gradient styles use a faded version of the color below so the text stays readable. Friend Card styles lay a card over the row background: Battle.net in its own colors, Selected tinted the color below.", sy)
    sy, areaColor = CreateColorPicker(s, "Color", "questAreaHighlightColor", function()
        addon:RefreshQuestAreaHighlights(true)
    end, sy, 250)
    AddDependency(function(db) return db.highlightQuestsInArea end, areaStyle)
    AddDependency(function(db)
        return db.highlightQuestsInArea and addon:QuestAreaHighlightUsesColor(db.questAreaHighlightStyle)
    end, areaColor)
    y = y - EndColumnRow(left, leftY, s, sy)

    s, sy = StartSection(appearance, "Progress Bars", y)
    sy = CreateSlider(s, "Border Size", "barBorderSize", 0, 10, 1, "Thickness of the progress bar border in pixels (0 hides it).", sy)
    sy = CreateDropdown(s, "Texture", "barTexture", GetBarTextureOptions, "Texture used for progress bars. Lists the textures other addons registered with LibSharedMedia.", sy)
    y = y - EndSection(s, sy)
    
    -- Fonts: one row per text type, font picker on the left and its size on the right
    s, sy = StartSection(appearance, "Fonts", y)
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
        CreateSlider(fontRight, row[3], row[4], row[5], row[6], 1, "Size of " .. row[7] .. ".", sy)
        sy = sy - 60
    end
    y = y - EndSection(s, sy)
    
    -- Colors: three labeled columns inside one section.
    s, sy = StartSection(appearance, "Colors", y)
    local COLOR_COLUMN_WIDTH = 190
    local function ColorColumn(index)
        local column = CreateFrame("Frame", nil, s)
        column:SetPoint("TOPLEFT", s, "TOPLEFT", (index - 1) * COLOR_COLUMN_WIDTH, 0)
        column:SetSize(COLOR_COLUMN_WIDTH, 1)
        return column
    end
    local updateDisplay = function() addon:RefreshDisplay() end
    local COLOR_COLUMNS = {
        { "Frame", {
            { "Bar Background", "barBackgroundColor", updateDisplay },
        } },
        { "Text", {
            { "Headers", "headerColor", updateDisplay },
            { "Quest Names", "questColor", updateDisplay },
            { "Objectives", "objectiveColor", updateDisplay },
            { "Completed", "completeColor", updateDisplay },
            { "Failed", "failedColor", updateDisplay },
        } },
        { "Trackable Types", {
            { "Achievements", "achievementColor", updateDisplay },
            { "Professions", "professionColor", updateDisplay },
            { "Monthly Activities", "monthlyColor", updateDisplay },
            { "Endeavors", "endeavorColor", updateDisplay },
            { "Scenarios", "scenarioColor", updateDisplay },
            { "Bonus Objectives", "bonusColor", updateDisplay },
        } },
    }
    local colorsBottom = sy
    local columnIndex = 0
    for _, columnInfo in ipairs(COLOR_COLUMNS) do
        local pickers = {}
        for _, picker in ipairs(columnInfo[2]) do
            if addon:IsSettingAvailable(picker[2]) then
                pickers[#pickers + 1] = picker
            end
        end
        -- A column with nothing left in it on this client is left out entirely.
        if #pickers > 0 then
            columnIndex = columnIndex + 1
            local column = ColorColumn(columnIndex)
            local columnY = CreateSubheader(column, columnInfo[1], sy)
            for _, picker in ipairs(pickers) do
                columnY = CreateColorPicker(column, picker[1], picker[2], picker[3], columnY, COLOR_COLUMN_WIDTH - 24)
            end
            colorsBottom = math.min(colorsBottom, columnY)
        end
    end
    sy = colorsBottom
    y = y - EndSection(s, sy)
    
    appearance:SetHeight(math.abs(y) + 20)
    
    ---------------------------------------------------------------------------
    -- Layout
    ---------------------------------------------------------------------------
    local layout = CreateSettingsPage("Layout", "Layout", "Fine-tune horizontal and vertical spacing.")
    y = -5
    
    left, leftY = StartColumnSection(layout, "Horizontal Spacing", y, 1)
    leftY = CreateSlider(left, "Major Header Indent", "spacingMajorHeaderIndent", 0, 50, 1, "Left indent for major category headers (Quests, Achievements).", leftY)
    leftY = CreateSlider(left, "Minor Header Indent", "spacingMinorHeaderIndent", 0, 50, 1, "Left indent for zone/subgroup headers.", leftY)
    leftY = CreateSlider(left, "Quest/Item Indent", "spacingTrackableIndent", 0, 50, 1, "Left indent for individual quests and trackables.", leftY)
    leftY = CreateSlider(left, "POI Button Padding", "spacingPOIButton", 0, 50, 1, "Left padding for text when the POI button is shown.", leftY)
    leftY = CreateSlider(left, "Objective Indent", "spacingObjectiveIndent", 0, 50, 1, "Extra indent for objective lines (relative to the quest).", leftY)
    leftY = CreateSlider(left, "Progress Bar Inset", "spacingProgressBarInset", 0, 50, 1, "Horizontal margin for progress bars from the edges.", leftY)
    leftY = CreateSlider(left, "Progress Bar Padding", "spacingProgressBarPadding", 0, 20, 1, "Vertical padding between text and a progress bar.", leftY)

    s, sy = StartColumnSection(layout, "Vertical Spacing", y, 2)
    sy = CreateSlider(s, "Item Spacing", "spacingItemVertical", 0, 20, 1, "Vertical gap between trackable items.", sy)
    sy = CreateSlider(s, "Major Header Gap", "spacingMajorHeaderAfter", 10, 50, 1, "Vertical space after major category headers.", sy)
    sy = CreateSlider(s, "Minor Header Gap", "spacingMinorHeaderAfter", 10, 50, 1, "Vertical space after zone/subgroup headers.", sy)
    y = y - EndColumnRow(left, leftY, s, sy)
    
    layout:SetHeight(math.abs(y) + 20)

    ---------------------------------------------------------------------------
    -- Debug
    ---------------------------------------------------------------------------
    local debugPage = CreateSettingsPage("Debug", "Debug", "Diagnostic logging and debug overlay controls.")
    y = -5

    local debugLevel, layoutDebug, sectionBoxes, openDebugBtn, clearDebugBtn
    s, sy = StartSection(debugPage, "Debug Options", y)
    sy = CreateCheckbox(s, "Enable Debugging", "debugEnabled", "Master switch for all TrackerPlus debugging features.", sy)
    sy, debugLevel = CreateDropdown(s, "Debug Log Level", "debugLevel", {
        {text = "Off", value = "off"},
        {text = "Errors", value = "error"},
        {text = "Warnings", value = "warn"},
        {text = "Info", value = "info"},
        {text = "Trace", value = "trace"},
    }, "Controls verbosity for TrackerPlus debug logging.", sy)
    sy, layoutDebug = CreateCheckbox(s, "Layout Debug Logging", "layoutDebug", "Logs detailed layout snapshots (use with Trace level).", sy)
    sy, sectionBoxes = CreateCheckbox(s, "Section Box Overlays", "debugSectionBoxes", "Draw labeled rectangles around tracker sections.", sy)
    sy, openDebugBtn = CreateButton(s, "Open Debug Window", 170, function()
        addon:ShowDebug()
    end, sy)
    sy, clearDebugBtn = CreateButton(s, "Clear Debug Log", 170, function()
        addon:ClearDebug()
        addon.Print("Debug log cleared.")
    end, sy)
    AddDependency(function(db) return db.debugEnabled end, debugLevel, layoutDebug, sectionBoxes, openDebugBtn, clearDebugBtn)
    y = y - EndSection(s, sy)
    debugPage:SetHeight(math.abs(y) + 20)

    -- The order pages appear under TrackerPlus in the Settings list, independent of build order.
    local PAGE_ORDER = { Tracking = 1, Nameplates = 2, Appearance = 3, Layout = 4, MapPins = 5, Debug = 6 }
    table.sort(orderedPages, function(a, b)
        return (PAGE_ORDER[a.id] or 99) < (PAGE_ORDER[b.id] or 99)
    end)

    addon.settingsPageOrder = orderedPages
    addon.settingsPages = {}
    for _, page in ipairs(orderedPages) do
        addon.settingsPages[page.id] = page
    end

    RefreshDependencies()
end

-- Confirmation dialog
StaticPopupDialogs["TRACKERPLUS_RESET_CONFIRM"] = {
    text = "Are you sure you want to reset all TrackerPlus settings to default?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        -- Reloading rebuilds the tracker and this panel from the fresh defaults.
        addon:ResetDatabase()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Register settings
addon.settingsCategory = nil
addon.settingsSubcategories = {}
local settingsFrame = CreateFrame("Frame")
settingsFrame:RegisterEvent("PLAYER_LOGIN")
settingsFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    do
        -- Core.lua's Initialize runs a moment after login; the panel needs the
        -- settings now. (InitDatabase is safe to run twice.)
        if not addon.db then
            addon:InitDatabase()
        end
        
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
        
        -- Opens a settings page by id ("Tracking", "Nameplates", ...), or the top-level
        -- TrackerPlus page when nil; used by /tp and /tp nameplates.
        addon.OpenSettings = function(pageID)
            if Settings and Settings.OpenToCategory then
                local targetCategory = (pageID and addon.settingsSubcategories[pageID]) or addon.settingsCategory

                local id = targetCategory and targetCategory:GetID()
                if id then
                    Settings.OpenToCategory(id)
                end
            elseif InterfaceOptionsFrame_OpenToCategory then
                local targetPanel = (pageID and addon.settingsPages[pageID] and addon.settingsPages[pageID].frame) or panel
                InterfaceOptionsFrame_OpenToCategory(targetPanel)
                InterfaceOptionsFrame_OpenToCategory(targetPanel)
            end
        end
    end
end)
