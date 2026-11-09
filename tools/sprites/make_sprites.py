"""Pixel-art staff sprites for The Drunken Dragon.

Run from the repo root:  python3 tools/sprites/make_sprites.py
It writes one sprite sheet per staff type to assets/sprites/staff/ and per
guest look to assets/sprites/guests/, plus preview sheets (staff_options.png,
guest_options.png) next to this script.

Each character is drawn on a 32x32 grid (inside a 32x40 frame, so tall hats
fit) in layers: shadow, legs, body, arms, head, hair/hat, props. Then it
gets a 1px dark outline from its silhouette.

Sheet layout (each frame 32x40):
    columns: front idle, front walk 1, front walk 2,
             side idle, side walk 1, side walk 2   (facing right)
             back idle, back walk 1, back walk 2
    rows:    0 = normal, 1 = carrying a dish (waiters; cooks repeat row 0)

The game recolors skin and hair per person with a palette-swap shader,
matching the exact SKIN / SKIN_DARK colors below and each look's hair color
(hair_key in staff_profiles.gd and guest_types.gd). Keep them in sync.
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


def shade_pass(img, keep):
    """Light from the upper left: pixels on an upper or left edge get
    lighter, lower or right edges darker, and a thin shadow falls under
    anything drawn over something else. Skin and hair are left alone:
    the game recolours exactly those colours for each person."""
    src = img.copy()

    def at(x, y):
        if 0 <= x < W and 0 <= y < H:
            return src.getpixel((x, y))
        return (0, 0, 0, 0)
    for y in range(H):
        for x in range(W):
            c = src.getpixel((x, y))
            if c[3] < 200 or c in keep:
                continue
            up, left, down, right = at(x, y - 1), at(x - 1, y), at(x, y + 1), at(x + 1, y)
            if up[3] < 100 or left[3] < 100:
                img.putpixel((x, y), shade(c, 1.15))
            elif down[3] < 100 or right[3] < 100:
                img.putpixel((x, y), shade(c, 0.8))
            elif up[3] >= 200 and up[:3] != c[:3] and up not in keep and sum(up[:3]) < sum(c[:3]):
                img.putpixel((x, y), shade(c, 0.88))   # shadow under a darker piece above


def shade(c, f):
    return (int(c[0] * f), int(c[1] * f), int(c[2] * f), 255)


# ---------------------------------------------------------------------
# A character is a dict of colors and options; draw() builds one frame.
# ---------------------------------------------------------------------
def draw(ch, view="front", step=0):
    """view: "front", "side", "back", or the three-quarter views
    "quarter" (turned a little to our right, walking down-right on screen)
    and "quarter_back" (walking away, up-right). Layers only know
    front/side/back, so they're drawn as the nearest of those."""
    quarter = view in ("quarter", "quarter_back")
    base = {"quarter": "front", "quarter_back": "back"}.get(view, view)
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
    if quarter:
        # Staggered: the far leg is a shade darker and tucked in.
        fwd = {0: 0, 1: 1, 2: -1}[step]
        rect(img, 13, 25 - lift_l, 15, 28 - lift_l, shade(leg, 0.82))
        rect(img, 13, 28 - lift_l, 16, 29 - lift_l, shade(shoe, 0.82))
        rect(img, 17 + fwd, 25 - lift_r, 19 + fwd, 28 - lift_r, leg)
        rect(img, 17 + fwd, 28 - lift_r, 20 + fwd, 29 - lift_r, shoe)
    elif view == "side":
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
    if quarter:
        # Narrower on the far side, with the near side in shade.
        rect(img, 11, body_y0 + 1, 21, body_y1, body)
        rect(img, 12, body_y0, 20, body_y0, body)
        rect(img, 20, body_y0 + 1, 21, body_y1, shade(body, 0.84))
        if ch.get("dress"):
            rect(img, 10, 21, 22, 26, body)
            rect(img, 20, 21, 22, 26, shade(body, 0.84))
            rect(img, 10, 26, 22, 26, shade(body, 0.75))
    elif view == "side":
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
        layer(img, base, body_y0, body_y1)

    # Arms (behind props). Side view shows one arm swinging.
    sleeve = ch.get("sleeve", body)
    if quarter:
        # The far arm mostly hidden behind the body; the near one swings.
        swing = {0: 0, 1: 1, 2: -1}[step]
        rect(img, 10, body_y0 + 2, 10, body_y0 + 6, shade(sleeve, 0.8))
        rect(img, 10, body_y0 + 7, 10, body_y0 + 7, ch.get("hand", SKIN))
        rect(img, 22, body_y0 + 1 + swing, 23, body_y0 + 6 + swing, sleeve)
        rect(img, 22, body_y0 + 7 + swing, 23, body_y0 + 8 + swing, ch.get("hand", SKIN))
    elif view == "side":
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
    elif view == "quarter":
        # Both eyes, shifted towards where they're looking; the nose
        # just shows on the edge of the face.
        px(img, 15, head_cy + 1, EYE); px(img, 15, head_cy + 2, EYE)
        px(img, 19, head_cy + 1, EYE); px(img, 19, head_cy + 2, EYE)
        px(img, 14, head_cy + 3, BLUSH); px(img, 20, head_cy + 3, BLUSH)
        px(img, 22, head_cy + 2, SKIN)
        px(img, 18, head_cy + 4, SKIN_DARK)
    elif view == "side":
        px(img, 19, head_cy + 1, EYE); px(img, 19, head_cy + 2, EYE)
        px(img, 21, head_cy + 2, SKIN)       # little nose
        px(img, 18, head_cy + 3, BLUSH)
    for layer in ch.get("head_layers", []):
        layer(img, base, head_cy)
    if view == "quarter_back":
        # Walking away: a glimpse of cheek and ear on the near side.
        rect(img, 21, head_cy + 1, 22, head_cy + 3, SKIN)
        px(img, 21, head_cy + 4, SKIN_DARK)

    # Props held in front (tray, spoon...)
    for layer in ch.get("props", []):
        layer(img, base, body_y0, step)
    # Extra details (towels, notepads, belts...) drawn over everything
    for layer in ch.get("extras", []):
        layer(img, base, body_y0, body_y1, head_cy)

    if ch.get("shade"):
        shade_pass(img, [SKIN, SKIN_DARK, BLUSH, EYE, ch.get("hair_key")])
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
            if style == "long":
                rect(img, 10, cy + 2, 21, cy + 9, color)
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
            if style == "long":
                rect(img, 9, cy - 1, 10, cy + 8, color)
                rect(img, 21, cy - 1, 22, cy + 8, color)
        else:  # side
            rect(img, 10, cy - 1, 14, cy + 3, color)
            if style == "braid":
                rect(img, 10, cy + 3, 11, cy + 9, color)
            if style == "long":
                rect(img, 10, cy + 3, 13, cy + 9, color)
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


