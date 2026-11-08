"""Pixel-art decorations for the isometric Drunken Dragon.

Run from the repo root:  python3 tools/sprites/make_decor.py
It writes preview sheets (decor_options.png, and fae_options.png with the
2 x 2 dragon statue and the fae wall mounts) next to this script.

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
import make_furniture as mf  # noqa: E402
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


class big_canvas:
    """Draws on a larger canvas for pieces bigger than one square, e.g.
    with big_canvas(112, 128, (56, 100)): ... The square coordinates then
    centre on the piece's whole footprint."""
    def __init__(self, w, h, anchor):
        self.new = (w, h, anchor)

    def __enter__(self):
        self.old = (mf.FW, mf.FH, mf.ANCHOR)
        mf.FW, mf.FH, mf.ANCHOR = self.new

    def __exit__(self, *_):
        mf.FW, mf.FH, mf.ANCHOR = self.old


BIG = (112, 128, (56, 100))   # canvas for a 2 x 2 piece, anchored at its middle


def dragon_statue():
    """The tavern's namesake: a big green dragon on a stone plinth. It
    takes up 2 x 2 squares (x and y run -24..24 around its middle)."""
    with big_canvas(*BIG):
        p = Piece()
        p.shadow(21)
        p.box(-19, -19, 0, 19, 19, 12, STONE)
        p.box(-21, -21, 12, 21, 21, 15, shade(STONE, 1.1), edge=False)
        rnd = random.Random(5)
        for _ in range(40):    # chisel marks on the plinth
            x, z = rnd.uniform(-18, 18), rnd.uniform(2, 11)
            p.px(*P(x, 19, z), shade(STONE, 0.75))
            p.px(*P(19, x, z), shade(STONE, 0.6))
        # A brass plaque on the front
        p.poly([P(-7, 19, 4), P(7, 19, 4), P(7, 19, 9), P(-7, 19, 9)], GOLD)
        cx, cy = P(0, 0, 15)
        k = 2.0   # the dragon is drawn at twice the one-square size
        d = p.d

        def pt(x, y):
            return (cx + x * k, cy + y * k)

        dark = shade(DRAGON, 0.72)
        # Spread wings behind the body, with membrane lines
        for side in (-1, 1):
            wing = [pt(side * 3, -11), pt(side * 16, -30), pt(side * 13, -18), pt(side * 17, -16), pt(side * 10, -9)]
            d.polygon(wing, fill=dark)
            for tip in (pt(side * 13, -18), pt(side * 17, -16)):
                d.line([pt(side * 3, -11), tip], fill=shade(DRAGON, 0.55))
            d.line([pt(side * 3, -11), pt(side * 16, -30)], fill=shade(DRAGON, 1.15), width=2)
        # Sitting body, belly scales and a curled tail
        d.ellipse([*pt(-7, -15), *pt(7, -1)], fill=DRAGON)
        d.ellipse([*pt(-4, -10), *pt(4, -2)], fill=(205, 192, 120, 255))
        for row in range(3):
            y = -8 + row * 2
            d.line([pt(-3, y), pt(3, y)], fill=(170, 155, 95, 255))
        d.arc([*pt(-1, -7), *pt(14, 3)], 270, 160, fill=DRAGON, width=6)
        d.polygon([pt(12, 1), pt(16, -1), pt(13, 3)], fill=dark)        # tail tip
        # Front claws on the plinth
        for x in (-5, 3):
            d.ellipse([*pt(x, -2), *pt(x + 3, 0)], fill=dark)
        # Neck and head, looking out at the room
        d.polygon([pt(-3, -13), pt(2, -13), pt(1, -23), pt(-3, -23)], fill=DRAGON)
        d.ellipse([*pt(-6, -29), *pt(3, -21)], fill=DRAGON)
        d.polygon([pt(-6, -26), pt(-11, -24), pt(-11, -22), pt(-6, -21)], fill=DRAGON)   # snout
        p.px(*pt(-10, -24), (40, 30, 30, 255))                                            # nostril
        d.rectangle([*pt(-3.5, -26), *pt(-2, -25)], fill=(250, 210, 60, 255))           # eye
        p.px(*pt(-2.5, -25.5), (40, 30, 30, 255))
        bone = (232, 222, 190, 255)
        d.line([pt(-2, -28.5), pt(1, -34)], fill=bone, width=2)                          # horns
        d.line([pt(1, -28), pt(4, -33)], fill=bone, width=2)
        for n in range(6):      # spines down the neck and back
            p.px(*pt(3, -21 + n * 3), shade(DRAGON, 1.45))
            p.px(*pt(3.5, -21 + n * 3), shade(DRAGON, 1.45))
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
# Fae wall mounts: earned through objectives and special events, not
# bought outright. They glow softly (the glow has no outline).
# ---------------------------------------------------------------------
SILVER = (205, 210, 225, 255)
BIRCH = (225, 220, 205, 255)
IVY = (60, 120, 70, 255)


