---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Difficulty-colored rings around the game's own world map quest pins, in either a
-- hard circle or the game's own soft glow (see the style constants below).
--
-- Both are drawn *behind* the pin and sized past it, so the pin's own banner covers
-- the middle and only the margin shows. For the circle that occlusion is what makes
-- the thickness adjustable at all: there is no ring texture to scale, and nothing can
-- punch a hole in a texture, so the ring has to be the exposed edge of an oversized
-- disc.
--
-- The pins belong to Blizzard (QuestPinTemplate, from Blizzard_SharedMapDataProviders),
-- so this deliberately keeps its footprint on them to added textures and nothing else:
-- those textures and the "already hooked" bookkeeping live in weak-keyed tables on our
-- side rather than as fields written onto the pooled pin frames.
--
-- Color comes from addon:GetQuestTitleColorByQuestID, i.e. the exact same rules the
-- tracker panel paints quest titles with -- including the super-track gold, which is
-- laid on last -- so a pin and its tracker row always agree.

local max, min, ceil = math.max, math.min, math.ceil

local QUEST_PIN_TEMPLATE = "QuestPinTemplate"

-- Two looks, chosen by db.mapPOIOutlineStyle:
--
-- "circle" -- a solid disc drawn behind the pin and sized a few pixels larger than
-- the pin's own banner, so the only part left visible is a flat ring of exactly the
-- configured thickness. These are mask atlases (a plain white disc on transparency),
-- which is what lets them tint to a flat, readable color.
--
-- "glow" -- the game's own soft ring art, tinted. A halo that fades outwards rather
-- than a hard edge, so it reads as softer than the circle at the same thickness.
local STYLE_CIRCLE = "circle"
local STYLE_GLOW = "glow"

-- Newer clients name the disc "common-mask-circle"; older ones only have
-- "CircleMaskScalable". If a client has neither, the glow is the only look available.
local CIRCLE_ATLASES = { "common-mask-circle", "CircleMaskScalable" }

-- The glow ring every client carrying POIButtonTemplate declares.
local GLOW_ATLAS = "UI-QuestPoi-OuterGlow"

-- A soft glow needs far more room than a hard edge to read at the same thickness, so
-- its reach beyond the pin is the thickness multiplied by this. At the default
-- thickness this lands close to the size the game draws its own ring at.
local GLOW_SPREAD = 4

-- db.mapPOIGlowOpacity is a plain 0-1 fraction, where 1 means "as solid as this can
-- be drawn". Getting there takes more than one draw: the glow art fades by design and
-- its own alpha never reaches full, so a single pass at alpha 1 still lets the map
-- through. The fraction is therefore spent as a budget of up to this many stacked
-- passes, each compositing over the last. Three takes art peaking near half alpha to
-- roughly 90% solid, which is about as far as stacking usefully goes.
--
-- Keeping the pass count on this side of the setting is deliberate: the slider stays
-- a normal opacity the player can reason about, and how many draws that costs stays
-- an implementation detail.
local GLOW_MAX_PASSES = 3

local MIN_THICKNESS, MAX_THICKNESS = 1, 10

-- The POI banner atlases carry a transparent margin around the visible coin, and
-- nothing in the texture API reports it -- an atlas element's bounds are all that can
-- be read back. Sizing the disc straight off the banner's box therefore yielded a
-- ring of that margin *plus* the requested thickness, so even thickness 1 came out
-- around ten pixels. Insetting by the margin first makes the exposed ring equal the
-- thickness exactly: disc = coin + 2t, so (disc - coin) / 2 == t.
--
-- Measured rather than derived, and in the banner's own pixels rather than as a
-- proportion -- the margin is baked into the art at a fixed size, and because the
-- banner is drawn at its native atlas size both it and the thickness are already in
-- the same pin-local units. Retune here if the pin art changes.
local COIN_INSET = 9

-- Styles whose banner is smaller than the standard coin would vanish behind a full
-- inset, so never shrink the disc past this fraction of the banner box.
local MIN_COIN_RATIO = 0.4

-- Below Blizzard's own Glow (BACKGROUND, sublevel 0) and LinkGlow (sublevel -1), so
-- the pin's own artwork always wins where they overlap -- that overlap is what turns
-- the disc into a ring.
local OUTLINE_SUBLEVEL = -7

local outlines = setmetatable({}, { __mode = "k" })
local hookedPins = setmetatable({}, { __mode = "k" })

-- Which disc atlas this client has, resolved once on first use. nil once resolved
-- means it has none, and the glow is then the only look that can be drawn.
local circleAtlas, circleAtlasResolved

