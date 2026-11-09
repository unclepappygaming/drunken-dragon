"""Pixel-art floors and walls for the tavern, to replace the plain colours
the game draws now.

Run from the repo root:  python3 tools/sprites/make_room.py
It writes room_options.png next to this script: a small room in each of
three styles, at the game's size, with furniture and a guest for scale.

A floor tile is one 48 x 24 diamond (drawn at 2x in the game). A wall
piece is one square's stretch of the top-right back wall: 48 wide and 38
tall, sloping down to the right; the left wall is the same picture
mirrored.
"""
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True

TW, TH = 48, 24          # floor diamond
WALL_H = 38              # wall height (the game's 76, at sprite scale)


def shade(c, f):
    return (min(255, int(c[0] * f)), min(255, int(c[1] * f)), min(255, int(c[2] * f)), 255)


def in_diamond(x, y):
    """Is pixel (x, y) inside the 48 x 24 floor diamond?"""
    cx, cy = TW / 2, TH / 2
    return abs(x + 0.5 - cx) / (TW / 2) + abs(y + 0.5 - cy) / (TH / 2) <= 1.0


def grid_coords(x, y):
    """Pixel -> position inside the square (u along x, v along y), 0..1."""
    sx, sy = (x + 0.5 - TW / 2) / (TW / 2), (y + 0.5) / (TH / 2)
    u = (sx + sy) / 2
    v = (sy - sx) / 2
    return u, v


# ---------------------------------------------------------------------
# Floors
# ---------------------------------------------------------------------
def floor_boards(seed):
    """Wooden floorboards running along x, with grain and nail heads."""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    tones = [(196, 140, 84, 255), (184, 128, 76, 255), (205, 150, 92, 255), (176, 122, 72, 255)]
    shift = rnd.random()
    for y in range(TH):
        for x in range(TW):
            if not in_diamond(x, y):
                continue
            u, v = grid_coords(x, y)
            board = int(v * 4) % 4
            c = tones[(board + seed) % 4]
            if (v * 4) % 1 < 0.09:
                c = shade(c, 0.72)                        # gap between boards
            elif ((u + shift + board * 0.37) * 1.0) % 1 < 0.03:
                c = shade(c, 0.8)                         # board end
            elif rnd.random() < 0.08:
                c = shade(c, rnd.choice((0.92, 1.06)))    # grain
            img.putpixel((x, y), c)
    return img


def floor_flagstones(seed):
    """Big warm-grey flagstones with darker mortar between them."""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    base = [(168, 156, 140, 255), (156, 146, 132, 255), (176, 164, 146, 255)]
    split_u, split_v = 0.35 + rnd.random() * 0.3, 0.35 + rnd.random() * 0.3
    for y in range(TH):
        for x in range(TW):
            if not in_diamond(x, y):
                continue
            u, v = grid_coords(x, y)
            slab = (u > split_u) * 2 + (v > split_v)
            c = base[(slab + seed) % 3]
            if abs(u - split_u) < 0.035 or abs(v - split_v) < 0.05 or u < 0.03 or v < 0.05:
                c = (110, 100, 90, 255)                   # mortar
            elif rnd.random() < 0.1:
                c = shade(c, rnd.choice((0.9, 1.08)))
            img.putpixel((x, y), c)
    return img


def floor_parquet(seed):
    """Herringbone parquet in two woods."""
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    a, b = (190, 128, 70, 255), (150, 98, 56, 255)
    for y in range(TH):
        for x in range(TW):
            if not in_diamond(x, y):
                continue
            u, v = grid_coords(x, y)
            cu, cv = int(u * 4), int(v * 4)
            along_u = (cu + cv) % 2 == 0
            c = a if along_u else b
            fu, fv = (u * 4) % 1, (v * 4) % 1
            if (fv if along_u else fu) < 0.12:
                c = shade(c, 0.75)
            img.putpixel((x, y), c)
    return img


def floor_slate(seed):
    """Kitchen floor: small slate tiles with light grout."""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
    for y in range(TH):
        for x in range(TW):
            if not in_diamond(x, y):
                continue
            u, v = grid_coords(x, y)
            fu, fv = (u * 3) % 1, (v * 3) % 1
            tile = int(u * 3) + int(v * 3) * 3
            c = shade((120, 124, 132, 255), 0.92 + ((tile * 37 + seed) % 5) * 0.04)
            if fu < 0.1 or fv < 0.1:
                c = (168, 166, 160, 255)
            elif rnd.random() < 0.06:
                c = shade(c, 1.12)
            img.putpixel((x, y), c)
    return img


# ---------------------------------------------------------------------
# Walls: one square's stretch of the top-right wall (48 x 24 + 38)
# ---------------------------------------------------------------------
EW = TW // 2              # one square's stretch of wall in the game (24 x 12 drop)