def glow(img, center, radius, color, strength=110):
    """A soft halo of light, laid over a finished piece."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for r in range(int(radius), 0, -1):
        a = int(strength * (1 - r / radius) ** 1.5)
        d.ellipse([center[0] - r, center[1] - r * 0.85, center[0] + r, center[1] + r * 0.85], fill=color[:3] + (a,))
    img.alpha_composite(layer)
    return img


def fae_lantern(frame=0):
    """An iron bracket holding a glass jar of drifting will-o'-wisps."""
    p = Piece()
    p.line(on_wall(p, 0, 34), on_wall(p, 0, 26), IRON)             # bracket on the wall
    top = P(0, -6, 34)
    p.line(on_wall(p, 0, 34), top, IRON)                           # arm out from the wall
    p.line(top, (top[0], top[1] + 3), IRON)                        # chain
    jx, jy = top[0], top[1] + 4
    p.d.rectangle([jx - 4, jy, jx + 4, jy + 1], fill=IRON)          # lid
    p.d.rectangle([jx - 4, jy + 2, jx + 4, jy + 12], fill=(170, 210, 200, 255))   # glass
    p.d.line([(jx - 3, jy + 3), (jx - 3, jy + 10)], fill=(225, 245, 240, 255))    # shine
    rnd = random.Random(frame)
    wisps = []
    for _ in range(3):
        wx, wy = jx + rnd.randint(-2, 2), jy + rnd.randint(4, 10)
        p.px(wx, wy, (255, 250, 190, 255))
        wisps.append((wx, wy))
    img = p.finish()
    return glow(img, (jx, jy + 7), 16, (230, 255, 170))


def moonflower_wreath():
    """A wreath of dark leaves with pale moonflowers that glow at night."""
    p = Piece()
    cx, cy = on_wall(p, 0, 25)
    rnd = random.Random(3)
    for n in range(36):           # leaves around the ring
        a = n / 36 * math.tau
        x, y = cx + math.cos(a) * 9, cy + math.sin(a) * 8
        p.d.ellipse([x - 2, y - 1.5, x + 2, y + 1.5], fill=rnd.choice((IVY, shade(IVY, 0.8), shade(IVY, 1.2))))
    flowers = []
    for n in range(5):            # five moonflowers
        a = n / 5 * math.tau - 1.2
        x, y = cx + math.cos(a) * 9, cy + math.sin(a) * 8
        p.d.ellipse([x - 2.5, y - 2.5, x + 2.5, y + 2.5], fill=(235, 240, 255, 255))
        p.px(x, y, (190, 210, 255, 255))
        flowers.append((x, y))
    p.d.polygon([(cx - 2, cy + 8), (cx + 2, cy + 8), (cx + 3, cy + 13), (cx, cy + 11), (cx - 3, cy + 13)], fill=(150, 160, 220, 255))   # ribbon
    img = p.finish()
    for f in flowers:
        glow(img, f, 6, (200, 215, 255), 60)
    return img


