local addonName, addon = ...

-- Localize hot-path globals
local ipairs, tostring = ipairs, tostring
local format = string.format

-------------------------------------------------------------------------------
-- Debug / layout helpers
-------------------------------------------------------------------------------
-- Gated on db.layoutDebug as well as the normal debug/level checks. Callers whose
-- arguments are costly should check addon:ShouldLog("trace") and db.layoutDebug first.
function addon.DebugLayout(owner, fmt, ...)
    if not owner.db.layoutDebug then return end
    owner:LogAt("trace", "[LAYOUT] " .. tostring(fmt), ...)
end

-------------------------------------------------------------------------------
-- Pinned section helpers
-------------------------------------------------------------------------------
local SECTION_BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
}

addon.SECTION_HEADER_GOLD = { r = 1, g = 0.82, b = 0, a = 1 }
addon.SECTION_HEADER_HEIGHT = 30

-- Takes a pooled button and makes it a pinned section's title header (Active Quest,
-- Campaign, Follow the Arrow, Bonus Objective, World Quests): title text, a dark
-- styled backdrop, anchored to the top of `parent`. The caller sizes
-- header.styledBackdrop once the section's rows are laid out, so it covers them too.
--
-- The header does nothing when clicked or hovered. Pooled buttons keep whatever
-- scripts their last role bound, so they are cleared here; otherwise a section title
-- would act on whichever quest row or zone header last used the button.
function addon:AcquireSectionHeader(parent, title, color, textRightInset)
    local db = self.db
    local header = self:GetOrCreateButton(parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    local text = header.text
    text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
    text:SetTextColor(color.r, color.g, color.b, color.a or 1)
    text:SetText(title)
    text:SetJustifyH("LEFT")
    text:ClearAllPoints()
    text:SetPoint("LEFT", 5, 0)
    text:SetPoint("RIGHT", textRightInset or -5, 0)

    if header.expandBtn then header.expandBtn:Hide() end

    local backdrop = header.styledBackdrop
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, header, "BackdropTemplate")
        if header:GetFrameLevel() > 1 then
            backdrop:SetFrameLevel(header:GetFrameLevel() - 1)
        else
            backdrop:SetFrameLevel(1)
            header:SetFrameLevel(2)
        end
        backdrop:SetBackdrop(SECTION_BACKDROP)
        backdrop:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
        backdrop:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        header.styledBackdrop = backdrop
    end
    backdrop:ClearAllPoints()
    backdrop:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    backdrop:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    backdrop:Show()
    header.bg:SetColorTexture(0, 0, 0, 0)

    header:SetHeight(addon.SECTION_HEADER_HEIGHT)
    header.trackableData = nil
    if header._scriptMode ~= "sectionHeader" then
        header:SetScript("OnClick", nil)
        header:SetScript("OnMouseUp", nil)
        header:SetScript("OnEnter", nil)
        header:SetScript("OnLeave", nil)
        header._scriptMode = "sectionHeader"
    end

    return header
end

-- Sizes a pinned section frame to `height` and shows it, unless the tracker is
-- minimized. A section with nothing to show (height 0) is hidden, and set to
-- `emptyHeight` when given.
function addon:FinishPinnedSection(frame, height, emptyHeight)
    if height > 0 then
        frame:SetHeight(height)
        frame:SetShown(not self.db.minimized)
    else
        if emptyHeight then frame:SetHeight(emptyHeight) end
        frame:Hide()
    end
end

-------------------------------------------------------------------------------
-- Section debug overlays
-------------------------------------------------------------------------------
local TOP_LEFT_LABEL = { point = "TOPLEFT", x = 3, y = -3 }
local TOP_RIGHT_LABEL = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -3, y = -3 }

-- `frame` names the addon field holding each section's frame.
local DEBUG_SECTIONS = {
    { key = "tracker", frame = "trackerFrame", color = {1.0, 0.35, 0.35}, anchor = TOP_LEFT_LABEL },
    { key = "autoquest", frame = "autoQuestFrame", color = {1.0, 0.65, 0.25}, anchor = TOP_RIGHT_LABEL },
    { key = "completedquest", frame = "completedQuestFrame", color = {0.8, 0.8, 0.2}, anchor = TOP_RIGHT_LABEL },
    { key = "scenario", frame = "scenarioFrame", color = {0.35, 0.95, 1.0}, anchor = TOP_LEFT_LABEL },
    { key = "activequest", frame = "activeQuestFrame", color = {1.0, 0.85, 0.2}, anchor = TOP_LEFT_LABEL },
    { key = "fta", frame = "ftaFrame", color = {0.4, 1.0, 0.75}, anchor = TOP_LEFT_LABEL },
    { key = "questtimer", frame = "questTimerFrame", color = {1.0, 0.3, 0.3}, anchor = TOP_LEFT_LABEL },
    { key = "campaign", frame = "campaignFrame", color = {1.0, 0.65, 0.2}, anchor = TOP_LEFT_LABEL },
    { key = "scroll", frame = "scrollFrame", color = {0.4, 1.0, 0.45}, anchor = TOP_LEFT_LABEL },
    { key = "content", frame = "contentFrame", color = {0.3, 0.7, 1.0}, anchor = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -3, y = 3 } },
    { key = "bonus", frame = "bonusFrame", color = {0.85, 0.45, 1.0}, anchor = TOP_LEFT_LABEL },
    { key = "wq", frame = "worldQuestFrame", color = {1.0, 0.35, 0.9}, anchor = TOP_LEFT_LABEL },
}

local sectionDebugOverlays = {}

local function EnsureSectionDebugOverlay(section, parentFrame)
    local overlay = sectionDebugOverlays[section.key]
    if not overlay then
        overlay = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
        overlay:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel(500)
        overlay.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        overlay.label:SetJustifyH("LEFT")
        overlay.label:SetTextColor(1, 1, 1, 0.95)
        -- very light tint so hidden/1px sections are still visible without obscuring content
        overlay._fill = overlay:CreateTexture(nil, "BACKGROUND")
        overlay._fill:SetAllPoints(overlay)
        sectionDebugOverlays[section.key] = overlay
    end

    if overlay:GetParent() ~= parentFrame then
        overlay:SetParent(parentFrame)
    end

    local color, labelAnchor = section.color, section.anchor
    overlay:ClearAllPoints()
    overlay:SetAllPoints(parentFrame)
    overlay:SetBackdropBorderColor(color[1], color[2], color[3], 0.95)
    overlay.label:ClearAllPoints()
    overlay.label:SetPoint(labelAnchor.point, overlay, labelAnchor.relPoint or labelAnchor.point, labelAnchor.x, labelAnchor.y)
    overlay.label:SetText(format("%s (%.0f)", section.frame, parentFrame:GetHeight() or 0))
    overlay._fill:SetColorTexture(color[1], color[2], color[3], 0.06)
    overlay:Show()
end

function addon:UpdateSectionDebugBoxes()
    local enabled = self.db.debugEnabled and self.db.debugSectionBoxes
    for _, section in ipairs(DEBUG_SECTIONS) do
        local frame = self[section.frame]
        if enabled and frame then
            EnsureSectionDebugOverlay(section, frame)
        elseif sectionDebugOverlays[section.key] then
            sectionDebugOverlays[section.key]:Hide()
        end
    end
end
