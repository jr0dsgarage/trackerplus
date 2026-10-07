---@diagnostic disable: undefined-global
local _, TrackerPlus = ...
TrackerPlus.Nameplates = TrackerPlus.Nameplates or {}
local Nameplates = TrackerPlus.Nameplates

-- "ON" in the color the unit is highlighted with.
local function buildOnText(info)
    local color = info.usesTargetStyle and Nameplates.db.currentTargetColor or info.highlightStyle.color
    return CreateColor(color.r, color.g, color.b, color.a):WrapTextInColorCode("ON")
end

local function ensureDebugFrame()
    if Nameplates.debugFrame then
        return Nameplates.debugFrame
    end

    local frame = CreateFrame("Frame", "TrackerPlusNameplatesDebugFrame", UIParent, "BackdropTemplate")
    frame:SetSize(720, 300)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
        Nameplates.db.debugFramePosition = { point, relativeTo and relativeTo:GetName(), relativePoint, xOfs, yOfs }
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Nameplates Debug")

    local config = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    config:SetSize(80, 22)
    config:SetPoint("TOPRIGHT", -126, -12)
    config:SetText("Config")
    config:SetScript("OnClick", function()
        Nameplates:OpenSettings()
    end)

    local reload = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reload:SetSize(80, 22)
    reload:SetPoint("TOPRIGHT", -38, -12)
    reload:SetText("Reload UI")
    reload:SetScript("OnClick", ReloadUI)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function()
        Nameplates.db.debugMode = false
        Nameplates:HideDebugFrame()
        TrackerPlus.Print("Nameplates debug mode disabled.")
    end)

    local scroll = CreateFrame("ScrollFrame", "TrackerPlusNameplatesDebugScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -8)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 32)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetWidth(620)
    editBox:SetHeight(400)
    editBox:SetHyperlinksEnabled(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
    editBox:SetScript("OnEnterPressed", editBox.ClearFocus)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
    end)
    scroll:SetScrollChild(editBox)

    frame.editBox = editBox
    frame.scroll = scroll

    local resizeHandle = CreateFrame("Frame", nil, frame)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)

    local handleTexture = resizeHandle:CreateTexture(nil, "OVERLAY")
    handleTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    handleTexture:SetAllPoints(resizeHandle)

    resizeHandle:EnableMouse(true)
    resizeHandle:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        Nameplates:UpdateDebugFrameLayout()
    end)
    resizeHandle:SetScript("OnEnter", function()
        handleTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    end)
    resizeHandle:SetScript("OnLeave", function()
        handleTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    end)

    frame:SetResizeBounds(520, 240, 900, 600)

    frame:SetScript("OnSizeChanged", function()
        Nameplates:UpdateDebugFrameLayout()
    end)

    frame.resizeHandle = resizeHandle
    Nameplates.debugFrame = frame
    return frame
end

function Nameplates:ShowDebugFrame()
    local frame = ensureDebugFrame()
    frame:Show()

    local position = Nameplates.db.debugFramePosition
    if position and position[1] then
        frame:ClearAllPoints()
        local relative = position[2] and _G[position[2]] or UIParent
        frame:SetPoint(position[1], relative, position[3], position[4], position[5])
    else
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function Nameplates:HideDebugFrame()
    if self.debugFrame then
        self.debugFrame:Hide()
    end
end

local function questLabelFor(info)
    if info.questName and info.questName ~= "" then
        return info.questName
    end
    if info.isWorldQuest then
        return "World Quest"
    end
    if info.hasQuestObjectiveMatch or info.hasTooltipObjective then
        return "Quest Objective"
    end
    if info.hasSoftTarget then
        return "Quest Item"
    end
    return "n/a"
end

