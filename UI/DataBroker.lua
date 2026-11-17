---@diagnostic disable: undefined-global
local addonName, addon = ...

-------------------------------------------------------------------------------
-- Launcher button for Titan Panel and other LibDataBroker displays
--
-- A LibDataBroker "launcher": Titan Panel lists it under Interface (from
-- `category`), and clicking it shows or hides the tracker. Other LDB displays
-- (Bazooka, ChocolateBar, ElvUI's DataTexts, ...) pick it up as well.
--
-- LibDataBroker isn't bundled. Every display ships its own copy, so when none is
-- loaded there's nothing to put the button on and it's simply not created. It's
-- looked up at PLAYER_LOGIN, by which point every addon that loads at startup has.
-------------------------------------------------------------------------------

local TITLE = "Tracker|cff00ff00Plus|r"
local ICON = "Interface\\Icons\\INV_Misc_Map_01" -- the TOC's IconTexture
local HINT = "|cffffd100%s|r %s"

local function StatusText()
    local db = addon.db
    if not db then
        return "|cff808080Loading|r"
    elseif not db.enabled then
        return "|cff808080Off|r"
    elseif db.hidden then
        return "|cffff8040Hidden|r"
    end
    return "|cff40ff40Shown|r"
end

local function OnTooltipShow(tooltip)
    tooltip:AddDoubleLine(TITLE, StatusText())
    if addon.db and not addon.db.enabled then
        tooltip:AddLine("Using the game's own tracker", 0.7, 0.7, 0.7)
    elseif addon.db and addon:IsTrackerShown() then
        -- Shown, but an automatic rule can still be keeping it off screen.
        local reason = addon:GetAutoHideReason()
        if reason then
            tooltip:AddLine("Hidden while " .. reason, 1, 0.5, 0.25, true)
        end
    end
    tooltip:AddLine(" ")
    tooltip:AddLine(format(HINT, "Click", "to show or hide the tracker"), 1, 1, 1)
    tooltip:AddLine(format(HINT, "Shift-Click", "to open settings"), 1, 1, 1)
end

local function OnClick(button, mouseButton)
    -- Titan Panel opens its own plugin menu on right-click. Before Initialize has
    -- run (about a second after login) there's no tracker to toggle yet.
    if mouseButton ~= "LeftButton" or not addon.trackerFrame then return end

    if IsShiftKeyDown() then
        if addon.OpenSettings then addon.OpenSettings() end
        return
    end

    addon:ToggleTrackerShown()

    -- Keep the status line current while the pointer is still on the button.
    if GameTooltip:IsOwned(button) then
        GameTooltip:ClearLines()
        OnTooltipShow(GameTooltip)
        GameTooltip:Show()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB then return end

    LDB:NewDataObject(addonName, {
        type = "launcher",
        label = "TrackerPlus",
        icon = ICON,
        tocname = addonName,
        category = "Interface", -- Titan Panel's menu; it would otherwise go under General
        OnClick = OnClick,
        OnTooltipShow = OnTooltipShow,
    })
end)
