-- Next Target Highlighter Addon
---@diagnostic disable: undefined-global, param-type-mismatch
local addonName, TrackerPlus = ...
TrackerPlus.Nameplates = TrackerPlus.Nameplates or {}
local Nameplates = TrackerPlus.Nameplates

Nameplates.frame = Nameplates.frame or CreateFrame("Frame")
Nameplates.pendingUpdate = Nameplates.pendingUpdate or false

local sanitizeCommand = Nameplates.SanitizeCommand

function Nameplates:UpdateHighlight()
    local inInstance = IsInInstance()
    -- Read by the selection border hook: when inactive, Blizzard's native border is left alone.
    self.active = Nameplates.db.enabled and not inInstance

    if not self.active then
        self:ClearHighlights()
        if not inInstance and Nameplates.db.debugMode then
            self:UpdateDebugFrame({})
        end
        return
    end

    local results = self:CollectHighlights()
    if Nameplates.db.debugMode then
        self:UpdateDebugFrame(results)
    end
end

function Nameplates:RequestUpdate()
    if self.pendingUpdate then
        return
    end

    if not C_Timer or not C_Timer.After then
        self:UpdateHighlight()
        return
    end

    self.pendingUpdate = true
    C_Timer.After(0.05, function()
        Nameplates.pendingUpdate = false
        Nameplates:UpdateHighlight()
    end)
end

local eventHandlers = {}

local function handleQuestDataChanged(self)
    if self.ResetCaches then
        self:ResetCaches()
    end
    self:RequestUpdate()
end

eventHandlers.ADDON_LOADED = function(self, loadedAddon)
    if loadedAddon ~= addonName then
        return
    end

    self:InitializeDB()

    self.frame:UnregisterEvent("ADDON_LOADED")

    if Nameplates.db.debugMode then
        self:ShowDebugFrame()
    end

    print("|cFF00FF00[next]|r loaded. Type |cFFFFFF00/next help|r for options.")

    self:RequestUpdate()
end

eventHandlers.PLAYER_TARGET_CHANGED = function(self)
    self:RequestUpdate()
end

eventHandlers.NAME_PLATE_UNIT_ADDED = function(self)
    self:RequestUpdate()
end

eventHandlers.NAME_PLATE_UNIT_REMOVED = function(self, unitToken)
    self:ReleaseNamePlateUnit(unitToken)
    self:RequestUpdate()
end

eventHandlers.PLAYER_ENTERING_WORLD = function(self)
    self:RequestUpdate()
end

eventHandlers.QUEST_LOG_UPDATE = handleQuestDataChanged
eventHandlers.QUEST_ACCEPTED = handleQuestDataChanged
eventHandlers.QUEST_REMOVED = handleQuestDataChanged
eventHandlers.QUEST_TURNED_IN = handleQuestDataChanged
eventHandlers.QUEST_WATCH_LIST_CHANGED = handleQuestDataChanged
eventHandlers.TASK_PROGRESS_UPDATE = handleQuestDataChanged
eventHandlers.QUESTLINE_UPDATE = handleQuestDataChanged

Nameplates.frame:SetScript("OnEvent", function(_, event, ...)
    local handler = eventHandlers[event]
    if handler then
        handler(Nameplates, ...)
    end
end)

Nameplates.frame:RegisterEvent("ADDON_LOADED")
Nameplates.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
Nameplates.frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
Nameplates.frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
Nameplates.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
Nameplates.frame:RegisterEvent("QUEST_LOG_UPDATE")
Nameplates.frame:RegisterEvent("QUEST_ACCEPTED")
Nameplates.frame:RegisterEvent("QUEST_REMOVED")
Nameplates.frame:RegisterEvent("QUEST_TURNED_IN")
Nameplates.frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
Nameplates.frame:RegisterEvent("TASK_PROGRESS_UPDATE")
Nameplates.frame:RegisterEvent("QUESTLINE_UPDATE")

SLASH_NEXT1 = "/next"

SlashCmdList.NEXT = function(msg)
    -- Wrap in pcall to prevent errors from breaking slash command system
    local success, err = pcall(function()
        msg = sanitizeCommand(msg or "")
        msg = msg:lower()

        if msg == "" then
            Nameplates:OpenSettings()
            print("|cFF00FF00[next]|r commands:")
            print("  |cFFFFFF00/next config|r - open settings")
            print("  |cFFFFFF00/next toggle|r - enable or disable the Nameplates")
            return
        end

        if msg == "config" or msg == "options" or msg == "settings" then
            Nameplates:OpenSettings()
            return
        end

        if msg == "toggle" then
            Nameplates.db.enabled = not Nameplates.db.enabled
            print(string.format("|cFF00FF00[next]|r Nameplates %s", Nameplates.db.enabled and "enabled" or "disabled"))
            Nameplates:RequestUpdate()
            return
        end

        if msg == "debug" then
            Nameplates.db.debugMode = not Nameplates.db.debugMode
            if Nameplates.db.debugMode then
                Nameplates:ShowDebugFrame()
            else
                Nameplates:HideDebugFrame()
            end
            Nameplates:RequestUpdate()
            return
        end

        print("|cFF00FF00[next]|r commands:")
        print("  |cFFFFFF00/next config|r - open settings")
        print("  |cFFFFFF00/next toggle|r - enable or disable the Nameplates")
    end)
    
    if not success then
        print("|cFFFF0000[next]|r Error processing command: " .. tostring(err))
    end
end