# Waiters carry an empty tray; the game draws what's on it (a plate of
# food, a mug for drinks, or dirty plates), see waiter.gd.
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
        props=[tray(mug=False)],
    ),
    "B. Serving Maid": dict(
        dress=True,
        body=(70, 105, 170, 255), sleeve=(70, 105, 170, 255),
        legs=(70, 105, 170, 255), shoes=(60, 40, 35, 255),
        layers=[apron((248, 245, 236, 255), full=True)],
        head_layers=[hair((180, 120, 60, 255), style="braid"), bonnet()],
        props=[tray(mug=False)],
    ),
    "C. Halfling Server": dict(
        small=True,
        body=(200, 150, 50, 255), sleeve=(245, 240, 225, 255),
        legs=(110, 85, 60, 255), shoes=(150, 100, 70, 255),   # big bare halfling feet
        layers=[vest((200, 150, 50, 255), (245, 240, 225, 255))],
        head_layers=[hair((95, 60, 35, 255), style="curly")],
        props=[tray(mug=False)],
    ),
}


# ---------------------------------------------------------------------
# Extra details (layer(img, view, y0, y1, head_cy)), drawn last
# ---------------------------------------------------------------------
GOLD_PX = (225, 185, 60, 255)
WHITE = (248, 246, 238, 255)


