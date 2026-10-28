"""Pixel-art staff sprites for The Drunken Dragon.

Run from the repo root:  python3 tools/sprites/make_sprites.py
It writes one sprite sheet per staff type to assets/sprites/staff/, plus a
preview sheet of all of them (staff_options.png) next to this script.

Each character is drawn on a 32x32 grid (inside a 32x40 frame, so tall hats
fit) in layers: shadow, legs, body, arms, head, hair/hat, props. Then it
gets a 1px dark outline from its silhouette.

Sheet layout (each frame 32x40):
    columns: front idle, front walk 1, front walk 2,
             side idle, side walk 1, side walk 2   (facing right)
             back idle, back walk 1, back walk 2
    rows:    0 = normal, 1 = carrying a dish (waiters; cooks repeat row 0)

The game recolors skin and hair per person with a palette-swap shader,
matching the exact SKIN / SKIN_DARK colors below and each type's hair color
(listed in GameManager.STAFF_TYPES as hair_key). Keep them in sync.
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 32, 40
# Characters are designed on a 32x32 grid; this pushes them down so tall
# hats have room above.
OFFSET_Y = 8
OUTLINE = (40, 26, 20, 255)
SKIN = (241, 194, 150, 255)
SKIN_DARK = (214, 160, 120, 255)
BLUSH = (232, 150, 140, 255)
EYE = (40, 30, 30, 255)
SHADOW = (0, 0, 0, 70)


def px(img, x, y, c):
    y += OFFSET_Y
    if 0 <= x < W and 0 <= y < H:
        img.putpixel((x, y), c)


def rect(img, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(img, x, y, c)


def ellipse(img, cx, cy, rx, ry, c, top_only=False, below=None):
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                if top_only and y > cy:
                    continue
                if below is not None and y < below:
                    continue
                px(img, x, y, c)


def outline(img):
    """Adds a 1px outline around everything that isn't the shadow."""
    src = img.copy()
    for y in range(H):
        for x in range(W):
            if src.getpixel((x, y))[3] > 100:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and src.getpixel((nx, ny))[3] > 100:
                    img.putpixel((x, y), OUTLINE)
                    break


def shade(c, f):
    return (int(c[0] * f), int(c[1] * f), int(c[2] * f), 255)


