---@diagnostic disable: undefined-global
local addonName, addon = ...

local floor = math.floor

-- Diagnostic command to inspect nameplate textures
SLASH_NEXTTEXTURE1 = "/nexttexture"
SlashCmdList["NEXTTEXTURE"] = function()
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if not plate then
        print("No target nameplate found")
        return
    end
    
    print("=== Nameplate Texture Inspection ===")
    local function inspectFrame(frame, name, depth)
        depth = depth or 0
        if depth > 3 then return end
        local indent = string.rep("  ", depth)
        
        for i = 1, frame:GetNumRegions() do
            local region = select(i, frame:GetRegions())
            if region and region:IsObjectType("Texture") then
                local texture = region:GetTexture()
                local atlas = (region.GetAtlas and region:GetAtlas()) or nil
                if texture or atlas then
                    print(indent .. name .. " Texture " .. i .. ":")
                    if atlas then
                        print(indent .. "  Atlas: " .. tostring(atlas))
                    end
                    if texture then
                        print(indent .. "  Path: " .. tostring(texture))
                    end
                end
            end
        end
        
        -- Check children
        for i = 1, frame:GetNumChildren() do
            local child = select(i, frame:GetChildren())
            if child then
                inspectFrame(child, name .. ".child" .. i, depth + 1)
            end
        end
    end
    
    inspectFrame(plate, "Nameplate", 0)
end

-- Diagnostic command to inspect mouseover frame textures
SLASH_NEXTINSPECT1 = "/nextinspect"
SlashCmdList["NEXTINSPECT"] = function()
    local frame = GetMouseFoci and GetMouseFoci()[1] or nil
    if not frame then
        print("No frame under mouse")
        return
    end
    
    print("=== Frame Texture Inspection ===")
    print("Frame name: " .. (frame:GetName() or "Anonymous"))
    print("Frame type: " .. (frame:GetObjectType() or "Unknown"))
    
    local function inspectFrame(f, name, depth)
        depth = depth or 0
        if depth > 4 then return end
        local indent = string.rep("  ", depth)
        
        -- Check textures
        for i = 1, f:GetNumRegions() do
            local region = select(i, f:GetRegions())
            if region and region:IsObjectType("Texture") then
                local texture = region:GetTexture()
                local atlas = (region.GetAtlas and region:GetAtlas()) or nil
                if texture or atlas then
                    print(indent .. name .. " Texture " .. i .. ":")
                    if atlas then
                        print(indent .. "  Atlas: " .. tostring(atlas))
                    end
                    if texture then
                        print(indent .. "  Path: " .. tostring(texture))
                    end
                    -- Check if it's animating
                    if region.GetAnimationGroups then
                        local numAnims = (region.GetNumAnimationGroups and region:GetNumAnimationGroups()) or 0
                        if numAnims > 0 then
                            print(indent .. "  Animations: " .. numAnims .. " groups")
                        end
                    end
                end
            end
        end
        
        -- Check children
        for i = 1, f:GetNumChildren() do
            local child = select(i, f:GetChildren())
            if child then
                inspectFrame(child, name .. ".child" .. i, depth + 1)
            end
        end
    end
    
    inspectFrame(frame, "Frame", 0)
    
    -- Also check parent for context
    local parent = frame:GetParent()
    if parent then
        print("\n=== Parent Frame ===")
        print("Parent name: " .. (parent:GetName() or "Anonymous"))
        inspectFrame(parent, "Parent", 0)
    end
end

