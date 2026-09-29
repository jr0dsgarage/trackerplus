# next - Quest Target Nameplate Highlighter

## Architecture Overview

World of Warcraft addon that highlights enemy nameplates based on quest relevance. Analyzes quest log and nameplate tooltips to determine which enemies are quest objectives, quest item droppers, world quest targets, or bonus objectives, then applies customizable visual highlights.

**Core Components:**
- [`Core.lua`](../Core.lua): Event registration, update scheduling, slash commands
- [`Database.lua`](../Database.lua): Settings persistence, defaults, migrations, table utilities
- [`Classification.lua`](../Classification.lua): Quest data parsing, nameplate tooltip analysis, caching
- [`Highlights.lua`](../Highlights.lua): Visual rendering, texture pooling, healthbar resolution
- [`Settings.lua`](../Settings.lua): Settings panel UI with per-highlight-type customization
- [`Debug.lua`](../Debug.lua): Debug window showing real-time classification results

**Load Order:** [`next.toc`](../next.toc) - Database → Classification → Highlights → Debug → Core → Settings

## Data Flow Architecture

**Update Pipeline:**
```
WoW Event → RequestUpdate() → 0.05s debounce → UpdateHighlight()
  ↓
CollectHighlights() reads quest log + scans nameplates
  ↓
Classification.lua parses tooltips, matches quest data
  ↓
Highlights.lua applies textures to healthbars
```

**Caching Strategy:**
- Quest cache: `Classification.lua` caches quest objectives/items in `addon.questCache`
- Cache invalidates on any quest-related event (QUEST_ACCEPTED, QUEST_REMOVED, etc.)
- `ResetCaches()` called before collecting new highlights
- Prevents redundant tooltip scanning/parsing per frame

## Nameplate Healthbar Resolution

**Current structure (12.x, `Blizzard_NamePlates.xml`):**
```lua
plate.UnitFrame.HealthBarsContainer.healthBar  -- NamePlateHealthBarMixin
plate.UnitFrame.healthBar                      -- CompactUnitFrame alias of the same bar
```
The lookup is two field reads, so it is not cached. Unit frames are pooled by Blizzard and move between plates, so never cache a bar on the plate.

The health bar owns `selectedBorder` (atlas `UI-HUD-Nameplates-Selected`) and `deselectedOverlay`. Blizzard toggles both in `UpdateSelectionBorder()` when target or focus changes; `ShouldUseSelectedBorder()` is false for the Classic nameplate style.

## Tooltip Analysis Pattern

**Critical Implementation ([`Classification.lua`](../Classification.lua)):**
```lua
-- WoW doesn't provide APIs to check "is this mob a quest objective"
-- Must scan the actual tooltip text that appears on mouseover
local tooltip = _G["NextTargetTooltip"] or CreateFrame("GameTooltip", "NextTargetTooltip", nil, "GameTooltipTemplate")
tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
tooltip:SetUnit(unitToken)  -- e.g., "nameplate1"

-- Scan tooltip lines for quest indicators
for i = 1, tooltip:NumLines() do
    local line = _G["NextTargetTooltipTextLeft" .. i]
    local text = line and line:GetText()
    -- Look for: quest names, "Quest Item" text, progress bars
end
```

**Quest Item Detection:**
- Items shown in tooltip section with item icons
- Must check `GetTooltipData()` item sections
- Fallback: scan for tooltip region textures (item icons appear as textures)

## Highlight Style System

**Three Style Types:**
1. **"blizzard"**: Our copy of the `UI-HUD-Nameplates-Selected` atlas, anchored to Blizzard's `selectedBorder` so it matches native geometry (offset 0 = native size)
2. **"outline"**: Blizzard's `NamePlateFullBorderTemplate` (pixel-snapped via `PixelUtil`), with a local fallback mixin if the template is missing
3. **"glow"**: `ButtonGreenGlow-NineSlice-*` atlas pieces with additive blending

**Replacing Blizzard's selected border:**
- Each health bar gets `hooksecurefunc(bar, "UpdateSelectionBorder", ...)`. The hook runs right after Blizzard reacts to target/focus changes, so there is no flash of the native border.
- When `next` has a style for a bar (current target style, or quest style), it hides `selectedBorder` and draws its own.
- When it stops owning the bar, it re-shows `selectedBorder` based on target/focus. It only ever hides Blizzard's texture, never recolors it.
- Never call Blizzard's `UpdateSelectionBorder()` from addon code: it would run Blizzard's unit checks tainted.
- The current target style applies only to a targeted nameplate that also has a quest style (the game draws its own target highlight otherwise). Quest styles apply to classified hostile units.