# ---------------------------------------------------------------------
# A character is a dict of colors and options; draw() builds one frame.
# ---------------------------------------------------------------------
def draw(ch, view="front", step=0):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    small = ch.get("small", False)          # dwarves / halflings are shorter
    top = 4 if small else 0                 # shift everything down a bit
    head_cy = 10 + top
    body_y0, body_y1 = 16 + top, 24
    if small:
        body_y0 = 18 + top - 2

    # Legs: the walk cycle lifts one leg a pixel and shifts the other.
    lift_l = 1 if step == 1 else 0
    lift_r = 1 if step == 2 else 0
    leg = ch["legs"]
    shoe = ch["shoes"]
    if view == "side":
        fwd = {0: 0, 1: 2, 2: -2}[step]
        rect(img, 15 - fwd, 25, 17 - fwd, 28, shade(leg, 0.8))
        rect(img, 15 + fwd, 25, 17 + fwd, 28, leg)
        rect(img, 15 + fwd, 28, 18 + fwd, 29, shoe)
        rect(img, 15 - fwd, 28, 18 - fwd, 29, shade(shoe, 0.8))
    else:
        rect(img, 12, 25 - lift_l, 14, 28 - lift_l, leg)
        rect(img, 17, 25 - lift_r, 19, 28 - lift_r, leg)
        rect(img, 12, 28 - lift_l, 14, 29 - lift_l, shoe)
        rect(img, 17, 28 - lift_r, 19, 29 - lift_r, shoe)

    # Body
    body = ch["body"]
    if view == "side":
        rect(img, 12, body_y0, 19, body_y1, body)
        rect(img, 12, body_y0, 12, body_y1, shade(body, 0.85))
    else:
        rect(img, 10, body_y0 + 1, 21, body_y1, body)
        rect(img, 11, body_y0, 20, body_y0, body)
        if ch.get("dress"):
            rect(img, 9, 21, 22, 26, body)    # skirt flares out
            rect(img, 9, 26, 22, 26, shade(body, 0.8))
    # Apron / vest / jacket details (front only for most)
    for layer in ch.get("layers", []):
        layer(img, view, body_y0, body_y1)

    # Arms (behind props). Side view shows one arm swinging.
    sleeve = ch.get("sleeve", body)
    if view == "side":
        swing = {0: 0, 1: 1, 2: -1}[step]
        rect(img, 15 + swing, body_y0 + 1, 17 + swing, body_y0 + 6, sleeve)
        rect(img, 15 + swing, body_y0 + 7, 17 + swing, body_y0 + 8, ch.get("hand", SKIN))
    else:
        rect(img, 8, body_y0 + 1, 9, body_y0 + 6, sleeve)
        rect(img, 22, body_y0 + 1, 23, body_y0 + 6, sleeve)
        rect(img, 8, body_y0 + 7, 9, body_y0 + 8, ch.get("hand", SKIN))
        rect(img, 22, body_y0 + 7, 23, body_y0 + 8, ch.get("hand", SKIN))

    # Head
    rx = 6.5 if not small else 7
    ellipse(img, 16, head_cy, rx, 6.5, SKIN)
    if view == "front":
        px(img, 13, head_cy + 1, EYE); px(img, 13, head_cy + 2, EYE)
        px(img, 18, head_cy + 1, EYE); px(img, 18, head_cy + 2, EYE)
        px(img, 12, head_cy + 3, BLUSH); px(img, 19, head_cy + 3, BLUSH)
        px(img, 15, head_cy + 4, SKIN_DARK); px(img, 16, head_cy + 4, SKIN_DARK)
    elif view == "side":
        px(img, 19, head_cy + 1, EYE); px(img, 19, head_cy + 2, EYE)
        px(img, 21, head_cy + 2, SKIN)       # little nose
        px(img, 18, head_cy + 3, BLUSH)
    for layer in ch.get("head_layers", []):
        layer(img, view, head_cy)

    # Props held in front (tray, spoon...)
    for layer in ch.get("props", []):
        layer(img, view, body_y0, step)

    outline(img)
    # Shadow goes under everything, after the outline.
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ellipse(shadow, 16, 30, 7, 1.8, SHADOW)
    shadow.alpha_composite(img)
    return shadow


# ---------------------------------------------------------------------
# Reusable layers
# ---------------------------------------------------------------------
def apron(color, y_from=4, full=False):
    def layer(img, view, y0, y1):
        if view == "back":
            rect(img, 15, y0 + 3, 16, y0 + 4, color)   # apron bow
            return
        x0, x1 = (12, 19) if view == "side" else (11, 20)
        if view == "side":
            x0, x1 = 17, 20
        start = y0 + (1 if full else y_from)
        rect(img, x0, start, x1, y1 + 1, color)
        if full and view == "front":
            rect(img, 13, y0, 18, y0 + 1, color)       # bib
    return layer


def buttons(color):
    def layer(img, view, y0, y1):
        if view != "front":
            return
        for y in range(y0 + 2, y1, 2):
            px(img, 13, y, color); px(img, 18, y, color)
    return layer


def vest(color, shirt):
    def layer(img, view, y0, y1):
        if view == "front":
            rect(img, 14, y0, 17, y0 + 6, shirt)        # shirt showing in the middle
            px(img, 15, y0 + 1, (120, 30, 30, 255)); px(img, 16, y0 + 1, (120, 30, 30, 255))
        elif view == "side":
            rect(img, 18, y0, 19, y0 + 5, shirt)
    return layer


def neckerchief(color):
    def layer(img, view, y0, y1):
        if view == "front":
            rect(img, 13, y0, 18, y0 + 1, color)
            rect(img, 15, y0 + 2, 16, y0 + 2, color)
        elif view == "side":
            rect(img, 15, y0, 19, y0 + 1, color)
    return layer


