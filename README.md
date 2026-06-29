# HoryUI

A lightweight, premium-minimal combat HUD for **World of Warcraft 1.12 (vanilla / Turtle WoW)**, built specifically for the **Rogue** class. Calm out of combat, instantly readable in combat — flat 1px borders, near-black panels, one deep Horde-red accent ("Garnet").

## Requirements

| | |
|---|---|
| **Game client** | WoW 1.12.x (interface `11200`) |
| **Required** | [Nampower](https://github.com/pepopo978/nampower) **3.0.0+** — fast unit-field reads and cast events. HoryUI warns and degrades if it's missing. |
| **Recommended** | **SuperWoW** (unified cast events, mouseover, spell info) and **UnitXP_SP3** (distance / line-of-sight). Both are optional and feature-gated. |

## Features

### Combat HUD
- **Unit frames** — player + target + target-of-target: 2D portraits, health/power, class/reaction-coloured names, difficulty-coloured level + elite/boss marker, dead/ghost/offline status, click-to-target, out-of-combat fade.
- **Rogue energy bar** with a sweeping tick line (energy-only), and **combo points** (1–5 pips, green→red, finisher glow).
- **Castbars** — player + enemy, from SuperWoW `UNIT_CASTEVENT` when present (Nampower `SPELL_*` fallback); enemy casts tracked by GUID for interrupt timing.
- **Auras** — player buffs (countdown timers + stacks + right-click cancel) and target buffs/debuffs with real time-left from cast events, hover tooltips throughout.
- **Range tracker** — exact yards to target (UnitXP_SP3) + closing-rate readout and a melee safe-zone highlight.

### Group & info
- **Party** and **raid** frames (raid laid out by subgroup, leader/assist icons, loot-method header), with debuff icons. Party hides while in a raid.
- **Weapon-poison** icons (time + charges), **XP / reputation** bar across the top of the minimap.

### Action bars
- A vendored standalone copy of the **Bongos** engine (`bongos/`) — action / pet / class-stance / bag / menu bars, flat Garnet-skinned, with a Garnet right-click bar menu and an **Actionbars** settings tab. Stays dormant while the standalone Bongos addon is enabled; disable Bongos and `/reload` to hand the bars to HoryUI. Existing Bongos layouts, keybinds, and profiles carry over (shared saved-var names).

### UI rework
- **Chat** rework — persistent history, movable + resizable panel, URL copy box, class-coloured names, flat Garnet tabs, timestamps, mouse-wheel scroll. Dormant while real pfUI is active.
- **Square minimap** with wheel zoom / shift-wheel scale and a collapsible addon-button tray.
- Native **Character** panel rebuild (Character / Reputation / Skills / PvP tabs) and a one-bag **Bags** rebuild, plus **Outfitter** integration and a movable **tooltip** anchor.
- A vendored standalone **pfUI skin engine** (`pfskin/`) for Blizzard window skins + nameplates, dormant while real pfUI is installed.

### Settings
- One tabbed `/hui` window — **General** (unlock/reset, UI-wide profiles), **Modules**, **Addons** (enable/disable any installed addon), **PfUI** (skin/nameplate toggles), **Load Times** (per-addon startup cost), **Actionbars**. Profiles snapshot all of HoryUI's settings plus the Bongos bar tables.

## Install

1. Copy the `!HoryUI` folder into `Interface/AddOns/` (the leading `!` makes it load first, so it can time every other addon).
2. Restart the client (the `.toc` is only scanned at launch).
3. Type `/hui` in-game to open settings; unlock to reposition panels.

## License

Personal project. The `pfskin/` directory is a vendored, renamed copy of [pfUI](https://github.com/shagu/pfUI)'s skin subsystem (MIT) so the skins run standalone. The `bongos/` directory is a vendored copy of [Bongos](https://github.com/tullamods/Bongos) (Tuller) so the action bars run standalone.
