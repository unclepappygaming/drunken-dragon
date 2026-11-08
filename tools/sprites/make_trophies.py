"""Animated trophy heads for the back wall: earned through achievements.

Run from the repo root:  python3 tools/sprites/make_trophies.py
It writes trophy_options.png (every frame of each trophy) and
trophy_options.gif (the trophies moving) next to this script.

Each trophy is a few frames on the same 64 x 72 canvas as the other
pieces, hung on the back wall (the y = -12 side) above a wooden plaque.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True
from make_furniture import P, Piece, shade, OAK_DARK, PW, PH, floor_patch, person, piece  # noqa: E402
from make_decor import on_wall, glow, wall_patch  # noqa: E402

BONE = (232, 222, 190, 255)
DARK = (40, 30, 30, 255)


def plaque(p):
    """The shield-shaped wooden board every trophy hangs from. Returns the
    screen point at its middle."""
    cx, cy = on_wall(p, 0, 24)
    p.d.polygon([(cx - 8, cy - 8), (cx + 8, cy - 4), (cx + 8, cy + 6), (cx, cy + 11), (cx - 8, cy + 3)], fill=OAK_DARK)
    p.d.line([(cx - 7, cy - 6), (cx + 7, cy - 2)], fill=shade(OAK_DARK, 1.3))
    return cx, cy


def wyvern(frame):
    """A wyvern head that slowly opens its jaws and puffs a wisp of smoke."""
    p = Piece()
    cx, cy = plaque(p)
    green, belly = (60, 130, 110, 255), (190, 200, 140, 255)
    jaw = [0, 2, 4, 2][frame]
    # Horns sweeping back
    p.d.line([(cx + 2, cy - 7), (cx + 8, cy - 15)], fill=BONE, width=2)
    p.d.line([(cx - 2, cy - 8), (cx + 2, cy - 17)], fill=BONE, width=2)
    # Head and upper snout, lower jaw that drops
    p.d.ellipse([cx - 7, cy - 10, cx + 5, cy + 2], fill=green)
    p.d.polygon([(cx - 6, cy - 6), (cx - 17, cy - 3), (cx - 17, cy), (cx - 6, cy + 1)], fill=green)
    p.d.polygon([(cx - 6, cy + 1), (cx - 16, cy + 1 + jaw), (cx - 15, cy + 3 + jaw), (cx - 5, cy + 4)], fill=belly)
    if jaw:
        p.d.polygon([(cx - 6, cy + 1), (cx - 16, cy + 1), (cx - 16, cy + 1 + jaw)], fill=(150, 40, 50, 255))   # mouth
        for x in (-14, -11, -8):
            p.px(cx + x, cy + 1, BONE)    # teeth
    p.d.rectangle([cx - 3, cy - 6, cx - 1, cy - 5], fill=(250, 200, 60, 255))    # eye
    p.px(cx - 2, cy - 6, DARK)
    for k in range(3):
        p.px(cx + 1 + k * 2, cy - 9 + k, shade(green, 1.4))                   # crest spines
    img = p.finish()
    if frame == 2:   # a puff of smoke at the widest bite
        for k, r in enumerate((2, 3, 2)):
            glow(img, (cx - 19 - k * 2, cy - 2 - k * 3), r * 2, (200, 200, 200), 140)
    return img


def centaur(frame):
    """A bearded centaur's head with a laurel crown; its eyes glow and pulse."""
    p = Piece()
    cx, cy = plaque(p)
    skin, hair = (205, 160, 120, 255), (90, 60, 40, 255)
    p.d.ellipse([cx - 6, cy - 12, cx + 6, cy + 3], fill=skin)                  # face
    p.d.pieslice([cx - 7, cy - 15, cx + 7, cy - 3], 180, 360, fill=hair)      # hair
    p.d.polygon([(cx - 6, cy), (cx - 3, cy + 1), (cx + 3, cy + 1), (cx + 6, cy), (cx + 4, cy + 7), (cx, cy + 10), (cx - 4, cy + 7)], fill=hair)   # beard
    p.d.line([(cx - 2, cy + 2), (cx + 2, cy + 2)], fill=(150, 80, 70, 255))    # mouth
    p.px(cx, cy - 3, shade(skin, 0.8))                                          # nose
    for a in range(-150, -20, 25):                                             # laurel
        r = math.radians(a)
        p.d.ellipse([cx + math.cos(r) * 7 - 1.5, cy - 7 + math.sin(r) * 6 - 1, cx + math.cos(r) * 7 + 1.5, cy - 7 + math.sin(r) * 6 + 1], fill=(110, 150, 60, 255))
    eyes = [(cx - 3, cy - 6), (cx + 3, cy - 6)]
    for e in eyes:
        p.d.rectangle([e[0] - 1, e[1], e[0] + 1, e[1] + 1], fill=(170, 240, 255, 255))
    img = p.finish()
    strength = [70, 120, 170, 120][frame]
    for e in eyes:
        glow(img, (e[0], e[1] + 0.5), 5, (120, 220, 255), strength)
    return img