def hair(color, style="short"):
    dark = shade(color, 0.8)

    def layer(img, view, cy):
        if view == "back":
            ellipse(img, 16, cy, 6.6, 6.6, color)
            if style == "braid":
                rect(img, 15, cy + 5, 16, cy + 11, color)
                px(img, 15, cy + 11, (200, 60, 60, 255)); px(img, 16, cy + 11, (200, 60, 60, 255))
            if style == "curly":
                for x in (11, 14, 17, 20):
                    px(img, x, cy + 6, dark)
            return
        ellipse(img, 16, cy - 1, 6.8, 5.6, color, top_only=True)
        if view == "front":
            rect(img, 10, cy - 1, 11, cy + 2, color)       # sideburns
            rect(img, 20, cy - 1, 21, cy + 2, color)
            for x in range(12, 20, 2):
                px(img, x, cy - 1, color)                    # fringe
            if style == "curly":
                for x in (10, 13, 16, 19, 22):
                    px(img, x, cy - 5, dark)
            if style == "braid":
                rect(img, 21, cy, 22, cy + 7, color)
                px(img, 21, cy + 8, (200, 60, 60, 255))
        else:  # side
            rect(img, 10, cy - 1, 14, cy + 3, color)
            if style == "braid":
                rect(img, 10, cy + 3, 11, cy + 9, color)
    return layer


def toque():
    white = (250, 250, 245, 255)
    shadow_c = (215, 215, 210, 255)

    def layer(img, view, cy):
        ellipse(img, 16, cy - 9, 6, 4, white)
        rect(img, 11, cy - 8, 20, cy - 4, white)
        rect(img, 10, cy - 4, 21, cy - 3, shadow_c)          # band
        if view == "front":
            px(img, 13, cy - 10, shadow_c); px(img, 18, cy - 9, shadow_c)
    return layer


def headscarf(color):
    def layer(img, view, cy):
        ellipse(img, 16, cy - 1, 7, 6, color, top_only=True)
        rect(img, 9, cy - 1, 22, cy, color)
        if view == "back":
            rect(img, 15, cy + 1, 17, cy + 3, color)          # knot
            px(img, 14, cy + 4, color); px(img, 18, cy + 4, color)
        elif view == "side":
            rect(img, 9, cy + 1, 10, cy + 3, color)           # knot tails
        else:
            for x in range(11, 22, 3):
                px(img, x, cy - 3, (250, 240, 220, 255))       # polka dots
    return layer


def bandana(color):
    def layer(img, view, cy):
        ellipse(img, 16, cy - 2, 7, 5, color, top_only=True)
        rect(img, 9, cy - 2, 23, cy - 1, color)
        if view == "side":
            rect(img, 9, cy - 1, 10, cy + 2, color)
    return layer


def beard(color):
    dark = shade(color, 0.8)

    def layer(img, view, cy):
        if view == "back":
            return
        if view == "front":
            ellipse(img, 16, cy + 6, 7, 6, color, below=cy + 3)
            rect(img, 13, cy + 3, 18, cy + 3, dark)           # mustache
            px(img, 15, cy + 9, dark); px(img, 17, cy + 11, dark)
        else:
            ellipse(img, 18, cy + 6, 4, 5, color, below=cy + 3)
    return layer


def bonnet():
    white = (250, 248, 240, 255)

    def layer(img, view, cy):
        rect(img, 11, cy - 6, 20, cy - 5, white)
        if view == "front":
            for x in range(11, 21, 2):
                px(img, x, cy - 7, white)                     # frill
    return layer


