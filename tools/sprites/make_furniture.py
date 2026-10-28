"""Pixel-art furniture for the isometric Drunken Dragon.

Run from the repo root:  python3 tools/sprites/make_furniture.py
It writes the game's furniture sprites to assets/sprites/furniture/ and a
preview sheet of options still being picked (furniture_options.png) next
to this script.

Furniture is built from simple 3D shapes (boxes and cylinders) and drawn
in the same 2:1 isometric view as the floor. One square of floor is 48 x 24
pixels here; the game draws everything at 2x, like the characters.

Coordinates: x runs down-right, y runs down-left, z is straight up (in
pixels). A square spans -12..12 in x and y, with (0, 0) at its middle.
"""
import math
import random
from PIL import Image, ImageDraw, ImageFont

FW, FH = 64, 72            # one piece's canvas
ANCHOR = (32, 58)          # where the middle of its square lands
OUTLINE = (40, 26, 20, 255)
SHADOW = (0, 0, 0, 60)


def P(x, y, z=0.0):
    return (ANCHOR[0] + (x - y), ANCHOR[1] + (x + y) / 2.0 - z)


def shade(c, f):
    return (min(255, int(c[0] * f)), min(255, int(c[1] * f)), min(255, int(c[2] * f)), 255)


class Piece:
    def __init__(self):
        self.img = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def px(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < FW and 0 <= y < FH:
            self.img.putpixel((x, y), c)

    def poly(self, pts, c):
        self.d.polygon([(round(a), round(b)) for a, b in pts], fill=c, outline=c)

    def line(self, a, b, c):
        self.d.line([(round(a[0]), round(a[1])), (round(b[0]), round(b[1]))], fill=c)

    def shadow(self, r):
        self.ellipse_flat(0, 0, 0, r, SHADOW)

    def ellipse_flat(self, x, y, z, r, c):
        cx, cy = P(x, y, z)
        rx, ry = r * 1.414, r * 0.707
        self.d.ellipse([round(cx - rx), round(cy - ry), round(cx + rx), round(cy + ry)], fill=c)

    def box(self, x0, y0, z0, x1, y1, z1, top, left=None, right=None, edge=True):
        """A box from (x0, y0, z0) to (x1, y1, z1). Visible faces: the top,
        the +y side (lower left on screen) and the +x side (lower right)."""
        left = left or shade(top, 0.82)
        right = right or shade(top, 0.66)
        self.poly([P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z1), P(x0, y1, z1)], left)
        self.poly([P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1)], right)
        self.poly([P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)], top)
        if edge:   # a light edge where the top meets the sides
            hi = shade(top, 1.15)
            self.line(P(x0, y1, z1), P(x1, y1, z1), hi)
            self.line(P(x1, y1, z1), P(x1, y0, z1), hi)

    def cylinder(self, x, y, z0, z1, r, side, top, bands=()):
        """An upright cylinder; `bands` are (z, color) rings around it."""
        cx, _ = P(x, y, 0)
        rx = r * 1.414
        for z in range(int(z0), int(z1)):
            _, cy = P(x, y, z)
            ry = r * 0.707
            ring = dict(bands).get(z)
            for sx in range(int(cx - rx), int(cx + rx) + 1):
                t = (sx + 0.5 - cx) / rx
                if abs(t) > 1:
                    continue
                # light from the left: lighter on the left, darker on the right
                f = 1.08 - 0.42 * (t + 1) / 2
                base = ring if ring else side
                self.px(sx, cy + ry * math.sqrt(1 - t * t), shade(base, f))
                self.px(sx, cy + ry * math.sqrt(1 - t * t) - 1, shade(base, f))
        self.ellipse_flat(x, y, z1, r, top)

    def finish(self):
        outline(self.img)
        return self.img


def outline(img):
    src = img.copy()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            if src.getpixel((x, y))[3] > 100:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src.getpixel((nx, ny))[3] > 100:
                    img.putpixel((x, y), OUTLINE)
                    break