def glowcap_shelf():
    """A little shelf of glowing toadstools from the fae woods."""
    p = Piece()
    p.box(-8, -12, 16, 8, -7, 18, OAK_DARK)                       # shelf
    for x in (-6, 6):                                             # brackets
        p.line(on_wall(p, x, 16), P(x, -9, 12), OAK_DARK)
    caps = []
    for x, h, r in ((-5, 4, 2.5), (-1, 7, 3.5), (3, 5, 2.5), (6, 3, 2)):
        base = P(x, -9.5, 18)
        p.d.line([base, (base[0], base[1] - h)], fill=(225, 230, 220, 255), width=2)      # stalk
        top = (base[0], base[1] - h)
        p.d.pieslice([top[0] - r * 1.4, top[1] - r * 1.2, top[0] + r * 1.4, top[1] + r * 1.2], 180, 360, fill=(70, 200, 210, 255))
        p.px(top[0] - 1, top[1] - r * 0.6, (210, 255, 255, 255))
        caps.append(top)
    img = p.finish()
    for c in caps:
        glow(img, (c[0], c[1] - 1), 8, (90, 230, 240), 55)
    return img


def gossamer_wings():
    """A birch-framed case holding a pair of shimmering fae wings."""
    p = Piece()
    frame = [on_wall(p, -9, 16), on_wall(p, 9, 16), on_wall(p, 9, 34), on_wall(p, -9, 34)]
    p.poly(frame, BIRCH)
    back = [on_wall(p, -7.5, 17.5), on_wall(p, 7.5, 17.5), on_wall(p, 7.5, 32.5), on_wall(p, -7.5, 32.5)]
    p.poly(back, (40, 45, 70, 255))
    cx, cy = on_wall(p, 0, 25)
    for side in (-1, 1):          # upper and lower wings on each side
        p.d.polygon([(cx, cy), (cx + side * 8, cy - 9), (cx + side * 9, cy - 3), (cx + side * 2, cy + 1)], fill=(175, 160, 235, 255))
        p.d.polygon([(cx, cy + 1), (cx + side * 6, cy + 4), (cx + side * 5, cy + 7), (cx + side * 1, cy + 3)], fill=(140, 220, 215, 255))
        p.d.line([(cx, cy), (cx + side * 8, cy - 8)], fill=(235, 230, 255, 255))
    for x, z in ((-8, 17), (8, 33), (-8, 33)):    # knots in the birch
        p.px(*on_wall(p, x, z), (90, 80, 70, 255))
    img = p.finish()
    return glow(img, (cx, cy - 1), 12, (210, 190, 255), 45)


def fae_mirror():
    """An oval mirror in a frame of silver vines; its glass shimmers."""
    p = Piece()
    cx, cy = on_wall(p, 0, 25)
    p.d.ellipse([cx - 8, cy - 11, cx + 8, cy + 11], fill=SILVER)
    p.d.ellipse([cx - 6, cy - 9, cx + 6, cy + 9], fill=(150, 185, 210, 255))
    p.d.ellipse([cx - 5, cy - 8, cx + 1, cy + 2], fill=(190, 215, 235, 255))      # reflection
    for a in range(0, 360, 40):   # vine curls and silver leaves
        r = math.radians(a)
        x, y = cx + math.cos(r) * 8.5, cy + math.sin(r) * 11.5
        p.px(x, y, (150, 160, 185, 255))
        p.px(x + 1, y - 1, (235, 240, 250, 255))
    p.d.polygon([(cx - 3, cy - 12), (cx, cy - 16), (cx + 3, cy - 12)], fill=SILVER)    # crest
    img = p.finish()
    for spot in ((cx + 2, cy - 4), (cx - 3, cy + 5)):   # sparkles
        img.putpixel((int(spot[0]), int(spot[1])), (255, 255, 255, 255))
    return glow(img, (cx, cy), 13, (200, 230, 255), 40)


