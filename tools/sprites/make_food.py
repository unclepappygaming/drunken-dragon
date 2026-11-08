"""Pixel-art dishes, seen from the same angle as the tables.

Run from the repo root:  python3 tools/sprites/make_food.py
It writes the game's dish sprites to assets/sprites/food/ (one 36 x 28
picture per dish, plus empty and dirty plates) and a preview sheet
(food_options.png) next to this script.

Each dish sits on a plate (or comes in its mug, goblet or bowl). The
middle of the plate is at (18, 18) in its picture.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

FW, FH = 36, 28
C = (18, 18)                 # middle of the plate
OUT = (40, 26, 20, 255)
PLATE = (246, 243, 234, 255)
PLATE_RIM = (214, 208, 196, 255)
GOLD = (226, 184, 70, 255)


def new():
    img = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def shade(c, f):
    return (min(255, int(c[0] * f)), min(255, int(c[1] * f)), min(255, int(c[2] * f)), c[3])


def plate(d, rx=14, ry=7, rim=PLATE_RIM, face=PLATE):
    """A round plate seen at the isometric angle (half as tall as wide)."""
    d.ellipse([C[0] - rx - 1, C[1] - ry - 1, C[0] + rx + 1, C[1] + ry + 1], fill=OUT)
    d.ellipse([C[0] - rx, C[1] - ry, C[0] + rx, C[1] + ry], fill=rim)
    d.ellipse([C[0] - rx + 2, C[1] - ry + 1, C[0] + rx - 2, C[1] + ry - 1], fill=face)


def blob(d, cx, cy, rx, ry, color, light=True):
    """A rounded lump of food with a darker underside and a highlight."""
    d.ellipse([cx - rx - 1, cy - ry - 1, cx + rx + 1, cy + ry + 1], fill=OUT)
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=shade(color, 0.78))
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry - 1], fill=color)
    if light:
        d.ellipse([cx - rx * 0.6, cy - ry * 0.8, cx - rx * 0.1, cy - ry * 0.3], fill=shade(color, 1.25))


def steam(d, x, y):
    for k in range(3):
        d.point((x + (1 if k % 2 else -1), y - k * 2), fill=(240, 240, 240, 200))


# ---------------------------------------------------------------------
# Drinks
# ---------------------------------------------------------------------
def tankard(liquid, foam, wood=(150, 100, 55, 255)):
    img, d = new()
    x0, x1, top, bottom = 12, 23, 6, 24
    d.rectangle([x0 - 1, top - 1, x1 + 1, bottom + 1], fill=OUT)
    d.rectangle([x0, top, x1, bottom], fill=wood)
    for y in (top + 3, bottom - 3):                              # iron hoops
        d.line([(x0, y), (x1, y)], fill=(80, 76, 80, 255))
    d.line([(x0 + 2, top), (x0 + 2, bottom)], fill=shade(wood, 1.2))
    d.rectangle([x1 + 2, top + 4, x1 + 4, bottom - 5], fill=OUT)   # handle
    d.rectangle([x1 + 2, top + 5, x1 + 3, bottom - 6], fill=wood)
    d.ellipse([x0 - 1, top - 3, x1 + 1, top + 2], fill=foam)        # foam spilling over
    d.point((x0 + 3, top - 2), fill=(255, 255, 255, 255))
    if liquid:
        d.point((x1 - 2, top), fill=liquid)
    return img


def ale():
    return tankard((214, 150, 50, 255), (250, 246, 230, 255))


def mead():
    """Honey mead in a clay cup, with a piece of honeycomb beside it."""
    img, d = new()
    plate(d, 9, 4.5)
    d.polygon([(12, 6), (22, 6), (21, 20), (13, 20)], fill=OUT)
    d.polygon([(13, 7), (21, 7), (20, 19), (14, 19)], fill=(190, 120, 80, 255))
    d.line([(14, 8), (14, 18)], fill=(215, 150, 105, 255))
    d.ellipse([12, 4, 22, 9], fill=OUT)
    d.ellipse([13, 5, 21, 8], fill=(240, 180, 60, 255))           # golden mead
    d.polygon([(24, 16), (29, 16), (30, 19), (25, 20)], fill=(235, 175, 50, 255))   # honeycomb
    for x, y in ((26, 17), (28, 18)):
        d.point((x, y), fill=(190, 120, 30, 255))
    return img


def wine():
    """Elven wine in a silver goblet, with a little bunch of grapes."""
    img, d = new()
    plate(d, 9, 4.5)
    d.ellipse([12, 3, 22, 9], fill=OUT)
    d.ellipse([13, 4, 21, 8], fill=(205, 210, 225, 255))
    d.ellipse([14, 4, 20, 7], fill=(120, 30, 70, 255))           # the wine
    d.polygon([(13, 7), (21, 7), (18, 12), (16, 12)], fill=(205, 210, 225, 255))
    d.line([(17, 12), (17, 18)], fill=(170, 175, 190, 255), width=2)   # stem
    d.ellipse([14, 17, 20, 20], fill=(170, 175, 190, 255))         # foot
    for x, y in ((25, 15), (27, 15), (26, 17), (28, 17), (27, 19)):   # grapes
        d.ellipse([x - 1, y - 1, x + 1, y + 1], fill=(110, 60, 140, 255))
    return img


# ---------------------------------------------------------------------
# Food
# ---------------------------------------------------------------------
def stew():
    """Mushroom stew in a wooden bowl, steaming, with a hunk of bread."""
    img, d = new()
    plate(d)
    d.ellipse([7, 10, 25, 23], fill=OUT)
    d.ellipse([8, 11, 24, 22], fill=(130, 85, 50, 255))             # bowl
    d.ellipse([10, 12, 22, 18], fill=(150, 90, 45, 255))            # stew
    rnd = random.Random(2)
    for _ in range(6):
        x, y = rnd.randint(11, 20), rnd.randint(13, 16)
        d.point((x, y), fill=rnd.choice([(225, 205, 170, 255), (235, 140, 50, 255), (100, 150, 60, 255)]))
    blob(d, 27, 18, 4, 2.5, (210, 160, 90, 255))                   # bread
    steam(d, 15, 9)
    steam(d, 19, 8)
    return img


def boar():
    """Roast boar: a glazed joint with an apple and greens."""
    img, d = new()
    plate(d)
    blob(d, 16, 16, 9, 5, (165, 85, 40, 255))
    for x in (11, 15, 19):                                           # crackling scores
        d.line([(x, 13), (x + 2, 18)], fill=(120, 60, 30, 255))
    d.line([(23, 13), (29, 10)], fill=OUT, width=3)                  # bone
    d.line([(23, 13), (29, 10)], fill=(240, 230, 205, 255))
    blob(d, 8, 19, 2.5, 2, (200, 50, 50, 255))                       # apple
    for x, y in ((24, 20), (26, 19), (22, 21)):
        d.point((x, y), fill=(90, 150, 60, 255))
    steam(d, 15, 10)
    return img


def cheese():
    """Troll cheese: a big wedge with holes, and a slice of bread."""
    img, d = new()
    plate(d)
    d.polygon([(8, 18), (22, 11), (24, 17), (11, 22)], fill=OUT)
    d.polygon([(9, 18), (22, 12), (23, 16), (11, 21)], fill=(240, 205, 80, 255))
    d.polygon([(9, 18), (22, 12), (21, 11), (8, 17)], fill=(250, 225, 120, 255))   # top
    for x, y in ((13, 18), (17, 16), (20, 15)):
        d.point((x, y), fill=(200, 160, 50, 255))
    blob(d, 26, 19, 4, 2.5, (200, 150, 85, 255))
    return img


def wings():
    """Wyvern wings: three glazed wings with bone tips and a dip."""
    img, d = new()
    plate(d)
    for i, (x, y) in enumerate(((10, 15), (17, 13), (14, 19))):
        blob(d, x, y, 4, 2.5, (200, 90, 40, 255))
        d.line([(x + 4, y - 1), (x + 6, y - 2)], fill=(240, 230, 205, 255))   # bone tip
    d.ellipse([22, 16, 28, 20], fill=OUT)
    d.ellipse([23, 16, 27, 19], fill=(240, 235, 220, 255))          # dip
    d.point((25, 17), fill=(150, 200, 90, 255))
    return img


def phoenix():
    """Phoenix roast: a golden bird with little flames dancing on it."""
    img, d = new()
    plate(d, rim=GOLD)
    blob(d, 17, 15, 8, 5, (220, 130, 40, 255))
    blob(d, 10, 18, 3, 2, (210, 120, 35, 255))                       # drumstick
    blob(d, 24, 18, 3, 2, (210, 120, 35, 255))
    for x, y in ((14, 9), (18, 8), (21, 10)):                        # flames
        d.polygon([(x - 1, y + 2), (x, y - 2), (x + 1, y + 2)], fill=(255, 210, 80, 255))
        d.point((x, y + 1), fill=(240, 90, 40, 255))
    return img


def feast():
    """The Dragonfire Feast: a gold platter heaped with roast, grapes,
    bread and a drumstick, with a little dragon-flame on top."""
    img, d = new()
    plate(d, 16, 8, rim=GOLD, face=(250, 235, 190, 255))
    blob(d, 17, 15, 7, 4, (165, 85, 40, 255))                        # roast
    blob(d, 8, 18, 3, 2, (210, 160, 90, 255))                        # bread
    blob(d, 27, 17, 3, 2, (200, 90, 40, 255))                        # drumstick
    for x, y in ((11, 13), (13, 12), (12, 14)):
        d.ellipse([x - 1, y - 1, x + 1, y + 1], fill=(110, 60, 140, 255))   # grapes
    for x, y in ((22, 21), (24, 20)):
        d.point((x, y), fill=(90, 150, 60, 255))
    d.polygon([(16, 13), (17, 6), (18, 13)], fill=(255, 210, 80, 255))      # flame
    d.polygon([(16, 13), (17, 9), (18, 13)], fill=(240, 90, 40, 255))
    return img


def empty_plate():
    img, d = new()
    plate(d)
    return img


def dirty_plate():
    img, d = new()
    plate(d)
    for x, y, c in ((12, 17, (175, 105, 55)), (19, 15, (150, 95, 50)), (22, 19, (190, 120, 60)), (15, 20, (160, 100, 50))):
        d.ellipse([x - 1, y - 1, x + 1, y], fill=c + (255,))
    d.line([(10, 18), (21, 21)], fill=(205, 205, 210, 255))          # a fork left behind
    return img


DISHES = {"ale": ale, "stew": stew, "mead": mead, "boar": boar, "cheese": cheese,
          "wings": wings, "wine": wine, "phoenix": phoenix, "feast": feast,
          "plate": empty_plate, "dirty": dirty_plate}
NAMES = {"ale": "Dragon Ale", "stew": "Mushroom Stew", "mead": "Honey Mead", "boar": "Roast Boar",
         "cheese": "Troll Cheese", "wings": "Wyvern Wings", "wine": "Elven Wine",
         "phoenix": "Phoenix Roast", "feast": "Dragonfire Feast", "plate": "(empty plate)",
         "dirty": "(dirty plate)"}


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    out = os.path.join(root, "assets", "sprites", "food")
    os.makedirs(out, exist_ok=True)
    pics = {}
    for name, make in DISHES.items():
        pics[name] = make()
        pics[name].save(os.path.join(out, name + ".png"))

    # Preview: each dish zoomed in, and on a table as the game shows it:
    # the table at 2x like all the furniture, the dishes at 1x (finer
    # pixels), two to a table, beside the old plain plate for size.
    table = Image.open(os.path.join(root, "assets", "sprites", "furniture", "table.png")).convert("RGBA")
    table2 = table.resize((128, 144), Image.NEAREST)
    font = ImageFont.load_default(size=14)
    Z = 4
    names = [n for n in DISHES if n not in ("plate",)]
    cw, ch = FW * Z + 30, FH * Z + 150
    sheet = Image.new("RGBA", (cw * 6 + 10, ch * 2 + 10), (60, 54, 48, 255))
    sd = ImageDraw.Draw(sheet)
    top = (64, 116 - 26)   # middle of the tabletop on the 2x table
    for i, name in enumerate(names):
        x0, y0 = 10 + (i % 5) * cw, 10 + (i // 5) * ch
        sheet.alpha_composite(pics[name].resize((FW * Z, FH * Z), Image.NEAREST), (x0, y0))
        sd.text((x0 + 4, y0 + FH * Z + 2), NAMES[name], fill=(240, 240, 235), font=font)
        t = table2.copy()
        for dx, dy in ((-11, -3), (11, 3)):   # two seats' worth
            t.alpha_composite(pics[name], (top[0] + dx - C[0], top[1] + dy - C[1]))
        sheet.alpha_composite(t.crop((10, 40, 118, 140)), (x0 + 30, y0 + FH * Z + 22))
    # The old plate for comparison, last slot
    x0, y0 = 10 + 5 * cw, 10 + ch
    old = table2.copy()
    od = ImageDraw.Draw(old)
    for dx, dy in ((-11, -3), (11, 3)):
        cx, cy = top[0] + dx, top[1] + dy
        od.ellipse([cx - 12, cy - 6, cx + 12, cy + 6], fill=OUT)
        od.ellipse([cx - 11, cy - 5.5, cx + 11, cy + 5.5], fill=PLATE)
        od.ellipse([cx - 7.5, cy - 4, cx + 7.5, cy + 3], fill=(195, 112, 50, 255))
    sheet.alpha_composite(old.crop((10, 40, 118, 140)), (x0 + 30, y0 + FH * Z + 22))
    sd.text((x0 + 4, y0 + FH * Z + 2), "Old plates (for size)", fill=(250, 230, 180), font=font)
    sheet.save(os.path.join(here, "food_options.png"))
    print("wrote", len(DISHES), "dishes and food_options.png")