-- Diagnostic command to inspect nameplate structure
SLASH_NEXTSTRUCTURE1 = "/nextstructure"
SlashCmdList["NEXTSTRUCTURE"] = function()
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if not plate then
        print("No target nameplate found")
        return
    end
    
    print("=== Nameplate Structure Analysis ===")
    
    local function printValue(name, value, indent)
        indent = indent or ""
        local valueType = type(value)
        if valueType == "table" or valueType == "userdata" then
            local objType = (value.GetObjectType and pcall(value.GetObjectType, value)) and value:GetObjectType() or "table"
            print(indent .. name .. " = <" .. objType .. ">")
        else
            print(indent .. name .. " = " .. tostring(value))
        end
    end
    
    local function inspectStructure(obj, name, depth, visited)
        depth = depth or 0
        visited = visited or {}
        
        if depth > 3 then return end
        if visited[obj] then return end
        visited[obj] = true
        
        local indent = string.rep("  ", depth)
        
        -- Try to get common properties
        local properties = {
            "unit", "namePlateUnitToken", "displayedUnit",
            "healthBar", "Health", "HealthBar",
            "UnitFrame", "healthBars", "HealthBarsContainer"
        }
        
        for _, prop in ipairs(properties) do
            if type(obj) == "table" or (type(obj) == "userdata" and obj[prop] ~= nil) then
                local success, value = pcall(function() return obj[prop] end)
                if success and value ~= nil then
                    printValue(prop, value, indent)
                    if type(value) == "table" or type(value) == "userdata" then
                        inspectStructure(value, prop, depth + 1, visited)
                    end
                end
            end
        end
    end
    
    inspectStructure(plate, "Nameplate", 0)
    
    -- Try to resolve healthbar
    print("\n=== Healthbar Resolution Test ===")
    if plate.UnitFrame and plate.UnitFrame.healthBar then
        print("✓ Found: plate.UnitFrame.healthBar")
    end
    if plate.UnitFrame and plate.UnitFrame.healthBars and plate.UnitFrame.healthBars.healthBar then
        print("✓ Found: plate.UnitFrame.healthBars.healthBar")
    end
    if plate.UnitFrame and plate.UnitFrame.HealthBarsContainer and plate.UnitFrame.HealthBarsContainer.healthBar then
        print("✓ Found: plate.UnitFrame.HealthBarsContainer.healthBar")
    end
    if plate.healthBar then
        print("✓ Found: plate.healthBar")
    end
    if plate.UnitFrame and plate.UnitFrame.Health then
        print("✓ Found: plate.UnitFrame.Health")
    end
    if plate.UnitFrame and plate.UnitFrame.HealthBar then
        print("✓ Found: plate.UnitFrame.HealthBar")
    end
end

-- Diagnostic command to find quest item icon (SoftTargetFrame)
SLASH_NEXTSOFTTARGET1 = "/nextsofttarget"
SlashCmdList["NEXTSOFTTARGET"] = function()
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if not plate then
        print("No target nameplate found")
        return
    end
    
    print("=== Quest Item Icon (SoftTargetFrame) Search ===")
    
    local function searchForSoftTarget(obj, path, depth, visited)
        depth = depth or 0
        visited = visited or {}
        
        if depth > 5 then return end
        if visited[obj] then return end
        visited[obj] = true
        
        -- Check common soft target / quest item names
        local softTargetNames = {
            "SoftTargetFrame", "softTargetFrame", "QuestItemIcon",
            "questItemIcon", "QuestIcon", "questIcon"
        }
        
        for _, name in ipairs(softTargetNames) do
            if type(obj) == "table" or type(obj) == "userdata" then
                local success, value = pcall(function() return obj[name] end)
                if success and value ~= nil then
                    local isFrame = pcall(function() return value:GetObjectType() end)
                    if isFrame then
                        local shown = value.IsShown and value:IsShown()
                        print(string.format("✓ Found: %s.%s <%s> Visible: %s", path, name, value:GetObjectType(), tostring(shown)))
                        
                        -- Check for Icon child
                        if value.Icon then
                            local iconShown = value.Icon.IsShown and value.Icon:IsShown()
                            print(string.format("  Has Icon: Visible: %s", tostring(iconShown)))
                        end
                    else
                        print(string.format("  Found: %s.%s = %s", path, name, tostring(value)))
                    end
                end
            end
        end
        
        -- Recursively search children
        if type(obj) == "table" or type(obj) == "userdata" then
            local success, numChildren = pcall(function() return obj:GetNumChildren() end)
            if success and numChildren then
                for i = 1, numChildren do
                    local child = select(i, obj:GetChildren())
                    if child then
                        local childName = child.GetName and child:GetName() or ("child" .. i)
                        searchForSoftTarget(child, path .. "." .. childName, depth + 1, visited)
                    end
                end
            end
        end
    end
    
    searchForSoftTarget(plate, "plate", 0)
    if plate.UnitFrame then
        searchForSoftTarget(plate.UnitFrame, "plate.UnitFrame", 0)
    end
end

