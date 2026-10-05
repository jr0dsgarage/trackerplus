---@diagnostic disable: undefined-global
local _, addon = ...

-- The tracker's title bar: title, FollowTheArrow/lock/settings buttons and minimize/maximize.

------------------------------------------------------------------------------
-- FollowTheArrow availability
--
-- The header's arrow toggle only makes sense when that addon is actually there,
-- so it stays hidden otherwise rather than offering a control that does nothing.
------------------------------------------------------------------------------

local FTA_ADDON_NAME = "FollowTheArrow"

function addon:IsFollowTheArrowAvailable()
    -- Deliberately keyed on "loaded" rather than merely installed: a disabled
    -- addon shouldn't get a toggle either.
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded then
        local ok, loaded = pcall(isLoaded, FTA_ADDON_NAME)
        if ok and loaded then
            return true
        end
    end

    -- Fallback in case it ships under a different folder name: the globals
    -- FollowTheArrow exposes once it has loaded.
    return (FollowTheArrowAPI ~= nil) or (FTACharDB ~= nil)
end

function addon:UpdateFTAToggleVisibility()
    if not (addon.trackerFrame and addon.trackerFrame.ftaToggleBtn) then return end

    if self.db.minimized or not self:IsFollowTheArrowAvailable() then
        addon.trackerFrame.ftaToggleBtn:Hide()
        return
    end

    addon.trackerFrame.ftaToggleBtn:Show()
    if addon.trackerFrame.ftaToggleBtn.UpdateColor then
        addon.trackerFrame.ftaToggleBtn.UpdateColor()
    end
end