function Nameplates:UpdateDebugFrame(results)
    if not Nameplates.db.debugMode then
        self:HideDebugFrame()
        return
    end

    local frame = ensureDebugFrame()
    if not frame:IsShown() then
        self:ShowDebugFrame()
    end

    local lines = {}
    local targetName = UnitName("target") or "none"
    lines[#lines + 1] = "Target: " .. targetName
    lines[#lines + 1] = "Tracked units: " .. tostring(#results)

    local totalNameplates, hostileNameplates = 0, 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            totalNameplates = totalNameplates + 1
            local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.displayedUnit)
            if token and UnitExists(token) then
                local reaction = UnitReaction and UnitReaction(token, "player")
                if not reaction or reaction <= 4 then
                    hostileNameplates = hostileNameplates + 1
                end
            end
        end
    end

    local highlightedCount, filteredCount = 0, 0
    for _, info in ipairs(results) do
        if info.highlighted then
            highlightedCount = highlightedCount + 1
        elseif info.reason or info.note or info.hasTooltipObjective or info.hasCompletedObjective then
            filteredCount = filteredCount + 1
        end
    end

    if filteredCount > 0 then
        lines[#lines + 1] = "Filtered units: " .. filteredCount
    end
    lines[#lines + 1] = ""

    -- Calculate max visible based on frame height
    -- Each entry uses ~4 lines (name, highlight, optional item/boss, optional tooltip)
    -- Reserve ~4 lines for header, assume ~16px per line
    local frameHeight = frame:GetHeight() or 300
    local headerLines = 4
    local linesPerEntry = 4
    local lineHeight = 16
    local maxVisibleEntries = math.max(3, math.floor((frameHeight - (headerLines * lineHeight)) / (linesPerEntry * lineHeight)))

    for index, info in ipairs(results) do
        if index > maxVisibleEntries then
            lines[#lines + 1] = "... (" .. (#results - maxVisibleEntries) .. " more)"
            break
        end

        local summary = string.format("%d) %s", index, info.name or "Unknown")
        lines[#lines + 1] = summary

        local highlightExplanation
        if info.highlighted then
            local reason = info.reason or "Active highlight"
            if info.usesTargetStyle then
                reason = string.format("%s (current target style)", reason)
            elseif info.isActiveQuest then
                reason = string.format("%s (active quest style)", reason)
            end
            local highlightOnText = buildOnText(info)
            highlightExplanation = string.format(
                "    Highlight: %s - %s - Quest: %s",
                highlightOnText,
                reason,
                questLabelFor(info)
            )
        else
            local explanation
            if info.suppressedReason then
                explanation = string.format("%s highlight disabled in settings", info.suppressedReason)
            elseif info.note then
                explanation = info.note
            elseif info.reason then
                explanation = string.format("Matches %s but filtered", info.reason)
            elseif info.hasCompletedObjective then
                explanation = "Quest objective already complete"
            elseif info.hasTooltipObjective then
                explanation = "Tooltip contains quest objective text"
            else
                explanation = "No highlight conditions met"
            end
            highlightExplanation = string.format(
                "    Highlight: |cFFFF5555OFF|r - %s - Quest: %s",
                explanation,
                questLabelFor(info)
            )
        end

        lines[#lines + 1] = highlightExplanation

    local hasQuestMeta = (info.questName and info.questName ~= "") or info.questID or info.questType or info.questMatchSource or info.hasTooltipObjective
        if hasQuestMeta then
            local questBits = {}
            questBits[#questBits + 1] = string.format("ID: %s", info.questID or "n/a")
            questBits[#questBits + 1] = string.format("Type: %s", info.questType or "unknown")
            questBits[#questBits + 1] = string.format("Src: %s", info.questMatchSource or "none")
            if info.hasTooltipObjective ~= nil then
                questBits[#questBits + 1] = string.format("Tooltip Objective: %s", info.hasTooltipObjective and "yes" or "no")
            end
            local questName = (info.questName and info.questName ~= "") and info.questName or "<unknown>"
            lines[#lines + 1] = string.format("    Quest Info: %s (%s)", questName, table.concat(questBits, "; "))
        end

        if info.hasSoftTarget then
            lines[#lines + 1] = "    Has quest item icon"
        end

        if info.isQuestBoss then
            lines[#lines + 1] = "    Quest boss"
        end

        if info.tooltipLines and #info.tooltipLines > 0 then
            lines[#lines + 1] = "    " .. table.concat(info.tooltipLines, " / ")
        end
    end

    local editBox = frame.editBox
    if editBox then
        editBox:SetText(table.concat(lines, "\n"))
        editBox:SetCursorPosition(0)
    end

    Nameplates:UpdateDebugFrameLayout()
end

function Nameplates:UpdateDebugFrameLayout()
    if not self.debugFrame then
        return
    end

    local frame = self.debugFrame
    local editBox = frame.editBox
    local scroll = frame.scroll
    if not editBox or not scroll then
        return
    end

    local width = math.max(360, frame:GetWidth() - 100)
    local height = math.max(240, frame:GetHeight() - 120)

    editBox:SetWidth(width)
    editBox:SetHeight(height)
end
