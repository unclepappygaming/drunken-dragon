"""Mock-up of the "polished pixel" look, to compare with the game as it is.

Run from the repo root:  python3 tools/sprites/make_polish.py [screenshot]
Writes polish_mockup.png next to this script. With a screenshot of the
game it puts that on the left, for a side-by-side.

Same sprite size as the game (everything is drawn at sprite scale, then
doubled), but with:
  - grass, dirt and floorboards that flow across squares (no checkerboard)
  - a stone foundation under the floor's front edges, a cap on the walls,
    the left wall in shade, framed windows with sills
  - soft shadows under everyone and everything, darker along the walls
  - shaded, outlined trees and bushes
  - wooden menus with a pixel font
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
from make_room import wall_timber  # noqa: E402

W, H = 360, 640            # the screen, at sprite scale (the game doubles it)
COLS, ROWS = 8, 7
OX, OY = 172, 200          # where the floor's back corner sits on screen
WALL_H = 38
FONT = os.environ.get("POLISH_FONT", "")


def shade(c, f):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))),
            max(0, min(255, int(c[2] * f))), c[3] if len(c) > 3 else 255)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


def iso(x, y):
    return OX + (x - y) * 24, OY + (x + y) * 12


def to_grid(sx, sy):
    a, b = (sx - OX) / 24, (sy - OY) / 12
    return (a + b) / 2, (b - a) / 2


# Smooth value noise, so colours drift in patches instead of per square.
_R = random.Random(7)
_LAT = [[_R.random() for _ in range(64)] for _ in range(64)]


def noise(x, y):
    xi, yi = math.floor(x), math.floor(y)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    g = lambda i, j: _LAT[(yi + j) % 64][(xi + i) % 64]
    top = g(0, 0) + (g(1, 0) - g(0, 0)) * fx
    bot = g(0, 1) + (g(1, 1) - g(0, 1)) * fx
    return top + (bot - top) * fy


BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def dither(v, x, y, steps):
    """v 0..1 -> one of `steps` bands, dithered where bands meet."""
    v = v * (steps - 1) + (BAYER[y % 4][x % 4] / 16 - 0.5) * 0.9
    return max(0, min(steps - 1, int(round(v))))


GRASS = [(84, 128, 64), (100, 146, 72), (116, 162, 80), (134, 178, 90)]
DIRT = [(150, 116, 78), (170, 134, 90), (188, 152, 104)]
BOARDS = [(176, 120, 70), (190, 132, 78), (166, 112, 66), (198, 142, 86)]
SLATE = (112, 116, 126)


def on_path(gx, gy):
    """The dirt path from the door, wandering off down the left."""
    if gy < ROWS:
        return False
    centre = 2.6 + math.sin(gy * 0.35) * 0.6
    return abs(gx - centre) < 0.9 + noise(gx * 3, gy * 3) * 0.35


def ground(img):
    px = img.load()
    rnd = random.Random(3)
    for sy in range(H):
        for sx in range(W):
            gx, gy = to_grid(sx + 0.5, sy + 0.5)
            inside = 0 <= gx < COLS and 0 <= gy < ROWS
            if inside:
                px[sx, sy] = floor_px(gx, gy, sx, sy)
            elif on_path(gx, gy):
                n = noise(gx * 2.2, gy * 2.2) * 0.7 + rnd.random() * 0.3
                c = DIRT[dither(n, sx, sy, 3)]
                if rnd.random() < 0.02:
                    c = (214, 196, 160)              # a pebble
                px[sx, sy] = c + (255,)
            else:
                n = noise(gx * 0.9, gy * 0.9) * 0.75 + noise(gx * 4, gy * 4) * 0.25
                c = GRASS[dither(n, sx, sy, 4)]
                # a little shade cast by the tavern on the grass in front of it
                if -0.6 < gx - COLS < 0.0 and gy < ROWS or -0.6 < gy - ROWS < 0 and gx < COLS:
                    c = shade(c, 0.88)
                px[sx, sy] = c[:3] + (255,)
    # grass tufts and flowers on top
    d = ImageDraw.Draw(img)
    for _ in range(900):
        sx, sy = rnd.randrange(W), rnd.randrange(H)
        gx, gy = to_grid(sx, sy)
        if (0 <= gx < COLS + 0.3 and 0 <= gy < ROWS + 0.3) or on_path(gx, gy):
            continue
        dark, light = (66, 104, 52, 255), (156, 196, 100, 255)
        d.point([(sx, sy), (sx + 2, sy), (sx + 1, sy - 1)], fill=dark)
        d.point([(sx, sy - 1), (sx + 2, sy - 2)], fill=light)
    for _ in range(26):   # little clumps of flowers
        cx, cy = rnd.randrange(W), rnd.randrange(H)
        gx, gy = to_grid(cx, cy)
        if (0 <= gx < COLS + 0.5 and 0 <= gy < ROWS + 0.5) or on_path(gx, gy):
            continue
        col = rnd.choice([(244, 226, 110), (246, 246, 240), (226, 130, 170), (150, 170, 240)])
        for _ in range(rnd.randint(3, 6)):
            x, y = cx + rnd.randint(-5, 5), cy + rnd.randint(-3, 3)
            d.point([(x, y + 1)], fill=(70, 110, 56, 255))
            d.point([(x, y)], fill=col + (255,))


def floor_px(gx, gy, sx, sy):
    if gx >= COLS - 2 and gy < 2:                      # the kitchen: slate tiles
        fu, fv = (gx * 2) % 1, (gy * 2) % 1
        t = int(gx * 2) * 7 + int(gy * 2) * 3
        c = shade(SLATE, 0.9 + (t % 4) * 0.05)
        if fu < 0.07 or fv < 0.07:
            c = (150, 150, 146, 255)
        elif fu > 0.85 or fv > 0.85:
            c = shade(c, 0.92)
    else:                                              # long planks along x
        board = math.floor(gy * 3)
        off = (board * 0.37) % 1
        seg = math.floor(gx / 2.3 + off)
        c = BOARDS[(board * 3 + seg) % 4] + (255,)
        if (gy * 3) % 1 < 0.1:
            c = shade(c, 0.66)                          # gap between planks
        elif (gx / 2.3 + off) % 1 < 0.02:
            c = shade(c, 0.74)                          # plank ends
        elif noise(gx * 9, gy * 30) > 0.72:
            c = shade(c, 0.93)                          # grain
        elif ((gx / 2.3 + off) % 1 > 0.06 and (gx / 2.3 + off) % 1 < 0.08) and (gy * 3) % 1 > 0.42 and (gy * 3) % 1 < 0.58:
            c = (110, 86, 70, 255)                      # nail
    # darker into the corners by the walls, lighter where the windows shine
    ao = min(gx, gy)
    if ao < 0.6:
        c = shade(c, 0.78 + 0.22 * (ao / 0.6))
    return c


def walls(img):
    """The two back walls: plaster and timber, the left one in shade, with
    a cap along the top and framed windows."""
    for x in range(COLS):
        px, py = iso(x, 0)
        piece = wall_timber(x)
        img.alpha_composite(piece, (px, py - WALL_H))
        if x in (1, 4, 6):
            window(img, px + 14, py - WALL_H + 13 + 7, False)
    for y in range(ROWS):
        px, py = iso(0, y)
        piece = wall_timber(y + 1).transpose(Image.FLIP_LEFT_RIGHT)
        piece = Image.eval(piece, lambda v: v)
        dark = Image.new("RGBA", piece.size, (40, 30, 50, 0))
        r, g, b, a = piece.split()
        piece = Image.merge("RGBA", [p.point(lambda v: int(v * 0.8)) for p in (r, g, b)] + [a])
        img.alpha_composite(piece, (px - 48, py - WALL_H))
        if y in (1, 4):
            window(img, px - 48 + 14, py - WALL_H + 13 + 7, True)
    d = ImageDraw.Draw(img)
    cap, cap_top = (92, 60, 36, 255), (138, 98, 62, 255)
    a, b, c = iso(0, ROWS), iso(0, 0), iso(COLS, 0)
    for k, col in ((0, cap_top), (1, cap), (2, cap)):
        d.line([(a[0], a[1] - WALL_H - 2 + k), (b[0], b[1] - WALL_H - 2 + k), (c[0], c[1] - WALL_H - 2 + k)], fill=col)


def window(img, x, y, mirrored):
    """A small leaded window, 16 x 18, slanted to sit on the wall."""
    win = Image.new("RGBA", (20, 26), (0, 0, 0, 0))
    d = ImageDraw.Draw(win)
    frame, glass, glint = (86, 56, 34, 255), (124, 168, 196, 255), (206, 230, 240, 255)
    d.rectangle((2, 2, 15, 19), fill=frame)
    d.rectangle((4, 4, 13, 17), fill=glass)
    d.rectangle((4, 4, 13, 9), fill=(150, 192, 214, 255))
    d.line((8, 4, 8, 17), fill=frame); d.line((4, 10, 13, 10), fill=frame)
    d.point([(5, 5), (6, 5), (5, 6), (10, 12)], fill=glint)
    d.rectangle((1, 20, 16, 21), fill=(160, 112, 70, 255))       # sill
    d.rectangle((1, 22, 16, 22), fill=(70, 46, 30, 255))
    # slant it like the wall: each column drops half a pixel per pixel
    out = Image.new("RGBA", (20, 36), (0, 0, 0, 0))
    for cx in range(20):
        col = win.crop((cx, 0, cx + 1, 26))
        out.alpha_composite(col, (cx, int(cx * 0.5)))
    if mirrored:
        out = out.transpose(Image.FLIP_LEFT_RIGHT)
        out = Image.merge("RGBA", [b.point(lambda v: int(v * 0.85)) if i < 3 else b for i, b in enumerate(out.split())])
    img.alpha_composite(out, (x, y))


def foundation(img):
    """Stones under the floor's two front edges, with a gap for the door."""
    d = ImageDraw.Draw(img)
    stone = [(150, 140, 128), (132, 124, 114), (164, 154, 140)]
    door_x = 2
    for side in ("left", "right"):
        n = COLS if side == "right" else ROWS
        for i in range(n):
            if side == "left":
                (ax, ay), (bx, by) = iso(i, ROWS), iso(i + 1, ROWS)
                f = 0.86
            else:
                (ax, ay), (bx, by) = iso(COLS, i), iso(COLS, i + 1)
                f = 1.0
            for sx in range(min(ax, bx), max(ax, bx)):
                t = (sx - ax) / (bx - ax)
                top = ay + (by - ay) * t
                for k in range(7):
                    row = k // 3
                    brick = int((t * 3 + row * 0.5)) % 3
                    c = stone[(brick + i + row) % 3]
                    if k % 3 == 2 or (t * 3 + row * 0.5) % 1 < 0.1:
                        c = (96, 90, 84)
                    d.point((sx, int(top) + 1 + k), fill=shade(c + (255,), f))
    # a sill of wood along the edge, and the doorway mat
    for side in ("left", "right"):
        a = iso(0, ROWS) if side == "left" else iso(COLS, ROWS)
        b = iso(COLS, ROWS) if side == "left" else iso(COLS, 0)
        d.line([a, b], fill=(118, 80, 48, 255))
    a, b, c, e = iso(door_x, ROWS - 0.15), iso(door_x + 1, ROWS - 0.15), iso(door_x + 1, ROWS + 0.75), iso(door_x, ROWS + 0.75)
    d.polygon([a, b, c, e], fill=(150, 46, 40, 255))
    a2 = [iso(door_x + 0.15, ROWS + 0.0), iso(door_x + 0.85, ROWS + 0.0), iso(door_x + 0.85, ROWS + 0.6), iso(door_x + 0.15, ROWS + 0.6)]
    d.polygon(a2, outline=(206, 160, 70, 255))