def wall_canvas(w=TW):
    return Image.new("RGBA", (w, w // 2 + WALL_H + 1), (0, 0, 0, 0))


def wall_pixels(img, fill):
    """Calls fill(t, h) for every pixel of the wall: t = 0..1 along it,
    h = 0..1 from the floor up."""
    w = img.width
    for x in range(w):
        floor_y = WALL_H + x * 0.5           # the wall's foot slopes down to the right
        for y in range(img.height):
            h = (floor_y - y) / WALL_H
            if 0 <= h <= 1:
                c = fill((x + 0.5) / w, h, x, y)
                if c:
                    img.putpixel((x, y), c)


def wall_timber(seed, w=TW):
    """Whitewashed plaster between dark timber beams, wood panelling below."""
    img = wall_canvas(w)
    plaster, beam, panel = (236, 226, 204, 255), (98, 64, 38, 255), (150, 98, 58, 255)
    rnd = random.Random(seed)

    def fill(t, h, x, y):
        if h < 0.34:
            c = panel if (x % 12) > 1 else shade(panel, 0.75)
            return c if h > 0.03 else shade(panel, 0.6)
        if h > 0.92 or abs(h - 0.34) < 0.03 or t < 0.06 or t > 0.94:
            return beam
        # a diagonal brace on every other stretch
        if seed % 2 == 0 and abs((h - 0.34) / 0.58 - t) < 0.06:
            return beam
        return shade(plaster, rnd.choice((1.0, 1.0, 0.96)))
    wall_pixels(img, fill)
    return img


def wall_stone(seed, w=TW):
    """Rough grey stone blocks with a wooden beam along the top."""
    img = wall_canvas(w)
    rnd = random.Random(seed)
    tones = [(150, 144, 136, 255), (138, 132, 126, 255), (162, 154, 144, 255)]

    def fill(t, h, x, y):
        if h > 0.92:
            return (98, 64, 38, 255)
        row = int(h * 6)
        off = (row % 2) * 0.25
        brick = int((t + off) * 4)
        if (h * 6) % 1 < 0.14 or ((t + off) * 4) % 1 < 0.06:
            return (96, 90, 84, 255)
        c = tones[(row * 7 + brick + seed) % 3]
        return shade(c, rnd.choice((1.0, 1.0, 0.93, 1.06)))
    wall_pixels(img, fill)
    return img


def wall_logs(seed, w=TW):
    """Stacked round logs, like a hunting lodge."""
    img = wall_canvas(w)

    def fill(t, h, x, y):
        f = (h * 7) % 1
        base = (150, 100, 58, 255) if int(h * 7) % 2 else (140, 92, 54, 255)
        if f < 0.12:
            return (82, 54, 32, 255)                     # gap between logs
        return shade(base, 0.8 + 0.4 * (1 - abs(f - 0.55) * 2))   # rounded log
    wall_pixels(img, fill)
    return img


STYLES = [
    ("A  Floorboards + timber-framed plaster", floor_boards, wall_timber),
    ("B  Flagstones + stone walls", floor_flagstones, wall_stone),
    ("C  Parquet + log walls", floor_parquet, wall_logs),
]


def room(floor, wall, n=6):
    """A little n x n room drawn like the game (at sprite scale)."""
    w = n * TW
    h = n * TH + WALL_H + 30
    img = Image.new("RGBA", (w + 20, h + 20), (0, 0, 0, 0))
    ox, oy = 10 + w // 2, 10 + WALL_H + 4

    def iso(x, y):
        return ox + (x - y) * TW // 2, oy + (x + y) * TH // 2
    for x in range(n):
        for y in range(n):
            kitchen = y < 2 and x >= 3
            tile = floor_slate(x * 7 + y) if kitchen else floor(x * 3 + y * 5)
            px, py = iso(x, y)
            img.alpha_composite(tile, (px - TW // 2, py))
    for x in range(n):     # top-right wall: one stretch per square
        px, py = iso(x, 0)
        img.alpha_composite(wall(x), (px, py - WALL_H))
    for y in range(n):     # left wall: the same picture mirrored
        px, py = iso(0, y)
        piece = wall(y).transpose(Image.FLIP_LEFT_RIGHT)
        img.alpha_composite(piece, (px - TW, py - WALL_H))
    return img, iso


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    table = Image.open(os.path.join(root, "assets", "sprites", "furniture", "table.png")).convert("RGBA")
    chair_b = Image.open(os.path.join(root, "assets", "sprites", "furniture", "chair_back.png")).convert("RGBA")
    chair_f = Image.open(os.path.join(root, "assets", "sprites", "furniture", "chair_front.png")).convert("RGBA")
    stove = Image.open(os.path.join(root, "assets", "sprites", "furniture", "hearth.png")).convert("RGBA").crop((0, 0, 64, 72))
    farmer = Image.open(os.path.join(root, "assets", "sprites", "guests", "farmer.png")).convert("RGBA").crop((0, 0, 32, 40))
    font = ImageFont.load_default(size=16)
    S = 2
    pics = []
    for label, floor, wall in STYLES:
        img, iso = room(floor, wall)

        def put(art, cell, anchor=(32, 58)):
            x, y = iso(*cell)
            img.alpha_composite(art, (int(x - anchor[0]), int(y + 12 - anchor[1])))
        put(stove, (4, 1))
        put(chair_b, (1, 3)); put(table, (2, 3)); put(chair_f, (3, 3))
        put(farmer, (2, 5), (16, 37))
        pics.append((label, img.resize((img.width * S, img.height * S), Image.NEAREST)))
    w = sum(p.width for _, p in pics) + 20 * (len(pics) + 1)
    h = max(p.height for _, p in pics) + 40
    sheet = Image.new("RGBA", (w, h), (52, 46, 42, 255))
    d = ImageDraw.Draw(sheet)
    x = 20
    for label, p in pics:
        sheet.alpha_composite(p, (x, 10))
        d.text((x + 10, 10 + p.height + 4), label, fill=(240, 240, 235), font=font)
        x += p.width + 20
    sheet.save(os.path.join(here, "room_options.png"))
    print("wrote room_options.png")