-- Builds the header chrome on the tracker frame. Called once from CreateTrackerFrame.
function addon:CreateTrackerHeader(trackerFrame)
    -- Main Header Background (Behind Title/Settings)
    trackerFrame.headerBg = trackerFrame:CreateTexture(nil, "BACKGROUND")
    trackerFrame.headerBg:SetPoint("TOPLEFT", 0, -addon.HEADER_TOP_INSET)
    trackerFrame.headerBg:SetPoint("TOPRIGHT", 0, -addon.HEADER_TOP_INSET)
    trackerFrame.headerBg:SetHeight(24) -- Standard header height

    -- Title Header (Left aligned)
    trackerFrame.title = trackerFrame:CreateFontString(nil, "OVERLAY")
    trackerFrame.title:SetPoint("LEFT", trackerFrame.headerBg, "LEFT", 8, 0)
    local titleFont = self.db.headerFontFace or "Fonts\\FRIZQT__.TTF"
    local titleSize = self.db.headerFontSize or 14
    trackerFrame.title:SetFont(titleFont, titleSize, self.db.headerFontOutline)
    trackerFrame.title:SetTextColor(
        self.db.headerColor.r,
        self.db.headerColor.g,
        self.db.headerColor.b,
        self.db.headerColor.a
    )
    trackerFrame.title:SetText("Tracker Plus")

    -- FTA Toggle Button (arrow icon, to the left of the auto-minimize button)
    trackerFrame.ftaToggleBtn = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.ftaToggleBtn:SetSize(16, 16)
    trackerFrame.ftaToggleBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -94, 0)
    local ftaArrowTex = trackerFrame.ftaToggleBtn:CreateTexture(nil, "ARTWORK")
    ftaArrowTex:SetAllPoints()
    ftaArrowTex:SetTexture("Interface\\Minimap\\MinimapArrow")
    trackerFrame.ftaToggleBtn._arrowTex = ftaArrowTex
    local function UpdateFTAToggleColor()
        if addon.db and addon.db.includeFTAQuests then
            ftaArrowTex:SetVertexColor(1, 0.82, 0, 1)   -- gold when enabled
        else
            ftaArrowTex:SetVertexColor(0.5, 0.5, 0.5, 1) -- grey when disabled
        end
    end
    trackerFrame.ftaToggleBtn.UpdateColor = UpdateFTAToggleColor
    UpdateFTAToggleColor()
    -- Hidden unless FollowTheArrow is actually loaded.
    self:UpdateFTAToggleVisibility()
    trackerFrame.ftaToggleBtn:SetScript("OnClick", function()
        addon.db.includeFTAQuests = not addon.db.includeFTAQuests
        UpdateFTAToggleColor()
        addon:RequestUpdate()
    end)
    trackerFrame.ftaToggleBtn:SetScript("OnEnter", function(self)
        local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
        tooltip:SetText(addon.db.includeFTAQuests and "Disable Follow the Arrow" or "Enable Follow the Arrow")
        tooltip:Show()
    end)
    trackerFrame.ftaToggleBtn:SetScript("OnLeave", function()
        addon:HideSharedTooltip()
    end)

    -- Auto-minimize Toggle Button ("A", to the left of the lock button). Gold when
    -- on, grey when off -- including when a manual header toggle switched it off.
    trackerFrame.autoMinBtn = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.autoMinBtn:SetSize(16, 16)
    trackerFrame.autoMinBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -74, 0)
    local autoMinText = trackerFrame.autoMinBtn:CreateFontString(nil, "ARTWORK")
    autoMinText:SetPoint("CENTER", 0, 0)
    autoMinText:SetFont(self.db.headerFontFace or "Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    autoMinText:SetText("A")
    trackerFrame.autoMinBtn._text = autoMinText
    trackerFrame.autoMinBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    local function UpdateAutoMinColor()
        if addon.db and addon.db.autoMinimizeHeaders then
            autoMinText:SetTextColor(1, 0.82, 0, 1)   -- gold when enabled
        else
            autoMinText:SetTextColor(0.5, 0.5, 0.5, 1) -- grey when disabled
        end
    end
    trackerFrame.autoMinBtn.UpdateColor = UpdateAutoMinColor
    UpdateAutoMinColor()
    trackerFrame.autoMinBtn:SetScript("OnClick", function(self)
        addon:SetAutoMinimize(not addon.db.autoMinimizeHeaders)
        if self:IsMouseOver() then
            self:GetScript("OnEnter")(self)
        end
    end)
    trackerFrame.autoMinBtn:SetScript("OnEnter", function(self)
        local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
        tooltip:SetText(addon.db.autoMinimizeHeaders and "Auto-minimize Zones: On" or "Auto-minimize Zones: Off")
        tooltip:AddLine("Keeps only your current zone and any quest area you're standing in expanded. Toggling a zone header by hand turns this off.", 1, 1, 1, true)
        tooltip:Show()
    end)
    trackerFrame.autoMinBtn:SetScript("OnLeave", function()
        addon:HideSharedTooltip()
    end)

    -- Lock Toggle Button (padlock icon, to the left of the settings button).
    -- Gold when locked, grey when unlocked. The tint is applied by
    -- UpdateTrackerLock so it also follows /tp lock, /tp unlock and the Lock Panel
    -- checkbox.
    trackerFrame.lockBtn = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.lockBtn:SetSize(16, 16)
    trackerFrame.lockBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -54, 0)
    local lockTex = trackerFrame.lockBtn:CreateTexture(nil, "ARTWORK")
    lockTex:SetAllPoints()
    lockTex:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
    trackerFrame.lockBtn._lockTex = lockTex
    trackerFrame.lockBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    trackerFrame.lockBtn:SetScript("OnClick", function(self)
        addon:SetSetting("locked", not addon.db.locked)
        addon:UpdateTrackerLock()
        if self:IsMouseOver() then
            self:GetScript("OnEnter")(self)
        end
    end)
    trackerFrame.lockBtn:SetScript("OnEnter", function(self)
        local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
        tooltip:SetText(addon.db.locked and "Unlock Panel" or "Lock Panel")
        tooltip:Show()
    end)
    trackerFrame.lockBtn:SetScript("OnLeave", function()
        addon:HideSharedTooltip()
    end)

    -- Settings Button (Gear icon)
    trackerFrame.settingsParam = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.settingsParam:SetSize(16, 16)
    -- Center vertically relative to header (-34 ensures it sits to left of minmax button)
    trackerFrame.settingsParam:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -34, 0)
    trackerFrame.settingsParam:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    trackerFrame.settingsParam:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    trackerFrame.settingsParam:SetScript("OnClick", function()
        if addon.OpenSettings then
            addon.OpenSettings()
        else
            print("|cff00ff00TrackerPlus:|r Settings not loaded.")
        end
    end)
    trackerFrame.settingsParam:SetScript("OnEnter", function(self)
        local tooltip = addon:AcquireTooltip(self, "ANCHOR_RIGHT")
        tooltip:SetText("Open Settings")
        tooltip:Show()
    end)
    trackerFrame.settingsParam:SetScript("OnLeave", function()
        addon:HideSharedTooltip()
    end)

    -- Minimize/Maximize Button
    trackerFrame.minMaxBtn = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.minMaxBtn:SetSize(24, 24) -- 1.5x bigger
    -- Center vertically relative to header
    trackerFrame.minMaxBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -5, 0)
    trackerFrame.minMaxBtn:SetNormalAtlas("UI-QuestTrackerButton-Secondary-Collapse")
    trackerFrame.minMaxBtn:SetPushedAtlas("UI-QuestTrackerButton-Secondary-Collapse")
    trackerFrame.minMaxBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")

    -- Keep the header chrome above everything the tracker renders. Pooled rows and
    -- their children climb well past the default child level -- the Active Quest
    -- row's quest-item icon is raised 25px up into this header strip at row level
    -- +10 and escapes its row via SetClipsChildren(false) -- which left it sitting
    -- on top of the gear and swallowing its clicks.
    local chromeLevel = (trackerFrame:GetFrameLevel() or 1) + 50
    trackerFrame.ftaToggleBtn:SetFrameLevel(chromeLevel)
    trackerFrame.autoMinBtn:SetFrameLevel(chromeLevel)
    trackerFrame.lockBtn:SetFrameLevel(chromeLevel)
    trackerFrame.settingsParam:SetFrameLevel(chromeLevel)
    trackerFrame.minMaxBtn:SetFrameLevel(chromeLevel)

    local function UpdateMinMaxState()
        if addon.db.minimized then
            -- Minimized State: Only Maximize button visible
            -- Save current dimensions if not already small
            if trackerFrame:GetWidth() > 50 then
                 addon.db.savedWidth = trackerFrame:GetWidth()
                 addon.db.savedHeight = trackerFrame:GetHeight()

                 -- Save position
                 local point, relativeTo, relativePoint, x, y = trackerFrame:GetPoint()
                 -- Ensure we only save if relativeTo is UIParent or nil (Screen), otherwise default logic
                 if relativeTo == UIParent or relativeTo == nil then
                      addon.db.savedPoint = {point = point, relativePoint = relativePoint, x = x, y = y}
                 end

                 -- Capture geometry before clearing points: an unanchored frame
                 -- reports nil edges.
                 --
                 -- The collapsed frame is a 34x34 box with the button centred in it,
                 -- so anchoring the box's CENTER to where the collapse button sits
                 -- right now leaves the maximize button in exactly the same place.
                 local btn = trackerFrame.minMaxBtn
                 local centerX, centerY
                 if btn then
                      local btnLeft, btnBottom = btn:GetLeft(), btn:GetBottom()
                      if btnLeft and btnBottom then
                           centerX = btnLeft + (btn:GetWidth() or 0) / 2
                           centerY = btnBottom + (btn:GetHeight() or 0) / 2
                      end
                 end

                 local top = trackerFrame:GetTop()
                 local right = trackerFrame:GetRight()

                 trackerFrame:ClearAllPoints()

                 if centerX and centerY then
                      trackerFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX, centerY)
                 elseif right and top then
                      -- Button not laid out yet; keep the tracker's top-right corner,
                      -- which is the corner the header chrome is anchored to.
                      trackerFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
                 end
            end

            -- Size to fit just the button (plus defined border padding)
            -- 34x34 box allows 24x24 button to sit with 5px padding (34-24)/2 = 5
            trackerFrame:SetSize(34, 34) 
            
            -- Gold-only textures (Plus)
            -- Quest Log option (Atlas)
            trackerFrame.minMaxBtn:SetNormalAtlas("UI-QuestTrackerButton-Secondary-Expand")
            trackerFrame.minMaxBtn:SetPushedAtlas("UI-QuestTrackerButton-Secondary-Expand") 
            
            -- Hide Elements
            trackerFrame.settingsParam:Hide()
            trackerFrame.lockBtn:Hide()
            trackerFrame.autoMinBtn:Hide()
            if trackerFrame.ftaToggleBtn then trackerFrame.ftaToggleBtn:Hide() end
            trackerFrame.title:Hide()
            trackerFrame.headerBg:Hide()
            trackerFrame.bg:Hide()
            if trackerFrame.border then trackerFrame.border:Hide() end
            if trackerFrame.resizeBR then trackerFrame.resizeBR:Hide() end
            if trackerFrame.resizeBL then trackerFrame.resizeBL:Hide() end
            if self.scrollFrame then self.scrollFrame:Hide() end
            if self.scrollShadowTop then self.scrollShadowTop:Hide() end
            if self.scrollShadowBottom then self.scrollShadowBottom:Hide() end
            if self.scenarioFrame then self.scenarioFrame:Hide() end
            if self.activeQuestFrame then self.activeQuestFrame:Hide() end
            if self.campaignFrame then self.campaignFrame:Hide() end
            if self.autoQuestFrame then self.autoQuestFrame:Hide() end
            if self.completedQuestFrame then self.completedQuestFrame:Hide() end
            if self.bonusFrame then self.bonusFrame:Hide() end
            if self.worldQuestFrame then self.worldQuestFrame:Hide() end
            if self.questTimerFrame then self.questTimerFrame:Hide() end
            
            -- Center button
            trackerFrame.minMaxBtn:ClearAllPoints()
            trackerFrame.minMaxBtn:SetPoint("CENTER", trackerFrame, "CENTER", 0, 0)
        else
            -- Restored State
            trackerFrame:SetSize(addon.db.savedWidth or 300, addon.db.savedHeight or 400)
            
            -- Restore Position if saved
            if addon.db.savedPoint then
                 trackerFrame:ClearAllPoints()
                 local point = addon.db.savedPoint.point or "TOPLEFT"
                 local relativePoint = addon.db.savedPoint.relativePoint or "TOPLEFT"
                 local x = addon.db.savedPoint.x or 100
                 local y = addon.db.savedPoint.y or -200
                 trackerFrame:SetPoint(point, UIParent, relativePoint, x, y)
                 addon.db.savedPoint = nil
            end
            
            -- Gold-only textures (Minus)
            trackerFrame.minMaxBtn:SetNormalAtlas("UI-QuestTrackerButton-Secondary-Collapse")
            trackerFrame.minMaxBtn:SetPushedAtlas("UI-QuestTrackerButton-Secondary-Collapse")

            -- Show Elements
            trackerFrame.settingsParam:Show()
            trackerFrame.lockBtn:Show()
            trackerFrame.autoMinBtn:Show()
            -- Stays hidden when FollowTheArrow isn't loaded.
            addon:UpdateFTAToggleVisibility()
            trackerFrame.title:Show()
            trackerFrame.headerBg:Show()
            trackerFrame.bg:Show()
            if trackerFrame.border then trackerFrame.border:Show() end
            if self.scrollFrame then self.scrollFrame:Show() end
            if self.scrollShadowTop then self.scrollShadowTop:Show() end
            if self.scrollShadowBottom then self.scrollShadowBottom:Show() end
            if self.scenarioFrame then self.scenarioFrame:Show() end
            if self.activeQuestFrame and self.activeQuestFrame:GetHeight() > 1 then self.activeQuestFrame:Show() end
            if self.campaignFrame and self.campaignFrame:GetHeight() > 1 then self.campaignFrame:Show() end
            if self.autoQuestFrame and self.autoQuestFrame:GetHeight() > 1 then self.autoQuestFrame:Show() end
            if self.completedQuestFrame and self.completedQuestFrame:GetHeight() > 1 then self.completedQuestFrame:Show() end
            if self.bonusFrame and self.bonusFrame:GetNumChildren() > 0 then self.bonusFrame:Show() end
            if self.worldQuestFrame and self.worldQuestFrame:GetNumChildren() > 0 then self.worldQuestFrame:Show() end
            
            -- Always right-aligned, matching where the button is first anchored and
            -- keeping it in the same chrome row as the settings, lock, auto-minimize and
            -- Follow the Arrow buttons (anchored RIGHT at -34, -54, -74 and -94). This used to follow
            -- db.headerIconPosition, but that setting controls which side the
            -- expand/collapse arrows sit on for headers inside the quest list, not the
            -- tracker window's own chrome. Since it defaults to "left", the button
            -- jumped to the left edge on first load and broke up that row.
            trackerFrame.minMaxBtn:ClearAllPoints()
            trackerFrame.minMaxBtn:SetPoint("RIGHT", trackerFrame.headerBg, "RIGHT", -5, 0)
            
            addon:RequestUpdate()
            if addon.RefreshQuestTimers then addon:RefreshQuestTimers() end
            
            -- Restore lock state (handles resize buttons)
            addon:UpdateTrackerLock()
        end
        
        -- After manipulation, ensure position is saved so reloading keeps the anchor choice
        local point, relativeTo, relativePoint, x, y = trackerFrame:GetPoint()
        addon.db.framePosition = {point = point, relativePoint = relativePoint, x = x, y = y}
    end

    trackerFrame.minMaxBtn:SetScript("OnClick", function()
        addon.db.minimized = not addon.db.minimized
        UpdateMinMaxState()
    end)
    
    -- Update tracker frame button state on demand
    function addon:UpdateMinMaxState()
        UpdateMinMaxState()
    end

    -- Initialize state
    UpdateMinMaxState()
    
end
