local addonName, addon = ...

local debugFrame = nil
local debugEditBox = nil
local msgBuffer = {}

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
    
    scrollFrame:SetScrollChild(debugEditBox)
    
    debugFrame:Hide()

    -- Flush buffer
    if #msgBuffer > 0 then
        for _, line in ipairs(msgBuffer) do
            debugEditBox:Insert(line)
        end
        msgBuffer = {}
    end
end

function addon:Log(...)
    local msg = string.format(...)
    local timeStamp = date("%H:%M:%S")
    local line = string.format("[%s] %s\n", timeStamp, msg)

    if debugFrame and debugEditBox then
        debugEditBox:Insert(line)
    else
        table.insert(msgBuffer, line)
    end
end

function addon:ShowDebug()
    if not debugFrame then
        self:CreateDebugFrame()
    end
    debugFrame:Show()
end

-- Global debug command
SLASH_TPDEBUG1 = "/tpdebug"
SlashCmdList["TPDEBUG"] = function()
    addon:ShowDebug()
end