local function GetCircleAtlas()
    if not circleAtlasResolved then
        circleAtlasResolved = true
        local getAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
        if getAtlasInfo then
            for _, atlas in ipairs(CIRCLE_ATLASES) do
                if getAtlasInfo(atlas) then
                    circleAtlas = atlas
                    break
                end
            end
        end
    end
    return circleAtlas
end

-- The style actually drawable right now, which is the requested one unless it asks
-- for a circle this client has no art for.
local function ResolveStyle(db)
    local style = db and db.mapPOIOutlineStyle
    if style ~= STYLE_GLOW and GetCircleAtlas() then
        return STYLE_CIRCLE
    end
    return STYLE_GLOW
end

-- Layers are stacked copies of the same art, used to drive the glow past the opacity
-- a single draw can reach (see MAX_GLOW_OPACITY). Every layer stays below Blizzard's
-- own Glow and LinkGlow, so the pin's artwork still wins over all of them.
local function GetOutlineLayer(pin, index)
    local layers = outlines[pin]
    if not layers then
        layers = {}
        outlines[pin] = layers
    end

    local layer = layers[index]
    if not layer then
        layer = pin:CreateTexture(nil, "BACKGROUND", nil, OUTLINE_SUBLEVEL + index - 1)
        layer:SetPoint("CENTER", pin, "CENTER", 0, 0)
        layers[index] = layer
    end
    return layer
end

local function HideOutlineLayers(pin, fromIndex)
    local layers = outlines[pin]
    if not layers then return end

    for i = fromIndex, #layers do
        layers[i]:Hide()
    end
end

-- Swapping style means swapping both the art and the blend mode, so only touch them
-- when it actually changed. The texture is ours, so caching the state on it is safe;
-- nothing here is written to the Blizzard pin.
local function ApplyOutlineStyle(layer, style)
    if layer._tpOutlineStyle == style then return end
    layer._tpOutlineStyle = style

    layer:SetAtlas(style == STYLE_GLOW and GLOW_ATLAS or GetCircleAtlas())

    -- The glow art is not neutral: it is painted gold, and the game recolors it by
    -- swapping to a different atlas per quest classification rather than tinting it.
    -- SetVertexColor multiplies, so tinting the gold directly can only ever darken it
    -- towards gold -- green came out muddy, and grey came out gold. Desaturating
    -- first leaves plain luminance for the tint to multiply into, so the difficulty
    -- color survives. The circle art is already a white mask and needs none of this.
    layer:SetDesaturated(style == STYLE_GLOW)

    -- Normal blending for both, including the glow. The glow used to draw additively,
    -- which is the real reason an opacity of 1 still read as faint: additive blending
    -- can only ever *brighten* what is under it, so over the map's lighter art there
    -- is nothing left to add, and stacking more of it converges on white rather than
    -- on the quest's color. Normal blending makes the alpha mean opacity, and keeps
    -- the hue intact all the way up.
    layer:SetBlendMode("BLEND")
end

-------------------------------------------------------------------------------
-- Per-pin update
-------------------------------------------------------------------------------
function addon:UpdateMapPOIOutline(pin)
    if not pin then return end

    local db = self.db
    local normal = pin.NormalTexture

    -- Pins in the QuestDisabled style stay in the pool with their banner's alpha
    -- zeroed; ringing one would draw a colored halo around nothing.
    local wanted = db and db.colorMapPOIsByDifficulty and normal and (normal:GetAlpha() or 0) > 0

    local questID = wanted and pin.GetQuestID and pin:GetQuestID()
    local color = questID and self:GetQuestTitleColorByQuestID(questID)

    -- The ring's width comes from how far the disc oversizes the pin's banner, so a
    -- banner that hasn't been given its artwork yet has nothing to measure against.
    local bannerW, bannerH = 0, 0
    if color then
        bannerW, bannerH = normal:GetSize()
    end

    if not color or not bannerW or bannerW <= 0 or not bannerH or bannerH <= 0 then
        HideOutlineLayers(pin, 1)
        return
    end

    local thickness = tonumber(db.mapPOIOutlineThickness) or 2
    if thickness < MIN_THICKNESS then thickness = MIN_THICKNESS end
    if thickness > MAX_THICKNESS then thickness = MAX_THICKNESS end

    local style = ResolveStyle(db)
    local r, g, b = color.r or 1, color.g or 1, color.b or 1
    local baseAlpha = color.a or 1
    local width, height, layerCount, passBudget

    if style == STYLE_GLOW then
        -- The glow spreads from the banner's own box rather than the inset coin: it
        -- fades out towards its edge, so starting it inside the banner would leave
        -- nothing visible at all.
        local reach = thickness * GLOW_SPREAD * 2
        width, height = bannerW + reach, bannerH + reach

        -- Spend the 0-1 opacity across up to GLOW_MAX_PASSES stacked draws, each
        -- compositing over the last, so the ring converges on solid without ever
        -- shifting hue. Zero buys no passes at all.
        local opacity = max(min(tonumber(db.mapPOIGlowOpacity) or 1, 1), 0)
        passBudget = opacity * GLOW_MAX_PASSES
        layerCount = ceil(passBudget)
    else
        local coinW = max(bannerW - COIN_INSET * 2, bannerW * MIN_COIN_RATIO)
        local coinH = max(bannerH - COIN_INSET * 2, bannerH * MIN_COIN_RATIO)
        width, height = coinW + thickness * 2, coinH + thickness * 2
        passBudget, layerCount = 1, 1
    end

    for i = 1, layerCount do
        -- Layer 1 takes the first whole pass of the budget, layer 2 the next, and so
        -- on; the last layer takes whatever fraction is left over.
        local layerAlpha = baseAlpha * max(min(passBudget - (i - 1), 1), 0)
        local layer = GetOutlineLayer(pin, i)
        ApplyOutlineStyle(layer, style)
        layer:SetSize(width, height)
        layer:SetVertexColor(r, g, b, layerAlpha)
        layer:Show()
    end

    HideOutlineLayers(pin, layerCount + 1)
