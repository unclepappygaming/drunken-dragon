# The Drunken Dragon

A cozy tavern-management game for phones, made with **Godot 4.4**.

Build tables and hearths, hire cooks and waiters, learn new recipes, and keep
your guests fed before their patience runs out. Win enough fame and you can
invite nobles to a banquet, but they only eat the fancy dishes.

## How to play

Each day runs from 09:00 to 21:00 (about two real minutes). Drag with one
finger to look around and pinch to zoom (mouse drag and wheel on a computer).

- **Tables** are three squares in a row: a chair, the table, a chair (2
  seats, 100g). A **Long Table** is two of those side by side (4 seats,
  220g). **Rotate** in the Build tray turns new tables the other way.
  Guests sit on the chairs, and each group (one guest, a pair or a party)
  gets a whole table, so match your tables to your crowd: parties of 3
  need a Long Table.
- **Guests** come in, sit at a free table that fits their group and call
  for a waiter. If no table is free, they wait in a **line outside the door** (up to 5) and take
  the next table that frees up. If they wait too long, or the line is full,
  they leave and you lose fame.
- **Guests come in different types**, each with their own look and habits:

  | Guest | Habits |
  | --- | --- |
  | Farmer | The everyday guest; orders any common dish |
  | Town Guard | In a hurry (60% patience), wants Dragon Ale, tips 30% if served quickly |
  | Merchant | Patient, only orders tier 2 dishes, pays 20% more |
  | Old Regular | Walks slowly, comes once a day, always orders the same favorite dish |
  | Adventurers | From 10 fame: a party of 2-3 sharing one table. Tip 25%, but if one storms off they all leave |
  | Pairs | Two farmers, merchants or guards who share a table, sitting across from each other. They wait in line together |
  | Lord / Lady | Only at Noble Banquets |
  | Bard | From 15 fame. Plays while seated: guests within 3 squares lose patience half as fast |
  | Dwarf Miner | From 20 fame. Always orders a second dish after the first |
  | Elf | From 40 fame, and only while Elven Wine is on the menu. Drinks only that, and pays double |
  | Wizard | From 55 fame. Impatient (60%), but tips 40% |
  | Food Critic, Fae | Only on their special event days |
- **The kitchen** is a zone 2 squares deep (grey stone floor). Hearths go
  on its front row; the **pass** (expo counter) is at the right end.
- **Cooks** walk straight along the kitchen aisle (never out through the
  dining room), stand behind their Hearth, always facing
  the room. When a dish is done they carry it to the pass. The pass holds 3
  plates; if it's full, cooks wait.
- **Waiters** take orders, collect dishes from the front of the pass (they
  never enter the kitchen) and carry them to the table.
- **Every dish has its own look**: ale in a tankard, stew in a steaming
  bowl, a roast boar on the bone, wyvern wings, a flaming phoenix roast,
  the Dragonfire Feast on a gold platter... You see them on the pass, on
  the waiters' trays, in the cooks' hands, and in front of each guest.
- **Tables stay bare until food arrives.** When guests finish, their empty
  plates stay behind, and nobody new can sit there until a waiter clears
  them and takes them back to the pass for washing. Waiters serve food
  first, then take orders, then clear tables, so a busy room needs enough
  waiters. Plates still out at closing get washed overnight.
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
- **Day to night**: while you're open the light outside changes with the
  clock, from morning daylight to warm afternoon sun, an orange dusk at
  the dinner rush and a blue night before closing, when the lamp posts
  and house windows glow. Inside stays lit: the windows show the night
  sky and candles come out on the tables.
