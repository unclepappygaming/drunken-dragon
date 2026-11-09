"""New characters, drawn in the same style as make_sprites.py: five new
guests, three fae guests for Fae Night, and three new staff roles.

Run from the repo root:  python3 tools/sprites/make_new_characters.py
It writes a preview sheet (new_characters_options.png) next to this
script. Nothing in the game uses these yet.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True
from PIL import Image  # noqa: E402
from make_sprites import (  # noqa: E402
    W, H, SKIN, GOLD, WOOD, STEEL, px, rect, ellipse, shade, sheet, hair, beard, beret, mustache, draw, tray,
    wizard_hat, magic_staff, belt, buttons, apron, vest, bandana, neckerchief, marks, towel,
    rolled_sleeves, watch_chain, hair_colour,
)

WHITE = (248, 246, 238, 255)


# ---------------------------------------------------------------------
# New layers
# ---------------------------------------------------------------------
def lute():
    """A bard's lute, held across the body."""
    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 18 if view == "front" else 15
        ellipse(img, x, y0 + 8, 3, 2.5, (190, 130, 70, 255))
        px(img, x, y0 + 8, (90, 55, 30, 255))
        rect(img, x + 2, y0 + 3, x + 5, y0 + 5, (150, 95, 50, 255))   # neck
        px(img, x + 6, y0 + 2, (150, 95, 50, 255))
    return layer


def ears():
    """Pointed elf ears poking out of the hair (skin, so they're recoloured)."""
    def layer(img, view, cy):
        if view == "front":
            px(img, 8, cy - 1, SKIN); px(img, 9, cy, SKIN); px(img, 23, cy - 1, SKIN); px(img, 22, cy, SKIN)
        elif view == "side":
            px(img, 13, cy - 2, SKIN); px(img, 13, cy - 1, SKIN); px(img, 12, cy - 3, SKIN)
    return layer


def circlet(gem=(120, 210, 140, 255)):
    def layer(img, view, cy):
        rect(img, 10, cy - 4, 21, cy - 4, GOLD)
        if view == "front":
            px(img, 15, cy - 4, gem); px(img, 16, cy - 4, gem)
    return layer


def mining_helmet():
    """A dented helmet with a candle stuck on the front."""
    def layer(img, view, cy):
        ellipse(img, 16, cy - 2, 7.4, 6.4, (150, 120, 70, 255), top_only=True)
        rect(img, 8, cy - 2, 23, cy - 1, (120, 95, 55, 255))
        if view != "back":
            x = 16 if view == "front" else 20
            rect(img, x, cy - 10, x, cy - 7, (240, 230, 200, 255))
            px(img, x, cy - 11, (255, 210, 90, 255))
    return layer


def pickaxe():
    def layer(img, view, y0, step):
        x = {"front": 24, "side": 20, "back": 8}[view]
        rect(img, x, y0 - 4, x, y0 + 10, WOOD)
        rect(img, x - 3, y0 - 5, x + 3, y0 - 5, STEEL)
        px(img, x - 4, y0 - 4, STEEL); px(img, x + 4, y0 - 4, STEEL)
    return layer


def top_hat(color=(35, 35, 40, 255)):
    def layer(img, view, cy):
        rect(img, 9, cy - 5, 22, cy - 4, color)                 # brim
        rect(img, 11, cy - 13, 20, cy - 5, color)
        rect(img, 11, cy - 7, 20, cy - 6, (150, 40, 50, 255))   # band
    return layer


def quill_pad():
    """The critic's notebook and quill, held up to write in."""
    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 20 if view == "front" else 17
        rect(img, x, y0 + 4, x + 3, y0 + 7, WHITE)
        rect(img, x + 4, y0 + 1, x + 4, y0 + 5, (240, 240, 245, 255))   # quill
        px(img, x + 5, y0, (240, 240, 245, 255))
    return layer


def wings(color=(190, 230, 250, 255)):
    """Pixie wings, see-through blue; seen behind the body."""
    def layer(img, view, y0, y1):
        edge = shade(color, 0.8)
        if view == "side":
            ellipse(img, 11, y0, 3, 5, color); px(img, 11, y0, edge)
            return
        for side in (-1, 1):
            ellipse(img, 16 + side * 8, y0 - 1, 3.2, 4.5, color)
            ellipse(img, 16 + side * 7, y0 + 5, 2.4, 3, color)
            px(img, 16 + side * 8, y0 - 1, edge)
    return layer