def tray(mug=True, plate=False):
    def layer(img, view, y0, step):
        if view == "back":
            rect(img, 22, y0 - 2, 27, y0 - 1, (150, 150, 155, 255))
            return
        tx = 24 if view == "front" else 22
        ty = y0 + 3
        rect(img, tx - 4, ty, tx + 4, ty + 1, (165, 165, 172, 255))   # tray
        if mug:
            rect(img, tx - 2, ty - 4, tx + 1, ty - 1, (205, 140, 50, 255))
            rect(img, tx - 2, ty - 5, tx + 1, ty - 5, (250, 245, 225, 255))   # foam
            px(img, tx + 2, ty - 3, (205, 140, 50, 255))
        if plate:
            rect(img, tx - 3, ty - 1, tx + 3, ty - 1, (250, 250, 250, 255))
            rect(img, tx - 2, ty - 3, tx + 2, ty - 2, (190, 110, 50, 255))
    return layer


def spoon():
    wood = (160, 110, 60, 255)

    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 23 if view == "front" else 18
        rect(img, x, y0 - 2, x, y0 + 7, wood)
        rect(img, x - 1, y0 - 4, x + 1, y0 - 2, wood)
    return layer


# ---------------------------------------------------------------------
# The design options
# ---------------------------------------------------------------------
COOKS = {
    "A. Classic Chef": dict(
        body=(245, 245, 240, 255), sleeve=(235, 235, 230, 255),
        legs=(80, 80, 90, 255), shoes=(50, 40, 35, 255),
        layers=[buttons((150, 150, 150, 255)), neckerchief((200, 50, 45, 255))],
        head_layers=[hair((110, 70, 40, 255)), toque()],
    ),
    "B. Tavern Cook": dict(
        body=(150, 95, 60, 255), sleeve=(150, 95, 60, 255),
        legs=(90, 70, 55, 255), shoes=(55, 40, 30, 255),
        layers=[apron((240, 230, 205, 255), full=True)],
        head_layers=[hair((120, 80, 50, 255)), headscarf((190, 55, 50, 255))],
        props=[spoon()],
    ),
    "C. Dwarf Cook": dict(
        small=True,
        body=(120, 80, 140, 255), sleeve=(120, 80, 140, 255),
        legs=(85, 65, 50, 255), shoes=(50, 35, 25, 255),
        layers=[apron((235, 225, 200, 255), y_from=2)],
        head_layers=[beard((200, 110, 50, 255)), bandana((60, 110, 170, 255))],
    ),
}

WAITERS = {
    "A. Barkeep": dict(
        body=(45, 95, 70, 255), sleeve=(245, 242, 232, 255),
        legs=(60, 50, 45, 255), shoes=(40, 30, 25, 255),
        layers=[vest((45, 95, 70, 255), (245, 242, 232, 255)), apron((235, 228, 210, 255), y_from=6)],
        head_layers=[hair((160, 100, 50, 255))],
        props=[tray()],
    ),
    "B. Serving Maid": dict(
        dress=True,
        body=(70, 105, 170, 255), sleeve=(70, 105, 170, 255),
        legs=(70, 105, 170, 255), shoes=(60, 40, 35, 255),
        layers=[apron((248, 245, 236, 255), full=True)],
        head_layers=[hair((180, 120, 60, 255), style="braid"), bonnet()],
        props=[tray()],
    ),
    "C. Halfling Server": dict(
        small=True,
        body=(200, 150, 50, 255), sleeve=(245, 240, 225, 255),
        legs=(110, 85, 60, 255), shoes=(150, 100, 70, 255),   # big bare halfling feet
        layers=[vest((200, 150, 50, 255), (245, 240, 225, 255))],
        head_layers=[hair((95, 60, 35, 255), style="curly")],
        props=[tray(mug=True)],
    ),
}


def frames(ch):
    """[front idle, front step 1, front step 2, side, side step, back]"""
    return [draw(ch, "front", 0), draw(ch, "front", 1), draw(ch, "front", 2),
            draw(ch, "side", 0), draw(ch, "side", 1), draw(ch, "back", 0)]


def carrying(ch):
    """Waiter carrying a dish to a table (the tray swaps the mug for a plate)."""
    c = dict(ch)
    c["props"] = [tray(mug=False, plate=True)]
    return draw(c, "front", 0)