- **Special events**: from day 3, 4 in 10 ordinary days bring one (shown
  on the day button while you're open):
  - **Festival Day**: twice the guests and 25% better tips. Festival
    crowds who can't get in don't count against the review.
  - **Rainy Day**: rain outside, 30% fewer guests, but 30% more patient.
  - **Food Critic** (from 10 fame): a critic arrives between 11:00 and
    16:00 and goes to the front of the line. Served with time to spare:
    a glowing review (+3 fame); served late: fair (+1); walked out:
    scathing (-3).
  - **Fae Night** (from 25 fame, rare): six fae (pixies, dryads, satyrs)
    arrive from 18:00, going to the front of the line. Send them all home
    happy for +2 fame and the Gossamer Wings trophy.
- **Rush hours**: guests come 1.7x as often at lunch (12:00-14:00) and 2x
  at dinner (18:00-20:00); mornings before 11:00 are quiet. The clock turns
  orange during a rush. Plan your staff for the rush, not the quiet hours.
- **Ingredients**: every dish costs something to make (about a third of its
  price), paid at night with the wages, even if the guest left before
  eating it.
- More fame brings guests faster. At 25 fame you can host **Noble Banquets**
  (tap Open Day, then Host a Banquet, 250g, once every 3 days). A party of
  nobles (gold crowns) arrives between 12:00 and 15:00. They skip the line,
  only order "Nobles only" dishes and tip 50%. If they all leave happy it's
  a triumph (+3 fame); at least half is +1; fewer than half is -2.
- **Recipes can't be bought.** Happy patrons share ideas, and quests (like
  "serve 12 Mushroom Stews") teach you new dishes. The recipe book shows
  every quest and your progress.

The bottom bar has four buttons:

- **Build** opens a tray: Table, Long Table, Rotate, Hearth, Bar, Sell,
  Door, Move Kitchen, Private Room, Decor, Expand.
  - **Bar** (300g): a counter for a bartender, who stands behind it.
  - **Private Room** (Grand Hall only, 40g a square): paint squares with a
    crimson carpet. A table standing wholly on it is private: nobles are
    seated there first, and nobles at a private table pay 30% more and are
    30% more patient. Ordinary guests only use it when nothing else is free. You can't
  block the doorway or wall anyone in.
  - **Door** moves the front door to any square along a wall (100g, between
    days). The waiting line follows it.
  - **Move Kitchen** moves the whole kitchen (Hearths and pass too) between
    days: tap where its back-left corner should go.
  - **Expand** makes the floor bigger, up to 12 x 14. Each expansion is
    unlocked by a quest (like "Serve 60 guests"), then bought with gold.
    The same card has **Widen Kitchen** (250g a square, up to 8 wide).
    Hearths cost 250g; selling anything gives half back.
  - **Decor** opens the decorations list. They're just for looks.
    - **Floor pieces** are bought and placed on a square: Potted Fern 60g,
      Ale Barrels 90g, Rug 120g (people walk over it), Suit of Armour 250g,
      Bookshelf 250g, Fireplace 400g (its fire flickers) and the Dragon
      Statue 1500g, which covers 2 x 2 squares and needs Legendary rank.
      **Rotate** turns them before placing (a bookshelf or fireplace can
      stand against either back wall). Sell gives half back.
    - **Wall trophies** are earned by achievements, never bought, and hang
      on a stretch of back wall (not over windows, banners or the door).
      Tap a hung piece with Sell to take it down; "Move" re-hangs it.

      | Trophy | Achievement |
      | --- | --- |
      | Painting | Reach Local Haunt |
      | Shield & Swords | Serve 25 Town Guards |
      | Antlers | Serve 100 Roast Boars |
      | Faerie Lantern (glows) | Open the tavern for 20 days |
      | Moonflower Wreath | Serve 50 Honey Meads |
      | Glowcap Shelf | Serve 100 Mushroom Stews |
      | Gossamer Wings | Delight the fae on a Fae Night |
      | Fae Mirror | Host 3 triumphant banquets |
      | Faerie Crown | Learn every recipe |
      | Wyvern Head (opens its jaws) | Serve 30 Wyvern Wings |
      | Centaur Head (glowing eyes) | Serve 50 adventurers |
      | Griffon Head (ruffles) | Reach Famed Hall |
      | Unicorn Head (glinting horn) | Serve 25 nobles |
      | Minotaur Head (snorts) | Serve 500 guests |
      | Kraken Tentacles (sway) | Move to the Grand Hall |

    Decorations stay behind when you move to the Grand Hall; earned
    trophies come along and can be hung again.
