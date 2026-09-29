# TrackerPlus

**Advanced Quest & Objective Tracker Replacement for World of Warcraft**

TrackerPlus is a comprehensive replacement for WoW's built-in quest tracker, offering advanced categorization, customization, and a clean, modern interface.

## Features

### 🎯 Core Functionality
- **Complete Quest Tracker Replacement** - Fully replaces the default Blizzard tracker
- **Smart Categorization** - Automatically groups quests by zone and category
- **Multiple Trackable Types**:
  - Regular Quests (Campaign, Side quests, etc.)
  - World Quests
  - Tracked Achievements with criteria progress
  - Bonus Objectives
  - Scenario/Dungeon Objectives
  - Profession Quest Tracking

### 🎨 Customization
- **Color Picker Integration** - Customize every color:
  - Background color with alpha transparency
  - Border color (optional border display)
  - Header text color
  - Quest text color
  - Objective text color
  - Completed objective color (green by default)
  - Failed quest color (red by default)
  
- **Font Customization**:
  - Adjustable font size (8-24pt)
  - Header font size (10-28pt)
  - Multiple font face options
  - Outline options (None, Outline, Thick, Monochrome)

- **Frame Customization**:
  - Adjustable width (150-500px)
  - Adjustable height (200-800px)
  - Frame scale (0.5x - 2.0x)
  - Optional border with customizable size
  - Movable and lockable position
  - No visible scrollbar (uses mouse wheel)

### 📊 Display Options
- **Quest Information**:
  - Show/hide quest levels
  - Show/hide quest type badges (Elite, Dungeon, Raid, etc.)
  - Distance to objective in yards
  - Objective progress (X/Y format)
  - Completed objectives highlighted in green

- **Organization**:
  - Group by zone
  - Group by category
  - Multiple sort methods:
    - Distance (closest first)
    - Level (highest first)
    - Name (alphabetical)
    - Manual (track order)

### 🎮 Interaction
- **Left-Click Quest** - Opens quest details/map location
- **Right-Click Quest** - Untrack quest (configurable)
- **Mouse Wheel** - Scroll through tracked quests
- **Drag Frame** - Move tracker when unlocked
- **Hover Tooltips** - Full quest/achievement details

### ⚙️ Advanced Features
- **Smart Visibility**:
  - Hide in dungeons/raids (optional)
  - Hide during combat (optional)
  - Auto-fade when empty (optional)
  - Manual enable/disable toggle

- **Performance Optimized**:
  - Debounced updates (0.1s default)
  - Efficient quest data caching
  - Smart event handling
  - Minimal memory footprint

- **Quest Type Coloring**:
  - Normal quests - Gold
  - Elite quests - Orange
  - Dungeon quests - Blue
  - Raid quests - Purple
  - PvP quests - Red
  - World quests - Cyan
  - Profession quests - Green

### 🎯 Nameplate Highlights
Highlights the nameplates of enemies you need for your active quests, using the in-game tooltip to decide what counts and the quest log to pick the color:
- **Quest Objectives** - standard kill/collect quests
- **Quest Items** - mobs that drop quest items, even when they aren't a kill objective
- **World Quests** and **Bonus Objectives** - targets for active world quests and area bonus objectives
- **Current Target** - when your target is a quest objective, draws the Current Target style instead of the quest highlight; other targets keep the game's own target highlight
- **Styles** - Blizzard (the game's own selection texture), Outline, Glow, or Rounded, each with its own color, thickness, and offset
- Configure under **TrackerPlus → Nameplates** in the Settings panel (with a live preview plate), or `/tp nameplates`

## Commands

- `/trackerplus` or `/tp` - Open settings panel
- `/tp toggle` - Enable/disable tracker
- `/tp lock` - Lock frame position
- `/tp unlock` - Unlock frame to move
- `/tp reset` - Reset all settings to defaults
- `/tp nameplates` - Open Nameplates settings
- `/tp nameplates toggle` - Enable/disable nameplate highlights
- `/tp nameplates debug` - Toggle the nameplate debug window

## Installation

1. Extract the `TrackerPlus` folder to your WoW addons directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```
2. Restart World of Warcraft or reload UI (`/reload`)
3. Type `/tp` to configure

## Default Key Features

- **Scrollable without scrollbar** - Clean look with mouse wheel support
- **No border by default** - Minimalist design (can be enabled)
- **Semi-transparent background** - Blends with UI (fully customizable)
- **Zone-based grouping** - Automatically organizes by location
- **Distance sorting** - Closest quests appear first
- **All trackable types enabled** - Quests, achievements, world quests, etc.

## Configuration

Access the full settings panel via:
- `/tp` or `/trackerplus`
- Game Menu → Interface → AddOns → TrackerPlus

### Settings Sections

1. **General Settings** - Enable/disable, lock frame
2. **Appearance** - Frame size, scale, border options
3. **Font Settings** - Font size and header size
4. **Display Options** - Quest level, type, distance, headers
5. **Trackable Types** - Toggle quest types, achievements, etc.
6. **Advanced Options** - Hide in instance/combat, tooltips
7. **Color Settings** - Comprehensive color picker interface
8. **Nameplates** - Nameplate highlight styles and preview

## Technical Details

- **Interface Version**: 120000 (WoW 12.0.0.0)
- **API Compliance**: Uses latest WoW 12.0 APIs
- **SavedVariables**: `TrackerPlusDB`
- **Load Order**: Database → Core → TrackerFrame → Settings

## Architecture

- **Database.lua** - Settings persistence and defaults management
- **Core.lua** - Event handling and the update loop
- **Settings.lua** - Modern WoW settings panel with full customization
- **Data/** - Collecting quests, achievements and other trackables; objective parsing, quest colors, sorting
- **Render/** - Drawing each tracker section (active quest, campaign, scenarios, world quests, ...)
- **UI/** - The tracker window, its title bar, button pooling and "Match Game Tracker"
- **Map/** - World map quest pin colors and quest-area highlighting
- **Nameplates/** - Quest target highlights on enemy nameplates

## Compatibility

- **WoW Version**: 12.0.0.0+ (The War Within and beyond)
- **No conflicts** with other quest addons
- Works with all quest types including campaign, world quests, and achievements

## Credits

Created by **jr0dsgarage**

Matches the design philosophy of the `next` and `knack` addon suite.

## License

All rights reserved. For personal use only.

---

**Enjoy enhanced quest tracking with TrackerPlus!** 🎯