def faerie_crown():
    """A crown of birch branches wound with ivy, where fireflies rest."""
    p = Piece()
    cx, cy = on_wall(p, 0, 22)
    for side in (-1, 1):          # branching like antlers
        pts = [(cx + side * 1, cy), (cx + side * 6, cy - 5), (cx + side * 8, cy - 12), (cx + side * 7, cy - 17)]
        p.d.line(pts, fill=BIRCH, width=2)
        p.d.line([(cx + side * 6, cy - 5), (cx + side * 11, cy - 8)], fill=BIRCH)
        p.d.line([(cx + side * 8, cy - 11), (cx + side * 12, cy - 15)], fill=BIRCH)
        for t in range(4):        # ivy leaves along the branch
            x, y = cx + side * (2 + t * 2), cy - 2 - t * 3.5
            p.d.ellipse([x - 1.5, y - 1, x + 1.5, y + 1], fill=IVY)
    p.d.ellipse([cx - 3, cy - 2, cx + 3, cy + 3], fill=(120, 90, 60, 255))     # knot where they meet
    img = p.finish()
    for spot in ((cx - 9, cy - 13), (cx + 10, cy - 9), (cx + 4, cy - 18), (cx - 5, cy - 4)):
        img.putpixel((int(spot[0]), int(spot[1])), (250, 255, 170, 255))
        glow(img, spot, 5, (240, 255, 150), 70)
    return img


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

    # Second sheet: the 2 x 2 dragon and the fae wall mounts, on a darker
    # evening wall so the glow shows.
    def dragon_scene():
        w, h = 176, 150
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        o = (88, 92)

        def sq(x, y):
            return (o[0] + (x - y) * 24, o[1] + (x + y) * 12)
        for gx in range(-2, 2):
            for gy in range(-2, 2):
                pts = [sq(gx, gy), sq(gx + 1, gy), sq(gx + 1, gy + 1), sq(gx, gy + 1)]
                d.polygon(pts, fill=FLOOR[(gx + gy) % 2], outline=(205, 160, 98))
        art = dragon_statue()
        img.alpha_composite(art, (o[0] - BIG[2][0], o[1] - BIG[2][1]))
        frame = Image.open(os.path.join(guests, "farmer.png")).convert("RGBA").crop((0, 0, 32, 40))
        x, y = sq(1.5, 0.5)
        img.alpha_composite(frame, (round(x - 16), round(y - 37)))
        return img

    fae = [
        ("A Faerie lantern", fae_lantern()),
        ("B Moonflower wreath", moonflower_wreath()),
        ("C Glowcap shelf", glowcap_shelf()),
        ("D Gossamer wings", gossamer_wings()),
        ("E Fae mirror", fae_mirror()),
        ("F Faerie crown", faerie_crown()),
    ]
    big = dragon_scene()
    cw, ch = PW * S + 16, PH * S + 34
    left = big.width * S + 20
    sheet = Image.new("RGBA", (left + cw * 3 + 10, ch * 2 + 10), (52, 46, 42, 255))
    d = ImageDraw.Draw(sheet)
    sheet.alpha_composite(big.resize((big.width * S, big.height * S), Image.NEAREST), (10, 40))
    d.text((18, 40 + big.height * S + 4), "6 Dragon statue, now 2 x 2", fill=(240, 240, 235), font=small)
    for i, (label, art) in enumerate(fae):
        img = floor_patch(FLOOR)
        wall_patch(img)
        # Evening light on the room only, so the glow shows
        dim = Image.new("RGBA", img.size, (20, 20, 60, 90))
        dim.putalpha(Image.eval(img.getchannel("A"), lambda a: 90 if a else 0))
        img.alpha_composite(dim)
        piece(img, art)
        x0, y0 = left + (i % 3) * cw, 6 + (i // 3) * ch
        sheet.alpha_composite(img.resize((PW * S, PH * S), Image.NEAREST), (x0, y0))
        d.text((x0 + 8, y0 + PH * S + 4), label, fill=(240, 240, 235), font=small)
    sheet.save(os.path.join(here, "fae_options.png"))
    print("wrote fae_options.png")
    print("wrote decor_options.png")