end

-- Repaint every pin currently on the map. Used when the colors themselves change
-- under us (the setting being toggled, or the player levelling) rather than the pins.
function addon:RefreshMapPOIOutlines()
    local map = WorldMapFrame
    if not map or not map.EnumeratePinsByTemplate then return end

    for pin in map:EnumeratePinsByTemplate(QUEST_PIN_TEMPLATE) do
        self:UpdateMapPOIOutline(pin)
    end
end

-------------------------------------------------------------------------------
-- Hook installation
-------------------------------------------------------------------------------
-- UpdateButtonStyle is what repaints a pin's artwork, and AddQuest calls it after
-- setting the pin's quest, so hooking it both catches the initial paint of a freshly
-- acquired pin and keeps the outline in step with later restyles (super-track
-- changes, a quest turning complete). Pins are pooled, and releasing one hides it --
-- taking the outline with it -- so there is nothing to clean up on release.
local function HookPin(pin)
    if hookedPins[pin] then return end
    if type(pin.UpdateButtonStyle) ~= "function" then return end

    hookedPins[pin] = true
    hooksecurefunc(pin, "UpdateButtonStyle", function(hookedPin)
        addon:UpdateMapPOIOutline(hookedPin)
    end)
end

function addon:InitMapPOIColors()
    if self._mapPOIHooked then return end

    local map = WorldMapFrame
    if not map or not map.RegisterPin or not map.EnumeratePinsByTemplate then
        -- Blizzard_WorldMap hasn't loaded yet; the ADDON_LOADED watcher below will
        -- call back in once it has.
        return
    end

    self._mapPOIHooked = true

    -- RegisterPin is the last thing AcquirePin does, so it fires for every pin the
    -- map hands out, new or recycled, before the caller configures it.
    hooksecurefunc(map, "RegisterPin", function(_, pin)
        if pin and pin.pinTemplate == QUEST_PIN_TEMPLATE then
            HookPin(pin)
        end
    end)

    -- Anything already on the canvas predates the hook and needs wiring by hand.
    for pin in map:EnumeratePinsByTemplate(QUEST_PIN_TEMPLATE) do
        HookPin(pin)
        self:UpdateMapPOIOutline(pin)
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local mapEvents = CreateFrame("Frame")
mapEvents:RegisterEvent("ADDON_LOADED")
mapEvents:RegisterEvent("PLAYER_LEVEL_UP")
mapEvents:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        -- Usually the map is already loaded by the time Initialize runs and hooks it,
        -- in which case this watcher has nothing left to wait for.
        if addon._mapPOIHooked then
            self:UnregisterEvent("ADDON_LOADED")
        elseif arg1 == "Blizzard_WorldMap" then
            self:UnregisterEvent("ADDON_LOADED")
            addon:InitMapPOIColors()
        end
    elseif event == "PLAYER_LEVEL_UP" then
        -- Every pin's difficulty color shifts when the player's level does. Deferred
        -- a tick because the level the color functions read isn't necessarily updated
        -- by the time this fires.
        C_Timer.After(0.1, function()
            addon:RefreshMapPOIOutlines()
        end)
    end
end)