def horns():
    def layer(img, view, cy):
        horn = (225, 215, 185, 255)
        if view == "side":
            px(img, 15, cy - 7, horn); px(img, 14, cy - 8, horn); px(img, 13, cy - 8, horn)
            return
        for x, d in ((12, -1), (19, 1)):
            px(img, x, cy - 7, horn); px(img, x + d, cy - 8, horn); px(img, x + d * 2, cy - 8, horn)
    return layer


def panpipes():
    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 19 if view == "front" else 17
        for k in range(4):
            rect(img, x + k, y0 + 2 + k, x + k, y0 + 7, (200, 170, 100, 255))
    return layer


def menu_book():
    """The host's leather-bound list of tables."""
    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 19 if view == "front" else 16
        rect(img, x, y0 + 4, x + 3, y0 + 8, (120, 40, 40, 255))
        rect(img, x + 1, y0 + 5, x + 2, y0 + 5, GOLD)
    return layer


def dish_brush():
    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 22 if view == "front" else 18
        rect(img, x, y0 + 4, x, y0 + 7, WOOD)
        rect(img, x - 1, y0 + 8, x + 1, y0 + 9, (220, 200, 140, 255))
    return layer


def held_mug():
    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 22 if view == "front" else 18
        rect(img, x, y0 + 5, x + 2, y0 + 8, (150, 100, 55, 255))
        rect(img, x, y0 + 4, x + 2, y0 + 4, (250, 246, 230, 255))
    return layer


def flower_crown(colors=((240, 120, 160, 255), (250, 230, 120, 255), (240, 240, 250, 255))):
    def layer(img, view, cy):
        for i, x in enumerate(range(10, 22, 2)):
            px(img, x, cy - 6 + (i % 2), colors[i % len(colors)])
    return layer


# ---------------------------------------------------------------------
# The characters
# ---------------------------------------------------------------------
NEW_GUESTS = {
    "Bard": dict(
        body=(175, 60, 50, 255), sleeve=(235, 190, 70, 255),
        legs=(60, 110, 70, 255), shoes=(90, 55, 35, 255),
        layers=[belt()],
        head_layers=[hair((200, 140, 70, 255)), beret((60, 130, 80, 255), (240, 200, 60, 255))],
        props=[lute()],
        extras=[marks((235, 190, 70, 255), front=[(12, "b", 2), (12, "b", 4), (19, "b", 2), (19, "b", 4)])],
    ),
    "Elf": dict(
        body=(70, 130, 90, 255), sleeve=(70, 130, 90, 255),
        legs=(95, 85, 60, 255), shoes=(80, 60, 40, 255),
        layers=[belt((120, 90, 50, 255), (200, 220, 210, 255))],
        head_layers=[hair((235, 225, 170, 255), style="long"), ears(), circlet()],
        extras=[marks((200, 220, 120, 255), front=[(13, "b", 1), (14, "b", 1)])],   # a leaf brooch
    ),
    "Dwarf Miner": dict(
        small=True,
        body=(110, 100, 95, 255), sleeve=(110, 100, 95, 255),
        legs=(90, 70, 50, 255), shoes=(50, 40, 30, 255),
        layers=[belt()],
        head_layers=[beard((150, 110, 70, 255)), mining_helmet()],
        props=[pickaxe()],
        extras=[marks((60, 60, 60, 255), front=[(11, "b", 6), (20, "b", 5), (13, "h", 1)])],   # coal smudges
    ),
    "Wizard": dict(
        dress=True,
        body=(90, 50, 130, 255), sleeve=(90, 50, 130, 255),
        legs=(90, 50, 130, 255), shoes=(50, 40, 60, 255),
        head_layers=[hair((215, 215, 220, 255)), beard((215, 215, 220, 255)), wizard_hat((90, 50, 130, 255))],
        props=[magic_staff()],
        extras=[marks((250, 240, 160, 255), front=[(11, "b", 8), (20, "b", 9), (12, "b", 11)])],
    ),
    "Food Critic": dict(
        body=(45, 45, 55, 255), sleeve=(45, 45, 55, 255),
        legs=(55, 55, 65, 255), shoes=(25, 25, 30, 255),
        layers=[neckerchief(WHITE)],
        head_layers=[hair((80, 60, 50, 255)), top_hat()],
        props=[quill_pad()],
        extras=[marks(GOLD, front=[(18, "h", 1), (18, "h", 2), (19, "h", 3)])],   # a monocle and its chain
    ),
}

