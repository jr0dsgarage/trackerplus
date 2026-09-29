---@diagnostic disable: undefined-global
local _, TrackerPlus = ...
TrackerPlus.Nameplates = TrackerPlus.Nameplates or {}
local Nameplates = TrackerPlus.Nameplates

local wipeTable = Nameplates.WipeTable

-- Blizzard's nameplate health bar ships a `selectedBorder` texture (this atlas) that it shows for the
-- target and focus via NamePlateHealthBarMixin:UpdateSelectionBorder. We hook that method per bar so
-- whenever Blizzard refreshes the border we can hide it and draw our own highlight in its place.
local BLIZZARD_BORDER_ATLAS = "UI-HUD-Nameplates-Selected"
local BORDER_TEMPLATE = "NamePlateFullBorderTemplate"
-- Used when a bar has no native selectedBorder to anchor to (settings preview, Classic nameplate style).
local FALLBACK_BLIZZARD_INSET = 4
-- Our "Blizzard" style is pulled in by this much from Blizzard's border: it's the baseline a style's
-- Offset of 0 means. renderBlizzard is the only place geometry relative to a native border is adjusted.
-- Blizzard's own textures are never moved (nameplate regions are restricted, so we can't read their
-- anchors, and their layout varies between client builds).
local DEFAULT_BORDER_SHRINK = 1
local NO_EDGE_ADJUST = { left = 0, top = 0, right = 0, bottom = 0 }
-- Our "Blizzard" style, per-edge on top of DEFAULT_BORDER_SHRINK (positive = inward): the bottom
-- edge is extended 1px so the bar's bottom edge isn't peeking out below it.
local BLIZZARD_STYLE_EDGE_ADJUST = { left = 0, top = 0, right = 0, bottom = -1 }
-- "Fix Default border offset": per-edge inward nudges (tuned in-game) that make Blizzard's default
-- border atlas (UI-HUD-CoolDownManager-Selected-yellow) sit evenly around the health bar.
local DEFAULT_BORDER_EDGE_ADJUST = { left = 2, top = 3, right = 1, bottom = 1 }
-- The same, tuned in-game for the level badge's own border. The badge only ever shows Blizzard's
-- default border (fixed or not), never our highlight styles.
local LEVEL_BADGE_EDGE_ADJUST = { left = 1, top = 4, right = 1, bottom = 2 }
local GLOW_SIZE = 16

-- Every health bar we've hooked (bars live in Blizzard's unit frame pool, so this stays small).
Nameplates.hookedBars = Nameplates.hookedBars or {}
-- Nameplate unit token -> health bar currently carrying a quest style, so removal can clear it immediately.
Nameplates.barsByUnit = Nameplates.barsByUnit or {}
-- Native border texture -> the color Blizzard last tinted it, captured by hooking SetVertexColor
-- (reading it back from a restricted region isn't reliable).
Nameplates.nativeColors = Nameplates.nativeColors or setmetatable({}, { __mode = "k" })
Nameplates.active = Nameplates.active or false

local function captureNativeColor(texture)
    if not texture or texture.tpnp_colorHooked then
        return
    end
    texture.tpnp_colorHooked = true
    hooksecurefunc(texture, "SetVertexColor", function(self, r, g, b)
        if type(r) == "number" then
            Nameplates.nativeColors[self] = { r = r, g = g, b = b }
        end
    end)
end

local function normalizeMode(mode)
    if mode == "border" or not mode then
        return "outline"
    end
    return mode
end

local function resolveHealthBar(plate)
    local unitFrame = plate and plate.UnitFrame
    if not unitFrame then
        return nil
    end
    local container = unitFrame.HealthBarsContainer
    return (container and container.healthBar) or unitFrame.healthBar
end

local function acquireNameplate(unitData)
    if unitData.frame then
        return unitData.frame
    end
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        return C_NamePlate.GetNamePlateForUnit(unitData.unit)
    end
    return nil
end

local function isBarForUnit(bar, unitToken)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unitToken)
    return plate ~= nil and resolveHealthBar(plate) == bar
end

local function usesNativeBorder(bar)
    if not bar.selectedBorder then
        return false
    end
    -- Blizzard turns the selected border off for the Classic nameplate style.
    return not bar.ShouldUseSelectedBorder or bar:ShouldUseSelectedBorder()
end

-- Border frames -------------------------------------------------------------

-- Mirrors NamePlateBorderTemplateMixin in case the Blizzard template is ever renamed or removed.
local FallbackBorderMixin = {}

