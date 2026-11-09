"""The floor and wall tiles the game draws the tavern with.

Run from the repo root:  python3 tools/sprites/make_room_tiles.py
Writes assets/sprites/room/:
  floor_<style>.png   4 variants of one floor square side by side (48 x 24 each)
  wall_<style>.png    4 variants of one square's stretch of the top-right
                      back wall (24 x 51 each); the game mirrors and shades
                      them for the left wall
  ground_<style>.png  a seamless patch of outdoor ground (128 x 128), and
                      ground_path / ground_street for the paths
  room_styles.png     a preview sheet of everything

Everything is at sprite scale; the game draws it at 2x.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "assets", "sprites", "room")
sys.dont_write_bytecode = True

TW, TH = 48, 24          # floor diamond
EW = 24                  # one square of wall, along the top edge (drops 12)
WALL_H = 38              # the game's 76
VARIANTS = 4

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def shade(c, f):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))),
            max(0, min(255, int(c[2] * f))), 255)


def dither(v, x, y, steps):
    v = v * (steps - 1) + (BAYER[y % 4][x % 4] / 16 - 0.5) * 0.9
    return max(0, min(steps - 1, int(round(v))))


class Noise:
    """Smooth value noise that repeats every `period` units, so textures
    made from it tile without seams."""

    def __init__(self, seed, period):
        r = random.Random(seed)
        self.p = period
        self.lat = [[r.random() for _ in range(period)] for _ in range(period)]

    def __call__(self, x, y):
        xi, yi = math.floor(x), math.floor(y)
        fx, fy = x - xi, y - yi
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        p = self.p
        g = lambda i, j: self.lat[(yi + j) % p][(xi + i) % p]
        top = g(0, 0) + (g(1, 0) - g(0, 0)) * fx
        bot = g(0, 1) + (g(1, 1) - g(0, 1)) * fx
        return top + (bot - top) * fy


# ---------------------------------------------------------------------
# Floors: one diamond, with u, v = where the pixel is in the square
# ---------------------------------------------------------------------
def in_diamond(x, y):
    return abs(x + 0.5 - TW / 2) / (TW / 2) + abs(y + 0.5 - TH / 2) / (TH / 2) <= 1.0


def grid_coords(x, y):
    sx, sy = (x + 0.5 - TW / 2) / (TW / 2), (y + 0.5) / (TH / 2)
    return (sx + sy) / 2, (sy - sx) / 2


def floor_tile(fn, seed):
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    rnd = random.Random(seed)
    for y in range(TH):
        for x in range(TW):
            if in_diamond(x, y):
                u, v = grid_coords(x, y)
                c = fn(u, v, x, y, seed, rnd)
                # a touch darker at the square's back corner, so the floor
                # isn't perfectly flat
                img.putpixel((x, y), c)
    return img


def f_boards(u, v, x, y, seed, rnd):
    tones = [(190, 132, 78), (176, 120, 70), (198, 142, 86), (168, 114, 66)]
    board = min(2, int(v * 3))
    off = ((board * 5 + seed * 3) % 7) / 7
    c = tones[(board + seed * 2) % 4] + (255,)
    fv = (v * 3) % 1
    if fv < 0.12:
        return shade(c, 0.64)                             # gap between planks
    if abs(((u + off) % 1) - 0.5) < 0.025 and seed % 2 == 0:
        return shade(c, 0.72)                             # a plank end
    if fv > 0.85:
        return shade(c, 1.07)                             # worn top edge
    if 0.46 < fv < 0.6 and (abs(((u + off) % 1) - 0.56) < 0.03 or abs(((u + off) % 1) - 0.44) < 0.03) and seed % 2 == 0:
        return (104, 80, 62, 255)                         # nail heads
    g = math.sin(u * 37 + board * 3 + seed) * 0.5 + 0.5
    if g > 0.86 and rnd.random() < 0.7:
        return shade(c, 0.92)                             # grain
    if rnd.random() < 0.05:
        return shade(c, 1.05)
    return c


def f_flagstones(u, v, x, y, seed, rnd):
    base = [(170, 160, 144), (156, 148, 134), (180, 168, 150), (162, 156, 146)]
    su, sv = [(0.45, 0.6), (0.6, 0.35), (0.38, 0.5), (0.55, 0.62)][seed % 4]
    slab = (u > su) * 2 + (v > sv)
    c = base[(slab + seed) % 4] + (255,)
    edge = min(abs(u - su), u, 1 - u) * 1.0, min(abs(v - sv), v, 1 - v)
    if abs(u - su) < 0.03 or abs(v - sv) < 0.045 or u < 0.025 or v < 0.04:
        return (104, 96, 88, 255)                         # mortar
    if abs(u - su) < 0.07 or abs(v - sv) < 0.09 or u < 0.07 or v < 0.09:
        c = shade(c, 1.07)                                # bevelled edge catches light
    if rnd.random() < 0.12:
        c = shade(c, rnd.choice((0.9, 1.06)))
    return c


def f_parquet(u, v, x, y, seed, rnd):
    a, b = (194, 132, 72), (152, 100, 58)
    cu, cv = int(u * 4), int(v * 4)
    along_u = (cu + cv) % 2 == 0
    c = (a if along_u else b) + (255,)
    fu, fv = (u * 4) % 1, (v * 4) % 1
    if (fv if along_u else fu) < 0.13:
        return shade(c, 0.72)
    if (fv if along_u else fu) > 0.87:
        return shade(c, 1.08)
    if rnd.random() < 0.06:
        return shade(c, 0.94)
    return c


def f_marble(u, v, x, y, seed, rnd):
    # Big white and grey squares, each square split in four, with veins.
    q = (int(u * 2) + int(v * 2)) % 2
    c = (232, 228, 220, 255) if q == 0 else (182, 178, 172, 255)
    fu, fv = (u * 2) % 1, (v * 2) % 1
    if fu < 0.04 or fv < 0.06:
        return shade(c, 0.82)
    vein = math.sin((u * 2.3 + v * 1.7) * 9 + seed * 2 + math.sin(v * 13) * 1.2)
    if abs(vein) < 0.06:
        return shade(c, 0.86)
    if fu > 0.9 or fv > 0.88:
        return shade(c, 1.04)
    return c


def f_slate(u, v, x, y, seed, rnd):
    fu, fv = (u * 2) % 1, (v * 2) % 1
    t = int(u * 2) * 7 + int(v * 2) * 3 + seed
    c = shade((114, 118, 128), 0.9 + (t % 4) * 0.05)
    if fu < 0.06 or fv < 0.08:
        return (150, 150, 146, 255)
    if fu > 0.86 or fv > 0.84:
        return shade(c, 0.9)
    if rnd.random() < 0.06:
        return shade(c, 1.1)
    return c


FLOORS = {"boards": f_boards, "flagstones": f_flagstones, "parquet": f_parquet,
          "marble": f_marble, "slate": f_slate}


# ---------------------------------------------------------------------
# Walls: one square's stretch of the top-right wall
# t = 0..1 along it, h = 0..1 from the floor up
# ---------------------------------------------------------------------
def wall_tile(fn, seed):
    img = Image.new("RGBA", (EW, EW // 2 + WALL_H + 1), (0, 0, 0, 0))
    rnd = random.Random(seed)
    for x in range(EW):
        foot = WALL_H + x * 0.5
        for y in range(img.height):
            h = (foot - y) / WALL_H
            if 0 <= h <= 1:
                img.putpixel((x, y), fn((x + 0.5) / EW, h, x, y, seed, rnd))
    return img


BEAM = (92, 60, 36, 255)
BEAM_L = (120, 82, 50, 255)


def w_timber(t, h, x, y, seed, rnd):
    plaster, panel = (238, 228, 206), (150, 98, 58)
    if h > 0.94:
        return BEAM_L if h > 0.975 else BEAM
    if h < 0.34:
        if h < 0.04:
            return shade(panel + (255,), 0.55)          # skirting
        if x % 8 in (0, 7) or abs(h - 0.32) < 0.02:
            return shade(panel + (255,), 0.75)
        return shade(panel + (255,), 1.0 + (0.06 if x % 8 == 1 else 0))
    if abs(h - 0.36) < 0.025:
        return BEAM
    if x <= 1:                                          # an upright between squares
        return BEAM if x == 0 else BEAM_L
    if seed % 2 == 0 and abs((h - 0.36) / 0.58 - (t - 0.08) / 0.92) < 0.045:
        return BEAM                                      # a diagonal brace
    c = plaster + (255,)
    if h > 0.86:
        c = shade(c, 0.94)                               # shade under the top beam
    if rnd.random() < 0.08:
        c = shade(c, 0.96)
    return c


def w_stone(t, h, x, y, seed, rnd):
    tones = [(152, 146, 138), (138, 132, 126), (164, 156, 146), (146, 142, 136)]
    if h > 0.94:
        return BEAM_L if h > 0.975 else BEAM
    rows = 7
    row = int(h * rows)
    off = (row % 2) * 0.5
    brick = int(t * 2 + off)
    fh, ft = (h * rows) % 1, (t * 2 + off) % 1
    if fh < 0.16 or ft < 0.08:
        return (98, 92, 86, 255)
    c = tones[(row * 3 + brick + seed) % 4] + (255,)
    if fh > 0.8:
        c = shade(c, 1.08)                               # top of each stone lit
    elif ft > 0.9:
        c = shade(c, 0.9)
    if rnd.random() < 0.1:
        c = shade(c, rnd.choice((0.92, 1.06)))
    return c


def w_logs(t, h, x, y, seed, rnd):
    logs = 7
    f = (h * logs) % 1
    base = (150, 100, 58) if int(h * logs) % 2 else (140, 92, 54)
    if f < 0.13:
        return (78, 50, 30, 255)
    c = shade(base + (255,), 0.78 + 0.42 * (1 - abs(f - 0.6) * 2))
    if x <= 1 and h < 0.98:                             # log ends at the corner joint
        ring = (196, 156, 104, 255) if x == 1 else (120, 80, 48, 255)
        return ring if 0.25 < f < 0.95 else c
    if rnd.random() < 0.07:
        c = shade(c, 0.9)
    return c


def w_royal(t, h, x, y, seed, rnd):
    stone, crimson, gold = (214, 206, 190), (140, 38, 44), (210, 170, 70)
    if h > 0.95:
        return (gold + (255,)) if h > 0.975 else shade(gold + (255,), 0.75)
    if h < 0.36:
        if abs(h - 0.34) < 0.025 or h < 0.03:
            return gold + (255,)
        c = crimson + (255,)
        if x % 12 in (0, 11):
            return shade(c, 0.78)
        if 0.08 < h < 0.28 and x % 12 in (2, 9) or (abs(h - 0.08) < 0.02 or abs(h - 0.28) < 0.02) and 2 <= x % 12 <= 9:
            return shade(gold + (255,), 0.85)            # gilded panel moulding
        return c
    # ashlar blocks above
    row = int((h - 0.36) * 8)
    off = (row % 2) * 0.5
    fh, ft = ((h - 0.36) * 8) % 1, (t + off) % 1
    c = stone + (255,)
    if fh < 0.08 or ft < 0.05:
        return shade(c, 0.86)
    if rnd.random() < 0.06:
        c = shade(c, 0.97)
    return c


WALLS = {"timber": w_timber, "stone": w_stone, "logs": w_logs, "royal": w_royal}


# ---------------------------------------------------------------------
# Outdoor ground: seamless 128 x 128 patches
# ---------------------------------------------------------------------
G = 128


def grass(pal, seed, tuft_dark, tuft_light, flowers, extra=None):
    n1, n2 = Noise(seed, 4), Noise(seed + 1, 16)
    img = Image.new("RGBA", (G, G))
    px = img.load()
    for y in range(G):
        for x in range(G):
            n = n1(x / G * 4, y / G * 4) * 0.7 + n2(x / G * 16, y / G * 16) * 0.3
            px[x, y] = pal[dither(n, x, y, len(pal))] + (255,)
    rnd = random.Random(seed)
    for _ in range(170):
        x, y = rnd.randrange(G), rnd.randrange(G)
        for dx, dy, c in ((0, 0, tuft_dark), (2, 0, tuft_dark), (1, -1, tuft_dark), (0, -1, tuft_light), (2, -2, tuft_light)):
            px[(x + dx) % G, (y + dy) % G] = c + (255,)
    for _ in range(flowers):
        cx, cy = rnd.randrange(G), rnd.randrange(G)
        col = rnd.choice([(244, 226, 110), (246, 246, 240), (226, 130, 170), (150, 170, 240)])
        for _ in range(rnd.randint(2, 5)):
            x, y = (cx + rnd.randint(-4, 4)) % G, (cy + rnd.randint(-2, 2)) % G
            px[x, (y + 1) % G] = tuft_dark + (255,)
            px[x, y] = col + (255,)
    if extra:
        extra(px, rnd)
    return img


def leaf_litter(px, rnd):
    for _ in range(60):
        x, y = rnd.randrange(G), rnd.randrange(G)
        c = rnd.choice([(150, 104, 54), (172, 128, 60), (120, 86, 50)])
        px[x, y] = c + (255,)
        px[(x + 1) % G, y] = shade(c + (255,), 0.8)


def dirt(seed):
    n1, n2 = Noise(seed, 8), Noise(seed + 5, 32)
    pal = [(146, 112, 76), (164, 128, 88), (182, 146, 102)]
    img = Image.new("RGBA", (G, G))
    px = img.load()
    rnd = random.Random(seed)
    for y in range(G):
        for x in range(G):
            n = n1(x / G * 8, y / G * 8) * 0.6 + n2(x / G * 32, y / G * 32) * 0.4
            px[x, y] = pal[dither(n, x, y, 3)] + (255,)
    for _ in range(90):
        x, y = rnd.randrange(G), rnd.randrange(G)
        px[x, y] = (212, 192, 156, 255)
        px[x, (y + 1) % G] = (120, 92, 64, 255)
    return img


def cobbles(seed):
    """Rounded cobbles laid in staggered rows (screen-aligned)."""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (G, G), (92, 88, 84, 255))
    d = ImageDraw.Draw(img)
    tones = [(150, 146, 138), (136, 132, 126), (162, 156, 146), (128, 124, 120)]
    rw, rh = 12, 6
    for row in range(G // rh + 1):
        off = (row % 2) * rw // 2
        for col in range(-1, G // rw + 1):
            x0 = col * rw + off + rnd.randint(-1, 1)
            y0 = row * rh
            c = rnd.choice(tones)
            for dx in (-G, 0, G):
                for dy in (-G, 0, G):
                    box = (x0 + 1 + dx, y0 + 1 + dy, x0 + rw - 1 + dx, y0 + rh - 1 + dy)
                    d.rounded_rectangle(box, 2, fill=c + (255,))
                    d.line((box[0] + 2, box[1], box[2] - 2, box[1]), fill=shade(c + (255,), 1.15))
                    d.line((box[0] + 2, box[3], box[2] - 2, box[3]), fill=shade(c + (255,), 0.8))
    return img


def flat_street(seed):
    img = cobbles(seed + 9)
    return Image.eval(img, lambda v: int(v * 0.86))


GROUNDS = {
    "meadow": lambda: grass([(84, 128, 64), (100, 146, 72), (116, 162, 80), (134, 178, 90)], 3,
                            (66, 104, 52), (156, 196, 100), 10),
    "forest": lambda: grass([(44, 82, 52), (54, 96, 60), (66, 110, 66), (80, 126, 74)], 4,
                            (36, 66, 44), (104, 150, 90), 0, leaf_litter),
    "city": lambda: cobbles(5),
    "path": lambda: dirt(6),
    "street": lambda: flat_street(7),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    sheets = {}
    for name, fn in FLOORS.items():
        strip = Image.new("RGBA", (TW * VARIANTS, TH), (0, 0, 0, 0))
        for i in range(VARIANTS):
            strip.alpha_composite(floor_tile(fn, i), (i * TW, 0))
        strip.save(os.path.join(OUT, f"floor_{name}.png"))
        sheets["floor_" + name] = strip
    for name, fn in WALLS.items():
        h = EW // 2 + WALL_H + 1
        strip = Image.new("RGBA", (EW * VARIANTS, h), (0, 0, 0, 0))
        for i in range(VARIANTS):
            strip.alpha_composite(wall_tile(fn, i), (i * EW, 0))
        strip.save(os.path.join(OUT, f"wall_{name}.png"))
        sheets["wall_" + name] = strip
    for name, fn in GROUNDS.items():
        img = fn()
        img.save(os.path.join(OUT, f"ground_{name}.png"))
    preview(sheets)


def preview(sheets):
    """Each floor in a small room with each wall style, for a look."""
    n = 5
    floors = ["boards", "flagstones", "parquet", "marble"]
    walls = ["timber", "stone", "logs", "royal"]
    S = 2
    cell_w, cell_h = n * TW + 20, n * TH + WALL_H + 24
    sheet = Image.new("RGBA", (len(walls) * cell_w * S + 40, len(floors) * (cell_h * S + 30) + 20), (52, 46, 42, 255))
    font = ImageFont.load_default(size=18)
    d = ImageDraw.Draw(sheet)
    for r, fl in enumerate(floors):
        for c, wa in enumerate(walls):
            img = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
            ox, oy = cell_w // 2, WALL_H + 14

            def iso(x, y):
                return ox + (x - y) * TW // 2, oy + (x + y) * TH // 2
            for x in range(n):
                for y in range(n):
                    kind = "slate" if (y < 1 and x >= 3) else fl
                    v = (x * 3 + y * 5) % VARIANTS
                    tile = sheets["floor_" + kind].crop((v * TW, 0, v * TW + TW, TH))
                    px, py = iso(x, y)
                    img.alpha_composite(tile, (px - TW // 2, py))
            strip = sheets["wall_" + wa]
            wh = strip.height
            for x in range(n):
                v = x % VARIANTS
                piece = strip.crop((v * EW, 0, v * EW + EW, wh))
                px, py = iso(x, 0)
                img.alpha_composite(piece, (px, py - WALL_H))
            for y in range(n):
                v = (y + 1) % VARIANTS
                piece = strip.crop((v * EW, 0, v * EW + EW, wh)).transpose(Image.FLIP_LEFT_RIGHT)
                piece = Image.merge("RGBA", [b.point(lambda q: int(q * 0.82)) if i < 3 else b for i, b in enumerate(piece.split())])
                px, py = iso(0, y)
                img.alpha_composite(piece, (px - EW, py - WALL_H))
            big = img.resize((cell_w * S, cell_h * S), Image.NEAREST)
            X, Y = 20 + c * cell_w * S, 10 + r * (cell_h * S + 30)
            sheet.alpha_composite(big, (X, Y))
            d.text((X + 10, Y + cell_h * S + 2), f"{fl} + {wa}", fill=(240, 240, 235), font=font)
    sheet.save(os.path.join(HERE, "room_styles.png"))


if __name__ == "__main__":
    main()
    print("wrote", OUT)
