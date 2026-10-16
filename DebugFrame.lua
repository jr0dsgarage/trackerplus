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
    return NormalizeLevel(addon.db and addon.db.debugLevel) or "error"
end

-- Writes the buffer into the window. Only done while the window is open; ShowDebug
-- catches it up when it opens, so logging with the window closed costs no UI work.
local function RenderBufferToFrame()
    if not (debugFrame and debugFrame:IsShown()) then return end
    if #debugLines == 0 then
        debugEditBox:SetText(string.format(
            "No log entries yet. Only messages at or above the Debug Log Level (currently %s) are recorded.",
            GetCurrentLevel()))
        return
    end
    debugEditBox:SetText(table.concat(debugLines, "\n"))
    debugEditBox:SetCursorPosition(1000000)
end

local function AppendLine(line)
    debugLines[#debugLines + 1] = line
    if #debugLines > MAX_DEBUG_LINES then
        table.remove(debugLines, 1)
    end
    RenderBufferToFrame()
end

-- Callers whose log arguments are costly to build can check this first.
function addon:ShouldLog(level)
    if not (self.db and self.db.debugEnabled) then
        return false
    end
    return LEVELS[GetCurrentLevel()] >= LEVELS[NormalizeLevel(level) or "info"]
end

function addon:LogAt(level, fmt, ...)
    if not self:ShouldLog(level) then return end

    local ok, msg = pcall(string.format, tostring(fmt or ""), ...)
    if not ok then
        msg = tostring(fmt)
    end

    local timeStamp = date("%H:%M:%S")
    local line = string.format("[%s] [%s] %s", timeStamp, string.upper(NormalizeLevel(level) or "info"), tostring(msg))
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
end

function addon:Log(...)
    self:LogAt("info", ...)
end

function addon:ShowDebug()
    self:CreateDebugFrame()
    debugFrame:Show()
    RenderBufferToFrame()
end

function addon:ClearDebug()
    wipe(debugLines)
    RenderBufferToFrame()
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

    addon:UpdateSectionDebugBoxes()
    addon:RequestUpdate("full")

    print("|cff00ff00TrackerPlus:|r Debugging " .. (enabled and "enabled" or "disabled") .. ".")
end
