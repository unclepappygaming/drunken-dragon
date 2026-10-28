# The Drunken Dragon

A cozy tavern-management game for phones, made with **Godot 4.4**.

Build tables and hearths, hire cooks and waiters, learn new recipes, and keep
your guests fed before their patience runs out. Win enough fame and nobles
start visiting, but they only eat the fancy dishes.

## How to play

Each day runs from 09:00 to 21:00 (about two real minutes). Drag with one
finger to look around and pinch to zoom (mouse drag and wheel on a computer).

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
| `scripts/tavern_camera.gd` | Drag, pinch and wheel camera; turns taps into build clicks |

## Roadmap

1. ✅ **Tavern grid, guests, hearths, day cycle**
2. ✅ **Staff, pathfinding, saving**
3. ✅ **Recipes, daily menu, nobles**, plus a camera: drag to look around,
   pinch (or mouse wheel) to zoom
4. ⬜ **Balance pass**
   - Busy-hour rushes so a well-staffed tavern still feels stretched
   - Slow down fame growth from nobles (it can jump 30 → 80 in two days)
   - Tune prices, cook times, patience and wages against real play
5. ⬜ **Bigger tavern**
   - Buy floor expansions (extra rows and columns) up to a maximum size
   - Move the front door to any wall, with the same "nothing gets blocked" check
   - The grid size and door position are saved; older saves load as the
     original 8×10 floor with the door at the bottom
   - The camera keeps a larger floor reachable on a phone screen
6. ⬜ **Art and sound**
   - Sprites for guests, nobles, staff, furniture and floor (sized to the
     final square size and zoom)
   - Sound effects and music (they start after the first tap, as browsers require)
7. ⬜ **UI moved into editable scenes**, so menus can be restyled in the
   Godot editor