# Type IDs used by the game, in the same order as the options above.
TYPE_IDS = {
    "A. Classic Chef": "chef", "B. Tavern Cook": "tavern_cook", "C. Dwarf Cook": "dwarf_cook",
    "A. Barkeep": "barkeep", "B. Serving Maid": "maid", "C. Halfling Server": "halfling",
}


def export_sheets(out_dir):
    views = [("front", s) for s in range(3)] + [("side", s) for s in range(3)] + [("back", s) for s in range(3)]
    for name, ch in list(COOKS.items()) + list(WAITERS.items()):
        is_waiter = name in WAITERS
        out = Image.new("RGBA", (W * len(views), H * 2), (0, 0, 0, 0))
        carry = dict(ch)
        if is_waiter:
            carry["props"] = [tray(mug=False, plate=True)]
        for row, c in enumerate([ch, carry]):
            for col, (view, step) in enumerate(views):
                out.alpha_composite(draw(c, view, step), (col * W, row * H))
        path = f"{out_dir}/{TYPE_IDS[name]}.png"
        out.save(path)
        print("wrote", path)


# ---------------------------------------------------------------------
# Preview sheet
# ---------------------------------------------------------------------
def floor_tile(w, h=None):
    h = h or w
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    sq = w // 2
    for i in range(2):
        for j in range((h + sq - 1) // sq):
            s = 0.38 if (i + j) % 2 == 0 else 0.33
            c = (int(255 * s), int(255 * s * 0.72), int(255 * s * 0.5), 255)
            d.rectangle([i * sq, j * sq, (i + 1) * sq - 1, (j + 1) * sq - 1], fill=c)
    return img


def sheet(groups, path):
    scale = 5                      # big view: 32px -> 160px
    cell_w, cell_h = W * scale, H * scale
    cell = cell_w
    gap = 14
    font = ImageFont.load_default(size=26)
    small_font = ImageFont.load_default(size=18)
    labels = ["Front", "Walk 1", "Walk 2", "Side", "Side walk", "Back", "In game"]
    rows = sum(len(g) for _, g in groups) + len(groups)
    width = 260 + 7 * (cell + gap)
    height = 20 + len(groups) * 60 + sum(len(g) for _, g in groups) * (cell_h + gap)
    out = Image.new("RGBA", (width, height), (38, 30, 26, 255))
    d = ImageDraw.Draw(out)
    y = 20
    for title, chars in groups:
        d.text((20, y), title, fill=(255, 220, 140, 255), font=font)
        for i, lab in enumerate(labels):
            d.text((260 + i * (cell + gap) + 10, y + 6), lab, fill=(200, 190, 170, 255), font=small_font)
        y += 50
        for name, ch in chars.items():
            d.text((20, y + cell_h // 2 - 14), name, fill=(240, 235, 225, 255), font=font)
            for i, fr in enumerate(frames(ch)):
                bg = floor_tile(cell_w, cell_h)
                bg.alpha_composite(fr.resize((cell_w, cell_h), Image.NEAREST))
                out.alpha_composite(bg, (260 + i * (cell + gap), y))
            # In-game size: 80px floor square, sprite at 2x (64px), with a carry pose for waiters
            # In game: floor squares are 80px and sprites are drawn 2x.
            game = floor_tile(cell_w, cell_h)
            is_waiter = any(word in name for word in ("Barkeep", "Maid", "Server"))
            sprite = carrying(ch) if is_waiter else frames(ch)[0]
            g = sprite.resize((W * 2, H * 2), Image.NEAREST)
            game.alpha_composite(g, ((cell_w - W * 2) // 2, (cell_h - H * 2) // 2))
            out.alpha_composite(game, (260 + 6 * (cell + gap), y))
            y += cell_h + gap
        y += 10
    out.save(path)


if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    export_sheets(os.path.join(root, "assets", "sprites", "staff"))
    sheet([("Cooks", COOKS), ("Waiters", WAITERS)], os.path.join(here, "staff_options.png"))
    print("wrote", os.path.join(here, "staff_options.png"))
