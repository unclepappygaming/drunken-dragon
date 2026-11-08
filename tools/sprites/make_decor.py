"""Pixel-art decorations for the isometric Drunken Dragon.

Run from the repo root:  python3 tools/sprites/make_decor.py
It writes a preview sheet (decor_options.png) next to this script.

Uses the same 3D helpers and 2:1 view as make_furniture.py: one square is
48 x 24 pixels, x runs down-right, y down-left, z up. Floor pieces stand
on a square; wall pieces hang on the back wall (the y = -12 side).
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True
from make_furniture import (P, Piece, shade, fire, OAK, OAK_DARK, PINE, IRON, STONE,  # noqa: E402
                            FW, FH, ANCHOR, PW, PH, PA, q, floor_patch, person, piece)

LEAF = (70, 140, 60, 255)
LEAF_DARK = (45, 100, 45, 255)
POT = (190, 100, 60, 255)
STEEL = (175, 180, 190, 255)
GOLD = (220, 180, 60, 255)
RED = (160, 40, 45, 255)
DRAGON = (70, 135, 80, 255)


# ---------------------------------------------------------------------
# Floor pieces
# ---------------------------------------------------------------------
def plant():
    """A leafy fern in a clay pot."""
    p = Piece()
    p.shadow(6)
    p.cylinder(0, 0, 0, 8, 5, POT, shade(POT, 0.6), bands=[(6, shade(POT, 1.15)), (7, shade(POT, 1.15))])
    rnd = random.Random(4)
    cx, cy = P(0, 0, 8)
    for _ in range(14):   # fronds fanning out from the middle
        ang = rnd.uniform(-math.pi, 0)
        length = rnd.uniform(7, 13)
        for k in range(int(length)):
            x = cx + math.cos(ang) * k
            y = cy + math.sin(ang) * k * 0.9 - k * 0.3
            p.px(x, y, LEAF if k < length - 3 else shade(LEAF, 1.25))
            p.px(x, y + 1, LEAF_DARK)
    return p.finish()


def barrels():
    """Two ale barrels with a third resting on top."""
    p = Piece()
    p.shadow(10)
    for x, y in ((-4, 4), (5, -4)):
        p.cylinder(x, y, 0, 13, 5, OAK, shade(OAK, 1.05), bands=[(2, IRON), (10, IRON)])
    p.cylinder(0, 0, 13, 24, 5, shade(OAK, 0.95), shade(OAK, 1.1), bands=[(15, IRON), (22, IRON)])
    sx, sy = P(0, 0, 24)
    p.px(sx, sy, (60, 40, 25, 255))   # the bung
    return p.finish()


def armor():
    """A suit of armour on a wooden stand, holding a halberd."""
    p = Piece()
    p.shadow(7)
    p.box(-6, -6, 0, 6, 6, 3, OAK_DARK)                       # stand
    for x in (-2, 2):                                       # legs
        p.box(x - 1.5, -1.5, 3, x + 1.5, 1.5, 15, STEEL, edge=False)
    p.box(-4, -3, 15, 4, 3, 27, STEEL)                         # body
    p.box(-6, -2, 24, 6, 2, 27, shade(STEEL, 1.1), edge=False)   # shoulders
    p.cylinder(0, 0, 27, 33, 3, STEEL, shade(STEEL, 1.2))      # helmet
    sx, sy = P(0, 3, 30)
    p.line((sx - 2, sy), (sx + 2, sy), (40, 40, 45, 255))      # visor slit
    sx, sy = P(0, 0, 34)
    p.line((sx, sy), (sx, sy - 4), RED)                        # plume
    a, b = P(7, 0, 0), P(7, 0, 40)
    p.line(a, b, OAK_DARK)                                     # halberd shaft
    p.poly([P(7, 0, 36), P(7, 0, 31), (b[0] + 4, b[1] + 6)], STEEL)
    return p.finish()


def bookshelf():
    """A tall shelf of colourful books (stands against a wall)."""
    p = Piece()
    p.shadow(9)
    p.box(-10, -5, 0, 10, 4, 34, OAK_DARK)
    colors = [RED, (60, 90, 160, 255), (70, 130, 70, 255), GOLD, (130, 70, 140, 255), (200, 120, 60, 255)]
    rnd = random.Random(2)
    for shelf in (3, 12, 21):    # books on the front-left face
        x = -9
        while x < 8:
            w = rnd.choice((1.5, 2, 2.5))
            h = rnd.randint(6, 8)
            c = rnd.choice(colors)
            p.poly([P(x, 4, shelf), P(x + w, 4, shelf), P(x + w, 4, shelf + h), P(x, 4, shelf + h)], c)
            x += w + 0.3
        p.line(P(-10, 4, shelf - 1), P(10, 4, shelf - 1), shade(OAK_DARK, 0.7))
    return p.finish()


def fireplace(frame=0):
    """A stone fireplace with a chimney breast; warms the guests nearby."""
    p = Piece()
    p.shadow(11)
    p.box(-11, -10, 0, 11, 2, 22, STONE)                         # the hearth block
    p.box(-7, -10, 22, 7, -2, 40, shade(STONE, 0.95))            # chimney breast
    p.box(-12, -11, 20, 12, 3, 23, OAK_DARK, edge=False)         # mantel shelf
    p.poly([P(-6, 2, 2), P(6, 2, 2), P(6, 2, 14), P(0, 2, 17), P(-6, 2, 14)], (30, 22, 20, 255))   # opening
    fire(p, 0, 2, 3, 4, frame)
    rnd = random.Random(7)
    for _ in range(30):        # stones on the faces
        x, z = rnd.uniform(-11, 11), rnd.uniform(1, 21)
        if abs(x) < 7 and z < 17:
            continue
        sx, sy = P(x, 2, z)
        p.px(sx, sy, shade(STONE, rnd.choice((0.75, 1.15))))
    for x in (-8, 8):          # candles on the mantel
        sx, sy = P(x, -2, 23)
        p.line((sx, sy), (sx, sy - 3), (240, 230, 200, 255))
        p.px(sx, sy - 4, (255, 214, 96, 255))
    return p.finish()


def dragon_statue():
    """The tavern's namesake: a green dragon on a stone plinth."""
    p = Piece()
    p.shadow(10)
    p.box(-8, -8, 0, 8, 8, 9, STONE)
    p.box(-9, -9, 9, 9, 9, 11, shade(STONE, 1.1), edge=False)
    cx, cy = P(0, 0, 11)
    d = p.d
    # Folded wings behind the body
    d.polygon([(cx - 3, cy - 10), (cx - 15, cy - 26), (cx - 10, cy - 14), (cx - 13, cy - 12)], fill=shade(DRAGON, 0.75))
    d.polygon([(cx + 3, cy - 10), (cx + 14, cy - 24), (cx + 9, cy - 13), (cx + 12, cy - 11)], fill=shade(DRAGON, 0.75))
    # Sitting body and a curled tail
    d.ellipse([cx - 7, cy - 14, cx + 7, cy - 1], fill=DRAGON)
    d.ellipse([cx - 4, cy - 9, cx + 4, cy - 2], fill=(200, 190, 120, 255))       # belly
    d.arc([cx - 2, cy - 7, cx + 12, cy + 2], 270, 160, fill=DRAGON, width=3)       # tail
    # Neck and head, looking at the room
    d.polygon([(cx - 3, cy - 12), (cx + 2, cy - 12), (cx + 1, cy - 22), (cx - 3, cy - 22)], fill=DRAGON)
    d.ellipse([cx - 6, cy - 28, cx + 3, cy - 20], fill=DRAGON)
    d.polygon([(cx - 6, cy - 25), (cx - 10, cy - 23), (cx - 6, cy - 21)], fill=DRAGON)   # snout
    p.px(cx - 3, cy - 25, (240, 200, 60, 255))                                      # eye
    d.line([(cx - 2, cy - 28), (cx, cy - 32)], fill=(230, 220, 190, 255))             # horns
    d.line([(cx + 1, cy - 27), (cx + 3, cy - 31)], fill=(230, 220, 190, 255))
    for k in range(4):      # spines down the back
        p.px(cx + 3, cy - 20 + k * 4, shade(DRAGON, 1.4))
    return p.finish()