# ---------------------------------------------------------------------
# Shaded, outlined trees and bushes
# ---------------------------------------------------------------------
LEAF = [(40, 72, 44), (58, 100, 52), (80, 128, 60), (112, 156, 72), (150, 186, 92)]
PINE = [(28, 58, 46), (38, 78, 56), (52, 100, 64), (74, 124, 74), (102, 150, 88)]
LIGHT = (-0.55, -0.7, 0.45)   # from the upper left, towards us


def blobs_shape(w, h, blobs, pal, seed):
    """Union of spheres, lit from the upper left, banded into the palette
    with dithering, a dark outline, and leafy speckle."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    rnd = random.Random(seed)
    L = LIGHT
    ln = math.sqrt(sum(v * v for v in L))
    for y in range(h):
        for x in range(w):
            best = None
            for (cx, cy, r) in blobs:
                dx, dy = (x + 0.5 - cx) / r, (y + 0.5 - cy) / r
                dd = dx * dx + dy * dy
                if dd <= 1:
                    z = math.sqrt(1 - dd)
                    if best is None or z + cy * 0.01 > best[0]:
                        best = (z + cy * 0.01, dx, dy, z)
            if best:
                _, dx, dy, z = best
                lam = max(0.0, (dx * L[0] + dy * L[1] + z * L[2]) / ln)
                v = 0.15 + lam * 0.85
                if rnd.random() < 0.18:
                    v += rnd.choice((-0.2, 0.15))     # leaves catching the light
                px[x, y] = pal[dither(max(0, min(1, v)), x, y, len(pal))] + (255,)
    outline(img, shade(pal[0] + (255,), 0.55))
    return img


def outline(img, col):
    a = img.split()[3]
    grown = a.filter(ImageFilter.MaxFilter(3))
    ring = Image.new("RGBA", img.size, col)
    ring.putalpha(Image.eval(grown, lambda v: 255 if v else 0))
    ring.alpha_composite(img)
    img.paste(ring)


def trunk(d, x, top, bottom, w):
    bark = [(70, 48, 34), (96, 66, 44), (122, 86, 58)]
    for yy in range(top, bottom):
        for xx in range(x - w, x + w + 1):
            t = (xx - (x - w)) / (2 * w)
            c = bark[0] if t > 0.7 else bark[1] if t > 0.3 else bark[2]
            if (yy * 7 + xx * 3) % 11 == 0:
                c = bark[0]
            d.point((xx, yy), fill=c + (255,))
    d.point([(x - w - 1, bottom - 1), (x + w + 1, bottom - 1), (x - w - 2, bottom)], fill=bark[1] + (255,))   # roots


def oak(seed):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (96, 128), (0, 0, 0, 0))
    trunk(ImageDraw.Draw(img), 48, 70, 116, 4)
    blobs = [(48, 52, 24)]
    for _ in range(9):
        a = rnd.uniform(0, math.tau)
        blobs.append((48 + math.cos(a) * 20, 52 + math.sin(a) * 14, rnd.uniform(11, 15)))
    blobs.append((48, 32, 16))
    crown = blobs_shape(96, 128, blobs, LEAF, seed)
    img.alpha_composite(crown)
    return img, (48, 116)


def pine(seed):
    img = Image.new("RGBA", (64, 128), (0, 0, 0, 0))
    trunk(ImageDraw.Draw(img), 32, 96, 116, 3)
    tiers = Image.new("RGBA", (64, 128), (0, 0, 0, 0))
    for i, (y, w) in enumerate([(98, 24), (80, 20), (62, 16), (46, 12), (32, 8)]):
        tier = Image.new("RGBA", (64, 128), (0, 0, 0, 0))
        d = ImageDraw.Draw(tier)
        d.polygon([(32 - w, y), (32 + w, y), (32, y - 26)], fill=PINE[2] + (255,))
        px = tier.load()
        for yy in range(128):
            for xx in range(64):
                if px[xx, yy][3]:
                    t = (xx - (32 - w)) / (2 * w)
                    v = 1 - t * 0.9 - (y - yy) * -0.004
                    if yy > y - 4:
                        v -= 0.35                        # dark under each tier
                    px[xx, yy] = PINE[dither(max(0, min(1, v)), xx, yy, 5)] + (255,)
        tiers.alpha_composite(tier)
    outline(tiers, (20, 40, 32, 255))
    img.alpha_composite(tiers)
    return img, (32, 116)


def bush(seed):
    rnd = random.Random(seed)
    blobs = [(32, 46, 13), (22, 50, 9), (42, 50, 9), (30, 38, 9)]
    img = blobs_shape(64, 72, blobs, LEAF, seed)
    for _ in range(5):                                     # berries
        x, y = rnd.randint(22, 42), rnd.randint(38, 54)
        if img.getpixel((x, y))[3]:
            img.putpixel((x, y), (200, 60, 60, 255))
            img.putpixel((x - 1, y - 1), (240, 140, 130, 255))
    return img, (32, 58)


def soft_shadow(img, x, y, rx, ry, alpha=70):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    d.ellipse((x - rx, y - ry, x + rx, y + ry), fill=(20, 24, 30, alpha))
    d.ellipse((x - rx * 0.7, y - ry * 0.7, x + rx * 0.7, y + ry * 0.7), fill=(20, 24, 30, alpha))
    img.alpha_composite(sh)


# ---------------------------------------------------------------------
# The scene
# ---------------------------------------------------------------------
def sprite(path, frame=0, w=32, h=40):
    im = Image.open(os.path.join(ROOT, "assets", "sprites", path)).convert("RGBA")
    return im.crop((frame * w, 0, frame * w + w, h))


def scene():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    ground(img)
    walls(img)
    foundation(img)
    furn = lambda n: sprite("furniture/" + n, 0, 64, 72)
    items = []   # (depth, art, (x, y) cell, anchor, shadow size)

    def put(art, cell, anchor, shadow=None):
        items.append((cell[0] + cell[1], art, cell, anchor, shadow))
    put(furn("hearth.png"), (6.5, 0.5), (32, 58), (16, 6))
    put(sprite("staff/tavern_cook.png"), (7.4, 0.6), (16, 37), (7, 3))
    put(furn("pass.png"), (7.5, 1.6), (32, 58))
    put(furn("chair_back.png"), (1.5, 2.5), (32, 58)); put(furn("table.png"), (2.5, 2.5), (32, 58), (18, 7))
    put(furn("chair_front.png"), (3.5, 2.5), (32, 58))
    put(sprite("guests/farmer.png"), (1.55, 2.55), (16, 37), (7, 3))
    put(furn("chair_back.png"), (2.5, 4.5), (32, 58)); put(furn("table.png"), (3.5, 4.5), (32, 58), (18, 7))
    put(furn("chair_front.png"), (4.5, 4.5), (32, 58))
    put(sprite("guests/merchant.png"), (2.55, 4.55), (16, 37), (7, 3))
    put(sprite("staff/maid.png"), (4.3, 3.9), (16, 37), (7, 3))
    for i, g in enumerate(["guard", "farmer", "regular", "farmer", "bard"]):
        put(sprite(f"guests/{g}.png"), (1.6 - i * 0.85, ROWS + 0.55), (16, 37), (7, 3))
    at = lambda sx, sy: to_grid(sx, sy)
    for (sx, sy), s in [((62, 196), 1), ((300, 150), 2), ((30, 470), 3), ((330, 470), 4), ((150, 120), 14)]:
        art, anc = oak(s)
        put(art, at(sx, sy), anc, (22, 8))
    for (sx, sy), s in [((20, 120), 5), ((215, 105), 6), ((350, 230), 7), ((100, 560), 8), ((345, 600), 15)]:
        art, anc = pine(s)
        put(art, at(sx, sy), anc, (14, 6))
    for (sx, sy), s in [((120, 210), 9), ((250, 160), 10), ((40, 300), 11), ((230, 500), 12), ((180, 560), 13), ((300, 520), 16)]:
        art, anc = bush(s)
        put(art, at(sx, sy), anc, (12, 5))
    cot = Image.open(os.path.join(ROOT, "assets/sprites/outdoors/cottage.png")).convert("RGBA").crop((0, 0, 128, 150))
    put(cot, at(70, 160), (64, 120), (40, 14))
    items.sort(key=lambda it: it[0])
    for depth, art, cell, anchor, sh in items:
        x, y = iso(*cell)
        y += 0
        if sh:
            soft_shadow(img, x + 2, y + 1, sh[0], sh[1])
        img.alpha_composite(art, (int(x - anchor[0]), int(y - anchor[1] + 12 * 0)))
    return img


def ui(big):
    """The menus drawn over the doubled scene (720 x 1280)."""
    font_path = FONT or os.path.join(HERE, "..", "..", "assets", "fonts", "Jersey10.ttf")
    f = lambda s: ImageFont.truetype(font_path, s)
    d = ImageDraw.Draw(big)
    wood, wood_d, wood_l = (92, 60, 38, 255), (58, 36, 22, 255), (132, 92, 58, 255)
    gold, parch = (250, 210, 100, 255), (246, 232, 196, 255)

    def plank_panel(box, rows=3):
        x0, y0, x1, y1 = box
        d.rectangle(box, fill=wood)
        for i in range(1, rows):
            yy = y0 + (y1 - y0) * i // rows
            d.line((x0, yy, x1, yy), fill=wood_d, width=2)
        d.rectangle((x0, y0, x1, y0 + 3), fill=wood_l)
        d.rectangle((x0, y1 - 5, x1, y1), fill=wood_d)

    # top bar
    plank_panel((0, 0, 720, 128), 2)
    for x in (12, 708):
        for y in (14, 104):
            d.rectangle((x - 4, y - 4, x + 4, y + 4), fill=(70, 70, 76, 255))
            d.rectangle((x - 2, y - 2, x + 2, y + 2), fill=(150, 150, 156, 255))
    d.ellipse((24, 18, 58, 52), fill=(196, 140, 40, 255)); d.ellipse((27, 20, 55, 48), fill=gold)
    d.text((33, 19), "g", font=f(26), fill=(150, 100, 30, 255))
    d.text((68, 12), "321", font=f(48), fill=gold, stroke_width=3, stroke_fill=wood_d)
    d.text((24, 62), "Day 1", font=f(36), fill=parch, stroke_width=3, stroke_fill=wood_d)
    d.text((150, 62), "15:58", font=f(36), fill=parch, stroke_width=3, stroke_fill=wood_d)
    star = [(0, -16), (5, -5), (16, -5), (7, 2), (10, 14), (0, 7), (-10, 14), (-7, 2), (-16, -5), (-5, -5)]
    d.polygon([(472 + a, 36 + b) for a, b in star], fill=gold, outline=wood_d)
    d.text((496, 12), "0  Unknown", font=f(40), fill=parch, stroke_width=3, stroke_fill=wood_d)
    d.text((410, 66), "Cooks 1  Waiters 1  66g/day", font=f(28), fill=(230, 210, 170, 255), stroke_width=2, stroke_fill=wood_d)
    # a parchment scroll for the hint
    d.rounded_rectangle((30, 134, 470, 172), 6, fill=parch, outline=(150, 112, 60, 255), width=3)
    d.text((44, 140), "Hire and let staff go between days.", font=f(28), fill=(80, 52, 30, 255))
    # bottom bars
    plank_panel((0, 1052, 720, 1280), 3)

    def button(box, label, size=26, on=False):
        x0, y0, x1, y1 = box
        d.rounded_rectangle((x0, y0 + 4, x1, y1 + 4), 8, fill=wood_d)
        d.rounded_rectangle(box, 8, fill=(170, 120, 72, 255) if on else (124, 84, 52, 255), outline=wood_d, width=3)
        d.line((x0 + 8, y0 + 5, x1 - 8, y0 + 5), fill=(200, 150, 96, 255) if on else wood_l, width=2)
        lines = label.split("\n")
        for i, ln in enumerate(lines):
            tw = d.textlength(ln, font=f(size))
            ty = (y0 + y1) / 2 - len(lines) * size * 0.55 + i * size * 1.05
            d.text(((x0 + x1) / 2 - tw / 2, ty), ln, font=f(size), fill=gold if on else parch, stroke_width=2, stroke_fill=wood_d)
    labels = ["Cook", "Waiter", "Host", "Dish-\nwasher", "Bar-\ntender", "Your\nStaff"]
    for i, l in enumerate(labels):
        button((10 + i * 118, 1066, 120 + i * 118, 1144), l, 28)
    for i, (l, on) in enumerate([("Build", False), ("Staff", True), ("Recipes\n& Goals", False), ("Open", False)]):
        button((10 + i * 177, 1164, 177 + i * 177, 1262), l, 38, on)
    return big


if __name__ == "__main__":
    big = scene().resize((W * 2, H * 2), Image.NEAREST)
    big = ui(big)
    out = big
    if len(sys.argv) > 1:
        shot = Image.open(sys.argv[1]).convert("RGBA").resize((720, 1138 * 720 // 720 if False else int(1972 * 720 / 1248)), Image.LANCZOS)
        out = Image.new("RGBA", (720 * 2 + 40, max(shot.height, 1280) + 70), (40, 34, 30, 255))
        out.alpha_composite(shot, (0, 70))
        out.alpha_composite(big, (760, 70))
        d = ImageDraw.Draw(out)
        fnt = ImageFont.truetype(FONT or os.path.join(ROOT, "assets", "fonts", "Jersey10.ttf"), 40)
        d.text((20, 14), "Now", font=fnt, fill=(250, 230, 180, 255))
        d.text((780, 14), "Polished pixel", font=fnt, fill=(250, 230, 180, 255))
    out.save(os.path.join(HERE, "polish_mockup.png"))
    print("wrote polish_mockup.png")
