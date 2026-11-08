"""Pixel-art scenery for around the tavern: trees, bushes, rocks, a lamp
post, a well, fences and a neighbour's cottage.

Run from the repo root:  python3 tools/sprites/make_outdoors.py
It writes the game's sprites to assets/sprites/outdoors/.

Same 3D helpers and 2:1 view as make_furniture.py. Tall pieces (trees,
the lamp post, the cottage) use taller frames; each entry in SIZES gives
a piece's frame size and where the middle of its square is in it.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True
import make_furniture as mf  # noqa: E402
from make_furniture import P, Piece, shade, OAK, OAK_DARK, STONE, IRON, SHADOW  # noqa: E402
from make_decor import big_canvas, glow  # noqa: E402

LEAF = (78, 140, 62, 255)
LEAF_DARK = (52, 104, 50, 255)
PINE = (40, 92, 64, 255)
BARK = (110, 76, 50, 255)
PLASTER = (236, 222, 190, 255)
TIMBER = (100, 66, 40, 255)
ROOF = (150, 64, 48, 255)

# frame width, height and the middle of the piece's square inside it
SIZES = {
    "oak": (96, 128, (48, 116)), "pine": (64, 128, (32, 116)), "lamp": (64, 104, (32, 92)),
    "cottage": (128, 150, (64, 120)), "townhouse": (128, 180, (64, 150)),
}


def canopy(p, cx, cy, r, rnd, base=LEAF):
    """A round, lumpy crown of leaves around a screen point."""
    for _ in range(14):
        a = rnd.uniform(0, math.tau)
        d = rnd.uniform(0, r * 0.6)
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d * 0.8
        s = rnd.uniform(r * 0.45, r * 0.7)
        p.d.ellipse([x - s, y - s * 0.85, x + s, y + s * 0.85], fill=shade(base, rnd.uniform(0.8, 1.0)))
    for _ in range(18):   # sunlit leaves on the upper left
        a = rnd.uniform(math.pi * 0.9, math.pi * 1.6)
        d = rnd.uniform(r * 0.3, r * 0.9)
        p.px(cx + math.cos(a) * d, cy + math.sin(a) * d * 0.8, shade(base, 1.3))


def oak():
    with big_canvas(*SIZES["oak"]):
        p = Piece()
        p.ellipse_flat(0, 0, 0, 14, SHADOW)
        p.cylinder(0, 0, 0, 30, 3, BARK, shade(BARK, 1.1))
        cx, cy = P(0, 0, 54)
        canopy(p, cx, cy, 26, random.Random(1))
        return p.finish()


def pine():
    with big_canvas(*SIZES["pine"]):
        p = Piece()
        p.ellipse_flat(0, 0, 0, 9, SHADOW)
        p.cylinder(0, 0, 0, 14, 2, BARK, shade(BARK, 1.1))
        for i, (z, w) in enumerate(((14, 18), (32, 14), (48, 10), (62, 6))):
            cx, cy = P(0, 0, z)
            p.d.polygon([(cx - w, cy), (cx, cy - 22), (cx + w, cy)], fill=shade(PINE, 1.0 + i * 0.05))
            p.d.line([(cx, cy - 22), (cx - w, cy)], fill=shade(PINE, 1.35))
        return p.finish()


def bush():
    p = Piece()
    p.shadow(9)
    cx, cy = P(0, 0, 8)
    canopy(p, cx, cy, 11, random.Random(3), LEAF_DARK)
    for k in range(4):   # a few red berries
        p.px(cx - 6 + k * 4, cy - 2 + (k % 2) * 3, (200, 50, 60, 255))
    return p.finish()


def rock():
    p = Piece()
    p.shadow(7)
    cx, cy = P(0, 0, 0)
    p.d.polygon([(cx - 10, cy), (cx - 7, cy - 8), (cx, cy - 11), (cx + 8, cy - 7), (cx + 10, cy), (cx + 3, cy + 3)], fill=STONE)
    p.d.polygon([(cx - 7, cy - 8), (cx, cy - 11), (cx + 2, cy - 5), (cx - 4, cy - 3)], fill=shade(STONE, 1.2))
    p.px(cx + 4, cy - 3, (90, 140, 70, 255))   # moss
    p.px(cx + 5, cy - 3, (90, 140, 70, 255))
    return p.finish()


def lamp():
    with big_canvas(*SIZES["lamp"]):
        p = Piece()
        p.shadow(5)
        p.box(-2, -2, 0, 2, 2, 3, IRON)
        p.box(-1, -1, 3, 1, 1, 44, IRON, edge=False)
        p.box(-4, -4, 44, 4, 4, 52, (250, 220, 140, 255), shade((250, 220, 140, 255), 0.9), shade((250, 220, 140, 255), 0.8))
        p.box(-5, -5, 52, 5, 5, 54, IRON, edge=False)
        img = p.finish()
        return glow(img, P(0, 0, 48), 16, (255, 230, 150), 120)


def well():
    p = Piece()
    p.shadow(10)
    p.cylinder(0, 0, 0, 10, 8, STONE, (40, 60, 90, 255), bands=[(3, shade(STONE, 0.8)), (7, shade(STONE, 0.8))])
    for x in (-8, 8):
        p.box(x - 1, -1, 10, x + 1, 1, 26, OAK_DARK, edge=False)
    p.poly([P(-10, -6, 26), P(10, -6, 26), P(10, 0, 31), P(-10, 0, 31)], ROOF)
    p.poly([P(-10, 0, 31), P(10, 0, 31), P(10, 6, 26), P(-10, 6, 26)], shade(ROOF, 0.8))
    p.line(P(0, 0, 25), P(0, 0, 14), (150, 130, 100, 255))   # rope
    p.box(-2, -2, 12, 2, 2, 15, OAK)                           # bucket
    return p.finish()


def fence():
    """A stretch of rail fence running along x (mirrored for along y)."""
    p = Piece()
    for x in (-11, 11):
        p.box(x - 1, -1, 0, x + 1, 1, 12, OAK_DARK, edge=False)
    for z in (4, 9):
        p.box(-12, -0.5, z, 12, 0.5, z + 1.5, OAK, edge=False)
    return p.finish()


def cottage(plaster=PLASTER, roof=ROOF, wall=30, storeys=1):
    """A timber-framed house, 2 x 2 squares. Taller walls and more
    storeys make a town house."""
    with big_canvas(*SIZES["cottage" if storeys == 1 else "townhouse"]):
        p = Piece()
        p.ellipse_flat(0, 0, 0, 26, SHADOW)
        p.box(-20, -20, 0, 20, 20, wall, plaster, shade(plaster, 0.92), shade(plaster, 0.8))
        for x in (-20, -7, 7, 20):   # timber frame on both faces
            p.line(P(x, 20, 0), P(x, 20, wall), TIMBER)
            p.line(P(20, x, 0), P(20, x, wall), TIMBER)
        floor_h = wall / storeys
        for k in range(1, storeys + 1):
            p.line(P(-20, 20, floor_h * k), P(20, 20, floor_h * k), TIMBER)
            p.line(P(20, -20, floor_h * k), P(20, 20, floor_h * k), TIMBER)
        p.poly([P(-6, 20, 0), P(2, 20, 0), P(2, 20, 12), P(-6, 20, 12)], (110, 70, 40, 255))   # door
        light = (250, 210, 120, 255)  # windows, warm light inside
        for k in range(storeys):
            z = floor_h * k + (16 if k == 0 else floor_h * 0.35)
            for y in (-12, 6):
                p.poly([P(20, y, z), P(20, y + 7, z), P(20, y + 7, z + 7), P(20, y, z + 7)], light)
            if k > 0:
                for x in (-14, 8):
                    p.poly([P(x, 20, z), P(x + 7, 20, z), P(x + 7, 20, z + 7), P(x, 20, z + 7)], light)
        top = wall + 20
        # Gable roof: ridge along x, slopes down to the y sides
        p.poly([P(-22, -22, wall), P(22, -22, wall), P(22, 0, top), P(-22, 0, top)], shade(roof, 0.85))
        p.poly([P(-22, 0, top), P(22, 0, top), P(22, 22, wall), P(-22, 22, wall)], roof)
        p.poly([P(22, -22, wall), P(22, 0, top), P(22, 22, wall)], shade(plaster, 0.75))      # gable end
        for k in range(1, 5):         # shingle rows
            p.line(P(-22, 22 - k * 4.4, wall + k * 4), P(22, 22 - k * 4.4, wall + k * 4), shade(roof, 0.7))
        p.box(8, -6, top - 6, 13, -1, top + 8, (140, 120, 110, 255))     # chimney
        return p.finish()


def stall(awning):
    """A market stall: a counter of goods under a striped awning."""
    p = Piece()
    p.shadow(11)
    p.box(-10, -7, 0, 10, 7, 10, OAK)
    rnd = random.Random(sum(awning))
    goods = [(200, 50, 50, 255), (230, 180, 80, 255), (120, 170, 70, 255), (190, 130, 70, 255)]
    for _ in range(14):     # apples, bread, greens on the counter
        sx, sy = P(rnd.uniform(-8, 8), rnd.uniform(-5, 5), 11)
        p.d.ellipse([sx - 1.5, sy - 1.5, sx + 1.5, sy + 1.5], fill=rnd.choice(goods))
    for x in (-10, 10):
        p.box(x - 1, -8, 0, x + 1, -6, 26, OAK_DARK, edge=False)
    for k in range(5):      # striped awning sloping towards us
        x0 = -11 + k * 4.4
        c = awning if k % 2 == 0 else (240, 232, 215, 255)
        p.poly([P(x0, -8, 26), P(x0 + 4.4, -8, 26), P(x0 + 4.4, 8, 18), P(x0, 8, 18)], c)
    return p.finish()


BLUE_PLASTER, SLATE = (200, 210, 220, 255), (80, 90, 110, 255)
PIECES = {
    "oak": oak, "pine": pine, "bush": bush, "rock": rock, "lamp": lamp, "well": well, "fence": fence,
    "cottage": cottage,
    "cottage_blue": lambda: cottage(BLUE_PLASTER, SLATE),
    "cottage_ochre": lambda: cottage((220, 190, 130, 255), (120, 80, 50, 255)),
    "townhouse": lambda: cottage(PLASTER, ROOF, 54, 2),
    "townhouse_blue": lambda: cottage(BLUE_PLASTER, SLATE, 54, 2),
    "townhouse_rose": lambda: cottage((225, 190, 180, 255), (110, 60, 50, 255), 54, 2),
    "stall_red": lambda: stall((180, 50, 50, 255)),
    "stall_blue": lambda: stall((60, 90, 160, 255)),
    "stall_green": lambda: stall((70, 130, 70, 255)),
}


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(os.path.dirname(os.path.dirname(here)), "assets", "sprites", "outdoors")
    os.makedirs(out, exist_ok=True)
    for name, make in PIECES.items():
        make().save(os.path.join(out, name + ".png"))
    print("wrote", len(PIECES), "outdoor sprites")