**Per-Type Configuration:**
Each highlight type (currentTarget, questObjective, questItem, worldQuest, bonusObjective) has:
- `*Style`: "blizzard" | "outline" | "glow"
- `*Color`: {r, g, b, a}
- `*Thickness`: Border width (outline mode)
- `*Offset`: Spacing from healthbar edge

**Applying Highlights:**
`addon:RenderBarHighlight(bar, style)` draws a style on any status bar; a nil style hides it. The settings preview uses it too.

## Persistent Per-Bar Parts (Memory Management)

Each bar lazily creates its highlight parts once (`bar.next_highlight`: `blizzard` texture, `outline` border frame, `glow` textures) and shows or hides them on each update. There is no global texture pool and no re-creation per update. Because Blizzard pools unit frames, the number of bars stays bounded. `addon.hookedBars` tracks them all. `addon.barsByUnit` maps nameplate tokens to quest-styled bars so `NAME_PLATE_UNIT_REMOVED` can clear a style before the unit frame is reused.

## Database Migrations

**Migration Pattern ([`Database.lua:40-50`](../Database.lua#L40-L50)):**
```lua
-- Old setting names → New setting names
local MIGRATION_MAP = {
    showCurrentTarget = "currentTargetEnabled",
    currentBorderThickness = "currentTargetThickness",
    -- ...
}
```

When `DB_VERSION` increments:
1. Remap old keys to new keys
2. Sanitize style values (convert invalid values to "blizzard")
3. Merge new defaults for missing keys

**Why:** Users upgrading from old versions shouldn't lose settings or crash.

## Debug Window

**Usage:** `/next debug` toggles debug overlay

**Displays:**
- List of all visible nameplates
- Unit name, unit token (nameplate1, nameplate2, etc.)
- Classification result (Quest Objective, Quest Item, World Quest, etc.)
- Quest name/ID associated with highlight

**Implementation:** Real-time table in draggable frame, updates with every `UpdateHighlight()` call.

## Instance Detection

**Key Optimization:**
```lua
local inInstance, instanceType = IsInInstance()
if inInstance then
    self:ClearHighlights()
    return
end
```

Highlights disabled in dungeons/raids (no quest nameplates there). Prevents wasted processing and visual clutter.

## Slash Commands

- `/next` - Show help, open settings
- `/next config` - Open settings panel
- `/next toggle` - Enable/disable addon
- `/next debug` - Toggle debug window

**Sanitization:** All commands go through `sanitizeCommand()` to handle nil input, trim whitespace, lowercase.

## Common WoW API Patterns

**Event Registration:**
```lua
addon.frame:RegisterEvent("QUEST_LOG_UPDATE")
addon.frame:SetScript("OnEvent", function(_, event, ...)
    eventHandlers[event](addon, ...)
end)
```

**Debouncing Updates:**
```lua
-- Prevent update spam when multiple events fire rapidly
if self.pendingUpdate then return end
self.pendingUpdate = true
C_Timer.After(0.05, function()
    addon.pendingUpdate = false
    addon:UpdateHighlight()
end)
```

**Settings Panel Registration (Dragonflight+):**
```lua
local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
Settings.RegisterAddOnCategory(category)
```

## Testing Workflows

1. **Quest Objective Test:**
   - Accept quest with kill objectives
   - Target mob → verify highlight color matches setting
   - Verify current target highlight overrides quest highlight

2. **Quest Item Test:**
   - Accept quest requiring item drops
   - Target mob that drops item but isn't kill objective
   - Verify different color from objective highlight

3. **World Quest Test:**
   - Activate world quest in zone
   - Target relevant mob
   - Verify world quest highlight color

4. **Style Test:**
   - Change style to "outline" → verify border appears
   - Change to "glow" → verify glow effect
   - Change to "blizzard" → verify native targeting texture

5. **Debug Window:**
   - Enable debug window
   - Target various mobs
   - Verify classification matches visual highlights

**Common Issues:**
- Highlights not showing: Check if in instance (auto-disabled), verify nameplate addon compatibility
- Wrong mob highlighted: Quest cache stale → reload UI
- Performance lag: Texture pool full → clear highlights forces cleanup