FAE_GUESTS = {
    "Pixie": dict(
        small=True, dress=True,
        body=(150, 210, 170, 255), sleeve=(150, 210, 170, 255),
        legs=(150, 210, 170, 255), shoes=(110, 170, 130, 255),
        layers=[wings()],
        head_layers=[hair((240, 170, 200, 255), style="curly"), flower_crown()],
    ),
    "Dryad": dict(
        dress=True,
        body=(120, 85, 55, 255), sleeve=(120, 85, 55, 255),
        legs=(120, 85, 55, 255), shoes=(90, 65, 40, 255),
        head_layers=[hair((90, 150, 70, 255), style="long"), flower_crown(((250, 250, 250, 255), (240, 200, 90, 255)))],
        extras=[marks((90, 150, 70, 255), front=[(11, "b", 3), (20, "b", 6), (13, "b", 9), (18, "b", 2)])],   # leaves on the bark
    ),
    "Satyr": dict(
        small=True,
        body=(140, 175, 110, 255), sleeve=(140, 175, 110, 255),
        legs=(120, 80, 50, 255), shoes=(50, 40, 35, 255),   # furry legs and hooves
        head_layers=[hair((110, 70, 40, 255), style="curly"), horns()],
        props=[panpipes()],
    ),
}

NEW_STAFF = {
    "Host": dict(
        body=(130, 30, 45, 255), sleeve=(130, 30, 45, 255),
        legs=(40, 35, 40, 255), shoes=(25, 20, 20, 255),
        layers=[buttons(GOLD), neckerchief(WHITE)],
        head_layers=[hair((60, 40, 30, 255))],
        props=[menu_book()],
        extras=[watch_chain()],
    ),
    "Dishwasher": dict(
        body=(200, 200, 190, 255), sleeve=(200, 200, 190, 255),
        legs=(80, 80, 90, 255), shoes=(50, 40, 35, 255),
        layers=[apron((70, 110, 160, 255), full=True)],
        head_layers=[hair((140, 90, 50, 255)), bandana((70, 110, 160, 255))],
        props=[dish_brush()],
        extras=[rolled_sleeves(), marks((235, 245, 255, 255), front=[(9, "b", 9), (23, "b", 9), (22, "b", 10)])],   # soap suds
    ),
    "Bartender": dict(
        body=(245, 242, 232, 255), sleeve=(245, 242, 232, 255),
        legs=(40, 40, 45, 255), shoes=(25, 20, 20, 255),
        layers=[vest((40, 40, 45, 255), (245, 242, 232, 255))],
        head_layers=[hair((50, 35, 25, 255)), mustache((50, 35, 25, 255))],
        props=[held_mug()],
        extras=[towel((150, 40, 50, 255))],
    ),
}


def shaded(group):
    """The same shading as the other characters (skin and hair left alone)."""
    return {name: dict(ch, shade=True, hair_key=hair_colour(ch)) for name, ch in group.items()}


# Ids the game uses for each sheet.
GAME_IDS = {"Bard": "bard", "Elf": "elf", "Dwarf Miner": "miner", "Wizard": "wizard", "Food Critic": "critic",
            "Pixie": "pixie", "Dryad": "dryad", "Satyr": "satyr",
            "Host": "host", "Dishwasher": "dishwasher", "Bartender": "bartender"}
CARRIERS = ("Dishwasher", "Bartender")   # they carry things on a tray (sheet row 1)


def export(out_dir, group):
    """Sheets in the game's layout: 9 frames (front, side, back; idle and
    two steps each), row 0 normal and row 1 carrying."""
    views = [("front", s) for s in range(3)] + [("side", s) for s in range(3)] + [("back", s) for s in range(3)]
    for name, ch in shaded(group).items():
        carry = dict(ch, props=[tray(mug=False, plate=True)]) if name in CARRIERS else ch
        out = Image.new("RGBA", (W * len(views), H * 2), (0, 0, 0, 0))
        for row, c in enumerate([ch, carry]):
            for col, (view, step) in enumerate(views):
                out.alpha_composite(draw(c, view, step), (col * W, row * H))
        out.save(os.path.join(out_dir, GAME_IDS[name] + ".png"))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    export(os.path.join(root, "assets", "sprites", "guests"), NEW_GUESTS)
    export(os.path.join(root, "assets", "sprites", "guests"), FAE_GUESTS)
    export(os.path.join(root, "assets", "sprites", "staff"), NEW_STAFF)
    sheet([("New guests", shaded(NEW_GUESTS)), ("Fae Night guests", shaded(FAE_GUESTS)),
           ("New staff", shaded(NEW_STAFF))], os.path.join(here, "new_characters_options.png"))
    print("wrote new_characters_options.png")