local function clamp01(value)
    if not value then
        return 0
    end
    if value <= 0 then
        return 0
    end
    if value >= 1 then
        return 1
    end
    return value
end

local function colorTableToHex(color)
    if not color then
        return "FF00FF00"
    end

    local a = floor(clamp01(color.a or 1) * 255 + 0.5)
    local r = floor(clamp01(color.r or 0) * 255 + 0.5)
    local g = floor(clamp01(color.g or 0) * 255 + 0.5)
    local b = floor(clamp01(color.b or 0) * 255 + 0.5)

    return string.format("%02X%02X%02X%02X", a, r, g, b)
end

local function resolveHighlightReason(info)
    if info.reason and info.reason ~= "" then
        return info.reason
    end
    return nil
end

local function resolveHighlightColor(info)
    if info.usesTargetStyle and NextTargetDB.currentTargetColor then
        return NextTargetDB.currentTargetColor
    end

    local reason = resolveHighlightReason(info)
    if reason == "Has Quest Item" and NextTargetDB.questItemColor then
        return NextTargetDB.questItemColor
    end
    if reason == "World Quest" and NextTargetDB.worldQuestColor then
        return NextTargetDB.worldQuestColor
    end
    if reason == "Bonus Objective" and NextTargetDB.bonusObjectiveColor then
        return NextTargetDB.bonusObjectiveColor
    end
    if reason == "Quest Objective" and NextTargetDB.questObjectiveColor then
        return NextTargetDB.questObjectiveColor
    end

    if info.highlightStyle and info.highlightStyle.color then
        return info.highlightStyle.color
    end

    if NextTargetDB.currentTargetColor then
        return NextTargetDB.currentTargetColor
    end

    return { r = 0, g = 1, b = 0, a = 1 }
end

local function buildOnText(info)
    local hex = colorTableToHex(resolveHighlightColor(info))
    return string.format("|c%sON|r", hex)
end

local function ensureDebugFrame()
    if addon.debugFrame then
        return addon.debugFrame
    end

    local frame = CreateFrame("Frame", addonName .. "DebugFrame", UIParent, "BackdropTemplate")
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
        NextTargetDB.debugFramePosition = { point, relativeTo and relativeTo:GetName(), relativePoint, xOfs, yOfs }
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("next debug")

    local config = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    config:SetSize(80, 22)
    config:SetPoint("TOPRIGHT", -126, -12)
    config:SetText("Config")
    config:SetScript("OnClick", function()
        if addon.OpenSettings then
            addon:OpenSettings()
        end
    end)

    local reload = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reload:SetSize(80, 22)
    reload:SetPoint("TOPRIGHT", -38, -12)
    reload:SetText("Reload UI")
    reload:SetScript("OnClick", ReloadUI)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function()
        NextTargetDB.debugMode = false
        addon:HideDebugFrame()
        print("|cFF00FF00[next]|r debug mode disabled")
    end)

    local scroll = CreateFrame("ScrollFrame", addonName .. "DebugScroll", frame, "UIPanelScrollFrameTemplate")
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
        addon:UpdateDebugFrameLayout()
    end)
    resizeHandle:SetScript("OnEnter", function()
        handleTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    end)
    resizeHandle:SetScript("OnLeave", function()
        handleTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    end)

    if frame.SetResizeBounds then
        frame:SetResizeBounds(520, 240, 900, 600)
    else
        if frame.SetMinResize then
            frame:SetMinResize(520, 240)
        end
        if frame.SetMaxResize then
            frame:SetMaxResize(900, 600)
        end
    end

    frame:SetScript("OnSizeChanged", function()
        addon:UpdateDebugFrameLayout()
    end)

    frame.resizeHandle = resizeHandle
    addon.debugFrame = frame
    return frame
end

function addon:ShowDebugFrame()
    local frame = ensureDebugFrame()
    frame:Show()

    local position = NextTargetDB.debugFramePosition
    if position and position[1] then
        frame:ClearAllPoints()
        local relative = position[2] and _G[position[2]] or UIParent
        frame:SetPoint(position[1], relative, position[3], position[4], position[5])
    else
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function addon:HideDebugFrame()
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

function addon:UpdateDebugFrame(results)
    if not NextTargetDB.debugMode then
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

    addon:UpdateDebugFrameLayout()
end

function addon:UpdateDebugFrameLayout()
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
