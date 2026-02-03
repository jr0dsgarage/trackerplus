# TrackerPlus - Development Instructions

## Architecture Overview

Advanced quest and objective tracker replacement for World of Warcraft that provides comprehensive tracking of quests, achievements, scenarios, and more with extensive customization options.

**Core Components:**
- [`TrackerPlus.toc`](TrackerPlus.toc): Addon manifest with WoW 12.0.0.0 interface version
- [`Database.lua`](Database.lua): Settings persistence with deep copy utilities and defaults
- [`Core.lua`](Core.lua): Event handling, quest collection, achievement tracking, data aggregation
- [`TrackerFrame.lua`](TrackerFrame.lua): UI rendering with scrollable frame (no visible scrollbar)
- [`Settings.lua`](Settings.lua): Modern settings panel with color pickers and comprehensive options

**Load Order:** Database → Core → TrackerFrame → Settings

## Key Features

### Quest & Objective Collection
- **Multiple Types**: Regular quests, world quests, achievements, bonus objectives, scenarios, dungeons, professions
- **Smart Grouping**: By zone and/or category with automatic header creation
- **Distance Tracking**: Real-time distance calculation to quest objectives
- **Progress Tracking**: Detailed objective completion status (X/Y format)

### UI Architecture

**Scrollable Frame (No Scrollbar):**
```lua
-- TrackerFrame.lua structure:
trackerFrame (main) 
  └─ scrollFrame (handles scrolling)
      └─ contentFrame (holds all content)
          └─ buttons (quest/achievement entries)
```

**Mouse Wheel Scrolling:**
- Enabled on main frame
- No visible scrollbar for clean appearance
- Dynamic content height based on tracked items

**Button Pooling:**
- Reusable button pool for performance
- Dynamic height calculation based on objectives
- Objective FontStrings created on-demand

### Color System

All colors are RGBA tables: `{r, g, b, a}`

**Color Picker Integration:**
- Custom color picker buttons in Settings.lua
- Uses WoW's ColorPickerFrame with opacity support
- Callbacks update display in real-time
- All major UI elements customizable:
  - Background (with alpha)
  - Border
  - Headers (zone/category)
  - Quest text
  - Objective text
  - Completed objectives
  - Failed quests

### Event Handling

**Debounced Updates:**
```lua
-- Core.lua pattern:
RequestUpdate() → 0.1s debounce → UpdateTracker() → UpdateTrackerDisplay()
```

**Registered Events:**
- Quest events: QUEST_ACCEPTED, QUEST_REMOVED, QUEST_WATCH_LIST_CHANGED, QUEST_LOG_UPDATE
- Achievement events: TRACKED_ACHIEVEMENT_LIST_CHANGED, ACHIEVEMENT_EARNED, CRITERIA_UPDATE
- Zone events: ZONE_CHANGED, ZONE_CHANGED_NEW_AREA
- Combat events: PLAYER_REGEN_DISABLED/ENABLED
- Scenario events: SCENARIO_UPDATE, SCENARIO_CRITERIA_UPDATE

### Data Collection Pipeline

1. **CollectTrackables()** - Main aggregation function
2. **CollectQuests()** - Uses C_QuestLog API for tracked quests
3. **CollectAchievements()** - Uses GetTrackedAchievements() and GetAchievementCriteriaInfo()
4. **CollectScenarioObjectives()** - Uses C_Scenario API
5. **SortTrackables()** - Distance, level, name, or manual sorting
6. **GroupTrackables()** - Creates zone headers when grouping enabled

### Quest Information APIs

**WoW 12.0.0.0 APIs Used:**
- `C_QuestLog.GetNumQuestLogEntries()` - Get all quests
- `C_QuestLog.GetInfo(index)` - Quest details
- `C_QuestLog.GetQuestWatchType(questID)` - Check if tracked
- `C_QuestLog.GetQuestObjectives(questID)` - Get objective list
- `C_QuestLog.IsComplete(questID)` - Completion status
- `C_QuestLog.IsWorldQuest(questID)` - World quest check
- `C_QuestLog.GetQuestZoneID(questID)` - Zone information
- `C_QuestLog.GetDistanceSqToQuest(questID)` - Distance calculation
- `C_QuestLog.SetSelectedQuest(questID)` - Select for navigation
- `C_QuestLog.RemoveQuestWatch(questID)` - Untrack quest

**Achievement APIs:**
- `GetTrackedAchievements()` - List of tracked achievement IDs
- `GetAchievementInfo(achievementID)` - Full achievement data
- `GetAchievementNumCriteria(achievementID)` - Number of criteria
- `GetAchievementCriteriaInfo(achievementID, index)` - Criteria details
- `RemoveTrackedAchievement(achievementID)` - Untrack