def rug():
    """A woven rug. Flat, so people can walk over it."""
    p = Piece()
    outer = [P(-11, -11), P(11, -11), P(11, 11), P(-11, 11)]
    inner = [P(-8, -8), P(8, -8), P(8, 8), P(-8, 8)]
    core = [P(-4, -4), P(4, -4), P(4, 4), P(-4, 4)]
    p.poly(outer, RED)
    p.poly(inner, GOLD)
    p.poly([P(-7, -7), P(7, -7), P(7, 7), P(-7, 7)], (130, 30, 40, 255))
    p.poly(core, GOLD)
    for x in range(-10, 12, 3):   # tassels along the front edges
        p.px(*P(x, 12), (240, 230, 200, 255))
        p.px(*P(12, x), (240, 230, 200, 255))
    return p.img   # no outline: it lies flat


# ---------------------------------------------------------------------
# Wall pieces (hang on the back wall; the game draws them on a wall segment)
# ---------------------------------------------------------------------
def on_wall(p, x, z):
    """Screen point on the back wall plane (y = -12) at x, height z."""
    return P(x, -12, z)


def painting():
    """A framed landscape: green hills under a blue sky."""
    p = Piece()
    f = [on_wall(p, -9, 18), on_wall(p, 9, 18), on_wall(p, 9, 32), on_wall(p, -9, 32)]
    p.poly(f, GOLD)
    sky = [on_wall(p, -7, 20), on_wall(p, 7, 20), on_wall(p, 7, 30), on_wall(p, -7, 30)]
    p.poly(sky, (140, 190, 230, 255))
    p.poly([on_wall(p, -7, 20), on_wall(p, 7, 20), on_wall(p, 7, 24), on_wall(p, 2, 26), on_wall(p, -3, 23), on_wall(p, -7, 25)], (90, 150, 70, 255))
    p.px(*on_wall(p, 4, 28), (250, 230, 120, 255))   # the sun
    return p.finish()


