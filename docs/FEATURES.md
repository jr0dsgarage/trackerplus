# TrackerPlus: an objective tracker replacement that colors quests by difficulty and highlights quest mobs on nameplates

I've been working on a replacement for the default objective tracker and it's at a point where I'd like other people to try it. It works on both **Retail** and **WoW Forever**. Anything Forever doesn't have (world quests, campaigns, achievements and so on) is switched off there and left out of the settings.

Here's what it does.

## The tracker

- **Quests colored by difficulty.** Quest names are gray, green, yellow, orange or red, the same colors the quest log uses, so you can see at a glance what's trivial and what will get you killed. Scaling quests get the right color too, because the game decides the difficulty.
- **Sections for everything you track.** Active Quest, Campaign, Quests (grouped by zone), Achievements, Professions, Monthly Activities, Endeavors, Bonus Objectives, World Quests and Scenarios each get their own section. You can turn off any type you don't care about.
- **Sorting.** Sort quests by difficulty (easiest or hardest first), by proximity, or alphabetically.
- **Quest level and party count.** Each quest can show its level, like `[28+]` for a group quest, and `(+2)` when two party members are also on it. Hover it to see who, in class colors.
- **Quest area marker.** When you're standing inside the area the map shades for a quest, that quest's row lights up. There are several styles: stripe, bracket, outline, tint, gradient, or a Battle.net friend card.
- **Auto-minimize zones.** One button collapses every zone header except the one you're in. Zones open back up when you get there.
- **Quest timers and popups.** Timed quests get a countdown, and auto-accept and auto-complete popups show up at the top of the tracker.
- **Click actions you'd expect.** Click to open the map, Shift-click to link, right-click for a menu (focus, untrack, share, abandon and so on), Shift-right-click to untrack a quest straight away. Quest item buttons and Find a Group buttons work like they do on the default tracker.

## Nameplate highlights

Enemies your quests need get highlighted on their nameplates, so you stop killing the wrong mobs.

- **Separate highlights** for your current target, Active Quest targets, kill objectives, mobs that drop quest items, world quest targets and bonus objective targets.
- **Each one can be styled separately.** Pick Rounded, Blizzard, Outline or Glow, then set the color, thickness and offset.
- **Live preview.** The settings page has a preview nameplate, so you can see each highlight without going out to find a mob.
- **Border tweaks.** You can hide Blizzard's own target border or move it down 1px so it sits evenly around the health bar.

## World map pins

The game's quest pins on the world map get a ring in the same difficulty color as the tracker, so the map and the tracker always agree. You can choose a soft glow or a hard circle and set how thick it is.

## Make it look how you want

- **Match Game Tracker.** By default it sits exactly where the default tracker is and follows your Edit Mode changes. If you drag it somewhere yourself, that turns off.
- **Size, scale and anchor** settings, plus options to hide it in instances, in combat, or when nothing is tracked.
- **Backgrounds, borders and row backgrounds.** You can use the game's own textures or anything that's registered with LibSharedMedia.
- **Fonts and sizes** for headers, quest names and objectives, set separately.
- **Colors** for every text type and every trackable type.
- **Layout sliders** for every indent and gap, if you're picky about spacing.

## Works with

- **FollowTheArrow:** shows the current guide step in its own section.
- **Spoken:** adds a Play button to quests so you can hear them read aloud.
- **Titan Panel and other LibDataBroker displays:** adds a button to show or hide the tracker.
- **Auctionator:** its crafting search button shows up in the Professions section.

## Getting it

Type `/tp` in game to open the settings. The code and install steps are on [GitHub](https://github.com/jr0dsgarage/trackerplus).

Feedback and bug reports are welcome. I'd especially like to hear from people playing on Forever.