OAK = (176, 116, 64, 255)
OAK_DARK = (120, 76, 40, 255)
PINE = (205, 150, 88, 255)
IRON = (70, 66, 70, 255)
STONE = (150, 146, 140, 255)
BRICK = (170, 74, 52, 255)
MORTAR = (205, 180, 150, 255)
FIRE = (240, 120, 40, 255)
FIRE_HOT = (255, 214, 96, 255)
EMBER = (200, 60, 30, 255)
PLATE = (245, 242, 232, 255)
FOAM = (250, 246, 230, 255)
ALE = (214, 150, 50, 255)


def mug(p, x, y, z):
    p.cylinder(x, y, z, z + 5, 1.6, (150, 100, 55, 255), FOAM, bands=[(1, IRON), (4, IRON)])
    sx, sy = P(x, y, z + 3)
    p.px(sx + 3, sy, (120, 80, 45, 255)); p.px(sx + 3, sy + 1, (120, 80, 45, 255))


def candle(p, x, y, z):
    p.box(x - 1, y - 1, z, x + 1, y + 1, z + 5, (240, 230, 200, 255), edge=False)
    sx, sy = P(x, y, z + 6)
    p.px(sx, sy, FIRE_HOT)
    p.px(sx, sy - 1, FIRE)


# ---------------------------------------------------------------------
# Tables
# ---------------------------------------------------------------------
def table_round():
    """Round oak table on one thick leg, with a candle."""
    p = Piece()
    p.shadow(10)
    p.cylinder(0, 0, 0, 3, 5, OAK_DARK, OAK_DARK)          # foot
    p.cylinder(0, 0, 3, 13, 2, OAK_DARK, OAK_DARK)          # post
    p.cylinder(0, 0, 13, 17, 10, OAK, shade(OAK, 1.1))      # top
    cx, cy = P(0, 0, 17)
    for i in (-6, 0, 6):   # wood grain
        p.line((cx - 9 + abs(i), cy + i / 3), (cx + 9 - abs(i), cy + i / 3), shade(OAK, 1.0))
    candle(p, -2, -2, 17)
    return p.finish()


def table_trestle():
    """Square plank table on X-shaped trestle legs, with two mugs."""
    p = Piece()
    p.shadow(11)
    for x in (-7, 7):   # X legs at each end
        p.line(P(x, -7, 0), P(x, 7, 14), OAK_DARK)
        p.line(P(x, 7, 0), P(x, -7, 14), OAK_DARK)
        p.line(P(x + 1, -7, 0), P(x + 1, 7, 14), shade(OAK_DARK, 0.8))
        p.line(P(x + 1, 7, 0), P(x + 1, -7, 14), shade(OAK_DARK, 0.8))
    p.box(-6, -1, 5, 6, 1, 7, OAK_DARK, edge=False)          # stretcher
    p.box(-10, -9, 14, 10, 9, 18, PINE)
    for y in (-3, 3):  # plank gaps
        p.line(P(-10, y, 18), P(10, y, 18), shade(PINE, 0.8))
    mug(p, -4, -4, 18)
    mug(p, 4, 3, 18)
    return p.finish()


def table_barrel():
    """An ale barrel standing on end, used as a table."""
    p = Piece()
    p.shadow(9)
    p.cylinder(0, 0, 0, 18, 8, OAK, shade(OAK, 1.05),
               bands=[(2, IRON), (3, IRON), (14, IRON), (15, IRON)])
    # staves: darker vertical lines down the front
    for sx_off in (-6, -2, 2, 6):
        cx, cy = P(0, 0, 0)
        for z in range(1, 18):
            if z in (2, 3, 14, 15):
                continue
            t = sx_off / (8 * 1.414)
            p.px(cx + sx_off, cy + 8 * 0.707 * math.sqrt(1 - t * t) - z, shade(OAK, 0.72))
    p.cylinder(0, 0, 18, 19, 9, shade(OAK, 0.9), shade(OAK, 1.15))   # a lid that sticks out
    mug(p, 2, -2, 19)
    return p.finish()


