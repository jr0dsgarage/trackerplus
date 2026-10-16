---@diagnostic disable: undefined-global
-- Settings controls built from the templates the game's own Settings panel uses, so
-- j__r0d's garage addons look and behave like the default options:
--   * checkboxes: SettingsCheckboxTemplate
--   * sliders: MinimalSliderWithSteppersTemplate (the < > arrows beside the track)
--   * dropdowns: SettingsDropdownWithButtonsTemplate (previous / next option buttons)
--   * scrolling pages: ScrollFrameTemplate (the thin MinimalScrollBar)
--   * hover rows: the faint highlight and tooltip the Settings list shows on each row
-- Kept identical in every garage addon; edit one copy, then copy it to the others.
local _, addon = ...

local W = {}
addon.SettingsWidgets = W

-- The template pads the track by 19px on each side for its arrows.
local SLIDER_STEPPER_PAD = 19
-- Width the previous / next buttons add around a dropdown box (26px each plus gaps).
local DROPDOWN_STEPPER_PAD = 61
-- A menu longer than this many entries scrolls instead of running off the screen.
local MENU_SCROLL_ROWS = 20
local MENU_ROW_HEIGHT = 20

-- The highlight behind a hovered row, as in the Settings list (HoverBackgroundTemplate).
local ROW_HOVER_ALPHA = 0.1

local function SetFontStringEnabled(fontString, enabled, color)
    fontString:SetTextColor((enabled and (color or HIGHLIGHT_FONT_COLOR) or GRAY_FONT_COLOR):GetRGB())
end
W.SetFontStringEnabled = SetFontStringEnabled

-- Scroll frame with the thin scroll bar the Settings list uses, hidden while there is
-- nothing to scroll. The bar sits 6px right of the frame and is 8px wide, so leave
-- about 16px between the frame and the page's right edge.
function W.CreateScrollFrame(parent, name)
    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "ScrollFrameTemplate")
    scrollFrame.ScrollBar:SetHideIfUnscrollable(true)
    return scrollFrame
end

