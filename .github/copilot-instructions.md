# TrackerPlus - Development Instructions

## Project Overview
TrackerPlus is an advanced quest and objective tracker replacement for World of Warcraft. The `.toc` declares Interface versions `120007, 120100, 16001` (the addon is currently installed/developed under `_classic_beta_`, not exclusively Retail). It compiles quests, achievements, scenarios, and monthly activities into a unified, customizable, scrollable UI.

## Architecture

### File Structure & Load Order (per TOC)

```
Database.lua              – Saved variables, defaults, deep-copy utilities
DebugFrame.lua            – In-game debug log window (/tpdebug toggles logging; window opens from Settings)
Core.lua                  – Initialization, event handling, data collectors, update loop
TrackerUtils.lua          – Button pooling, trackable sorting/grouping, header toggle
MapPOIColor.lua           – Difficulty-coloured circles on Blizzard's world map quest pins (hooks only; draws no UI of its own)
RendererUtils.lua         – Shared renderer utilities (debug overlays only — see note below)
ObjectiveParser.lua       – Objective text/progress parsing, quest-item resolution
RenderItem.lua            – Single quest/achievement row rendering
RenderAutoQuests.lua      – Auto-quest popup stealing from Blizzard frames (Blizzard hijack)
RenderScenario.lua        – Scenario/delve/dungeon section (Blizzard hijack only; no manual fallback)
RenderActiveQuest.lua     – Super-tracked "Active Quest" section
RenderFollowTheArrow.lua  – Follow-the-Arrow guide section (between Active Quest and Campaign)
RenderCampaign.lua        – Campaign quest section (pinned, below Active Quest/FTA)
RenderBonusObjectives.lua – Bonus objectives section (manual render only; does not hijack a Blizzard frame)
RenderWorldQuests.lua     – World quests section (manual render only; does not hijack a Blizzard frame)
RenderHeaders.lua         – Normal trackable list (major/minor headers + quest items)
TrackerRenderer.lua       – Orchestrator: categorises trackables, delegates to sections
TrackerFrame.lua          – Main UI window, scrolling, drag/resize, layout anchors
Settings.lua              – Configuration UI (custom scrollable options panel)
```