function FallbackBorderMixin:SetVertexColor(r, g, b, a)
    for _, texture in ipairs(self.Textures) do
        texture:SetVertexColor(r, g, b, a)
    end
end

function FallbackBorderMixin:SetBorderSizes(borderSize, borderSizeMinPixels)
    self.borderSize = borderSize
    self.borderSizeMinPixels = borderSizeMinPixels
end

function FallbackBorderMixin:UpdateSizes()
    local size = self.borderSize or 1
    local minPixels = self.borderSizeMinPixels or 1

    PixelUtil.SetWidth(self.Left, size, minPixels)
    PixelUtil.SetPoint(self.Left, "TOPRIGHT", self, "TOPLEFT", 0, size, 0, minPixels)
    PixelUtil.SetPoint(self.Left, "BOTTOMRIGHT", self, "BOTTOMLEFT", 0, -size, 0, minPixels)

    PixelUtil.SetWidth(self.Right, size, minPixels)
    PixelUtil.SetPoint(self.Right, "TOPLEFT", self, "TOPRIGHT", 0, size, 0, minPixels)
    PixelUtil.SetPoint(self.Right, "BOTTOMLEFT", self, "BOTTOMRIGHT", 0, -size, 0, minPixels)

    PixelUtil.SetHeight(self.Bottom, size, minPixels)
    PixelUtil.SetPoint(self.Bottom, "TOPLEFT", self, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetPoint(self.Bottom, "TOPRIGHT", self, "BOTTOMRIGHT", 0, 0)

    PixelUtil.SetHeight(self.Top, size, minPixels)
    PixelUtil.SetPoint(self.Top, "BOTTOMLEFT", self, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(self.Top, "BOTTOMRIGHT", self, "TOPRIGHT", 0, 0)
end

local function templateExists(name)
    return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

local function createOutlineFrame(bar)
    local frame
    if templateExists(BORDER_TEMPLATE) then
        frame = CreateFrame("Frame", nil, bar, BORDER_TEMPLATE)
    else
        frame = CreateFrame("Frame", nil, bar)
        frame.Textures = {}
        for _, key in ipairs({ "Left", "Right", "Top", "Bottom" }) do
            local texture = frame:CreateTexture()
            texture:SetColorTexture(1, 1, 1, 1)
            frame[key] = texture
            frame.Textures[#frame.Textures + 1] = texture
        end
        Mixin(frame, FallbackBorderMixin)
    end

    -- The template draws at BACKGROUND -8, beneath the bar's own background art; lift it above.
    for _, texture in ipairs(frame.Textures) do
        texture:SetDrawLayer("OVERLAY", 0)
    end
    return frame
end

-- Renderers -----------------------------------------------------------------
-- Each bar keeps its own persistent parts (created on first use) that are shown or hidden per update.

-- A host can carry several independent sets of parts (the health bar hosts its own and the badge's).
local function getParts(host, key)
    local sets = host.tpnp_highlight
    if not sets then
        sets = {}
        host.tpnp_highlight = sets
    end
    local parts = sets[key]
    if not parts then
        parts = {}
        sets[key] = parts
    end
    return parts
end

local function hideParts(parts)
    if parts.blizzard then
        parts.blizzard:Hide()
    end
    if parts.outline then
        parts.outline:Hide()
    end
    if parts.glow then
        for _, texture in ipairs(parts.glow) do
            texture:Hide()
        end
    end
end

-- Renderers take (host, parts, style, r, g, b, a, geo): parts are created on `host`, and `geo` says
-- what to wrap. geo.frame is the region outline/glow surround, geo.native is Blizzard's border for that
-- surface (nil when there isn't one), and geo.atlas is the atlas the "Blizzard" style draws with.

local function renderBlizzard(host, parts, style, r, g, b, a, geo)
    local texture = parts.blizzard
    if not texture then
        texture = host:CreateTexture(nil, "OVERLAY", nil, 0)
        parts.blizzard = texture
    end

    -- The redrawn default border passes Blizzard's own atlas; our styles use the plain tintable one.
    local atlas = style.atlas or geo.atlas or BLIZZARD_BORDER_ATLAS
    if texture.tpnp_atlas ~= atlas then
        texture:SetAtlas(atlas)
        texture.tpnp_atlas = atlas
    end
    -- The "Rounded" style strips a pre-colored atlas's baked-in color so the vertex color can tint it.
    texture:SetDesaturated(style.desaturate == true)

    -- Anchor to Blizzard's own border so we inherit its exact geometry (it re-anchors on every resize).
    -- The redrawn default border passes nativeInset = 0 to sit exactly on it.
    local anchor, inset = geo.frame, FALLBACK_BLIZZARD_INSET
    -- Per-edge nudges toward the bar (positive = inward), applied on top of the offset.
    local adjust = NO_EDGE_ADJUST
    if geo.native then
        anchor, inset = geo.native, style.nativeInset or -DEFAULT_BORDER_SHRINK
        adjust = style.nativeEdgeAdjust or BLIZZARD_STYLE_EDGE_ADJUST
    end
    local offset = math.floor(style.offset or 0) + inset

    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", anchor, "TOPLEFT", -offset + adjust.left, offset - adjust.top)
    texture:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", offset - adjust.right, -offset + adjust.bottom)
    texture:SetVertexColor(r, g, b, a)
    texture:Show()
end

local function renderOutline(host, parts, style, r, g, b, a, geo)
    local border = parts.outline
    if not border then
        border = createOutlineFrame(host)
        parts.outline = border
    end

    local frame = geo.frame
    local offset = style.offset or 0
    local thickness = style.thickness or 2

    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
    border:SetBorderSizes(thickness, 1)
    border:UpdateSizes()
    border:SetVertexColor(r, g, b, a)
    border:Show()
end

-- Order matters: edges first, then corners (TopLeft, TopRight, BottomLeft, BottomRight).
local GLOW_PIECES = {
    { atlas = "_ButtonGreenGlow-NineSlice-EdgeTop", texCoord = { 1, 0, 0, 1 } },
    { atlas = "_ButtonGreenGlow-NineSlice-EdgeBottom", texCoord = { 1, 0, 0, 1 } },
    { atlas = "!ButtonGreenGlow-NineSlice-EdgeLeft", texCoord = { 0, 1, 1, 0 } },
    { atlas = "!ButtonGreenGlow-NineSlice-EdgeRight", texCoord = { 0, 1, 1, 0 } },
    { atlas = "ButtonGreenGlow-NineSlice-Corner", texCoord = { 0, 1, 0, 1 } },
    { atlas = "ButtonGreenGlow-NineSlice-Corner", texCoord = { 1, 0, 0, 1 } },
    { atlas = "ButtonGreenGlow-NineSlice-Corner", texCoord = { 0, 1, 1, 0 } },
    { atlas = "ButtonGreenGlow-NineSlice-Corner", texCoord = { 1, 0, 1, 0 } },
}

local function renderGlow(host, parts, style, r, g, b, a, geo)
    local bar = geo.frame
    local glow = parts.glow
    if not glow then
        glow = {}
        for index, piece in ipairs(GLOW_PIECES) do
            local texture = host:CreateTexture(nil, "OVERLAY", nil, 1)
            texture:SetAtlas(piece.atlas, index > 4)
            texture:SetBlendMode("ADD")
            texture:SetTexCoord(unpack(piece.texCoord))
            glow[index] = texture
        end
        parts.glow = glow
    end

    -- Negative so the glow sits tighter to the health bar.
    local offset = math.floor((style.offset or 0) - 4)
    local top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight = unpack(glow)

    for _, texture in ipairs(glow) do
        texture:ClearAllPoints()
        texture:SetVertexColor(r, g, b, a)
        texture:Show()
    end

    top:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -offset, offset)
    top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", offset, offset)
    top:SetHeight(GLOW_SIZE)

    bottom:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -offset, -offset)
    bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", offset, -offset)
    bottom:SetHeight(GLOW_SIZE)

    left:SetPoint("TOPRIGHT", bar, "TOPLEFT", -offset, offset)
    left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -offset, -offset)
    left:SetWidth(GLOW_SIZE)

    right:SetPoint("TOPLEFT", bar, "TOPRIGHT", offset, offset)
    right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", offset, -offset)
    right:SetWidth(GLOW_SIZE)

    topLeft:SetSize(GLOW_SIZE, GLOW_SIZE)
    topLeft:SetPoint("BOTTOMRIGHT", bar, "TOPLEFT", -offset, offset)
    topRight:SetSize(GLOW_SIZE, GLOW_SIZE)
    topRight:SetPoint("BOTTOMLEFT", bar, "TOPRIGHT", offset, offset)
    bottomLeft:SetSize(GLOW_SIZE, GLOW_SIZE)
    bottomLeft:SetPoint("TOPRIGHT", bar, "BOTTOMLEFT", -offset, -offset)
    bottomRight:SetSize(GLOW_SIZE, GLOW_SIZE)
    bottomRight:SetPoint("TOPLEFT", bar, "BOTTOMRIGHT", offset, -offset)
end

local renderers = {
    outline = renderOutline,
    blizzard = renderBlizzard,
    glow = renderGlow,
}

local function barGeometry(bar)
    return {
        frame = bar,
        native = usesNativeBorder(bar) and bar.selectedBorder or nil,
        atlas = BLIZZARD_BORDER_ATLAS,
    }
end

-- The level-difference badge beside the health bar (newer clients give it its own selectedBorder).
local function badgeGeometry(badge)
    return {
        frame = badge,
        native = badge.selectedBorder,
        atlas = BLIZZARD_BORDER_ATLAS,
    }
end

local function renderSurface(host, key, style, geo)
    local parts = getParts(host, key)
    hideParts(parts)
    if not style then
        return
    end

    local color = style.color or {}
    local renderer = renderers[normalizeMode(style.mode)] or renderOutline
    renderer(host, parts, style, color.r or 1, color.g or 1, color.b or 1, color.a or 1, geo)
end

-- Draws `style` on any status bar (live nameplate or the settings preview); nil style hides it.
function Nameplates:RenderBarHighlight(bar, style)
    renderSurface(bar, "bar", style, barGeometry(bar))
end

-- Nameplate bar state ---------------------------------------------------------

local function currentTargetStyle()
    if not Nameplates.db.currentTargetEnabled then
        return nil
    end
    return {
        color = Nameplates.db.currentTargetColor,
        thickness = Nameplates.db.currentTargetThickness,
        offset = Nameplates.db.currentTargetOffset,
        mode = normalizeMode(Nameplates.db.currentTargetStyle or Nameplates:GetDefault("currentTargetStyle")),
        origin = "currentTarget",
    }
end

-- "Fix Default border offset": Blizzard's own border redrawn by us with its atlas's uneven padding
-- corrected (DEFAULT_BORDER_EDGE_ADJUST). The atlas and tint are copied per surface from that
-- surface's native border (see nativeCopyStyle), so only the geometry differs from Blizzard's.
local DEFAULT_BORDER_STYLE = {
    offset = 0,
    nativeInset = 0,
    nativeEdgeAdjust = DEFAULT_BORDER_EDGE_ADJUST,
    mode = "blizzard",
    origin = "default",
}

-- Blizzard's current atlas on a native border (e.g. "UI-HUD-CoolDownManager-Selected-yellow"; the color
-- is baked in). GetAtlas is readable on restricted regions, unlike anchors; nil if it can't be read.
local function nativeAtlas(native)
    local ok, atlas = pcall(native.GetAtlas, native)
    if ok and type(atlas) == "string" and atlas ~= "" then
        return atlas
    end
    return nil
end

-- "Rounded" style: Blizzard's current nameplate border atlas, whose corners match the nameplate's.
-- An uncolored variant is used if the client has one; otherwise the pre-colored one is desaturated
-- so our color can tint it. Positioned with the tuned default-border geometry, then the style's Offset.
local ROUNDED_NEUTRAL_ATLASES = { "UI-HUD-CoolDownManager-Selected", "UI-HUD-CoolDownManager-Selected-white" }
local ROUNDED_FALLBACK_ATLAS = "UI-HUD-CoolDownManager-Selected-yellow"
local roundedNeutralAtlas

local function findNeutralRoundedAtlas()
    if roundedNeutralAtlas == nil then
        roundedNeutralAtlas = false
        if C_Texture and C_Texture.GetAtlasInfo then
            for _, name in ipairs(ROUNDED_NEUTRAL_ATLASES) do
                if C_Texture.GetAtlasInfo(name) then
                    roundedNeutralAtlas = name
                    break
                end
            end
        end
    end
    return roundedNeutralAtlas or nil
end

local function renderRounded(host, parts, style, r, g, b, a, geo)
    local atlas, desaturate = findNeutralRoundedAtlas(), false
    if not atlas then
        atlas = (geo.native and nativeAtlas(geo.native)) or ROUNDED_FALLBACK_ATLAS
        desaturate = true
    end
    local rounded = {
        atlas = atlas,
        desaturate = desaturate,
        offset = style.offset,
        nativeInset = 0,
        nativeEdgeAdjust = DEFAULT_BORDER_EDGE_ADJUST,
    }
    renderBlizzard(host, parts, rounded, r, g, b, a, geo)
end
renderers.rounded = renderRounded

-- DEFAULT_BORDER_STYLE made to look exactly like `native`: its atlas, plus any tint Blizzard applied
-- (untinted when Blizzard never calls SetVertexColor). Nil if the atlas can't be read, in which case
-- Blizzard's own border is left showing.
local function nativeCopyStyle(style, native)
    local atlas = nativeAtlas(native)
    if not atlas then
        return nil
    end
    local color = Nameplates.nativeColors[native] or { r = 1, g = 1, b = 1 }
    return {
        color = { r = color.r, g = color.g, b = color.b, a = 1 },
        atlas = atlas,
        offset = style.offset,
        nativeInset = style.nativeInset,
        nativeEdgeAdjust = style.nativeEdgeAdjust,
        mode = style.mode,
        origin = style.origin,
    }
end

local function isSelectedBar(bar)
    return isBarForUnit(bar, "target") or isBarForUnit(bar, "focus")
end

-- Returns the style to draw on the health bar (or nil) and whether Blizzard's border should be hidden.
local function resolveBarStyle(bar)
    if not Nameplates.active then
        return nil, false
    end

    -- The game draws its own current-target highlight, so ours only overrides quest highlights.
    if bar.tpnp_questStyle and isBarForUnit(bar, "target") then
        local targetStyle = currentTargetStyle()
        if targetStyle then
            return targetStyle, true
        end
    end
    if bar.tpnp_questStyle then
        return bar.tpnp_questStyle, true
    end

    -- Nothing of ours on this bar; optionally hide or redraw Blizzard's default border.
    if Nameplates.db.hideDefaultBorder then
        return nil, true
    end
    if Nameplates.db.fixDefaultBorderOffset and usesNativeBorder(bar) and isSelectedBar(bar) then
        return DEFAULT_BORDER_STYLE, true
    end
    return nil, false
end

-- Shows Blizzard's border again after we stop owning a bar. We only ever Hide() it (never recolor it),
-- so restoring is just recomputing its shown state; we avoid calling Blizzard's UpdateSelectionBorder
-- from addon code so its unit checks never run tainted.
local function restoreNativeBorder(bar)
    if not usesNativeBorder(bar) then
        return
    end
    bar.selectedBorder:SetShown(isSelectedBar(bar))
end

-- The level badge only ever shows Blizzard's default border, independent of our highlight styles
-- on the health bar: "Disable Default Level Badge border" hides it, otherwise "Fix Default border
-- offset" redraws it (while the unit is the target/focus). Blizzard only toggles that border's shown
-- state, so we hide it via alpha instead of fighting its updates.
local function refreshBadge(bar)
    local unitFrame = bar.tpnp_unitFrame
    local badge = unitFrame and unitFrame.PlayerLevelDiffFrame
    local native = badge and badge.selectedBorder
    if not native then
        return
    end
    captureNativeColor(native)

    local hideBadge = Nameplates.active and Nameplates.db.hideLevelBadgeBorder
    local badgeStyle
    if Nameplates.active and not hideBadge and Nameplates.db.fixDefaultBorderOffset and isSelectedBar(bar) then
        badgeStyle = nativeCopyStyle(DEFAULT_BORDER_STYLE, native)
        if badgeStyle then
            badgeStyle.nativeEdgeAdjust = LEVEL_BADGE_EDGE_ADJUST
        end
    end

    renderSurface(badge, "badge", badgeStyle, badgeGeometry(badge))
    native:SetAlpha((hideBadge or badgeStyle ~= nil) and 0 or 1)
end

-- fromHook: Blizzard just ran UpdateSelectionBorder, so its own border state is already correct.
local function refreshBar(bar, fromHook)
    local style, hideNative = resolveBarStyle(bar)
    refreshBadge(bar)
    if style and style.origin == "default" then
        -- If Blizzard's atlas can't be read we can't copy it faithfully; leave Blizzard's showing.
        style = nativeCopyStyle(style, bar.selectedBorder)
        if not style then
            hideNative = false
        end
    end
    Nameplates:RenderBarHighlight(bar, style)

    if hideNative then
        if bar.selectedBorder then
            bar.selectedBorder:Hide()
        end
        bar.tpnp_hidNativeBorder = true
    elseif bar.tpnp_hidNativeBorder then
        bar.tpnp_hidNativeBorder = false
        if not fromHook then
            restoreNativeBorder(bar)
        end
    end
end

local function onSelectionBorderUpdated(bar)
    refreshBar(bar, true)
end

local function ensureHooked(bar)
    if Nameplates.hookedBars[bar] then
        return
    end
    Nameplates.hookedBars[bar] = true
    captureNativeColor(bar.selectedBorder)
    if type(bar.UpdateSelectionBorder) == "function" then
        hooksecurefunc(bar, "UpdateSelectionBorder", onSelectionBorderUpdated)
    end
end

-- questStyles: bar -> quest style; barTokens: nameplate unit token -> bar.
local function syncBars(questStyles, barTokens)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        -- Hook every visible plate so the current target style applies to non-quest units too.
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local bar = resolveHealthBar(plate)
            if bar then
                -- A bar always belongs to the same pooled unit frame; remember it to reach the level badge.
                bar.tpnp_unitFrame = bar.tpnp_unitFrame or plate.UnitFrame
                ensureHooked(bar)
            end
        end
    end
    for bar in pairs(questStyles) do
        ensureHooked(bar)
    end

    for bar in pairs(Nameplates.hookedBars) do
        bar.tpnp_questStyle = questStyles[bar]
        refreshBar(bar)
    end

    wipeTable(Nameplates.barsByUnit)
    for token, bar in pairs(barTokens) do
        Nameplates.barsByUnit[token] = bar
    end
end

local function determineStyle(result)
    local configMap = {
        ["Has Quest Item"] = "questItem",
        ["Bonus Objective"] = "bonusObjective",
        ["World Quest"] = "worldQuest",
        ["Quest Objective"] = "questObjective",
    }

    local prefix = configMap[result.reason]
    if not prefix or not Nameplates.db[prefix .. "Enabled"] then
        return nil
    end

    return {
        color = Nameplates.db[prefix .. "Color"],
        thickness = Nameplates.db[prefix .. "Thickness"],
        offset = Nameplates.db[prefix .. "Offset"],
        mode = normalizeMode(Nameplates.db[prefix .. "Style"] or Nameplates:GetDefault(prefix .. "Style")),
        origin = prefix,
    }
end

local function isCurrentTarget(result)
    if not result or not result.unit then
        return false
    end

    if result.unit == "target" then
        return true
    end

    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local targetPlate = C_NamePlate.GetNamePlateForUnit("target")
        if targetPlate and result.frame and targetPlate == result.frame then
            return true
        end
    end

    return false
end

function Nameplates:ClearHighlights()
    for bar in pairs(self.hookedBars) do
        bar.tpnp_questStyle = nil
        refreshBar(bar)
    end
    wipeTable(self.barsByUnit)
end

-- Called on NAME_PLATE_UNIT_REMOVED so a pooled unit frame never carries a stale quest style to its next unit.
function Nameplates:ReleaseNamePlateUnit(unitToken)
    local bar = unitToken and self.barsByUnit[unitToken]
    if not bar then
        return
    end
    self.barsByUnit[unitToken] = nil
    bar.tpnp_questStyle = nil
    refreshBar(bar)
end

function Nameplates:CollectHighlights()
    local relevantUnits = self:GetRelevantUnits()
    local results = {}
    local questStyles = {}
    local barTokens = {}

    for _, unitData in ipairs(relevantUnits) do
        local classification = self:ClassifyUnit(unitData)
        if classification then
            classification.frame = classification.frame or unitData.frame
            classification.highlighted = false
            classification.isCurrentTarget = isCurrentTarget(classification)
            results[#results + 1] = classification

            local style = determineStyle(classification)
            classification.usesTargetStyle = classification.isCurrentTarget and Nameplates.db.currentTargetEnabled
                and style ~= nil
            if style then
                classification.highlighted = true
                if classification.note == "Disabled in settings" then
                    classification.note = nil
                end
                classification.highlightStyle = style
                local plate = acquireNameplate(classification)
                local bar = resolveHealthBar(plate)
                if bar then
                    questStyles[bar] = style
                    local token = plate and plate.namePlateUnitToken
                    if token then
                        barTokens[token] = bar
                    end
                end
            elseif classification.reason then
                if not classification.note then
                    classification.note = "Disabled in settings"
                end
                classification.suppressedReason = classification.reason
            elseif classification.usesTargetStyle and not classification.note then
                classification.note = "Current target (target style only)"
            end
        end
    end

    syncBars(questStyles, barTokens)

    return results
end