def griffon(frame):
    """A griffon's eagle head; its crest feathers ruffle."""
    p = Piece()
    cx, cy = plaque(p)
    white, gold = (240, 236, 225, 255), (230, 175, 50, 255)
    ruffle = [0, 1, 2, 1][frame]
    for k in range(4):   # crest feathers at the back of the head
        p.d.polygon([(cx + 2, cy - 8 + k * 3), (cx + 9 + ruffle, cy - 12 + k * 3 - ruffle), (cx + 4, cy - 5 + k * 3)], fill=shade(white, 0.85))
    p.d.ellipse([cx - 6, cy - 11, cx + 5, cy + 3], fill=white)
    p.d.polygon([(cx - 5, cy - 6), (cx - 13, cy - 3), (cx - 9, cy + 2), (cx - 4, cy - 1)], fill=gold)   # hooked beak
    p.d.line([(cx - 12, cy - 2), (cx - 9, cy + 1)], fill=shade(gold, 0.7))
    p.d.rectangle([cx - 3, cy - 7, cx - 1, cy - 6], fill=(240, 170, 40, 255))
    p.px(cx - 2, cy - 7, DARK)
    for k in range(3):   # neck feathers into the plaque
        p.d.polygon([(cx - 4 + k * 3, cy + 2), (cx - 2 + k * 3, cy + 7), (cx + k * 3, cy + 2)], fill=shade(white, 0.9))
    return p.finish()


def unicorn(frame):
    """A white unicorn's head; a glint runs up its spiral horn."""
    p = Piece()
    cx, cy = plaque(p)
    white, mane = (242, 240, 248, 255), (190, 160, 220, 255)
    p.d.polygon([(cx - 3, cy - 10), (cx + 4, cy - 9), (cx + 3, cy + 4), (cx - 3, cy + 4)], fill=white)   # neck/face
    p.d.polygon([(cx - 3, cy - 6), (cx - 13, cy - 1), (cx - 12, cy + 3), (cx - 3, cy + 2)], fill=white)  # muzzle
    p.px(cx - 11, cy, DARK)                                                                              # nostril
    p.d.polygon([(cx + 3, cy - 11), (cx + 8, cy - 8), (cx + 7, cy + 4), (cx + 3, cy + 3)], fill=mane)     # mane
    p.d.rectangle([cx - 2, cy - 7, cx - 1, cy - 6], fill=(90, 70, 140, 255))                            # eye
    horn = [(cx - 2, cy - 10), (cx - 5, cy - 22)]
    p.d.line(horn, fill=(250, 225, 140, 255), width=3)
    for k in range(4):   # the spiral
        t = k / 4
        p.px(horn[0][0] + (horn[1][0] - horn[0][0]) * t, horn[0][1] + (horn[1][1] - horn[0][1]) * t, (205, 170, 80, 255))
    img = p.finish()
    t = [0.15, 0.45, 0.75, 1.0][frame]
    spot = (horn[0][0] + (horn[1][0] - horn[0][0]) * t, horn[0][1] + (horn[1][1] - horn[0][1]) * t)
    img.putpixel((int(spot[0]), int(spot[1])), (255, 255, 255, 255))
    return glow(img, spot, 6, (255, 250, 200), 150)


def minotaur(frame):
    """A minotaur's bull head with great horns and a nose ring; it snorts steam."""
    p = Piece()
    cx, cy = plaque(p)
    brown = (110, 70, 45, 255)
    for side in (-1, 1):   # horns curving up and out
        p.d.line([(cx + side * 4, cy - 7), (cx + side * 11, cy - 9), (cx + side * 13, cy - 16)], fill=BONE, width=3)
    p.d.ellipse([cx - 7, cy - 11, cx + 7, cy + 3], fill=brown)
    p.d.ellipse([cx - 5, cy - 1, cx + 5, cy + 7], fill=shade(brown, 1.25))     # muzzle
    p.px(cx - 2, cy + 2, DARK)
    p.px(cx + 2, cy + 2, DARK)
    p.d.arc([cx - 2, cy + 3, cx + 2, cy + 8], 0, 180, fill=(225, 185, 60, 255))  # nose ring
    for side in (-1, 1):
        p.d.rectangle([cx + side * 4 - 1, cy - 6, cx + side * 4, cy - 5], fill=(200, 40, 40, 255))   # angry eyes
    img = p.finish()
    if frame in (1, 2):
        for side in (-1, 1):
            glow(img, (cx + side * (4 + frame * 2), cy + 4 + frame), 3 + frame, (220, 220, 220), 150)
    return img