- **Staff** opens a tray with a button per job. Besides cooks and waiters:

  | Job | Trait | Wage | How many |
  | --- | --- | --- | --- |
  | Host | Guests in line wait twice as long; every guest sits down with 10s more patience | 28g | 1 |
  | Dishwasher | Clears and washes every table, so waiters only take orders and serve | 20g | up to 3 |
  | Bartender | Works a Bar: pours every drink (ale, mead, wine) and carries it out, so drinks skip the kitchen | 32g | one per Bar |
- **Staff** tray details: **Hire Cook**, **Hire Waiter** (three new
  applicants each day) and **Your Staff** (let someone go). Between days
  only. Hiring costs a signing fee of 4 days' wages up front, then wages
  are paid every night. Every staff member has a name, their own look, and
  a trait that comes with their type:

  | Type | Trait | Wage |
  | --- | --- | --- |
  | Classic Chef | Trained: cooks every dish 25% faster | 42g |
  | Tavern Cook | Hearty Portions: their dishes earn 15% more gold | 36g |
  | Dwarf Cook | Roast Master: roasts cook 40% faster | 38g |
  | Barkeep | Smooth Talker: +10s patience for guests they serve | 30g |
  | Serving Maid | Nimble: walks 25% faster | 30g |
  | Halfling Server | Lucky: 1 in 3 guests tips +50%, but walks 10% slower | 25g |
- **Recipes & Goals** opens the book: pick up to 4 dishes for the menu,
  check your quests, and see your rank and milestones.
- **Open Day** starts the next day (once banquets are unlocked, it asks
  whether to host one). The end-of-day summary closes with Continue, so you
  can build and hire first.

### The Grand Hall

Once the tavern is fully expanded (12 x 14) and you're **Legendary** (140
fame), the Expand card offers a move to **the Grand Hall** in the capital
(15000g, tap twice to confirm). Your fame, recipes, stats and staff come
along; the furniture stays behind and you start with a 6-wide kitchen,
three Hearths and eight tables.

- The hall starts at 16 x 16 and has four expansions of its own, up to
  24 x 24 (6000g to 18000g), each unlocked by a hall quest: serve 300
  guests, serve 20 nobles, have 3 perfect days, serve 1500 guests.
- City guests pay 25% more. Instead of fame, the hall's crowds grow with
  each expansion, down to about one guest a second outside rushes.
- Up to 12 cooks and 12 waiters, and the kitchen can widen to 12 squares.
- Marble floors, stone walls with crimson panelling, gold trim and banners.

**Test shortcut:** tap the Gold counter 5 times quickly (between days) to
jump to a Legendary, full-size tavern with every recipe, every wall
trophy, 4 cooks, 4 waiters and enough gold to move. It's switched on by `TEST_SHORTCUT` in
`scripts/hud.gd`; turn that off before releasing the game.

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

The floor and walls are drawn in code; characters and furniture are pixel-art sprites made by the scripts in `tools/sprites/`:

| Script | What it does |
| --- | --- |
| `scripts/game_manager.gd` | Global state (autoload): gold, fame, clock, recipes, menu, wages, saving |
| `scripts/main.gd` | Wires everything together: spawns guests, hires staff, day summary |
| `scripts/tavern_grid.gd` | The floor: building, pathfinding, tables, Hearth cooking |
| `scripts/walker.gd` | Shared walking code for anyone who moves around furniture |
| `scripts/customer.gd` | One guest's state machine |
| `scripts/cook.gd` / `waiter.gd` | Staff behavior |
| `scripts/scenery.gd` | The world around the tavern: a meadow, a busy medieval city (the Grand Hall's) or a fae forest |
| `scripts/lighting.gd` | Day turning to night outside, and the glow of lamps after dark |
| `scripts/hud.gd` | All the on-screen UI, built in code |
| `scripts/tavern_camera.gd` | Drag, pinch and wheel camera; turns taps into build clicks |
| `scripts/staff_profiles.gd` | Staff types, traits, wages, names and looks |
| `scripts/guest_types.gd` | Guest types, how often they come, and their looks |
| `shaders/palette_swap.gdshader` | Gives each staff member their own skin and hair color |
| `tools/sprites/make_sprites.py` | Draws the pixel-art staff and guest sprite sheets (`python3 tools/sprites/make_sprites.py`) |
| `tools/sprites/make_outdoors.py` | Draws the scenery: trees, bushes, rocks, lamp posts, a well, fences, houses and market stalls |
| `tools/sprites/make_food.py` | Draws every dish, empty and dirty plates, and finished drinks |
| `tools/sprites/make_furniture.py` | Draws the isometric furniture: table, brick stove (with fire frames) and the serving-hatch pass |

## Roadmap

1. ✅ **Tavern grid, guests, hearths, day cycle**
2. ✅ **Staff, pathfinding, saving**
3. ✅ **Recipes, daily menu, nobles**, plus a camera: drag to look around,
   pinch (or mouse wheel) to zoom
   - ✅ Recipes earned through quests and patron ideas instead of bought
   - ✅ Waiting line outside the door when the tavern is full
   - ✅ Compact bottom bar with Build and Staff trays
   - ✅ Nobles come only to Noble Banquets you host (unlocked at 25 fame)
4. ✅ **Balance pass**
   - ✅ Lunch and dinner rushes so a well-staffed tavern still feels stretched
   - ✅ Fame from nightly reviews, milestones and banquets instead of every
     guest, with ranks from Unknown to Legendary
   - ✅ Ingredient costs, cheaper dishes, a hiring fee, pricier furniture,
     expansions and wages, tested with a bot over 50-day games: a good
     player reaches Local Haunt around day 6-11, Town Favorite day 12-16,
     Talk of the Realm day 18-22, Famed Hall day 26-33 and Legendary around
     day 44-52 (with 3 x 1 tables and chairs)
   - ✅ The Grand Hall gives late-game gold a goal (a bot reaches it around
     day 47 and fills it out over the next ~40 days)
5. ✅ **Bigger tavern**
   - ✅ Four floor expansions up to 12 x 14, each earned by a quest, then bought
   - ✅ Move the front door to any wall, with the same "nothing gets blocked" check
   - ✅ Size and door are saved; older saves load as the original 8 x 10 floor
   - ✅ The camera zooms to fit the floor after each expansion
6. ⬜ **Art and sound**
   - ✅ Pixel-art staff: 3 cook and 3 waiter types, each with a trait,
     walk animations in 4 directions and per-person skin and hair colors
   - ✅ Guest types with pixel-art looks: Farmer, Town Guard, Merchant,
     Old Regular, Adventurers (knight, mage, rogue), Lord and Lady
   - ⬜ More guests (bard, elf, dwarf miner, wizard, food critic...)
   - ✅ Pixel-art furniture: plank trestle tables, brick stoves with a
     flickering fire, a serving hatch for the pass
   - ✅ Plates on tables, and waiters clear them after guests leave
   - ✅ Decorations: seven floor pieces to buy and fifteen wall trophies
     earned by achievements, some animated
   - ✅ Scenery around the building: a meadow for the tavern, a busy
     medieval city (with townsfolk walking the streets) for the Grand Hall,
     and a fae forest
   - ⬜ Sprites for the floor and walls
   - Sound effects and music (they start after the first tap, as browsers require)
7. ⬜ **The Grand Hall, continued**
   - ✅ Step 1: the move, a bigger floor with its own look and expansions
   - ⬜ Rooms: a private dining room for nobles, a bar
   - ⬜ New staff roles: host, dishwasher, bartender, head chef
   - ⬜ New guests and dishes, and ranks beyond Legendary
8. ⬜ **UI moved into editable scenes**, so menus can be restyled in the
   Godot editor