### Core Components
- **Core.lua**: Central hub. Handles addon initialization (`addon:Initialize`), event registration (`RegisterEvents`), and the main update loop (`RequestUpdate`). Uses a debounce pattern for updates (`db.updateInterval`, default `0.15`s in `Database.lua`; adaptive — faster during active objective churn, slower when idle/minimized/hidden).
- **TrackerFrame.lua**: Manages the main UI window. Implements custom scrolling logic (no visible scrollbars), button pooling, drag/resize, and layout anchoring (`UpdateLayoutAnchors`, `UpdateTrackerAppearance`).
- **TrackerUtils.lua**: Button pool management (`ResetButtonPool`, `GetOrCreateButton`, `GetOrCreateSecureButton`, `FinalizeButtonPool`), trackable grouping (`OrganizeTrackables`), header collapse/expand (`ToggleHeader`), click handling (`OnTrackableClick`).
- **Database.lua**: Manages saved variables (TrackerPlusDB) with deep copy utilities and safe defaults.
- **Settings.lua**: Implements the configuration UI using a custom scrollable options panel.
- **DebugFrame.lua**: Provides an in-game logging window for development (toggle with `/tpdebug`).
- **MapPOIColor.lua**: Draws a circle around Blizzard's own world map quest pins (`QuestPinTemplate`) in the colour that quest's title has in the tracker, gated on `db.colorMapPOIsByDifficulty`, with `db.mapPOIOutlineStyle` (`"glow"` default/`"circle"`), `db.mapPOIOutlineThickness` (1–10px) and `db.mapPOIGlowOpacity` (glow only, a 0–1 fraction spent as up to `GLOW_MAX_PASSES` stacked draws — the glow art fades by design and never reaches full alpha in one pass, so the pass count is how 1.0 gets to "solid"; keep that detail behind the setting). The circle is a solid disc (`common-mask-circle`, falling back to `CircleMaskScalable`) drawn *behind* the pin and oversized by the thickness on each side — the pin's own banner occludes the middle, and the exposed margin is the ring. Nothing can punch a hole in a texture, so do not "simplify" this into a single ring texture unless one with adjustable thickness exists. The glow style must keep its `SetDesaturated(true)`: `UI-QuestPoi-OuterGlow` is painted gold (the game recolours it by swapping atlases per quest classification, never by tinting), and since `SetVertexColor` multiplies, tinting it undesaturated turns green quests muddy and grey ones gold. The disc is first inset by `COIN_INSET`, the transparent margin baked into the POI banner atlases, which no API reports and which is therefore an empirically calibrated constant — without it the ring comes out that margin *wider* than asked for at every setting. It owns no frames of its own: it hooks `WorldMapFrame:RegisterPin` (the last call in `AcquirePin`, so it sees every pin the map hands out) and, per pin, `UpdateButtonStyle` (called by `QuestDataProviderMixin:AddQuest` *after* the pin's quest is set, and again on every restyle). Outline textures and hook bookkeeping live in weak-keyed module tables, **not** as fields written onto the pooled Blizzard pins. Colour comes from `addon:GetQuestTitleColorByQuestID` (`Core.lua`), which rebuilds the `C_QuestLog.GetInfo` table `GetQuestColor` expects and then applies the super-track gold via `ApplySuperTrackedTitleColor`. **Quest title colour is decided in exactly one place.** `RenderItem.lua` calls the same `ApplySuperTrackedTitleColor`; do not reintroduce an inline override in the row renderer — when the gold lived only there, a super-tracked quest was gold in the tracker but a different colour on its map pin. Difficulty colours come from `C_PlayerInfo.GetContentDifficultyQuestForPlayer` (via `GetRelativeDifficultyColor` in `Core.lua`), mapped to `QuestDifficultyColors` by `Enum.RelativeContentDifficulty` **member name**, never by hardcoded number. Do not "simplify" this back to `GetQuestDifficultyColor(level)`: on this client that function has no reachable green band at all — its green check goes through `GetQuestGreenRange`, which returns nil here, so it returns gold for roughly −4 to +2 levels and drops straight to grey. It is also level-based and so cannot rate a scaling quest. The level-based path survives only as `GetDifficultyColorForLevel`, a fallback for clients that lack the newer API; it looks `GetQuestDifficultyColor` up **as a global on every call** — do not "optimise" it into a file-local alongside the others at the top of `Core.lua`, which is what silently disabled difficulty colouring entirely (the global isn't guaranteed to exist when the file loads, and the captured nil made the guarding branch fall through to the flat quest colour for the whole session). `GetQuestColor` also has **no** "quest is complete" branch by design: titles and pins show the level difference right up to turn-in, and `db.completeColor` green belongs to finished *objective lines* only. Completion is conveyed by the POI turn-in icon, not by recolouring the title.

### Renderer Architecture
The rendering pipeline is split into an orchestrator and specialised section files:

- **TrackerRenderer.lua** (orchestrator): `UpdateTrackerDisplay(trackables)` categorises incoming trackables into temporary arrays (scenarios, auto-quests, super-tracked, campaign, bonus, world quests, remaining) plus a `questItemDataByID` map, and delegates to section renderers. Also contains `ShowTrackableTooltip`.
- **RendererUtils.lua**: Only exposes `addon.DebugLayout(owner, fmt, ...)`, `addon.ClearArray(t)`, and `addon:UpdateSectionDebugBoxes()`. There is **no** shared hijack helper API (`EnsureHijackedParent`/`RestoreHijackedParent`/`EnsureFrameVisible`/`ResetAnchorState`/`GetScenarioTrackerSource` do not exist anywhere in the codebase) — each hijacking section file implements its own bespoke borrow/restore/anchor-guard logic. See "Blizzard Frame Hijacking" below.
- **ObjectiveParser.lua**: Exposes `addon.ParseObjectiveDisplay(item, obj, objIndex)` (with internal caching, keyed in part on text *lengths* to catch stage-transition text changes without embedding the protected string itself) and `addon.ResolveTrackableItemData(item)`.
- **RenderItem.lua**: Exposes `addon:RenderTrackableItem(parent, item, yOffset, indent)` → returns `height`. Renders a single quest/achievement row with POI button, item button, group finder icon, objectives, and progress bars. Secure item-button attribute/geometry mutation is skipped entirely while `InCombatLockdown()` is true.
- **Section Files**: Each section file exposes a single method on `addon` and returns its Y offset (with the exception noted below):
  - `addon:RenderAutoQuestSection(autoQuests)` – auto-quest popups (Blizzard hijack)
  - `addon:RenderScenarioSection()` → `scenarioYOffset` – uses `self.currentScenarios`; Blizzard hijack only, no manual-render fallback
  - `addon:RenderActiveQuestSection(superTrackedItems)` → `aqYOffset`
  - `addon:RenderFollowTheArrowSection()` – does not return/use a yOffset; `TrackerFrame.lua`'s `UpdateLayoutAnchors` reads `self.ftaFrame`'s height/shown state directly instead
  - `addon:RenderCampaignSection(campaignItems)` → `campaignYOffset`
  - `addon:RenderBonusSection(bonusObjectives)` → `bonusYOffset` (manual render; no Blizzard hijack)
  - `addon:RenderWorldQuestSection(worldQuestItems)` → `wqYOffset` (manual render; no Blizzard hijack)
  - `addon:RenderNormalTrackables(trackables, contentFrame)` → `renderedNormalItems, renderedHeaders, yOffset`

### Cross-File Function Exposure Pattern
- **`addon.FunctionName`** (plain function on the table): Used for stateless utilities that don't need `self`. Called as `addon.FunctionName(...)` or via local aliases like `local DebugLayout = function(...) return addon.DebugLayout(...) end`.
- **`addon:MethodName`** (method with implicit `self`): Used for functions that access addon state (`self.db`, `self.trackerFrame`, etc.). Called as `self:MethodName(...)`.
- Local aliases are defined at the top of each file for hot-path functions to avoid repeated table lookups.

### Data Flow
1. **Event Trigger**: WoW fires events (e.g., QUEST_LOG_UPDATE, ZONE_CHANGED).
2. **Aggregation**: Core.lua's `CollectTrackables` calls specific collectors:
   - `CollectQuests()` (Standard & World Quests)
   - `CollectAchievements()`
   - `CollectScenarioObjectives()` (Dungeons/Delves/Scenarios)
   - `CollectMonthlyActivities()` (Traveler's Log)
   - `CollectEndeavors()` (Player Housing/Profs)
   - `CollectAutoQuests()` (Popups)
3. **Processing**: Items are sorted (`SortTrackables`) and grouped (`OrganizeTrackables`).
4. **Rendering**: `TrackerRenderer.lua` orchestrates: categorises trackables → delegates to section renderers → finalises layout via `FinalizeButtonPool`, `UpdateTrackerAppearance`, `UpdateSectionDebugBoxes`.

### Blizzard Frame Hijacking
Only two sections actually reparent a Blizzard native tracker frame into a TrackerPlus container: **Scenario** (`RenderScenario.lua`, borrows `ScenarioObjectiveTracker`/`DelvesObjectiveTracker`/`DelveObjectiveTracker`) and **Auto-Quest Popups** (`RenderAutoQuests.lua`, borrows the popup frames). Bonus Objectives and World Quests are pure from-scratch manual renderers and never touch a Blizzard tracker frame. There is no shared hijack-helper API — each of the two hijacking files implements its own borrow/restore/anchor-guard logic (see `addon:RestoreAllHijackedFrames` in `Core.lua` for the real cross-file restore entry point used by `RenderScenario.lua`).

## Developer Workflow

### Debugging
- **Debug Logging Toggle**: `/tpdebug [on|off]` toggles `db.debugEnabled` (accepts `on|1|true`/`off|0|false`, or flips if no argument). It does **not** open the debug window.
- **Debug Window**: Opened via Settings → Debug → "Open Debug Window" (`addon:ShowDebug()`), not via `/tpdebug`.
- **Logging**: Use `addon:Log("Message", ...)` (info level) or `addon:LogAt(level, fmt, ...)` to write to the debug window's buffer.
- **Console**: `addon.Print(...)` writes to the standard chat frame.
- **Layout Debugging**: `addon.DebugLayout(owner, fmt, ...)` logs layout diagnostics (gated on `db.debugEnabled` **and** `db.layoutDebug`). `addon:UpdateSectionDebugBoxes()` renders visual overlays (gated on `db.debugSectionBoxes`).

### Testing
- **Reloading**: Logic changes require a UI reload (`/reload`).
- **Slash Commands** (`/trackerplus` and `/tp` are equivalent):
  - `/tp`, `/tp config`, `/tp settings`, or `/tp options`: Opens settings.
  - `/tp toggle`: Toggles visibility.
  - `/tp lock` / `/tp unlock`: Locks/unlocks the frame position.
  - `/tp reset`: Resets the database to defaults immediately — unlike the Settings-panel reset button, this skips the confirmation dialog.
  - `/tpdebug [on|off]`: Toggles debug logging (see above).

## Coding Conventions

### Namespace
Start every file with:
```lua
local addonName, addon = ...
```
- `addon` is the shared service container.
- Do not check for `addon` existence; it is guaranteed by the TOC loader.

### Adding New Renderer Sections
1. Create a new `Render<SectionName>.lua` file.
2. Define a single method: `function addon:Render<SectionName>Section(...) ... return yOffset end`.
3. Use local aliases for any `addon.*` utility functions at the top of the file.
4. Add the file to `TrackerPlus.toc` **before** `TrackerRenderer.lua`.
5. Call the new method from `TrackerRenderer.lua`'s `UpdateTrackerDisplay`.

### UI Patterns
- **No XML**: All frames are created in Lua using `CreateFrame`.
- **Button Pooling**: Reuse metadata frames. See `ResetButtonPool`, `GetOrCreateButton`, `GetOrCreateSecureButton`, `FinalizeButtonPool` in `TrackerUtils.lua`.
- **ScrollFrame**: Custom implementation where `contentFrame` is moved. No standard scrollbars.
- **Signature Caching**: Many UI elements use `_signature` string keys to skip redundant SetFont/SetPoint/SetAtlas calls when recycled frames already match.

### Event Handling
- Register events in `Core.lua`.
- Trigger updates via `addon:RequestUpdate()` to ensure coalescing.

## Integration & APIs
- **Target Interface**: `## Interface: 120007, 120100, 16001` per `TrackerPlus.toc` — this build targets both current Retail-family interface versions and a Classic-family (16xxx) one; the addon is currently developed/installed under `_classic_beta_`.
- **Key APIs**:
  - `C_QuestLog`: GetInfo, GetQuestObjectives, IsComplete.
  - `C_Scenario`: GetInfo, GetStepInfo, IsInScenario.
  - `C_SuperTrack`: GetSuperTrackedQuestID.
  - `C_TaskQuest`: GetTrackedQuestIDs (world quests).
  - `GetTrackedAchievements`: Achievement IDs.
  - `POIButtonUtil`: For quest POI icons.
- **Libraries**: LibSharedMedia-3.0 (LSM) for status bar textures in progress bars.
- **Dependencies**: None beyond optional LSM.

## Blizzard Frame Borrowing (Hijacking) Pattern
Two sections of TrackerPlus "borrow" Blizzard's native tracker frames — the scenario/delve/dungeon tracker (`ScenarioObjectiveTracker` / `DelvesObjectiveTracker` / `DelveObjectiveTracker`, in `RenderScenario.lua`) and auto-quest popups (in `RenderAutoQuests.lua`) — and reparent them into TrackerPlus containers instead of rendering from scratch. `BonusObjectiveTracker` and `WorldQuestTrackerButton` are **not** hijacked; Bonus Objectives and World Quests render manually from collected data. This pattern is efficient but introduces complexity around ownership and anchor stability.

### Borrowing Lifecycle
1. **Detection**: Search for active Blizzard tracker frame(s) that match criteria (shown, has content, etc.).
2. **Original State Capture**: Before reparenting, store the frame's original parent and anchor points:
   ```lua
   borrowedFrame._trackerPlusOriginalParent = borrowedFrame:GetParent()
   borrowedFrame._trackerPlusOriginalPoint1,
   borrowedFrame._trackerPlusOriginalRelTo,
   borrowedFrame._trackerPlusOriginalPoint2,
   borrowedFrame._trackerPlusOriginalX,
   borrowedFrame._trackerPlusOriginalY = borrowedFrame:GetPoint(1)
   ```
3. **Reparent**: Move frame under TrackerPlus parent (only outside combat):
   ```lua
   if not InCombatLockdown() then
       borrowedFrame:SetParent(self.containerFrame)
   end
   ```
4. **Anchor**: Apply our own anchor (see "Borrowed Blizzard Frame Anchor Stability" below).
5. **Restoration** (on teardown or tracker swap): Restore original parent and anchor:
   ```lua
   if frameToRestore._trackerPlusOriginalParent then
       frameToRestore:SetParent(frameToRestore._trackerPlusOriginalParent)
       frameToRestore:ClearAllPoints()
       if frameToRestore._trackerPlusOriginalPoint1 then
           frameToRestore:SetPoint(
               frameToRestore._trackerPlusOriginalPoint1,
               frameToRestore._trackerPlusOriginalRelTo,
               frameToRestore._trackerPlusOriginalPoint2,
               frameToRestore._trackerPlusOriginalX or 0,
               frameToRestore._trackerPlusOriginalY or 0
           )
       end
       -- Clear metadata
       frameToRestore._trackerPlusOriginal* = nil
   end
   ```
   `RenderScenario.lua` performs this restoration by calling `self:RestoreAllHijackedFrames()` (`Core.lua`), which walks the same candidate tracker names and restores anything carrying these `_trackerPlusOriginal*` fields — **not** a per-file `RestoreBorrowedFrames` method (no such method exists; a prior version called it anyway, so the borrowed frame was silently never returned — fixed). `RenderAutoQuests.lua` restores its own borrowed popups inline via `RestoreStaleBorrowedPopups`, which only clears a popup's tracking entry once the restore has actually happened (a popup that is currently protected, or that we're in combat during, stays tracked so a later call retries instead of the frame being silently forgotten while still reparented).

### Key Files
- [TrackerPlus.toc](../TrackerPlus.toc): Manifest and load order.
- [Core.lua](../Core.lua): Event handling, data collection, update loop.
- [TrackerRenderer.lua](../TrackerRenderer.lua): Render orchestrator.
- [TrackerFrame.lua](../TrackerFrame.lua): UI window, scrolling, layout.
- [TrackerUtils.lua](../TrackerUtils.lua): Button pooling, sorting, grouping.

## Regression Guardrails (Do Not Reintroduce)

### Active Quest item icon parity
- Active Quest rows (`type == "supertrack"`) must resolve quest-item icons using the same data path as normal quest rows.
- In `TrackerRenderer.lua` orchestrator, keep/maintain fallback propagation from matching quest ID item data when `supertrack` lacks `item.link` or `item.texture` (the `questItemDataByID` lookup).
- `RenderTrackableItem` (in `RenderItem.lua`) must always attempt icon resolution in this order: cached texture → `GetItemIcon(link)` → `GetItemInfoInstant(link)` iconID → fallback question-mark icon.

### World Quests header lifecycle
- The floating/dangling `World Quests` text must never remain after a world quest ends.
- In `Core.lua` `CollectQuests`, treat quests under the quest-log `WORLD_QUESTS` header as world-quest entries even if `C_QuestLog.IsWorldQuest` is transiently false.
- Completed/ended world quests should be excluded from collection immediately so the grouped header cannot linger.
- `RenderWorldQuests.lua` restores hijacked Blizzard frames when no world quests are tracked.

### Borrowed Blizzard Frame Anchor Stability (Critical)
**Problem**: When borrowing a Blizzard frame (e.g., ScenarioObjectiveTracker) into a TrackerPlus parent, Blizzard's internal update code **continuously injects secondary anchor points** each frame. If we only enforce our primary anchor conditionally, the frame drifts/jumps as competing anchors fight for control.

**Solution Pattern** (implemented in `RenderScenario.lua` and `RenderAutoQuests.lua` — the only two hijacking sections; `RenderBonusObjectives.lua`/`RenderWorldQuests.lua` never hijack a frame and so have no need for this pattern):
1. **Reactive hooks**: `hooksecurefunc` the borrowed frame's `SetPoint`, `ClearAllPoints`, **and `SetAllPoints`** (a distinct Frame API — easy to forget) so any Blizzard-triggered anchor mutation is caught and normalized immediately, regardless of render cadence.
   ```lua
   function EnsureFrameBorrowAnchor(owner, borrowedFrame)
       if not (owner and owner.parentFrame and borrowedFrame) then return end
       pcall(function()
           borrowedFrame:ClearAllPoints()
           borrowedFrame:SetPoint("TARGETPOINT", owner.parentFrame, "TARGETPOINT", xOffs, yOffs)
       end)
   end
   ```
2. **Multi-point detection**: Check `GetNumPoints()` on every call. If > 1, strip immediately.
3. **Protected calls**: Wrap anchor operations in `pcall()` to avoid errors when frames are protected during combat.
4. **Periodic call is dirty-gated, and that's fine**: the periodic per-render call to the normalize function (as opposed to the reactive hooks above) *does* early-return when nothing is dirty — this is a deliberate optimization, not a bug, because the hooks in point 1 already catch Blizzard's own anchor injections as they happen. Do not remove the dirty-gate as a "fix"; do make sure all three of `SetPoint`/`ClearAllPoints`/`SetAllPoints` are hooked.

**Why this works**: the reactive hooks suppress Blizzard's secondary anchor additions at the moment they happen, so the periodic call only needs to catch cases the hooks didn't (e.g. first borrow).

**Prevention**: If adding a new section that hijacks Blizzard frames, always implement aggressive anchor normalization for that frame. Test by watching the frame visually for popping/jumping, and log multi-point detections to verify the fix is triggering.

### Secure item-button pool aliasing (Critical)
- The secure-button pool (`secureButtons[]` in `TrackerUtils.lua`) is indexed by a flat per-render counter that only advances for rows with resolved item data. A row widget's `button.itemButton` reference must be set to `nil` (not just hidden) whenever that row has no item this render — leaving a stale non-nil reference lets it alias a secure button a *different* row legitimately claims later in the same or a later pass, hiding that other row's active item button out from under it.
- All secure item-button geometry/attribute mutation (`ClearAllPoints`/`SetPoint`/`SetSize`/`SetFrameLevel`/`SetAttribute`) in `RenderItem.lua` must be skipped entirely while `InCombatLockdown()` is true — an actionable `SecureActionButtonTemplate` button cannot have these safely mutated mid-combat. Leave existing state as-is; the next out-of-combat render catches up.

### Scenario hijack restore correctness (Critical)
- `RenderScenario.lua`'s restore call sites must invoke `self:RestoreAllHijackedFrames()` (the real implementation, in `Core.lua`) — never a `self.RestoreBorrowedFrames`-named method, which does not exist anywhere in the codebase. A prior version silently no-op'd here, permanently orphaning the borrowed Blizzard scenario tracker frame.
- The borrowed scenario tracker's alpha must be asserted (`SetAlpha(1)` + `SetIgnoreParentAlpha(true)`, on both the tracker and its `ContentsFrame`) every render, not just anchored — Blizzard's own stage-complete/criteria fade animations can otherwise leave it invisible while the section still reports a valid height.

### Rendering ownership notes
- Pinned section rendering lives in dedicated section files (`RenderActiveQuest.lua`, `RenderBonusObjectives.lua`, `RenderWorldQuests.lua`), **not** in `TrackerFrame.lua`.
- The orchestrator (`TrackerRenderer.lua`) owns the render lifecycle: reset pool → categorise → delegate sections → update layout anchors → render normal trackables → finalise pool.
- Any header-style or pooled-button changes must preserve hide/cleanup behavior for recycled buttons across section show/hide transitions.
- Each section file is self-contained: it manages its own frame height, show/hide state, and Blizzard frame hijacking lifecycle.