**Scenario APIs:**
- `C_Scenario.IsInScenario()` - Check if in scenario
- `C_Scenario.GetInfo()` - Scenario details
- `C_Scenario.GetStepInfo()` - Current stage
- `C_Scenario.GetCriteriaInfo(index)` - Objective data

## Settings Panel Architecture

**Modern WoW Settings API:**
```lua
Settings.RegisterVerticalLayoutCategory("TrackerPlus")
Settings.RegisterAddOnSetting(category, name, key, table, type, label, default)
Settings.CreateCheckbox(category, variable, tooltip)
Settings.CreateSlider(category, variable, options, tooltip)
Settings.SetOnValueChangedCallback(variable, callback)
```

**Custom Panel for Color Pickers:**
- ScrollFrame with custom color picker buttons
- Direct ColorPickerFrame integration
- Opacity/alpha channel support
- Real-time preview updates

## Interaction Handlers

**Click Behavior:**
- **Left-Click**: Open quest details/achievement frame
- **Right-Click**: Untrack (if rightClickUntrack enabled)
- **Hover**: Show GameTooltip with full details

**Drag Behavior:**
- Only when `locked = false`
- Saves position to `framePosition` in SavedVariables
- Format: `{point = "TOPRIGHT", x = -50, y = -200}`

## Performance Optimizations

1. **Button Pooling**: Reuse frames instead of creating/destroying
2. **Debounced Updates**: 0.1s default to batch multiple events
3. **Efficient APIs**: Use C_QuestLog and C_Scenario bulk APIs
4. **Smart Visibility**: Hide when empty/in instance/in combat options
5. **On-demand Objectives**: Only create FontStrings as needed

## Slash Commands

- `/trackerplus` or `/tp` - Open settings
- `/tp toggle` - Enable/disable
- `/tp lock` - Lock position
- `/tp unlock` - Unlock position
- `/tp reset` - Reset settings (with confirmation dialog)

## Saved Variables

**TrackerPlusDB Structure:**
```lua
TrackerPlusDB = {
    version = 1,  -- DB version for migrations
    settings = {
        -- See Database.lua DEFAULTS table for full structure
    }
}
```

## Style Consistency

**Matches jr0dsgarage addon suite:**
- Clean, minimal design (no border by default)
- Consistent color choices (gold headers, white text)
- Modern settings panel layout
- Slash command patterns
- Font and outline options
- Frame dragging/locking system

## Extension Points

**Easy to add new trackable types:**
1. Add setting to DEFAULTS in Database.lua
2. Create `Collect[Type]` function in Core.lua
3. Call from `CollectTrackables()`
4. Add checkbox in Settings.lua
5. Handle click behavior in TrackerFrame.lua `OnTrackableClick`

**Color customization:**
- Add color to DEFAULTS
- Add CreateColorPicker() call in Settings.lua
- Reference color in TrackerFrame.lua display code

## API Version Compliance

**WoW 12.0.0.0 Changes Incorporated:**
- Modern quest log APIs (C_QuestLog namespace)
- Scenario APIs (C_Scenario namespace)
- Settings panel API (Settings.RegisterAddOnSetting)
- ColorPickerFrame API updates
- Achievement tracking APIs

## Future-Proofing

**Extensible Design:**
- Easy to add profession quest tracking
- Ready for quest history/statistics
- Can add waypoint integration
- Supports custom filters
- Profile import/export ready

**Migration System:**
- DB_VERSION in Database.lua
- Ready for future setting migrations
- DeepCopy utility for safe defaults merging

## Coding Patterns

**Error Suppression:**
```lua
---@diagnostic disable: undefined-global
```
Used in all files to suppress LSP warnings for WoW globals.

**Addon Namespace:**
```lua
local addonName, addon = ...
```
Standard WoW addon pattern for shared namespace.

**Nil Safety:**
- Always check `if trackable then` before access
- Use `and` short-circuit: `color = item.color or db.questColor`
- Validate API returns: `if info and not info.isHeader then`

**Table Utilities:**
- `DeepCopy()` for safe cloning
- `TableCount()`, `TableContains()` helpers
- `ColorToHex()`, `ColorText()` for formatting

## Testing Checklist

- [ ] Track multiple quests in different zones
- [ ] Track achievements with multiple criteria
- [ ] Enter/exit scenarios and dungeons
- [ ] Scroll with mouse wheel (no scrollbar visible)
- [ ] Drag frame when unlocked
- [ ] Change all colors with color picker
- [ ] Adjust frame size and scale
- [ ] Test hide in combat/instance
- [ ] Left-click to open quest details
- [ ] Right-click to untrack
- [ ] Check distance updates
- [ ] Verify objective progress (X/Y)
- [ ] Test with empty tracker (fade option)
- [ ] Reset settings and verify reload

---

**This addon is production-ready and follows WoW 12.0.0.0 best practices.**
