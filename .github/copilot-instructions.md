# TrackerPlus - Development Instructions

## Project Overview
TrackerPlus is an advanced quest and objective tracker replacement for World of Warcraft (Retail). It compiles quests, achievements, scenarios, and monthly activities into a unified, customizable, scrollable UI.

## Architecture

### File Structure & Load Order (per TOC)

```
Database.lua              – Saved variables, defaults, deep-copy utilities
DebugFrame.lua            – In-game debug log window (/tpdebug)
Core.lua                  – Initialization, event handling, data collectors, update loop
TrackerUtils.lua          – Button pooling, trackable sorting/grouping, header toggle
RendererUtils.lua         – Shared renderer utilities (frame hijacking, debug overlays)
ObjectiveParser.lua       – Objective text/progress parsing, quest-item resolution
RenderItem.lua            – Single quest/achievement row rendering
RenderAutoQuests.lua      – Auto-quest popup stealing from Blizzard frames
RenderScenario.lua        – Scenario/delve/dungeon section (Blizzard hijack + manual)
RenderActiveQuest.lua     – Super-tracked "Active Quest" section
RenderBonusObjectives.lua – Bonus objectives section (Blizzard hijack + manual)
RenderWorldQuests.lua     – World quests section (Blizzard hijack + manual)
RenderHeaders.lua         – Normal trackable list (major/minor headers + quest items)
TrackerRenderer.lua       – Orchestrator: categorises trackables, delegates to sections
TrackerFrame.lua          – Main UI window, scrolling, drag/resize, layout anchors
Settings.lua              – Configuration UI (custom scrollable options panel)
```

### Core Components
- **Core.lua**: Central hub. Handles addon initialization (`addon:Initialize`), event registration (`RegisterEvents`), and the main update loop (`RequestUpdate`). Uses a debounce pattern (0.1s) for updates.
- **TrackerFrame.lua**: Manages the main UI window. Implements custom scrolling logic (no visible scrollbars), button pooling, drag/resize, and layout anchoring (`UpdateLayoutAnchors`, `UpdateTrackerAppearance`).
- **TrackerUtils.lua**: Button pool management (`ResetButtonPool`, `GetOrCreateButton`, `GetOrCreateSecureButton`, `FinalizeButtonPool`), trackable grouping (`OrganizeTrackables`), header collapse/expand (`ToggleHeader`), click handling (`OnTrackableClick`).
- **Database.lua**: Manages saved variables (TrackerPlusDB) with deep copy utilities and safe defaults.
- **Settings.lua**: Implements the configuration UI using a custom scrollable options panel.
- **DebugFrame.lua**: Provides an in-game logging window for development (toggle with `/tpdebug`).

### Renderer Architecture
The rendering pipeline is split into an orchestrator and specialised section files:

- **TrackerRenderer.lua** (orchestrator, ~220 lines): `UpdateTrackerDisplay(trackables)` categorises incoming trackables into temporary arrays (scenarios, auto-quests, super-tracked, bonus, world quests, remaining) and delegates to section renderers. Also contains `ShowTrackableTooltip`.
- **RendererUtils.lua**: Shared utilities used across all renderer files. Exposes functions on the `addon` table (not methods): `addon.GetScenarioTrackerSource()`, `addon.EnsureFrameVisible()`, `addon.EnsureHijackedParent()`, `addon.RestoreHijackedParent()`, `addon.ResetAnchorState()`, `addon.DebugLayout()`, `addon.ClearArray()`. Also exposes `addon:UpdateSectionDebugBoxes()`.
- **ObjectiveParser.lua**: Exposes `addon.ParseObjectiveDisplay(item, obj, objIndex)` (with internal caching) and `addon.ResolveTrackableItemData(item)`.
- **RenderItem.lua**: Exposes `addon:RenderTrackableItem(parent, item, yOffset, indent)` → returns `height`. Renders a single quest/achievement row with POI button, item button, group finder icon, objectives, and progress bars.
- **Section Files**: Each section file exposes a single method on `addon` and returns its Y offset:
  - `addon:RenderAutoQuestSection(autoQuests)` – auto-quest popups
  - `addon:RenderScenarioSection()` → `scenarioYOffset` – uses `self.currentScenarios`
  - `addon:RenderActiveQuestSection(superTrackedItems)` → `aqYOffset`
  - `addon:RenderBonusSection(bonusObjectives)` → `bonusYOffset`
  - `addon:RenderWorldQuestSection(worldQuestItems)` → `wqYOffset`
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
Several sections (Scenario, Bonus Objectives, World Quests, Auto-Quest Popups) use a hijacking pattern where Blizzard's native tracker frames are reparented into TrackerPlus containers. Key utilities in `RendererUtils.lua`:
- `EnsureHijackedParent` — reparents a Blizzard frame, saving original parent
- `RestoreHijackedParent` — returns it to its original parent
- `ResetAnchorState` — clears cached anchor/width state for re-anchoring
- Each section has both a Blizzard-hijack path and a manual-render fallback

## Developer Workflow

### Debugging
- **Debug Window**: Type `/tpdebug` to open the internal debug log.
- **Logging**: Use `addon:Log("Message", ...)` to write to the debug window.
- **Console**: `addon.Print(...)` writes to the standard chat frame.
- **Layout Debugging**: `addon.DebugLayout(self, fmt, ...)` logs layout diagnostics. `addon:UpdateSectionDebugBoxes()` renders visual overlays.

### Testing
- **Reloading**: Logic changes require a UI reload (`/reload`).
- **Slash Commands**:
  - `/tp` or `/trackerplus`: Opens settings.
  - `/tp toggle`: Toggles visibility.
  - `/tp lock`: Locks the frame.
  - `/tp reset`: Resets database.

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
- **Target Interface**: WoW Retail (12.0.0.0 per TOC).
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
Several sections of TrackerPlus "borrow" Blizzard's native tracker frames (ScenarioObjectiveTracker, BonusObjectiveTracker, WorldQuestTrackerButton, auto-quest popups) and reparent them into TrackerPlus containers instead of rendering from scratch. This pattern is efficient but introduces complexity around ownership and anchor stability.

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

**Solution Pattern** (implemented in `RenderScenario.lua`, `RenderAutoQuests.lua`, `RenderBonusObjectives.lua`, `RenderWorldQuests.lua`):
1. **Unconditional anchor normalization**: Run anchor enforcement **every single render tick**, not just when drift is detected.
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
4. **No conditional gates**: Do not gate the normalization behind `if needsAnchorUpdate then ... end`. Blizzard adds anchors too fast for conditional checks to catch them.

**Why this works**: By unconditionally normalizing on every frame, we suppress Blizzard's secondary anchor additions faster than they can cause visible drift (the visual rendering passes between our anchor fix and Blizzard's next injection).

**Prevention**: If adding a new section that hijacks Blizzard frames, always implement aggressive anchor normalization for that frame. Test by watching the frame visually for popping/jumping, and log multi-point detections to verify the fix is triggering.

### Rendering ownership notes
- Pinned section rendering lives in dedicated section files (`RenderActiveQuest.lua`, `RenderBonusObjectives.lua`, `RenderWorldQuests.lua`), **not** in `TrackerFrame.lua`.
- The orchestrator (`TrackerRenderer.lua`) owns the render lifecycle: reset pool → categorise → delegate sections → update layout anchors → render normal trackables → finalise pool.
- Any header-style or pooled-button changes must preserve hide/cleanup behavior for recycled buttons across section show/hide transitions.
- Each section file is self-contained: it manages its own frame height, show/hide state, and Blizzard frame hijacking lifecycle.