def shield():
    """A round shield with two crossed swords behind it."""
    p = Piece()
    for a, b in (((-9, 14), (9, 32)), ((9, 14), (-9, 32))):
        p.line(on_wall(p, *a), on_wall(p, *b), STEEL)
        p.line(on_wall(p, a[0], a[1] + 1), on_wall(p, b[0], b[1] + 1), shade(STEEL, 0.7))
    cx, cy = on_wall(p, 0, 23)
    p.d.ellipse([cx - 7, cy - 8, cx + 7, cy + 6], fill=RED)
    p.d.ellipse([cx - 4, cy - 5, cx + 4, cy + 3], fill=GOLD)
    p.d.ellipse([cx - 2, cy - 3, cx + 2, cy + 1], fill=shade(GOLD, 0.7))
    return p.finish()


def antlers():
    """A mounted pair of antlers on a wooden plaque."""
    p = Piece()
    p.poly([on_wall(p, -3, 20), on_wall(p, 3, 20), on_wall(p, 3, 27), on_wall(p, -3, 27)], OAK_DARK)
    cx, cy = on_wall(p, 0, 25)
    bone = (225, 210, 175, 255)
    for side in (-1, 1):
        pts = [(cx + side * 2, cy), (cx + side * 7, cy - 4), (cx + side * 9, cy - 11), (cx + side * 8, cy - 15)]
        p.d.line(pts, fill=bone, width=2)
        p.d.line([(cx + side * 7, cy - 4), (cx + side * 11, cy - 6)], fill=bone)
        p.d.line([(cx + side * 9, cy - 9), (cx + side * 12, cy - 13)], fill=bone)
    return p.finish()


# ---------------------------------------------------------------------
# Preview sheet
# ---------------------------------------------------------------------
def wall_patch(img):
    """A stretch of back wall behind the middle square, for wall pieces."""
    d = ImageDraw.Draw(img)
    for gx in range(-1, 2):
        a, b = q(gx - 0.5, -0.5), q(gx + 0.5, -0.5)
        top = 38   # the game's 76-pixel walls, at sheet scale
        d.polygon([a, b, (b[0], b[1] - top), (a[0], a[1] - top)], fill=(240, 226, 194, 255))
        panel = top * 0.38
        d.polygon([a, b, (b[0], b[1] - panel), (a[0], a[1] - panel)], fill=(152, 100, 60, 255))
        d.line([(a[0], a[1] - top), (b[0], b[1] - top)], fill=(105, 66, 38, 255), width=2)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    guests = os.path.join(root, "assets", "sprites", "guests")
    FLOOR = [(237, 201, 138, 255), (226, 185, 118, 255)]

    def floor_scene(art, against_wall=False):
        img = floor_patch(FLOOR)
        if against_wall:
            wall_patch(img)
        piece(img, art)
        person(img, os.path.join(guests, "farmer.png"), (1, 0))   # a guest for size
        return img

    def wall_scene(art):
        img = floor_patch(FLOOR)
        wall_patch(img)
        piece(img, art)
        person(img, os.path.join(guests, "merchant.png"), (0, 1))
        return img

    items = [
        ("1 Potted fern", floor_scene(plant())),
        ("2 Ale barrels", floor_scene(barrels())),
        ("3 Suit of armour", floor_scene(armor())),
        ("4 Bookshelf", floor_scene(bookshelf(), True)),
        ("5 Fireplace", floor_scene(fireplace(), True)),
        ("6 Dragon statue", floor_scene(dragon_statue())),
        ("7 Rug (walk on it)", floor_scene(rug())),
        ("8 Painting (wall)", wall_scene(painting())),
        ("9 Shield & swords (wall)", wall_scene(shield())),
        ("10 Antlers (wall)", wall_scene(antlers())),
    ]
    S, per_row = 2, 4
    cw, ch = PW * S + 16, PH * S + 34
    rows = (len(items) + per_row - 1) // per_row
    sheet = Image.new("RGBA", (cw * per_row + 10, ch * rows + 10), (52, 46, 42, 255))
    d = ImageDraw.Draw(sheet)
    small = ImageFont.load_default(size=15)
    for i, (label, img) in enumerate(items):
        x0, y0 = 10 + (i % per_row) * cw, 6 + (i // per_row) * ch
        sheet.alpha_composite(img.resize((PW * S, PH * S), Image.NEAREST), (x0, y0))
        d.text((x0 + 8, y0 + PH * S + 4), label, fill=(240, 240, 235), font=small)
    sheet.save(os.path.join(here, "decor_options.png"))
    print("wrote decor_options.png")
