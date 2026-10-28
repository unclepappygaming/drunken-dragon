# The Drunken Dragon

A cozy tavern-management game for phones, made with **Godot 4.4**.

Build tables and hearths, hire cooks and waiters, learn new recipes, and keep
your guests fed before their patience runs out. Win enough fame and you can
invite nobles to a banquet, but they only eat the fancy dishes.

## How to play

Each day runs from 09:00 to 21:00 (about two real minutes). Drag with one
finger to look around and pinch to zoom (mouse drag and wheel on a computer).

- **Guests** come in, sit beside a free Table and call for a waiter. If no
  table is free, they wait in a **line outside the door** (up to 5) and take
  the next table that frees up. If they wait too long, or the line is full,
  they leave and you lose fame.
- **Waiters** take orders, fetch finished dishes from a Hearth and carry them
  to the table.
- **Cooks** work the Hearths. A Hearth only cooks while a cook stands at it.
- Every guest has a **patience bar**. If it runs out, they storm off.
- **Fame** grows slowly, and comes from three places:
  - **Nightly reviews**: the share of today's guests who left happy (anyone
    who walked out, found nothing they liked, or never got a seat counts
    against you). Glowing +2, Good +1, Mixed 0, Poor -1, Terrible -2.
  - **Milestones**, once each: serve 25/100/250/500 guests, perfect days,
    learning recipes, expanding, a triumphant banquet.
  - **Banquets** (below).
- Fame earns **ranks**: Unknown, Local Haunt (10), Town Favorite (25), Talk
  of the Realm (55), Famed Hall (90), Legendary (140). More fame also brings
  guests faster, so keep building to keep the reviews good.
- More fame brings guests faster. At 25 fame you can host **Noble Banquets**
  (tap Open Day, then Host a Banquet, 150g, once every 3 days). A party of
  nobles (gold crowns) arrives between 12:00 and 15:00. They skip the line,
  only order "Nobles only" dishes and tip 50%. If they all leave happy it's
  a triumph (+3 fame); at least half is +1; fewer than half is -2.
- **Recipes can't be bought.** Happy patrons share ideas, and quests (like
  "serve 12 Mushroom Stews") teach you new dishes. The recipe book shows
  every quest and your progress.

The bottom bar has four buttons:

- **Build** opens a tray: Table, Hearth, Sell, Door and Expand. You can't
  block the doorway or wall anyone in.
  - **Door** moves the front door to any square along a wall (100g, between
    days). The waiting line follows it.
  - **Expand** makes the floor bigger, up to 12 x 14. Each expansion is
    unlocked by a quest (like "Serve 60 guests"), then bought with gold.
- **Staff** opens a tray: **Hire Cook**, **Hire Waiter** (three new
  applicants each day) and **Your Staff** (let someone go). Between days
  only. Wages are paid every night. Every staff member has a name, their
  own look, and a trait that comes with their type:

  | Type | Trait | Wage |
  | --- | --- | --- |
  | Classic Chef | Trained: cooks every dish 25% faster | 30g |
  | Tavern Cook | Hearty Portions: their dishes earn 15% more gold | 25g |
  | Dwarf Cook | Roast Master: roasts cook 40% faster | 27g |
  | Barkeep | Smooth Talker: +10s patience for guests they serve | 22g |
  | Serving Maid | Nimble: walks 25% faster | 22g |
  | Halfling Server | Lucky: 1 in 3 guests tips +50%, but walks 10% slower | 18g |
- **Recipes & Goals** opens the book: pick up to 4 dishes for the menu,
  check your quests, and see your rank and milestones.
- **Open Day** starts the next day (once banquets are unlocked, it asks
  whether to host one). The end-of-day summary closes with Continue, so you
  can build and hire first.

The game saves automatically between days. **New Game** on the day summary
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
| `scripts/staff_profiles.gd` | Staff types, traits, wages, names and looks |
| `shaders/palette_swap.gdshader` | Gives each staff member their own skin and hair color |
| `tools/sprites/make_sprites.py` | Draws the pixel-art staff sprite sheets (`python3 tools/sprites/make_sprites.py`) |

## Roadmap

1. ✅ **Tavern grid, guests, hearths, day cycle**
2. ✅ **Staff, pathfinding, saving**
3. ✅ **Recipes, daily menu, nobles**, plus a camera: drag to look around,
   pinch (or mouse wheel) to zoom
   - ✅ Recipes earned through quests and patron ideas instead of bought
   - ✅ Waiting line outside the door when the tavern is full
   - ✅ Compact bottom bar with Build and Staff trays
   - ✅ Nobles come only to Noble Banquets you host (unlocked at 25 fame)
4. ⬜ **Balance pass**
   - Busy-hour rushes so a well-staffed tavern still feels stretched
   - ✅ Fame from nightly reviews, milestones and banquets instead of every
     guest, with ranks from Unknown to Legendary
   - Tune prices, cook times, patience and wages against real play
5. ✅ **Bigger tavern**
   - ✅ Four floor expansions up to 12 x 14, each earned by a quest, then bought
   - ✅ Move the front door to any wall, with the same "nothing gets blocked" check
   - ✅ Size and door are saved; older saves load as the original 8 x 10 floor
   - ✅ The camera zooms to fit the floor after each expansion
6. ⬜ **Art and sound**
   - ✅ Pixel-art staff: 3 cook and 3 waiter types, each with a trait,
     walk animations in 4 directions and per-person skin and hair colors
   - ⬜ Sprites for guests, nobles, furniture and floor
   - Sound effects and music (they start after the first tap, as browsers require)
7. ⬜ **UI moved into editable scenes**, so menus can be restyled in the
   Godot editor
