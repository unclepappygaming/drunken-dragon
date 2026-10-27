# The Drunken Dragon

A cozy tavern-management game for phones, made with **Godot 4.4**.

Build tables and hearths, hire cooks and waiters, learn new recipes, and keep
your guests fed before their patience runs out. Win enough fame and nobles
start visiting, but they only eat the fancy dishes.

## How to play

Each day runs from 09:00 to 21:00 (about two real minutes).

- **Guests** come in, sit beside a free Table and call for a waiter. If no
  table is free, they leave and you lose fame.
- **Waiters** take orders, fetch finished dishes from a Hearth and carry them
  to the table.
- **Cooks** work the Hearths. A Hearth only cooks while a cook stands at it.
- Every guest has a **patience bar**. If it runs out, they storm off and you
  lose fame. Happy guests pay and raise your fame.
- More fame brings guests faster. At 25 fame, **nobles** (with gold crowns)
  start to arrive. They only order dishes marked "Nobles only".

Between days you can:

- **Build or sell** furniture with the bottom buttons. You can't block the
  doorway or wall anyone in.
- **Hire or fire** staff. Wages are paid every night.
- Open **Menu & Recipes** to learn new dishes and choose up to 4 for
  tomorrow's menu.

The game saves automatically between days. **New Game** on the day screen
erases the save (it asks twice).

## Opening the project

1. Install [Godot 4.4](https://godotengine.org/download) (the standard version,
   not .NET).
2. In the Godot Project Manager, choose **Import** and pick this folder's
   `project.godot`.
3. Press **F5** to play. The window opens in phone (portrait) shape.

To make a web version: **Project → Export → Web → Export Project** (you'll be
asked to download export templates the first time).

## Code tour

All art is placeholder shapes drawn in code, so the scripts are the whole game:

| Script | What it does |
| --- | --- |
| `scripts/game_manager.gd` | Global state (autoload): gold, fame, clock, recipes, menu, wages, saving |
| `scripts/main.gd` | Wires everything together: spawns guests, hires staff, day summary |
| `scripts/tavern_grid.gd` | The floor: building, pathfinding, tables, Hearth cooking |
| `scripts/walker.gd` | Shared walking code for anyone who moves around furniture |
| `scripts/customer.gd` | One guest's state machine |
| `scripts/cook.gd` / `waiter.gd` | Staff behavior |
| `scripts/hud.gd` | All the on-screen UI, built in code |

## Milestones

1. ✅ Tavern grid, guests, hearths, day cycle
2. ✅ Staff, pathfinding, saving
3. ✅ Recipes, daily menu, nobles
4. ⬜ UI moved into editable scenes
5. ⬜ Art and sound