# ---------------------------------------------------------------------
# Hearths (the cook stands behind it, so it stays low)
# ---------------------------------------------------------------------
def fire(p, x, y, z, size, frame):
    rnd = random.Random(frame * 7 + 1)
    cx, cy = P(x, y, z)
    for i in range(size * 5):
        dx = rnd.randint(-size, size)
        h = rnd.randint(1, size + 2 - abs(dx) // 2)
        for k in range(h):
            p.px(cx + dx, cy - k, FIRE_HOT if k < h / 2 and abs(dx) < size / 2 else FIRE)
    for dx in range(-size, size + 1, 2):
        p.px(cx + dx, cy + 1, EMBER)


def hearth_stone(frame=0):
    """A ring of field stones around an open fire, with a cauldron."""
    p = Piece()
    p.shadow(11)
    p.box(-10, -10, 0, 10, 10, 8, STONE)
    rnd = random.Random(3)
    for _ in range(26):   # stones
        x, y = rnd.randint(-10, 9), rnd.randint(-10, 9)
        if abs(x) < 7 and abs(y) < 7:
            continue
        sx, sy = P(x, y, 8)
        p.px(sx, sy, shade(STONE, rnd.choice((0.8, 1.15))))
        p.px(sx + 1, sy, shade(STONE, 0.9))
    for x in range(-9, 10, 4):    # stones on the front faces
        for z in (2, 6):
            sx, sy = P(x + (2 if z == 6 else 0), 10, z)
            p.px(sx, sy, shade(STONE, 0.65))
            sx, sy = P(10, x + (2 if z == 6 else 0), z)
            p.px(sx, sy, shade(STONE, 0.5))
    p.box(-7, -7, 7, 7, 7, 8, (55, 45, 40, 255), edge=False)    # the fire pit
    fire(p, 0, 0, 8, 5, frame)
    p.cylinder(0, 0, 11, 18, 6, (60, 58, 62, 255), (110, 80, 50, 255), bands=[(16, (85, 82, 88, 255))])   # cauldron
    sx, sy = P(0, 0, 18)
    for dx in (-3, 0, 3):
        p.px(sx + dx, sy, (150, 200, 90, 255))   # bubbling stew
    return p.finish()


def hearth_stove(frame=0, lit=True):
    """A brick cooking range with an iron top, two pots and a fire door.
    Unlit (nobody cooking) it just glows; lit, the fire and steam move."""
    p = Piece()
    p.shadow(11)
    p.box(-10, -10, 0, 10, 10, 15, BRICK, shade(BRICK, 0.9), shade(BRICK, 0.72))
    for z in (3, 7, 11):    # mortar lines
        p.line(P(-10, 10, z), P(10, 10, z), shade(MORTAR, 0.9))
        p.line(P(10, 10, z), P(10, -10, z), shade(MORTAR, 0.75))
    for i, z in enumerate((0, 3, 7, 11)):
        for x in range(-8 + (i % 2) * 3, 10, 6):
            p.line(P(x, 10, z), P(x, 10, z + 3), shade(MORTAR, 0.9))
            p.line(P(10, x, z), P(10, x, z + 3), shade(MORTAR, 0.75))
    p.box(-10, -10, 15, 10, 10, 17, IRON, shade(IRON, 1.2), shade(IRON, 0.9))
    # fire door in the front-left face
    p.poly([P(-5, 10, 3), P(3, 10, 3), P(3, 10, 10), P(-5, 10, 10)], (35, 25, 25, 255))
    fire(p, -1, 10, 3.5, 3 if lit else 1, frame)
    p.cylinder(-4, -4, 17, 23, 5, (70, 70, 78, 255), (120, 85, 50, 255))   # stew pot
    p.cylinder(5, 4, 17, 18, 4, (40, 40, 44, 255), (25, 25, 28, 255))      # frying pan
    p.line(P(9, 4, 18), P(12, 4, 18), (40, 40, 44, 255))
    sx, sy = P(5, 4, 18)
    p.px(sx - 1, sy, (250, 240, 200, 255)); p.px(sx + 1, sy, (240, 180, 60, 255))   # an egg
    sx, sy = P(-4, -4, 23)
    for k in range(3 if lit else 0):  # steam
        p.px(sx + (1 if (k + frame) % 2 else -1), sy - 3 - k * 2, (235, 235, 235, 200))
    return p.finish()


def hearth_spit(frame=0):
    """A low stone fire pit with a meat roast turning on a spit."""
    p = Piece()
    p.shadow(11)
    p.box(-10, -8, 0, 10, 8, 6, STONE)
    p.box(-8, -6, 5, 8, 6, 6, (55, 45, 40, 255), edge=False)
    fire(p, 0, 0, 6, 5, frame)
    for x in (-10, 10):     # iron uprights
        p.box(x - 1, -1, 6, x + 1, 1, 20, IRON, edge=False)
    p.line(P(-11, 0, 18), P(11, 0, 18), (150, 150, 155, 255))   # the spit
    roast = (165, 85, 45, 255)
    for x in range(-6, 7):     # a roast lying along the spit, fattest in the middle
        r = 4.2 * math.sqrt(1 - (x / 7.5) ** 2)
        sx, sy = P(x, 0, 18)
        p.d.ellipse([round(sx - r), round(sy - r), round(sx + r), round(sy + r)], fill=shade(roast, 0.75))
        p.d.ellipse([round(sx - r), round(sy - r), round(sx + r * 0.5), round(sy + r * 0.3)], fill=roast)
    for x in (-3, 1, 4):
        sx, sy = P(x, 0, 18)
        p.px(sx - 1, sy - 3, (225, 150, 90, 255))   # crackling shine
    sx, sy = P(11, 0, 18)
    p.line((sx, sy), (sx + 3, sy + 3), (150, 150, 155, 255))    # crank handle
    return p.finish()


# ---------------------------------------------------------------------
# The pass (where cooks leave plates and waiters pick them up). It needs
# a flat top for up to three plates; the game draws the plates.
# ---------------------------------------------------------------------
def pass_plain():
    """A stone-topped wooden counter, nothing else."""
    p = Piece()
    p.shadow(11)
    p.box(-11, -9, 0, 11, 9, 12, OAK, shade(OAK, 0.85), shade(OAK, 0.68))
    for x in range(-7, 11, 6):   # panels
        p.line(P(x, 9, 2), P(x, 9, 10), OAK_DARK)
    p.box(-12, -10, 12, 12, 10, 14, (214, 200, 176, 255))
    return p.finish()


def pass_bell():
    """A marble-topped counter with a brass bell to ring when food's up."""
    p = Piece()
    p.shadow(11)
    p.box(-11, -9, 0, 11, 9, 12, (110, 80, 60, 255))
    p.box(-12, -10, 12, 12, 10, 14, (232, 232, 226, 255), (190, 190, 186, 255), (160, 160, 158, 255))
    p.cylinder(8, 6, 14, 15, 3, (150, 110, 40, 255), (170, 130, 50, 255))
    p.cylinder(8, 6, 15, 18, 2, (215, 170, 60, 255), (240, 200, 90, 255))
    sx, sy = P(8, 6, 19)
    p.px(sx, sy, (240, 200, 90, 255))
    return p.finish()


def pass_window():
    """A serving hatch: a counter under a little tiled roof."""
    p = Piece()
    p.shadow(11)
    p.box(-11, -9, 0, 11, 9, 12, PINE, shade(PINE, 0.85), shade(PINE, 0.68))
    p.box(-12, -10, 12, 12, 10, 14, OAK)
    for x in (-11, 11):    # posts at the back corners
        p.box(x - 1, -10, 14, x + 1, -8, 30, OAK_DARK, edge=False)
    roof = (170, 70, 50, 255)
    p.poly([P(-13, -11, 30), P(13, -11, 30), P(13, -4, 34), P(-13, -4, 34)], roof)
    p.poly([P(-13, -4, 34), P(13, -4, 34), P(13, -4, 32), P(-13, -4, 32)], shade(roof, 0.7))
    for x in range(-11, 13, 4):
        p.line(P(x, -11, 30), P(x, -4, 34), shade(roof, 0.8))
    return p.finish()


# ---------------------------------------------------------------------
# Preview sheet, with people next to each piece for size
# ---------------------------------------------------------------------
PW, PH = 128, 104          # one preview patch
PA = (64, 74)              # the middle square's middle in the patch


def q(x, y):
    """Screen spot of square (x, y) in the preview patch."""
    return (PA[0] + (x - y) * 24, PA[1] + (x + y) * 12)


def floor_patch(colors):
    img = Image.new("RGBA", (PW, PH), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for gx in range(-1, 2):
        for gy in range(-1, 2):
            c = colors[(gx + gy) % 2]
            pts = [q(gx - 0.5, gy - 0.5), q(gx + 0.5, gy - 0.5), q(gx + 0.5, gy + 0.5), q(gx - 0.5, gy + 0.5)]
            d.polygon(pts, fill=c, outline=(205, 160, 98) if colors[0][0] > 200 else (140, 142, 145))
    return img


def person(img, sheet, cell, flip=False):
    """Pastes a character's front idle frame, feet on the given square."""
    frame = Image.open(sheet).convert("RGBA").crop((0, 0, 32, 40))
    if flip:
        frame = frame.transpose(Image.FLIP_LEFT_RIGHT)
    x, y = q(*cell)
    img.alpha_composite(frame, (round(x - 16), round(y - 37)))


def piece(img, art):
    img.alpha_composite(art, (PA[0] - ANCHOR[0], PA[1] - ANCHOR[1]))


if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    staff = os.path.join(root, "assets", "sprites", "staff")
    guests = os.path.join(root, "assets", "sprites", "guests")
    FLOOR = [(237, 201, 138, 255), (226, 185, 118, 255)]
    KITCHEN = [(176, 178, 180, 255), (160, 163, 166, 255)]

    def table_scene(art):
        img = floor_patch(FLOOR)
        piece(img, art)
        person(img, os.path.join(guests, "farmer.png"), (1, 0))   # guest at its side
        return img

    def hearth_scene(art):
        img = floor_patch(KITCHEN)
        person(img, os.path.join(staff, "chef.png"), (0, -1))     # cook behind it
        piece(img, art)
        return img

    def pass_scene(art):
        img = floor_patch(KITCHEN)
        person(img, os.path.join(staff, "tavern_cook.png"), (0, -1))
        piece(img, art)
        person(img, os.path.join(staff, "maid.png"), (0, 1))       # waiter in front
        return img

    # The pieces the game uses (chosen: plank trestle table, brick stove).
    out = os.path.join(root, "assets", "sprites", "furniture")
    os.makedirs(out, exist_ok=True)
    table_trestle().save(os.path.join(out, "table.png"))
    # Hearth sheet: frame 0 is the idle glow, frames 1-3 the cooking fire.
    hearth = Image.new("RGBA", (FW * 4, FH), (0, 0, 0, 0))
    hearth.paste(hearth_stove(0, lit=False), (0, 0))
    for f in range(3):
        hearth.paste(hearth_stove(f, lit=True), (FW * (f + 1), 0))
    hearth.save(os.path.join(out, "hearth.png"))

    rows = [
        ("Pass (no sign)", [("A  Plain stone-topped counter", pass_scene(pass_plain())),
                            ("B  Marble + brass bell", pass_scene(pass_bell())),
                            ("C  Serving hatch", pass_scene(pass_window()))]),
    ]
    S = 2                   # the game's own size
    cw, ch = PW * S + 20, PH * S + 48
    sheet = Image.new("RGBA", (cw * 3 + 10, ch * len(rows) + 10), (52, 46, 42, 255))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=17)
    small = ImageFont.load_default(size=15)
    for r, (name, items) in enumerate(rows):
        y0 = 10 + r * ch
        d.text((14, y0), name, fill=(250, 230, 180), font=font)
        for c, (label, img) in enumerate(items):
            x0 = 10 + c * cw
            sheet.alpha_composite(img.resize((PW * S, PH * S), Image.NEAREST), (x0, y0 + 22))
            d.text((x0 + 10, y0 + 24 + PH * S), label, fill=(240, 240, 235), font=small)
    sheet.save(os.path.join(here, "furniture_options.png"))
    print("wrote furniture_options.png")