-- Checkbox from the Settings panel with its label to the right; clicking the label
-- toggles it too. Like InterfaceOptionsCheckButtonTemplate, the label is .Text, and
-- it greys out while the checkbox is disabled.
function W.CreateCheckbox(parent, name)
    local checkbox = CreateFrame("CheckButton", name, parent, "SettingsCheckboxTemplate")

    -- The template's hover texture and tooltip are laid out for a row of the Settings
    -- list (the texture fills the checkbox's parent); W.AttachHover does both here.
    checkbox.HoverBackground:Hide()
    checkbox.HoverBackground = nil
    checkbox:SetScript("OnEnter", nil)
    checkbox:SetScript("OnLeave", nil)

    local text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    text:SetJustifyH("LEFT")
    checkbox.Text = text

    -- Stretch the clickable area over the label
    hooksecurefunc(text, "SetText", function()
        checkbox:SetHitRectInsets(0, -(text:GetUnboundedStringWidth() + 2), 0, 0)
    end)

    checkbox:HookScript("OnEnable", function() SetFontStringEnabled(text, true) end)
    checkbox:HookScript("OnDisable", function() SetFontStringEnabled(text, false) end)

    -- PostClick, so callers can still SetScript("OnClick") freely
    checkbox:SetScript("PostClick", function(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    return checkbox
end

local function GetTooltip()
    return SettingsTooltip or GameTooltip
end

-- The parts of a control the mouse can be over, for W.AttachHover.
local function GetHoverFrames(control)
    if control.Slider then
        return { control, control.Slider, control.Back, control.Forward, control.ValueBox }
    elseif control.Dropdown then
        return { control, control.Dropdown, control.DecrementButton, control.IncrementButton }
    end
    return { control }
end

-- Lights up a control's row while the mouse is anywhere over it, as the Settings list
-- does, and shows a tooltip: the title in white, then `body` in gold (no tooltip
-- without a body).
-- The row runs from the top of opts.top (default: the control, or a slider's label) to the bottom of the
-- control, and across its parent; opts.left / opts.right narrow it to the left edge of
-- one region / right edge of another, for controls that share a line.
-- opts:
--   body      tooltip text (string, or a function returning one)
--   title     tooltip heading; defaults to the control's label (.Text / .Label) or opts.top's text
--   top, left, right   regions bounding the row, as above
--   anchor    what the tooltip sits to the right of (default: the label beside a
--             checkbox, the value beside a slider, else the control)
--   frames    more frames whose hover should count as hovering the row
function W.AttachHover(control, opts)
    opts = opts or {}
    local parent = control:GetParent()

    -- Below the controls (they sit one level above their parent) so they keep the mouse
    local row = CreateFrame("Frame", nil, parent)
    row:SetFrameLevel(parent:GetFrameLevel())
    -- A slider's label sits above it, so its row starts there
    row:SetPoint("TOP", opts.top or (control.Slider and control.Label) or control, "TOP", 0, 3)
    row:SetPoint("BOTTOM", control, "BOTTOM", 0, -3)
    if opts.left then
        row:SetPoint("LEFT", opts.left, "LEFT", -6, 0)
    else
        row:SetPoint("LEFT", parent, "LEFT", 4, 0)
    end
    if opts.right then
        row:SetPoint("RIGHT", opts.right, "RIGHT", 6, 0)
    else
        row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    end
    control.HoverRow = row

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, ROW_HOVER_ALPHA)
    highlight:Hide()

    local anchor = opts.anchor or control.Text or control.ValueBox or control

    -- First non-empty label (the dropdown template has an unused, empty .Label)
    local function GetTitle()
        if opts.title then return opts.title end
        local labels = { control.Text, control.Label, opts.top } -- any may be nil
        for i = 1, 3 do
            local label = labels[i]
            local text = label and label.GetText and label:GetText()
            if text and text ~= "" then return text end
        end
        return ""
    end

    local function ShowTooltip()
        local body = type(opts.body) == "function" and opts.body() or opts.body
        if not body then return end
        local tooltip = GetTooltip()
        tooltip:SetOwner(anchor, "ANCHOR_RIGHT", 10, 0)
        tooltip:SetText(GetTitle() or "", HIGHLIGHT_FONT_COLOR:GetRGB())
        tooltip:AddLine(body, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
        tooltip:Show()
    end

    -- Polls only while lit, until the mouse leaves the row's rectangle. Moving between
    -- the control's parts never flickers, since the row contains them all.
    local function WatchForLeave(self)
        if not self:IsMouseOver() then
            self:SetScript("OnUpdate", nil)
            highlight:Hide()
            local tooltip = GetTooltip()
            if tooltip:GetOwner() == anchor then
                tooltip:Hide()
            end
        end
    end

    local function OnEnter()
        if highlight:IsShown() then return end
        highlight:Show()
        ShowTooltip()
        row:SetScript("OnUpdate", WatchForLeave)
    end

    -- Takes hover but not clicks, so the gaps between controls light the row
    if row.SetMouseMotionEnabled then
        row:SetMouseMotionEnabled(true)
        row:SetMouseClickEnabled(false)
    else
        row:EnableMouse(true)
    end
    row:SetScript("OnEnter", OnEnter)

    -- A hidden control (e.g. one this client doesn't support) takes its row with it
    row:SetShown(control:IsShown())
    control:HookScript("OnShow", function() row:Show() end)
    control:HookScript("OnHide", function() row:Hide() end)

    for _, frame in ipairs(GetHoverFrames(control)) do
        if frame then frame:HookScript("OnEnter", OnEnter) end
    end
    for _, frame in ipairs(opts.frames or {}) do
        frame:HookScript("OnEnter", OnEnter)
    end

    return row
end

-- Slider with the stepper arrows from the game's Settings panel, a label above it and
-- the value to its right. Clicking the value lets an exact number be typed.
-- opts:
--   min, max, step   range and step (step defaults to 1)
--   value            starting value
--   width            length of the track (default 200); arrows and value add to this
--   label            text above the slider
--   decimals, scale  the value is shown as value * scale to this many decimals
--                    (scale 100 shows a 0-1 setting as a percentage)
--   showValue        false hides the value; use labelFormat to show it in the label
--   labelFormat      function(value) returning the label text, re-run on every change
--   onChange         function(value), called with the value snapped to the step
-- Returns the slider frame, with :SetValue(value, silent), :GetValue(),
-- :SetMinMaxValues(min, max), :SetEnabled(enabled), :IsEnabled() and .Label.
function W.CreateSlider(parent, opts)
    local control = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
    control:SetSize((opts.width or 200) + SLIDER_STEPPER_PAD * 2, 20)
    local slider = control.Slider

    local minVal, maxVal = opts.min, opts.max
    local step = opts.step or 1
    local scale = opts.scale or 1
    local fmt = "%." .. (opts.decimals or 0) .. "f"
    local current
    local silent = false

    local function Snap(value)
        value = minVal + math.floor((value - minVal) / step + 0.5) * step
        value = math.max(minVal, math.min(maxVal, value))
        -- Drops float noise such as 0.30000000000000004
        return tonumber(string.format("%.6f", value))
    end

    local label = control:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("BOTTOMLEFT", control, "TOPLEFT", 0, 2)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(opts.label or "")
    control.Label = label

    -- Sits where the Settings panel puts its value text, but can take focus to be typed into.
    local box
    if opts.showValue ~= false then
        box = CreateFrame("EditBox", nil, control)
        box:SetSize(44, 20)
        box:SetPoint("LEFT", slider, "RIGHT", 25, 0)
        box:SetFontObject(GameFontNormal)
        box:SetJustifyH("LEFT")
        box:SetAutoFocus(false)
        box:SetMaxLetters(7)
        control.ValueBox = box

        local hover = box:CreateTexture(nil, "BACKGROUND")
        hover:SetPoint("TOPLEFT", -4, 0)
        hover:SetPoint("BOTTOMRIGHT", 0, 0)
        hover:SetColorTexture(1, 1, 1, 0.1)
        hover:Hide()

        box:SetScript("OnEnter", function() hover:Show() end)
        box:SetScript("OnLeave", function(self)
            if not self:HasFocus() then hover:Hide() end
        end)
        box:SetScript("OnEditFocusGained", function(self)
            hover:Show()
            self:HighlightText()
        end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(self)
            self:SetText("") -- discarded: the stored value is re-shown below
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function(self)
            hover:Hide()
            self:HighlightText(0, 0)
            local num = tonumber(self:GetText())
            if num then
                control:SetValue(num / scale)
            end
            -- Re-show the stored value: covers invalid input, clamping and rounding
            control:ShowValue(current)
        end)
    end

    function control:ShowValue(value)
        if box and not box:HasFocus() then
            box:SetText(string.format(fmt, value * scale))
            box:SetCursorPosition(0)
        end
        if opts.labelFormat then
            label:SetText(opts.labelFormat(value))
        end
    end

    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetScript("OnValueChanged", function(_, raw)
        local value = Snap(raw)
        control:UpdateStepperStates()
        control:ShowValue(value)
        if value ~= current then
            current = value
            if not silent and opts.onChange then
                opts.onChange(value)
            end
        end
    end)

    -- silent: move the slider without calling onChange (for refreshing from saved settings)
    function control:SetValue(value, isSilent)
        silent = isSilent and true or false
        slider:SetValue(math.max(minVal, math.min(maxVal, value)))
        silent = false
    end

    function control:GetValue()
        return current
    end

    function control:SetMinMaxValues(newMin, newMax)
        minVal, maxVal = newMin, newMax
        slider:SetMinMaxValues(newMin, newMax)
        self:UpdateStepperStates()
    end

    function control:SetEnabled(enabled)
        MinimalSliderWithSteppersMixin.SetEnabled(self, enabled)
        SetFontStringEnabled(label, enabled)
        if box then
            if not enabled then box:ClearFocus() end
            box:SetEnabled(enabled)
            SetFontStringEnabled(box, enabled, NORMAL_FONT_COLOR)
        end
    end

    function control:Enable() self:SetEnabled(true) end
    function control:Disable() self:SetEnabled(false) end

    function control:IsEnabled()
        return self:IsSliderEnabled()
    end

    current = Snap(opts.value or minVal)
    silent = true
    slider:SetValue(current)
    silent = false
    control:ShowValue(current)
    control:UpdateStepperStates()

    return control
end

-- Dropdown with the previous / next option buttons from the game's Settings panel.
-- `width` is the box itself; the buttons sit outside it, and the returned frame spans
-- all three, so anchoring its left edge lines up the left button.
-- generator(dropdown, rootDescription) builds the menu (see Blizzard_Menu); it is re-run
-- every time the menu opens and by :Refresh(). The buttons step through its radios,
-- submenus included.
-- Returns the frame, with :Refresh(), :SetEnabled(enabled) and .Dropdown.
function W.CreateDropdown(parent, width, generator)
    local control = CreateFrame("Frame", nil, parent, "SettingsDropdownWithButtonsTemplate")
    control:SetSize(width + DROPDOWN_STEPPER_PAD, 26)
    control.Dropdown:SetWidth(width)
    control.Dropdown:SetupMenu(generator)

    -- Re-reads the saved value, e.g. after it changed somewhere other than this dropdown
    function control:Refresh()
        self.Dropdown:GenerateMenu()
        self:UpdateSteppers()
    end

    function control:Enable() self:SetEnabled(true) end
    function control:Disable() self:SetEnabled(false) end

    function control:IsEnabled()
        return self.Dropdown:IsEnabled()
    end

    return control
end

-- Makes `description`'s list scroll when it has more than MENU_SCROLL_ROWS entries.
function W.LimitMenuHeight(description, count)
    if count > MENU_SCROLL_ROWS then
        description:SetScrollMode(MENU_SCROLL_ROWS * MENU_ROW_HEIGHT)
    end
end

-- Dropdown over a fixed list of choices.
-- options: list of { text = ..., value = ... }, or a function returning one (re-read
-- every time the menu opens). get() returns the saved value; set(value) stores a new one.
function W.CreateChoiceDropdown(parent, width, options, get, set)
    local function GetOptions()
        return type(options) == "function" and options() or options
    end

    local function IsSelected(value) return get() == value end
    local function SetSelected(value) set(value) end

    return W.CreateDropdown(parent, width, function(_, rootDescription)
        local list = GetOptions()
        for _, option in ipairs(list) do
            rootDescription:CreateRadio(option.text, IsSelected, SetSelected, option.value)
        end
        W.LimitMenuHeight(rootDescription, #list)
    end)
end

-- Adds a radio to a font menu, drawn in its own font. fontObject may be nil.
function W.CreateFontRadio(description, text, fontObject, isSelected, setSelected, data)
    local radio = description:CreateRadio(text, isSelected, setSelected, data)
    if fontObject then
        radio:AddInitializer(function(button)
            button.fontString:SetFontObject(fontObject)
        end)
    end
    return radio
end
