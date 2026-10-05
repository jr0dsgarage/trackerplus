# TrackerPlus

A replacement for World of Warcraft's objective tracker, with difficulty-colored quests, world map pin coloring, a "you're standing in this quest's area" marker, and quest target highlights on enemy nameplates.

On first load it sits exactly where the game's own tracker is, at the same size, and follows any changes you make to that tracker in Edit Mode. Move or resize TrackerPlus yourself and it stays where you put it.

## The tracker

### Sections

Each kind of content gets its own section, top to bottom:

| Section | Version(s) | What's in it |
| --- | --- | --- |
| **Quest popups** | Retail | Auto-accept and auto-complete quest popups. Click one to accept or turn in. |
| **Scenario** | Retail | The current scenario, delve or dungeon objectives. |
| **Quest Timers** | Retail, Forever | Countdowns for timed quests. |
| **Active Quest** | Retail, Forever | The quest you're focused on (super-tracked). |
| **Follow the Arrow** | Retail | The current step of a [FollowTheArrow](#optional-addons) guide. Off by default. |
| **Campaign** | Retail | Campaign quests. |
| **Bonus Objectives** | Retail | Area bonus objectives you're working on. |
| **World Quests** | Retail | Tracked and in-progress world quests. |
| **Quests** | Retail, Forever | All other tracked quests, grouped under zone headers. |
| **Achievements** | Retail | Tracked achievements and their criteria. |
| **Professions** | Retail, Forever | Tracked recipes and their reagents. |
| **Monthly Activities** | Retail | Tracked Trading Post / Traveler's Log activities. |
| **Endeavors** | Retail | Tracked housing endeavors. |

Each type can be turned off under **Settings → Tracking**. Headers collapse and expand with a click. Shift-click a section header to collapse all of its zone groups at once.

### Quest colors

- **By difficulty.** Quest names are colored gray, green, yellow, orange or red the same way the quest log colors them. The game decides how hard the quest is for you, so scaling quests are colored correctly. Turn this off to use one flat quest color instead.
- **Focused quest.** The quest you're focused on is always shown in gold.
- **Standing in the quest area.** While you're inside the shaded area the map draws for a quest, that quest's row is marked. Choose a style (stripe on the left or right, bracket, outline, background tint, or a gradient fade from the left or right) and a color.

### World map pins

The game's own quest pins on the world map get a ring in the same color as that quest's name in the tracker, so the map and the tracker always agree. You can pick a soft glow or a solid circle, and set its thickness and how opaque the glow is.

### Clicking

| On a… | Click | Shift-click | Right-click |
| --- | --- | --- | --- |
| Quest | Open the map to it | Link it in chat | Menu: Focus, Stop Tracking, Show in Quest Log, Share (in a group), Link to Chat, Abandon |
| World quest / bonus objective | — | Link it in chat | — |
| Achievement | Open it in the Achievements window | Link it in chat | Menu: Link to Chat, Stop Tracking |
| Recipe | Open it in your profession window | Link it in chat | Menu: Link to Chat, Stop Tracking |
| Monthly activity | Open the Traveler's Log | Link it in chat | Menu: Link to Chat, Stop Tracking |
| Endeavor | Open it in the housing window | Link it in chat | Menu: Link to Chat, Stop Tracking |

Quest items show a button you can click to use the item, the same as on the default tracker. The mouse wheel scrolls the tracker; there's no visible scrollbar.

### Title bar

The title bar has buttons to lock or unlock the frame, open settings, minimize the tracker, and turn Follow the Arrow on or off (that button only shows when FollowTheArrow is loaded). When the frame is unlocked, drag it by the title bar to move it and drag a bottom corner to resize it.

## Nameplate highlights

Enemy nameplates are highlighted when that enemy is something your quests need. The game's own unit tooltip decides what counts, so the highlights match what the game considers a quest target.

| Highlight | Used for | Default color |
| --- | --- | --- |
| **Quest Objective** | Enemies you need to kill for a quest | Yellow |
| **Quest Item** | Enemies that drop an item you need for a quest, even when killing them isn't an objective | Cyan |
| **World Quest** | Targets for active world quests | Blue |
| **Bonus Objective** | Targets for area bonus objectives | Pink |
| **Current Target** | Your target, when it's also a quest target | Green |

When you target an enemy that isn't a quest target, the game's normal target border is shown instead.

Each highlight can be turned on or off separately and has its own style, color, thickness and offset. The styles are **Blizzard** (the game's own target border), **Outline**, **Glow** and **Rounded**. The settings page has a preview nameplate so you can see your changes before going into the world.

There are also options to hide the game's default health bar and level badge borders, or to redraw the default border so it sits evenly around the health bar.

## Settings

Type `/tp` or open **Game Menu → Options → AddOns → TrackerPlus**. The settings are split into pages:

- **TrackerPlus**: turn the tracker on or off, and lock it.
- **General**: hide the tracker in instances or in combat, hide it when there's nothing tracked, turn tooltips on or off, and reset all settings.
- **Appearance**: Match Game Tracker, width, height and scale, border, the expand/collapse icon style and position, header backgrounds, progress bar style, fonts, and colors for every text and content type.
- **Layout**: indents and spacing.
- **Tracking**: which content types to show, quest level, difficulty colors, world map pin colors, the quest area marker, zone headers and sort order. Sort order can be by difficulty (easiest or hardest first), by proximity, or alphabetically.
- **Nameplates**: everything under [Nameplate highlights](#nameplate-highlights).
- **Debug**: logging and layout overlays, for troubleshooting.

## Slash commands

| Command | Does |
| --- | --- |
| `/tp` or `/trackerplus` | Open settings |
| `/tp toggle` | Turn the tracker on or off |
| `/tp lock` / `/tp unlock` | Lock or unlock the frame |
| `/tp reset` | Reset all settings to their defaults |
| `/tp nameplates` | Open the Nameplates settings page |
| `/tp nameplates toggle` | Turn nameplate highlights on or off |
| `/tp nameplates debug` | Show the nameplate debug window |

## Optional addons

- **[FollowTheArrow](https://www.curseforge.com/wow/addons/followthearrow)**: when it's loaded, TrackerPlus can show the current guide step in its own section. Turn it on with the arrow button in the title bar or under **Settings → Tracking**.
- **Auctionator**: its crafting search button is moved into the Professions section.

## Installation

1. Copy the `TrackerPlus` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
2. Restart the game, or type `/reload`.

Settings are saved per account in `TrackerPlusDB`.

## For developers

| Folder / file | What it does |
| --- | --- |
| `Database.lua` | Default settings and saved-variable migrations |
| `Core.lua` | Events, the update loop and slash commands |
| `Data/` | Collects quests, achievements and other trackables; parses objectives, picks quest colors and sorts trackables |
| `Render/` | Draws each tracker section; `TrackerRenderer.lua` lays them out |
| `UI/` | The tracker frame, title bar, button pools, click handling and Match Game Tracker |
| `Map/` | World map pin colors and the quest area marker |
| `Nameplates/` | Nameplate highlights, their settings page and debug window |
| `Settings.lua` | The settings pages |

## Credits

Created by **jr0dsgarage**. All rights reserved; for personal use only.