def towel(stripe):
    """A cloth over the left shoulder."""
    def layer(img, view, y0, y1, cy):
        if view == "front":
            rect(img, 19, y0, 21, y0 + 5, WHITE)
            px(img, 20, y0 + 2, stripe); px(img, 19, y0 + 2, stripe); px(img, 21, y0 + 2, stripe)
        elif view == "side":
            rect(img, 13, y0, 15, y0 + 3, WHITE)
            px(img, 14, y0 + 1, stripe)
    return layer


def notepad():
    """An apron pocket with an order pad and a pencil."""
    def layer(img, view, y0, y1, cy):
        if view == "front":
            rect(img, 12, y1 - 3, 15, y1 - 1, shade(WHITE, 0.82))   # pocket
            rect(img, 13, y1 - 5, 14, y1 - 3, WHITE)                 # pad
            px(img, 15, y1 - 5, (230, 190, 60, 255)); px(img, 15, y1 - 4, (230, 190, 60, 255))   # pencil
    return layer


def watch_chain():
    def layer(img, view, y0, y1, cy):
        if view == "front":
            for x, y in ((11, y0 + 4), (12, y0 + 5), (13, y0 + 5)):
                px(img, x, y, GOLD_PX)
    return layer


def lace_hem():
    """White lace dots along the bottom of the apron."""
    def layer(img, view, y0, y1, cy):
        if view == "front":
            for x in range(11, 21, 2):
                px(img, x, y1 + 2, WHITE)
    return layer


def suspenders(color):
    def layer(img, view, y0, y1, cy):
        if view == "front":
            rect(img, 12, y0, 12, y1, color)
            rect(img, 19, y0, 19, y1, color)
            px(img, 12, y0 + 3, GOLD_PX); px(img, 19, y0 + 3, GOLD_PX)
        elif view == "side":
            rect(img, 16, y0, 16, y1, color)
    return layer


def work_belt():
    """A leather belt with a buckle and a little knife."""
    def layer(img, view, y0, y1, cy):
        if view == "front":
            rect(img, 10, y1 - 4, 21, y1 - 4, (90, 60, 35, 255))
            px(img, 15, y1 - 4, GOLD_PX); px(img, 16, y1 - 4, GOLD_PX)
            rect(img, 20, y1 - 3, 20, y1 - 1, (190, 195, 205, 255))   # knife
        elif view == "side":
            rect(img, 12, y1 - 4, 19, y1 - 4, (90, 60, 35, 255))
    return layer


def beard_beads():
    def layer(img, view, y0, y1, cy):
        if view == "front":
            px(img, 14, cy + 9, GOLD_PX); px(img, 17, cy + 9, GOLD_PX)
        elif view == "side":
            px(img, 18, cy + 8, GOLD_PX)
    return layer


def toque_pleats():
    def layer(img, view, y0, y1, cy):
        if view != "back":
            for x in (13, 16, 19):
                px(img, x, cy - 9, (215, 215, 210, 255)); px(img, x, cy - 10, (215, 215, 210, 255))
    return layer


def checked_trousers():
    def layer(img, view, y0, y1, cy):
        for y in range(25, 28):
            for x in range(12, 20):
                if (x + y) % 2 == 0 and img.getpixel((x, y + OFFSET_Y))[:3] == (80, 80, 90):
                    px(img, x, y, (110, 110, 120, 255))
    return layer


def rolled_sleeves():
    """Bare forearms below rolled-up sleeves."""
    def layer(img, view, y0, y1, cy):
        if view == "front":
            rect(img, 8, y0 + 4, 9, y0 + 6, SKIN)
            rect(img, 22, y0 + 4, 23, y0 + 6, SKIN)
            rect(img, 8, y0 + 3, 9, y0 + 3, WHITE); rect(img, 22, y0 + 3, 23, y0 + 3, WHITE)
    return layer


