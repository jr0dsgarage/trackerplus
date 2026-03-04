# TrackerPlus - Development Instructions

## Project Overview
TrackerPlus is an advanced quest and objective tracker replacement for World of Warcraft (Retail). It compiles quests, achievements, scenarios, and monthly activities into a unified, customizable, scrollable UI.

## Architecture

### Core Components
- **Core.lua**: Central hub. Handles addon initialization (ddon:Initialize), event registration (RegisterEvents), and the main update loop (RequestUpdate). Uses a debounce pattern (0.1s) for updates.
- **TrackerFrame.lua**: Manages the main UI window. Implements custom scrolling logic (no visible scrollbars), button pooling, and drag/resize functionality.
- **Database.lua**: Manages saved variables (TrackerPlusDB) with deep copy utilities and safe defaults.
- **Settings.lua**: Implements the configuration UI using a custom scrollable options panel.
- **DebugFrame.lua**: Provides an in-game logging window for development (toggle with /tpdebug).

### Data Flow
1. **Event Trigger**: WoW fires events (e.g., QUEST_LOG_UPDATE, ZONE_CHANGED).
2. **Aggregation**: Core.lua's CollectTrackables calls specific collectors:
   - CollectQuests() (Standard & World Quests)
   - CollectAchievements()
   - CollectScenarioObjectives() (Dungeons/Delves/Scenarios)
   - CollectMonthlyActivities() (Traveler's Log)
   - CollectEndeavors() (Player Housing/Profs)
   - CollectAutoQuests() (Popups)
3. **Processing**: Items are sorted (SortTrackables) and grouped (GroupTrackables).
4. **Rendering**: TrackerFrame.lua updates the display view (UpdateTrackerDisplay), allocating buttons from the 	rackableButtons pool.

## Developer Workflow

### Debugging
- **Debug Window**: Type /tpdebug to open the internal debug log.
- **Logging**: Use ddon:Log("Message", ...) to write to the debug window.
- **Console**: ddon.Print(...) writes to the standard chat frame.

### Testing
- **Reloading**: Logic changes require a UI reload (/reload).
- **Slash Commands**:
  - /tp or /trackerplus: Opens settings.
  - /tp toggle: Toggles visibility.
  - /tp lock: Locks the frame.
  - /tp reset: Resets database.

## Coding Conventions

### Namespace
Start every file with:
`lua
local addonName, addon = ...
`
- ddon is the global service container.
- Do not check for ddon existence; it is guaranteed by the TOC loader.

### UI Patterns
- **No XML**: All frames are created in Lua using CreateFrame.
- **Button Pooling**: Reuse metadata frames. See secureButtons and 	rackableButtons in TrackerFrame.lua.
- **ScrollFrame**: Custom implementation where contentFrame is moved. No standard scrollbars.

### Event Handling
- Register events in Core.lua.
- Trigger updates via ddon:RequestUpdate() to ensure coalescing.

## Integration & APIs
- **Target Interface**: WoW Retail (12.0.0.0 per TOC).
- **Key APIs**:
  - C_QuestLog: GetInfo, GetQuestObjectives, IsComplete.
  - C_Scenario: GetInfo, GetStepInfo.
  - GetTrackedAchievements: Achievement IDs.
- **Dependencies**: None (Self-contained).

## Key Files
- [TrackerPlus.toc](TrackerPlus.toc): Manifest.
- [Core.lua](Core.lua): Logic heart.
- [TrackerFrame.lua](TrackerFrame.lua): UI implementation.

## Regression Guardrails (Do Not Reintroduce)

### Active Quest item icon parity
- Active Quest rows (`type == "supertrack"`) must resolve quest-item icons using the same data path as normal quest rows.
- In `TrackerRenderer.lua`, keep/maintain fallback propagation from matching quest ID item data when `supertrack` lacks `item.link` or `item.texture`.
- `RenderTrackableItem` must always attempt icon resolution in this order when needed: cached texture -> `GetItemIcon(link)` -> `GetItemInfoInstant(link)` iconID -> fallback question-mark icon.

### World Quests header lifecycle
- The floating/dangling `World Quests` text must never remain after a world quest ends.
- In `Core.lua` `CollectQuests`, treat quests under the quest-log `WORLD_QUESTS` header as world-quest entries even if `C_QuestLog.IsWorldQuest` is transiently false.
- Completed/ended world quests should be excluded from collection immediately so the grouped header cannot linger.

### Rendering ownership notes
- Pinned section rendering (Active Quest / Bonus / World Quests) is in `TrackerRenderer.lua`; do not assume `TrackerFrame.lua` owns section content lifecycle.
- Any header-style or pooled-button changes must preserve hide/cleanup behavior for recycled buttons across section show/hide transitions.
