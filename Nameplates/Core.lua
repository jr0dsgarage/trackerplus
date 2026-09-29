-- Next Target Highlighter Addon
---@diagnostic disable: undefined-global, param-type-mismatch
local addonName, addon = ...

addon.frame = addon.frame or CreateFrame("Frame")
addon.pendingUpdate = addon.pendingUpdate or false

local sanitizeCommand = addon.SanitizeCommand

function addon:UpdateHighlight()
    local inInstance = IsInInstance()
    -- Read by the selection border hook: when inactive, Blizzard's native border is left alone.
    self.active = NextTargetDB.enabled and not inInstance

    if not self.active then
        self:ClearHighlights()
        if not inInstance and NextTargetDB.debugMode then
            self:UpdateDebugFrame({})
        end
        return
    end

    local results = self:CollectHighlights()
    if NextTargetDB.debugMode then
        self:UpdateDebugFrame(results)
    end
end

function addon:RequestUpdate()
    if self.pendingUpdate then
        return
    end

    if not C_Timer or not C_Timer.After then
        self:UpdateHighlight()
        return
    end

    self.pendingUpdate = true
    C_Timer.After(0.05, function()
        addon.pendingUpdate = false
        addon:UpdateHighlight()
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

    if NextTargetDB.debugMode then
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

addon.frame:SetScript("OnEvent", function(_, event, ...)
    local handler = eventHandlers[event]
    if handler then
        handler(addon, ...)
    end
end)

addon.frame:RegisterEvent("ADDON_LOADED")
addon.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
addon.frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
addon.frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
addon.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
addon.frame:RegisterEvent("QUEST_LOG_UPDATE")
addon.frame:RegisterEvent("QUEST_ACCEPTED")
addon.frame:RegisterEvent("QUEST_REMOVED")
addon.frame:RegisterEvent("QUEST_TURNED_IN")
addon.frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
addon.frame:RegisterEvent("TASK_PROGRESS_UPDATE")
addon.frame:RegisterEvent("QUESTLINE_UPDATE")

SLASH_NEXT1 = "/next"

SlashCmdList.NEXT = function(msg)
    -- Wrap in pcall to prevent errors from breaking slash command system
    local success, err = pcall(function()
        msg = sanitizeCommand(msg or "")
        msg = msg:lower()

        if msg == "" then
            addon:OpenSettings()
            print("|cFF00FF00[next]|r commands:")
            print("  |cFFFFFF00/next config|r - open settings")
            print("  |cFFFFFF00/next toggle|r - enable or disable the addon")
            return
        end

        if msg == "config" or msg == "options" or msg == "settings" then
            addon:OpenSettings()
            return
        end

        if msg == "toggle" then
            NextTargetDB.enabled = not NextTargetDB.enabled
            print(string.format("|cFF00FF00[next]|r addon %s", NextTargetDB.enabled and "enabled" or "disabled"))
            addon:RequestUpdate()
            return
        end

        if msg == "debug" then
            NextTargetDB.debugMode = not NextTargetDB.debugMode
            if NextTargetDB.debugMode then
                addon:ShowDebugFrame()
            else
                addon:HideDebugFrame()
            end
            addon:RequestUpdate()
            return
        end

        print("|cFF00FF00[next]|r commands:")
        print("  |cFFFFFF00/next config|r - open settings")
        print("  |cFFFFFF00/next toggle|r - enable or disable the addon")
    end)
    
    if not success then
        print("|cFFFF0000[next]|r Error processing command: " .. tostring(err))
    end
end