# The extra details for each staff type, for the "more detail" option.
DETAILS = {
    "A. Classic Chef": [toque_pleats(), checked_trousers(), towel((200, 50, 45, 255))],
    "B. Tavern Cook": [rolled_sleeves(), work_belt(), towel((60, 110, 170, 255))],
    "C. Dwarf Cook": [beard_beads(), rolled_sleeves()],
    "A. Barkeep": [watch_chain(), towel((60, 110, 70, 255))],
    "B. Serving Maid": [notepad(), lace_hem()],
    "C. Halfling Server": [suspenders((110, 70, 40, 255)), notepad()],
}
HAIR_KEYS = {
    "A. Classic Chef": (110, 70, 40, 255), "B. Tavern Cook": (120, 80, 50, 255), "C. Dwarf Cook": (200, 110, 50, 255),
    "A. Barkeep": (160, 100, 50, 255), "B. Serving Maid": (180, 120, 60, 255), "C. Halfling Server": (95, 60, 35, 255),
}


def marks(color, front=(), side=()):
    """A few single pixels of detail: (x, y) with y counted from the top
    of the body ("b", y) or from the middle of the head ("h", y)."""
    def layer(img, view, y0, y1, cy):
        for x, ref, y in (front if view == "front" else side if view == "side" else ()):
            px(img, x, (y0 if ref == "b" else cy) + y, color)
    return layer


# Guests get the same shading, plus a touch of detail each.
GUEST_DETAILS = {
    "farmer": [marks((90, 125, 185, 255), front=[(17, "b", 5), (18, "b", 5), (17, "b", 6), (18, "b", 6)]),   # a patch
               marks((230, 200, 90, 255), front=[(20, "h", -6), (21, "h", -7)])],                              # wheat in the hat
    "guard": [marks(GOLD_PX, front=[(15, "b", 3), (16, "b", 3), (15, "b", 4), (16, "b", 4), (14, "b", 4), (17, "b", 4)])],
    "merchant": [marks(GOLD_PX, front=[(15, "b", 2), (16, "b", 3), (15, "b", 4)], side=[(18, "b", 2)])],      # a gold pendant
    "regular": [marks((110, 70, 40, 255), front=[(18, "h", 4), (19, "h", 4), (20, "h", 3)], side=[(21, "h", 3), (22, "h", 2)])],   # a pipe
    "knight": [marks(GOLD_PX, front=[(15, "b", 2), (16, "b", 2), (15, "b", 3), (16, "b", 3)])],
    "mage": [marks((250, 240, 160, 255), front=[(12, "b", 4), (19, "b", 7), (14, "b", 9), (18, "b", 3)])],     # stars on the robe
    "rogue": [marks((70, 50, 35, 255), front=[(12, "b", 1), (13, "b", 2), (14, "b", 3), (15, "b", 4), (16, "b", 5), (17, "b", 6)])],   # a strap
    "lord": [marks(GOLD_PX, front=[(12, "b", 2), (13, "b", 3), (14, "b", 4), (15, "b", 4), (16, "b", 4), (17, "b", 4), (18, "b", 3), (19, "b", 2)])],   # chain of office
    "lady": [marks((245, 245, 250, 255), front=[(13, "b", 1), (14, "b", 2), (16, "b", 2), (17, "b", 2), (18, "b", 1)])],   # pearls
}


def hair_colour(ch):
    """The colour of a guest's hair layer (what the game recolours)."""
    for layer in ch.get("head_layers", []):
        cells = getattr(layer, "__closure__", None) or ()
        for cell in cells:
            v = cell.cell_contents
            if isinstance(v, tuple) and len(v) == 4 and layer.__qualname__.startswith("hair"):
                return v
    return None


def detailed_staff(name, ch):
    return dict(ch, shade=True, hair_key=HAIR_KEYS[name], extras=DETAILS[name])


def detailed_guest(name, ch):
    return dict(ch, shade=True, hair_key=hair_colour(ch), extras=GUEST_DETAILS.get(name, []))