def kraken(frame):
    """Kraken tentacles curling out from a ship's-wheel plaque."""
    p = Piece()
    cx, cy = plaque(p)
    purple, sucker = (130, 70, 140, 255), (220, 170, 200, 255)
    p.d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], outline=(150, 110, 60, 255), width=2)    # wheel
    for a in range(0, 360, 45):
        r = math.radians(a)
        p.d.line([(cx, cy), (cx + math.cos(r) * 8, cy + math.sin(r) * 8)], fill=(150, 110, 60, 255))
    sway = [0, 1, 0, -1][frame]
    for n, base in enumerate(((-4, -3), (4, -2), (0, 5))):
        pts = []
        for k in range(8):
            t = k / 7
            ang = -1.6 + n * 1.9 + math.sin(t * 3 + sway * 0.8 + n) * 0.9
            pts.append((cx + base[0] + math.cos(ang) * 12 * t, cy + base[1] + math.sin(ang) * 10 * t))
        p.d.line(pts, fill=purple, width=3)
        for q in pts[2:7:2]:
            p.px(q[0], q[1], sucker)
    return p.finish()


TROPHIES = [
    ("Wyvern head", wyvern),
    ("Centaur head", centaur),
    ("Griffon head", griffon),
    ("Unicorn head", unicorn),
    ("Minotaur head", minotaur),
    ("Kraken tentacles", kraken),
]
FRAMES = 4


def scene(art):
    """The trophy on a stretch of wall, with a guest for size."""
    here = os.path.dirname(os.path.abspath(__file__))
    guests = os.path.join(os.path.dirname(os.path.dirname(here)), "assets", "sprites", "guests")
    img = floor_patch([(237, 201, 138, 255), (226, 185, 118, 255)])
    wall_patch(img)
    piece(img, art)
    person(img, os.path.join(guests, "farmer.png"), (0, 1))
    return img


GAME_IDS = {"Wyvern head": "wyvern", "Centaur head": "centaur", "Griffon head": "griffon",
            "Unicorn head": "unicorn", "Minotaur head": "minotaur", "Kraken tentacles": "kraken"}


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(os.path.dirname(os.path.dirname(here)), "assets", "sprites", "decor")
    os.makedirs(out, exist_ok=True)
    for name, make in TROPHIES:   # the game's frames, side by side
        frames = [make(f) for f in range(FRAMES)]
        sheet = Image.new("RGBA", (frames[0].width * FRAMES, frames[0].height), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            sheet.paste(fr, (i * fr.width, 0))
        sheet.save(os.path.join(out, GAME_IDS[name] + ".png"))
    S = 2
    font = ImageFont.load_default(size=15)
    cw, ch = PW * S + 16, PH * S + 30

    # Every frame of every trophy, a row each (zoomed in on the wall).
    crop = (24, 6, 104, 70)   # the wall area of a preview patch
    zw, zh = (crop[2] - crop[0]) * 3, (crop[3] - crop[1]) * 3
    sheet = Image.new("RGBA", (180 + (zw + 10) * FRAMES, 10 + (zh + 10) * len(TROPHIES)), (52, 46, 42, 255))
    d = ImageDraw.Draw(sheet)
    for r, (name, make) in enumerate(TROPHIES):
        y0 = 10 + r * (zh + 10)
        d.text((12, y0 + zh / 2 - 8), "%d %s" % (r + 1, name), fill=(240, 240, 235), font=font)
        for f in range(FRAMES):
            img = scene(make(f)).crop(crop).resize((zw, zh), Image.NEAREST)
            sheet.alpha_composite(img, (180 + f * (zw + 10), y0))
    sheet.save(os.path.join(here, "trophy_options.png"))

    # The trophies moving, side by side at game size.
    frames = []
    for f in range(FRAMES):
        frame = Image.new("RGBA", (cw * 3 + 10, ch * 2 + 10), (52, 46, 42, 255))
        d = ImageDraw.Draw(frame)
        for i, (name, make) in enumerate(TROPHIES):
            x0, y0 = 10 + (i % 3) * cw, 6 + (i // 3) * ch
            frame.alpha_composite(scene(make(f)).resize((PW * S, PH * S), Image.NEAREST), (x0, y0))
            d.text((x0 + 8, y0 + PH * S + 2), "%d %s" % (i + 1, name), fill=(240, 240, 235), font=font)
        frames.append(frame.convert("RGB"))
    frames[0].save(os.path.join(here, "trophy_options.gif"), save_all=True, append_images=frames[1:], duration=350, loop=0)
    print("wrote trophy_options.png and trophy_options.gif")
