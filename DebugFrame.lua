local addonName, addon = ...

local debugFrame = nil
local debugEditBox = nil
local MAX_DEBUG_LINES = 400
local debugLines = {}

local LEVELS = {
    off = 0,
    error = 1,
    warn = 2,
    info = 3,
    trace = 4,
}

local function NormalizeLevel(level)
    local key = tostring(level or ""):lower()
    if key == "warning" then key = "warn" end
    if key == "on" then key = "info" end
    if key == "1" then key = "info" end
    if key == "0" then key = "off" end
    if LEVELS[key] then return key end
    return nil
end

local function GetCurrentLevel()
    local fromDb = addon and addon.db and addon.db.debugLevel
    local normalized = NormalizeLevel(fromDb)
    return normalized or "error"
end

local function AppendLine(line)
    debugLines[#debugLines + 1] = line
    if #debugLines > MAX_DEBUG_LINES then
        table.remove(debugLines, 1)
    end

    if debugFrame and debugEditBox then
        debugEditBox:SetText(table.concat(debugLines, "\n"))
        debugEditBox:SetCursorPosition(1000000)
    end
end

local function RenderBufferToFrame()
    if not (debugFrame and debugEditBox) then return end
    debugEditBox:SetText(table.concat(debugLines, "\n"))
    debugEditBox:SetCursorPosition(1000000)
end

function addon:ShouldLog(level)
    if not (self.db and self.db.debugEnabled) then
        return false
    end
    local normalized = NormalizeLevel(level) or "info"
    local current = GetCurrentLevel()
    return LEVELS[current] >= LEVELS[normalized]
end

function addon:LogAt(level, fmt, ...)
    local normalized = NormalizeLevel(level) or "info"
    if not self:ShouldLog(normalized) then return end

    local ok, msg = pcall(string.format, tostring(fmt or ""), ...)
    if not ok then
        msg = tostring(fmt)
    end

    local timeStamp = date("%H:%M:%S")
    local line = string.format("[%s] [%s] %s", timeStamp, string.upper(normalized), tostring(msg))
    AppendLine(line)
end

function addon:CreateDebugFrame()
    if debugFrame then return end
    
    debugFrame = CreateFrame("Frame", "TrackerPlusDebugFrame", UIParent, "BackdropTemplate")
    debugFrame:SetSize(600, 400)
    debugFrame:SetPoint("CENTER")
    debugFrame:SetFrameStrata("DIALOG")
    debugFrame:EnableMouse(true)
    debugFrame:SetMovable(true)
    debugFrame:RegisterForDrag("LeftButton")
    debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
    debugFrame:SetScript("OnDragStop", debugFrame.StopMovingOrSizing)
    
    debugFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    
    local title = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -15)
    title:SetText("TrackerPlus Debug")
    
    local close = CreateFrame("Button", nil, debugFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, debugFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -40, 20)
    
    debugEditBox = CreateFrame("EditBox", nil, scrollFrame)
    debugEditBox:SetMultiLine(true)
    debugEditBox:SetFontObject(ChatFontNormal)
    debugEditBox:SetWidth(540)
    debugEditBox:SetAutoFocus(false)
    debugEditBox:SetText("")
    
    scrollFrame:SetScrollChild(debugEditBox)
    
    debugFrame:Hide()

    RenderBufferToFrame()
end

function addon:Log(...)
    self:LogAt("info", ...)
end

function addon:ShowDebug()
    if not debugFrame then
        self:CreateDebugFrame()
    end
    RenderBufferToFrame()
    debugFrame:Show()
end

function addon:ClearDebug()
    wipe(debugLines)
    if debugFrame and debugEditBox then
        debugEditBox:SetText("")
    end
end

local function ParseToggleArg(msg, current)
    local arg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "on" or arg == "1" or arg == "true" then
        return true
    end
    if arg == "off" or arg == "0" or arg == "false" then
        return false
    end
    return not current
end

-- Global debug command
SLASH_TPDEBUG1 = "/tpdebug"
SlashCmdList["TPDEBUG"] = function(msg)
    if not addon.db then
        print("|cff00ff00TrackerPlus:|r Debug settings are not ready yet.")
        return
    end

    local enabled = ParseToggleArg(msg, addon.db.debugEnabled == true)
    addon.db.debugEnabled = enabled

    if addon.UpdateSectionDebugBoxes then
        addon:UpdateSectionDebugBoxes()
    end
    if addon.RequestUpdate then
        addon:RequestUpdate("full")
    end

    print("|cff00ff00TrackerPlus:|r Debugging " .. (enabled and "enabled" or "disabled") .. ".")
end

-- ============================================================================
-- Nameplates: debug window (/tp nameplates debug)
-- ============================================================================
---@diagnostic disable: undefined-global
do
    local _, TrackerPlus = ...
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
end