def quarter_options(path):
    """Each character as now (front, side, back) beside the new
    three-quarter views (quarter, quarter mirrored, quarter from behind),
    zoomed in, and walking across a floor at game size."""
    from PIL import ImageFont
    font = ImageFont.load_default(size=15)
    cast = [(n.split(". ")[1], detailed_staff(n, c)) for n, c in list(COOKS.items())[:2] + list(WAITERS.items())[:2]]
    cast += [(n.title(), detailed_guest(n, c)) for n, c in GUESTS.items() if n in ("farmer", "guard", "knight", "lady")]
    Z, gap = 3, 4
    cw = (W * Z + gap) * 3
    sheet_img = Image.new("RGBA", (140 + cw * 2 + 40, 34 + len(cast) * (H * Z + 10)), (60, 54, 48, 255))
    d = ImageDraw.Draw(sheet_img)
    d.text((150, 8), "As now: front, side, back", fill=(250, 230, 180), font=font)
    d.text((150 + cw + 30, 8), "Three-quarter: toward you (both ways), walking away", fill=(250, 230, 180), font=font)
    for r, (name, ch) in enumerate(cast):
        y0 = 34 + r * (H * Z + 10)
        d.text((8, y0 + H * Z // 2 - 8), name, fill=(240, 240, 235), font=font)
        now = [draw(ch, "front", 0), draw(ch, "side", 1), draw(ch, "back", 0)]
        q = draw(ch, "quarter", 1)
        new = [q, q.transpose(Image.FLIP_LEFT_RIGHT), draw(ch, "quarter_back", 1)]
        for i, pic in enumerate(now):
            sheet_img.alpha_composite(pic.resize((W * Z, H * Z), Image.NEAREST), (150 + i * (W * Z + gap), y0))
        for i, pic in enumerate(new):
            sheet_img.alpha_composite(pic.resize((W * Z, H * Z), Image.NEAREST), (150 + cw + 30 + i * (W * Z + gap), y0))
    sheet_img.save(path)


def detail_options(path):
    """Each staff member three ways: as now, shaded, shaded with details;
    front, side and carrying, zoomed in."""
    from PIL import ImageFont
    font = ImageFont.load_default(size=14)
    staff = list(COOKS.items()) + list(WAITERS.items())
    Z, gap = 4, 6
    cell = (W * Z + gap) * 3 + 16
    sheet_img = Image.new("RGBA", (130 + cell * 3, 30 + len(staff) * (H * Z + 12)), (60, 54, 48, 255))
    d = ImageDraw.Draw(sheet_img)
    for col, label in enumerate(["A  As now", "B  Shaded", "C  Shaded + details"]):
        d.text((130 + col * cell + 10, 8), label, fill=(250, 230, 180), font=font)
    for r, (name, ch) in enumerate(staff):
        y0 = 30 + r * (H * Z + 12)
        d.text((8, y0 + H * Z // 2 - 8), name.split(". ")[1], fill=(240, 240, 235), font=font)
        versions = [dict(ch), dict(ch, shade=True, hair_key=HAIR_KEYS[name]),
                    dict(ch, shade=True, hair_key=HAIR_KEYS[name], extras=DETAILS[name])]
        for col, c in enumerate(versions):
            pics = [draw(c, "front", 0), draw(c, "side", 1)]
            if name in WAITERS:
                pics.append(draw(dict(c, props=[tray(mug=False, plate=True)]), "front", 0))
            else:
                pics.append(draw(c, "front", 1))
            for i, pic in enumerate(pics):
                big = pic.resize((W * Z, H * Z), Image.NEAREST)
                sheet_img.alpha_composite(big, (130 + col * cell + i * (W * Z + gap), y0))
    sheet_img.save(path)


def frames(ch):
    """[front idle, front step 1, front step 2, side, side step, back]"""
    return [draw(ch, "front", 0), draw(ch, "front", 1), draw(ch, "front", 2),
            draw(ch, "side", 0), draw(ch, "side", 1), draw(ch, "back", 0)]


def carrying(ch):
    """Waiter carrying a dish to a table (the tray swaps the mug for a plate)."""
    c = dict(ch)
    c["props"] = [tray(mug=False, plate=True)]
    return draw(c, "front", 0)


# ---------------------------------------------------------------------
# Guest layers
# ---------------------------------------------------------------------
STEEL = (175, 180, 190, 255)
STEEL_DARK = (120, 125, 135, 255)
WOOD = (150, 100, 55, 255)
GOLD = (225, 185, 60, 255)


def straw_hat():
    straw = (230, 200, 110, 255)
    band = (150, 90, 50, 255)

    def layer(img, view, cy):
        rect(img, 7, cy - 4, 24, cy - 3, straw)               # wide brim
        rect(img, 11, cy - 8, 20, cy - 4, straw)
        ellipse(img, 16, cy - 8, 5, 2, straw)
        rect(img, 11, cy - 5, 20, cy - 5, band)
    return layer


def overalls(color):
    def layer(img, view, y0, y1):
        if view == "side":
            rect(img, 13, y0 + 4, 19, y1, color)
            rect(img, 16, y0, 17, y0 + 4, color)
            return
        rect(img, 11, y0 + 4, 20, y1, color)                  # bib and trousers
        rect(img, 12, y0, 13, y0 + 4, color)                  # straps
        rect(img, 18, y0, 19, y0 + 4, color)
        if view == "front":
            px(img, 12, y0 + 4, GOLD); px(img, 19, y0 + 4, GOLD)   # buttons
    return layer


def helmet():
    def layer(img, view, cy):
        ellipse(img, 16, cy - 2, 7.2, 6.2, STEEL, top_only=True)
        rect(img, 9, cy - 2, 22, cy - 1, STEEL_DARK)          # rim
        if view == "front":
            rect(img, 15, cy - 1, 16, cy + 2, STEEL)          # nose guard
        elif view == "side":
            rect(img, 20, cy - 1, 21, cy + 1, STEEL)
    return layer


def tabard(color):
    def layer(img, view, y0, y1):
        if view == "side":
            rect(img, 17, y0 + 1, 19, y1 + 1, color)
        else:
            rect(img, 13, y0 + 1, 18, y1 + 1, color)
            if view == "front":
                rect(img, 15, y0 + 3, 16, y0 + 5, GOLD)       # crest
    return layer


def spear():
    def layer(img, view, y0, step):
        x = {"front": 24, "side": 20, "back": 8}[view]
        rect(img, x, y0 - 14, x, y0 + 12, WOOD)
        rect(img, x - 1, y0 - 17, x + 1, y0 - 15, STEEL)
        px(img, x, y0 - 18, STEEL)
    return layer


def trim(color):
    def layer(img, view, y0, y1):
        if view == "front":
            rect(img, 15, y0, 16, y1, color)                  # gold edging down the front
            rect(img, 10, y1 - 1, 21, y1, color)
        elif view == "side":
            rect(img, 19, y0, 19, y1, color)
    return layer


def purse():
    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 20 if view == "front" else 18
        rect(img, x, y0 + 6, x + 1, y0 + 8, GOLD)
        px(img, x, y0 + 5, (120, 80, 30, 255))
    return layer


def beret(color, feather=(240, 240, 235, 255)):
    def layer(img, view, cy):
        ellipse(img, 15, cy - 5, 7.5, 3.2, color)
        rect(img, 9, cy - 4, 22, cy - 3, shade(color, 0.85))
        if view != "back":
            rect(img, 20, cy - 10, 21, cy - 6, feather)       # feather
            px(img, 22, cy - 11, feather)
    return layer


def mustache(color):
    def layer(img, view, cy):
        if view == "front":
            rect(img, 13, cy + 3, 18, cy + 3, color)
            px(img, 12, cy + 4, color); px(img, 19, cy + 4, color)
        elif view == "side":
            rect(img, 18, cy + 3, 20, cy + 3, color)
    return layer


def cane():
    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 7 if view == "front" else 21
        rect(img, x, y0 + 2, x, 29, WOOD)
        rect(img, x, y0 + 1, x + 2, y0 + 1, WOOD)             # handle
    return layer


def cape(color):
    def layer(img, view, y0, y1):
        if view == "back":
            rect(img, 10, y0, 21, y1 + 2, color)
        elif view == "front":
            rect(img, 9, y0 + 1, 9, y1 + 1, color)
            rect(img, 22, y0 + 1, 22, y1 + 1, color)
        else:
            rect(img, 11, y0, 12, y1 + 2, color)
    return layer


def belt(color=(70, 45, 30, 255), buckle=GOLD):
    def layer(img, view, y0, y1):
        x0, x1 = (12, 19) if view == "side" else (10, 21)
        rect(img, x0, y0 + 6, x1, y0 + 6, color)
        if view == "front":
            px(img, 15, y0 + 6, buckle); px(img, 16, y0 + 6, buckle)
    return layer


def sword():
    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 21 if view == "front" else 14
        rect(img, x, y0 + 6, x, y0 + 12, STEEL)
        rect(img, x - 1, y0 + 6, x + 1, y0 + 6, WOOD)
    return layer


def wizard_hat(color):
    def layer(img, view, cy):
        for i in range(10):
            half = max(0, int(6.5 - i * 0.7))
            lean = i // 4                                     # the tip flops over
            rect(img, 16 - half + lean, cy - 5 - i, 16 + half + lean, cy - 5 - i, color)
        rect(img, 8, cy - 5, 23, cy - 4, shade(color, 0.85))  # brim
        if view != "back":
            px(img, 15, cy - 8, GOLD); px(img, 18, cy - 11, GOLD)   # stars
    return layer


def magic_staff():
    def layer(img, view, y0, step):
        x = {"front": 24, "side": 20, "back": 8}[view]
        rect(img, x, y0 - 6, x, y0 + 12, WOOD)
        ellipse(img, x, y0 - 8, 2.2, 2.2, (110, 220, 240, 255))
    return layer


def hood(color):
    def layer(img, view, cy):
        if view == "back":
            ellipse(img, 16, cy, 7.5, 7.5, color)
            rect(img, 14, cy + 6, 17, cy + 8, color)
            return
        ellipse(img, 16, cy - 1, 7.6, 6.8, color, top_only=True)
        if view == "front":
            rect(img, 9, cy - 1, 10, cy + 5, color)
            rect(img, 21, cy - 1, 22, cy + 5, color)
        else:
            rect(img, 9, cy - 1, 13, cy + 5, color)
    return layer


def dagger():
    def layer(img, view, y0, step):
        if view == "back":
            return
        x = 19 if view == "front" else 15
        rect(img, x, y0 + 7, x, y0 + 10, STEEL)
        px(img, x, y0 + 6, WOOD)
    return layer


def ermine():
    white = (248, 248, 245, 255)

    def layer(img, view, y0, y1):
        x0, x1 = (12, 19) if view == "side" else (10, 21)
        rect(img, x0, y0, x1, y0 + 1, white)
        rect(img, x0, y1, x1, y1, white)
        for x in range(x0 + 1, x1, 3):
            px(img, x, y0 + 1, (30, 30, 30, 255))
    return layer


def crown():
    def layer(img, view, cy):
        rect(img, 12, cy - 8, 19, cy - 6, GOLD)
        for x in (12, 15, 16, 19):
            px(img, x, cy - 9, GOLD)
        if view != "back":
            px(img, 15, cy - 7, (200, 40, 50, 255)); px(img, 16, cy - 7, (200, 40, 50, 255))
    return layer


def tiara():
    def layer(img, view, cy):
        rect(img, 12, cy - 6, 19, cy - 6, GOLD)
        px(img, 15, cy - 7, GOLD); px(img, 16, cy - 7, GOLD)
        if view != "back":
            px(img, 15, cy - 8, (80, 170, 230, 255)); px(img, 16, cy - 8, (80, 170, 230, 255))
    return layer


# ---------------------------------------------------------------------
# The guests. Each entry is one look; adventurers and nobles have several.
# ---------------------------------------------------------------------
GUESTS = {
    "farmer": dict(
        body=(225, 210, 170, 255), sleeve=(225, 210, 170, 255),
        legs=(70, 100, 160, 255), shoes=(110, 75, 45, 255),
        layers=[overalls((70, 100, 160, 255))],
        head_layers=[hair((130, 85, 50, 255)), straw_hat()],
    ),
    "guard": dict(
        body=(140, 145, 155, 255), sleeve=(140, 145, 155, 255),
        legs=(80, 70, 60, 255), shoes=(55, 40, 30, 255),
        layers=[tabard((175, 45, 45, 255))],
        head_layers=[hair((90, 60, 40, 255)), helmet()],
        props=[spear()],
    ),
    "merchant": dict(
        body=(40, 115, 115, 255), sleeve=(40, 115, 115, 255),
        legs=(70, 55, 70, 255), shoes=(50, 35, 30, 255),
        layers=[trim(GOLD)],
        head_layers=[hair((60, 40, 30, 255)), beret((130, 50, 140, 255))],
        props=[purse()],
    ),
    "regular": dict(
        body=(125, 95, 65, 255), sleeve=(125, 95, 65, 255),
        legs=(85, 80, 75, 255), shoes=(60, 45, 35, 255),
        layers=[buttons((90, 65, 40, 255))],
        head_layers=[hair((205, 205, 210, 255)), mustache((205, 205, 210, 255))],
        props=[cane()],
    ),
    "knight": dict(
        body=(190, 195, 205, 255), sleeve=(190, 195, 205, 255),
        legs=(110, 115, 125, 255), shoes=(70, 70, 80, 255),
        layers=[cape((50, 75, 165, 255)), belt()],
        head_layers=[hair((150, 95, 50, 255))],
        props=[sword()],
    ),
    "mage": dict(
        dress=True,
        body=(60, 75, 175, 255), sleeve=(60, 75, 175, 255),
        legs=(60, 75, 175, 255), shoes=(50, 40, 60, 255),
        layers=[belt((200, 170, 60, 255), (240, 240, 240, 255))],
        head_layers=[hair((175, 110, 60, 255), style="long"), wizard_hat((60, 75, 175, 255))],
        props=[magic_staff()],
    ),
    "rogue": dict(
        body=(105, 75, 50, 255), sleeve=(45, 75, 55, 255),
        legs=(55, 50, 45, 255), shoes=(40, 32, 28, 255),
        layers=[belt()],
        head_layers=[hair((70, 50, 35, 255)), hood((45, 75, 55, 255))],
        props=[dagger()],
    ),
    "lord": dict(
        body=(160, 30, 45, 255), sleeve=(160, 30, 45, 255),
        legs=(90, 25, 35, 255), shoes=(30, 25, 25, 255),
        layers=[ermine()],
        head_layers=[hair((95, 65, 40, 255)), crown()],
    ),
    "lady": dict(
        dress=True,
        body=(115, 50, 145, 255), sleeve=(115, 50, 145, 255),
        legs=(115, 50, 145, 255), shoes=(60, 40, 60, 255),
        layers=[ermine()],
        head_layers=[hair((190, 140, 70, 255), style="long"), tiara()],
    ),
}


# Type IDs used by the game, in the same order as the options above.
TYPE_IDS = {
    "A. Classic Chef": "chef", "B. Tavern Cook": "tavern_cook", "C. Dwarf Cook": "dwarf_cook",
    "A. Barkeep": "barkeep", "B. Serving Maid": "maid", "C. Halfling Server": "halfling",
}


def export_sheets(out_dir):
    views = [("front", s) for s in range(3)] + [("side", s) for s in range(3)] + [("back", s) for s in range(3)]
    for name, ch in list(COOKS.items()) + list(WAITERS.items()):
        is_waiter = name in WAITERS
        ch = detailed_staff(name, ch)
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


def export_guest_sheets(out_dir):
    """Same layout as the staff sheets; guests don't carry, so row 1 repeats row 0."""
    views = [("front", s) for s in range(3)] + [("side", s) for s in range(3)] + [("back", s) for s in range(3)]
    for name, ch in GUESTS.items():
        ch = detailed_guest(name, ch)
        out = Image.new("RGBA", (W * len(views), H * 2), (0, 0, 0, 0))
        for row in range(2):
            for col, (view, step) in enumerate(views):
                out.alpha_composite(draw(ch, view, step), (col * W, row * H))
        path = f"{out_dir}/{name}.png"
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
            is_waiter = name in WAITERS
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
    os.makedirs(os.path.join(root, "assets", "sprites", "guests"), exist_ok=True)
    export_guest_sheets(os.path.join(root, "assets", "sprites", "guests"))
    sheet([("Cooks", {k: detailed_staff(k, v) for k, v in COOKS.items()}),
           ("Waiters", {k: detailed_staff(k, v) for k, v in WAITERS.items()})], os.path.join(here, "staff_options.png"))
    detail_options(os.path.join(here, "staff_detail_options.png"))
    quarter_options(os.path.join(here, "quarter_options.png"))
    sheet([("Guests", {k.title(): detailed_guest(k, v) for k, v in GUESTS.items()})], os.path.join(here, "guest_options.png"))
    print("wrote previews")
