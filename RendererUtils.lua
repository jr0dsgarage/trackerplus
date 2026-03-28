local addonName, addon = ...

-- Localize hot-path globals
local pairs, ipairs, next, type, tostring = pairs, ipairs, next, type, tostring
local format, match, gsub = string.format, string.match, string.gsub
local max, min, floor = math.max, math.min, math.floor

-------------------------------------------------------------------------------
-- Debug / layout helpers
-------------------------------------------------------------------------------
function addon.DebugLayout(owner, fmt, ...)
    if not owner then return end
    local enabled = owner.db and owner.db.debugEnabled == true and owner.db.layoutDebug == true
    if not enabled then return end

    if owner.LogAt then
        owner:LogAt("trace", "[LAYOUT] " .. tostring(fmt), ...)
    end
end

function addon.ClearArray(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

-------------------------------------------------------------------------------
-- Section debug overlays
-------------------------------------------------------------------------------
local function EnsureSectionDebugOverlay(owner, key, parentFrame, displayLabel, color, labelAnchor)
    owner._sectionDebugOverlays = owner._sectionDebugOverlays or {}
    local overlay = owner._sectionDebugOverlays[key]
    if not overlay then
        overlay = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
        overlay:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel(500)
        overlay.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        overlay.label:SetPoint("TOPLEFT", overlay, "TOPLEFT", 3, -3)
        overlay.label:SetJustifyH("LEFT")
        overlay.label:SetTextColor(1, 1, 1, 0.95)
        owner._sectionDebugOverlays[key] = overlay
    end

    if overlay:GetParent() ~= parentFrame then
        overlay:SetParent(parentFrame)
    end

    overlay:ClearAllPoints()
    overlay:SetAllPoints(parentFrame)
    overlay:SetBackdropBorderColor(color[1], color[2], color[3], 0.95)
    if labelAnchor then
        overlay.label:ClearAllPoints()
        overlay.label:SetPoint(labelAnchor.point, overlay, labelAnchor.relPoint or labelAnchor.point, labelAnchor.x or 3, labelAnchor.y or -3)
    end
    local h = parentFrame.GetHeight and (parentFrame:GetHeight() or 0) or 0
    overlay.label:SetText(format("%s (%.0f)", displayLabel, h))

    -- very light tint so hidden/1px sections are still visible without obscuring content
    if not overlay._fill then
        overlay._fill = overlay:CreateTexture(nil, "BACKGROUND")
        overlay._fill:SetAllPoints(overlay)
    end
    overlay._fill:SetColorTexture(color[1], color[2], color[3], 0.06)

    overlay:Show()
end

function addon:UpdateSectionDebugBoxes()
    if not self._sectionDebugOverlays then
        self._sectionDebugOverlays = {}
    end

    local enabled = self.db and self.db.debugEnabled == true and self.db.debugSectionBoxes == true
    if not enabled then
        for _, overlay in pairs(self._sectionDebugOverlays) do
            overlay:Hide()
        end
        return
    end

    local sections = {
        { key = "tracker", frame = self.trackerFrame, label = "trackerFrame", color = {1.0, 0.35, 0.35}, anchor = { point = "TOPLEFT", x = 3, y = -3 } },
        { key = "autoquest", frame = self.autoQuestFrame, label = "autoQuestFrame", color = {1.0, 0.65, 0.25}, anchor = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -3, y = -3 } },
        { key = "completedquest", frame = self.completedQuestFrame, label = "completedQuestFrame", color = {0.8, 0.8, 0.2}, anchor = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -3, y = -3 } },
        { key = "scenario", frame = self.scenarioFrame, label = "scenarioFrame", color = {0.35, 0.95, 1.0}, anchor = { point = "TOPLEFT", x = 3, y = -3 } },
        { key = "activequest", frame = self.activeQuestFrame, label = "activeQuestFrame", color = {1.0, 0.85, 0.2}, anchor = { point = "TOPLEFT", x = 3, y = -3 } },
        { key = "campaign", frame = self.campaignFrame, label = "campaignFrame", color = {1.0, 0.65, 0.2}, anchor = { point = "TOPLEFT", x = 3, y = -3 } },
        { key = "scroll", frame = self.scrollFrame, label = "scrollFrame", color = {0.4, 1.0, 0.45}, anchor = { point = "TOPLEFT", x = 3, y = -3 } },
        { key = "content", frame = self.contentFrame, label = "contentFrame", color = {0.3, 0.7, 1.0}, anchor = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -3, y = 3 } },
        { key = "bonus", frame = self.bonusFrame, label = "bonusFrame", color = {0.85, 0.45, 1.0}, anchor = { point = "TOPLEFT", x = 3, y = -3 } },
        { key = "wq", frame = self.worldQuestFrame, label = "worldQuestFrame", color = {1.0, 0.35, 0.9}, anchor = { point = "TOPLEFT", x = 3, y = -3 } },
    }

    local seen = {}
    for _, section in ipairs(sections) do
        if section.frame then
            EnsureSectionDebugOverlay(self, section.key, section.frame, section.label, section.color, section.anchor)
            seen[section.key] = true
        end
    end

    for key, overlay in pairs(self._sectionDebugOverlays) do
        if not seen[key] then
            overlay:Hide()
        end
    end
end
