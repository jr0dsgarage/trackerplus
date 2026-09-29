# next - A Target highlighter

<img width="128" height="128" alt="next" src="https://github.com/user-attachments/assets/116e95f1-68e0-4c6a-8358-f90a65dce95d" align="left"/>

next is a World of Warcraft addon that highlights potential enemy targets, helping the player decide which enemy they should target next.
<br>
<br>
The target highlighter uses the in-game tooltip information about each enemy within nameplate range to determine what to highlight, and the quest log to determine what color to use.
<br>

## Features

- **Smart Quest Highlighting:**
  - Automatically highlights nameplates for mobs relevant to your active tasks:
    - **Quest Objectives**: Standard kill/collect quests.
    - **Quest Items**: Mobs that drop quest items (even if not a direct kill objective).
    - **World Quests**: Targets for active world quests.
    - **Bonus Objectives**: Targets for area bonus objectives.
- **Current Target Indicator:**
  - When your target is a quest objective, draws your chosen Current Target style instead of the quest highlight. Other targets keep the game's own target highlight.
- **Customizable Styles:**
  - Choose from multiple visual styles for each highlight type:
    - **Blizzard**: Uses the native Blizzard selection texture (clean & integrated).
    - **Outline**: Draws a colored border around the health bar.
    - **Glow**: Adds a soft glow effect around the health bar.
  - Configure **Color**, **Thickness**, and **Offset** for each type independently.
  - Settings panel available in Interface > AddOns or via `/next config`.

## Examples
Highlight the current target if its a quest objective.  Keep track of what's an objective and what's not (the Feral Ghoul is not an objective)

<img width="421" height="222" alt="Screenshot 2025-11-07 205151" src="https://github.com/user-attachments/assets/47eda204-cf8f-4b7b-bb65-620f587b7e9f" />

___ 

Easily spot the hard to find quest objective targets 

<img width="307" height="275" alt="Screenshot 2025-11-05 114319" src="https://github.com/user-attachments/assets/d001f98f-f057-4d1c-b43f-873f65bfee84" />

___

Customize using the built-in Settings Panel

<img width="798" height="713" alt="Screenshot 2025-11-07 194751" src="https://github.com/user-attachments/assets/eacbf1c8-3bb2-4ae4-acb7-4b3a04c14176" />

## Usage

- **Commands:**
  - `/next config` — Open settings panel
  - `/next toggle` — Enable/disable addon
  - `/next debug` — Toggle debug window

## Installation

1. Download the latest `next.zip` from the releases or clone the addon inside your `Interface/AddOns/` folder
2. Restart WoW or reload the UI
3. Configure via `/next config` or Interface > AddOns > Next

## Support

For issues or feature requests, open an issue on [GitHub](https://github.com/jr0dsgarage/next) or contact the author.
