"""Assembles an isometric board from its art kit, exactly to the approved layout.

Layout (grid units on the island's square lawn): a square loop of 28 spaces, 4 corners plus 6
per side; one building plot outside each of the 21 property spaces; the park in the middle.
Every piece is placed by maths, so counts and positions are always exact. Writes the board
image and art/boards/<id>/kit_layout.json (screen positions of spaces, plots and corner slots).

  python tools/compose_board.py [--built]
"""
import json
import math
import os
import random
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEME = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--theme=")), "sky")
SKY_KIT = os.path.join(ROOT, "art", "incoming", "kit")
KIT = SKY_KIT if THEME == "sky" else os.path.join(ROOT, "art", "incoming", "kit_" + THEME)
OUT = os.path.join(ROOT, "art", "boards", THEME)
GAME_DIR = os.path.join(ROOT, "art", "boards", THEME + "_game")
# Each city re-colours the measured sky island (so every board shares the exact geometry):
# ground ramp (dark, light), cliff ramp (dark, light), sky tint (colour, strength).
ISLANDS = {
    "forest": ((46, 104, 52), (132, 190, 96), (74, 52, 38), (150, 112, 78), ((120, 170, 140), 0.18)),
    "desert": ((196, 146, 82), (246, 218, 156), (150, 74, 40), (232, 150, 92), ((255, 196, 150), 0.22)),
    "city": ((70, 140, 72), (150, 205, 110), (88, 90, 104), (170, 168, 176), ((170, 190, 230), 0.15)),
    "metro": ((150, 156, 170), (226, 230, 238), (58, 64, 84), (130, 138, 160), ((140, 160, 220), 0.25)),
    "future": ((150, 170, 230), (236, 244, 255), (52, 40, 110), (130, 110, 220), ((90, 70, 170), 0.45)),
}
FONT = os.path.join(ROOT, "art", "fonts", "Fredoka.ttf")
BUILT = "--built" in sys.argv
EXPORT = "--export" in sys.argv  # game assets: static base + live sprites + layout
CENTRE = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--centre=")), "pond")

LAWN_UNITS = 10.9
C = LAWN_UNITS / 2.0
EDGE = 3.6    # corner centres at C +- EDGE
PLOT = 1.34   # plot centre distance outside its space
MARK = 1.12   # corner landmark centre distance (along u and v) outside its corner space
MARK_W = 1.0  # landmark base width in cells: leaves a small lawn gap to the corner space
SPECIAL = {0: "payday", 5: "metro", 7: "audit", 14: "jackpot", 19: "windfall", 21: "tax_raid", 25: "permit"}
PRICES = [0, 60, 60, 70, 100, 0, 100, 0, 110, 140, 140, 150, 180, 180, 0, 190, 220, 220, 230, 0, 260, 0, 260,
          280, 320, 0, 320, 350]
PLAYERS = [(255, 194, 61), (255, 93, 115), (61, 220, 151), (92, 200, 255)]


# ---------------------------------------------------------------- sprite cutting

def cut(img):
    """White background to transparent, grey contact shadow to a soft dark shadow (flood fill
    from the edges, so white inside the object stays)."""
    img = img.convert("RGB")
    w, h = img.size
    a = np.asarray(img).astype(np.int32)
    lum = a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114
    sat = a.max(2) - a.min(2)
    bgish = (lum >= 150) & (sat <= 12)
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if seen[y, x] or not bgish[y, x]:
            continue
        seen[y, x] = True
        if x > 0:
            q.append((x - 1, y))
        if x < w - 1:
            q.append((x + 1, y))
        if y > 0:
            q.append((x, y - 1))
        if y < h - 1:
            q.append((x, y + 1))
    # Defringe: object pixels touching the background that are pale and colourless are just the
    # white backdrop blended into the object's edge; treat them as background too (2 passes).
    from scipy import ndimage
    for _ in range(3):
        edge = ndimage.binary_dilation(seen) & ~seen
        pale = edge & (lum > 200) & (sat < 26)
        if not pale.any():
            break
        seen = seen | pale
    rgba = np.dstack([a, np.full((h, w), 255)]).astype(np.uint8)
    dark = np.clip((238 - lum) * 2.6, 0, 150).astype(np.uint8)
    rgba[seen, 0:3] = (52, 38, 82)
    rgba[seen, 3] = dark[seen]
    out = Image.fromarray(rgba, "RGBA")
    al = out.getchannel("A").filter(ImageFilter.GaussianBlur(0.7))
    out.putalpha(al)
    from scipy import ndimage
    solid = (~seen)
    lab, n = ndimage.label(ndimage.binary_closing(solid, iterations=2))
    if n > 1:
        sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
        keep = lab == (int(np.argmax(sizes)) + 1)
        # Keep the main object plus its own shadow (shadow pixels near it), drop other fragments.
        near = ndimage.binary_dilation(keep, iterations=40)
        arr = np.asarray(out).copy()
        arr[~near, 3] = 0
        arr[solid & ~keep, 3] = 0
        out = Image.fromarray(arr, "RGBA")
    return out.crop(out.getchannel("A").point(lambda v: 255 if v > 18 else 0).getbbox()), None


def quarters(path):
    im = Image.open(path)
    w, h = im.size
    m = int(w * 0.03)  # inset so no neighbour's edge comes along
    return [im.crop((x * w // 2 + m, y * h // 2 + m, (x + 1) * w // 2 - m, (y + 1) * h // 2 - m))
            for y in (0, 1) for x in (0, 1)]


def dehalo(sprite):
    """Removes pale, colourless pixels connected to the transparent outside (a white floor plate
    or backdrop haze around a sprite's base), flooding in from the edge."""
    from scipy import ndimage
    a = np.asarray(sprite).copy()
    rgb = a[..., :3].astype(np.int32)
    lum = rgb.mean(2)
    sat = rgb.max(2) - rgb.min(2)
    pale = (lum > 196) & (sat < 46)
    clear = a[..., 3] < 40
    # The flood also crosses the contact shadow (cut() paints it one flat colour), so a pale
    # backdrop rim beyond the shadow goes too.
    shadow = (rgb[..., 0] == 52) & (rgb[..., 1] == 38) & (rgb[..., 2] == 82)
    reach = clear.copy()
    for _ in range(80):
        grown = ndimage.binary_dilation(reach) & (pale | clear | shadow)
        if (grown == reach).all():
            break
        reach = grown
    a[reach & pale, 3] = 0
    return Image.fromarray(a, "RGBA")


def solid_cut(img):
    """Cut and also return the solid object's bounds inside the cropped sprite."""
    sprite, solid_box = cut(img)
    full = img.convert("RGB")
    s2, _ = cut(full)
    return sprite


# ---------------------------------------------------------------- iso frame

class Frame:
    """Maps lawn grid units (u toward the right corner, v toward the left corner) to pixels."""

    def __init__(self, top, right, left):
        self.top = np.array(top, float)
        self.eu = (np.array(right, float) - self.top) / LAWN_UNITS
        self.ev = (np.array(left, float) - self.top) / LAWN_UNITS

    def p(self, u, v):
        return tuple(self.top + self.eu * u + self.ev * v)

    def cell_w(self):
        return float(self.eu[0] - self.ev[0])  # screen width of a 1 x 1 diamond


def loop():
    """Grid positions (u, v), the outward direction of each of the 28 spaces, front corner first."""
    hi, lo = C + EDGE, C - EDGE
    pts = []
    for i in range(28):
        k = i % 7
        t = (k - 3.5)  # -2.5 .. 2.5 for k = 1..6
        if i == 0:
            pts.append(((hi, hi), (1, 1)))
        elif i == 7:
            pts.append(((lo, hi), (-1, 1)))
        elif i == 14:
            pts.append(((lo, lo), (-1, -1)))
        elif i == 21:
            pts.append(((hi, lo), (1, -1)))
        elif i < 7:     # front-left edge, v = hi, u decreasing
            pts.append(((C - t, hi), (0, 1)))
        elif i < 14:    # back-left edge, u = lo, v decreasing
            pts.append(((lo, C - t), (-1, 0)))
        elif i < 21:    # back-right edge, v = lo, u increasing
            pts.append(((C + t, lo), (0, -1)))
        else:           # front-right edge, u = hi, v increasing
            pts.append(((hi, C + t), (1, 0)))
    return pts


def face_centre(sprite):
    """Where an isometric slab's top face centre is: the middle of its widest solid row (the
    face's left-right diagonal). Returns (x, y) in sprite pixels and the solid width there."""
    al = np.asarray(sprite.getchannel("A")) > 200
    widths = al.sum(1)
    # Ignore the lowest rows (contact shadow and slab sides spread there too).
    y = int(np.argmax(widths[: int(len(widths) * 0.8)]))
    xs = np.nonzero(al[y])[0]
    return ((xs.min() + xs.max()) / 2.0, float(y)), float(xs.max() - xs.min())


def place(canvas, sprite, anchor, width, face=None):
    """Pastes an isometric slab so its top face centre lands on anchor and the face spans `width`."""
    (fx, fy), fw = face_centre(sprite)
    s = width / max(fw, 1.0)
    sp = sprite.resize((max(1, int(sprite.width * s)), max(1, int(sprite.height * s))), Image.LANCZOS)
    canvas.alpha_composite(sp, (int(anchor[0] - fx * s), int(anchor[1] - fy * s)))


def prep(sprite, width, standing):
    """The resized sprite and its paste offset from the anchor (same maths as place/place_on)."""
    (fx, fy), fw = footprint(sprite) if standing else face_centre(sprite)
    s = width / max(fw, 1.0)
    sp = sprite.resize((max(1, int(sprite.width * s)), max(1, int(sprite.height * s))), Image.LANCZOS)
    return sp, -int(round(fx * s)), -int(round(fy * s))


def footprint(sprite):
    """Centre and width of a standing object's base: the widest solid row in its lower 45%."""
    al = np.asarray(sprite.getchannel("A")) > 200
    h = al.shape[0]
    lo = int(h * 0.55)
    widths = al[lo:].sum(1)
    y = lo + int(np.argmax(widths))
    xs = np.nonzero(al[y])[0]
    return ((xs.min() + xs.max()) / 2.0, float(y)), float(xs.max() - xs.min())


def place_on(canvas, sprite, anchor, base_width):
    """Stands an object so its base's centre sits on anchor, the base spanning base_width."""
    (fx, fy), fw = footprint(sprite)
    s = base_width / max(fw, 1.0)
    sp = sprite.resize((max(1, int(sprite.width * s)), max(1, int(sprite.height * s))), Image.LANCZOS)
    # The widest row is the base's horizontal diagonal, i.e. its centre line.
    canvas.alpha_composite(sp, (int(anchor[0] - fx * s), int(anchor[1] - fy * s)))


def place_base(canvas, sprite, anchor, width):
    """Pastes a standing object so the bottom-centre of its footprint diamond sits on anchor."""
    s = width / sprite.width
    sp = sprite.resize((max(1, int(sprite.width * s)), max(1, int(sprite.height * s))), Image.LANCZOS)
    x = int(anchor[0] - sp.width / 2)
    y = int(anchor[1] - sp.height + sp.width * 0.25)
    canvas.alpha_composite(sp, (x, y))


def diamond_of(sprite):
    """The top face of an isometric slab sprite: top = topmost solid pixel; left/right = the
    highest solid pixel in the leftmost/rightmost columns (where the face edges meet, above the
    slab's side); bottom = the top mirrored through the left-right line."""
    al = np.asarray(sprite.getchannel("A")) > 200
    ys, xs = np.nonzero(al)
    top_y = int(ys.min())
    top_x = float(np.median(xs[ys <= top_y + 2]))
    xl, xr = int(xs.min()), int(xs.max())
    yl = float(np.nonzero(al[:, xl:xl + 4].any(1))[0].min())
    yr = float(np.nonzero(al[:, xr - 3:xr + 1].any(1))[0].min())
    ym = (yl + yr) / 2.0
    return {"top": (top_x, float(top_y)), "right": (float(xr), yr), "bottom": (top_x, 2 * ym - top_y),
            "left": (float(xl), yl)}


def warp_onto(canvas, sprite, dst_top, dst_right, dst_left):
    """Affine-maps the sprite so its diamond face lands exactly on the destination corners;
    anything rising above the face (fountains, statues) keeps its proportions."""
    d = diamond_of(sprite)
    src = np.array([d["top"], d["right"], d["left"]], float)
    dst = np.array([dst_top, dst_right, dst_left], float)
    # Solve dst = A @ [x, y, 1] for the 2x3 matrix A, then invert for PIL (output -> input).
    M = np.hstack([src, np.ones((3, 1))])
    A = np.linalg.solve(M, dst).T  # 2 x 3
    full = np.vstack([A, [0, 0, 1]])
    inv = np.linalg.inv(full)
    out = sprite.transform(canvas.size, Image.AFFINE, tuple(inv[:2].flatten()), resample=Image.BICUBIC)
    dst_bottom = (dst_right[0] + dst_left[0] - dst_top[0], dst_right[1] + dst_left[1] - dst_top[1])
    cxm = (dst_left[0] + dst_right[0]) / 2.0
    cym = (dst_top[1] + dst_bottom[1]) / 2.0
    shrink = lambda p: (cxm + (p[0] - cxm) * 0.99, cym + (p[1] - cym) * 0.98)
    dst_left, dst_right, dst_bottom = shrink(dst_left), shrink(dst_right), shrink(dst_bottom)
    mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(mask).polygon([dst_left, dst_bottom, dst_right, (dst_right[0], 0), (dst_left[0], 0)], fill=255)
    al = out.getchannel("A")
    out.putalpha(Image.fromarray(np.minimum(np.asarray(al), np.asarray(mask))))
    canvas.alpha_composite(out)


def solid_share(sprite):
    """Fraction of a sprite's bounding box that is solid (a cut that ate the object is low)."""
    al = np.asarray(sprite.getchannel("A")) > 200
    return float(al.mean())


def tint_sprite(sprite, color):
    """Multiplies a sprite's colours toward a tint, keeping its shading."""
    a = np.asarray(sprite).astype(np.float32)
    lum = (a[..., :3].mean(2) / 255.0)[..., None]
    a[..., :3] = np.clip(np.array(color, np.float32) * (0.45 + 0.6 * lum), 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def tint_plot(sprite, color):
    """Paints a plot's bare soil in its owner's colour (fence and shading kept)."""
    a = np.asarray(sprite).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    soil = (r > g + 12) & (g > b + 4) & (a[..., 3] > 200) & (r < 225)
    lum = (a[..., :3].mean(2) / 255.0)[..., None]
    col = np.array(color, np.float32)
    a[soil, :3] = col * (0.62 + 0.55 * lum[soil])
    a[..., :3] = np.clip(a[..., :3], 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def tint_roof(sprite, color):
    """Recolours the white roof of a kit building to a player's colour."""
    a = np.asarray(sprite).astype(np.float32)
    lum = a[..., :3].mean(2)
    sat = a[..., :3].max(2) - a[..., :3].min(2)
    h = a.shape[0]
    upper = np.zeros(lum.shape, bool)
    upper[: int(h * 0.62)] = True
    roof = (lum > 185) & (sat < 30) & (a[..., 3] > 200) & upper
    col = np.array(color, np.float32)
    shade = (lum / 255.0)[..., None]
    a[roof, :3] = (col * (0.55 + 0.45 * shade[roof]))
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def chip(draw, at, text, fill, ink, size):
    font = ImageFont.truetype(FONT, size)
    font.set_variation_by_axes([700, 100])
    tw = draw.textlength(text, font=font)
    h = size * 1.45
    w = tw + size * 1.1
    x0, y0 = at[0] - w / 2, at[1] - h / 2
    draw.rounded_rectangle((x0, y0 + 3, x0 + w, y0 + h + 3), radius=h / 2, fill=(40, 30, 70, 90))
    draw.rounded_rectangle((x0, y0, x0 + w, y0 + h), radius=h / 2, fill=fill, outline=tuple(int(c * 0.78) for c in fill[:3]),
                           width=3)
    draw.text((at[0], at[1] + 1), text, font=font, fill=ink, anchor="mm")


def recolour_island(img, spec):
    """Maps the sky island's green lawn and brown cliff onto a city's ramps, keeping the shading."""
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    from scipy import ndimage
    sat = (a.max(2) - a.min(2)) / 255.0
    # Sky: light, soft pixels connected to the image's top and side edges.
    light = (lum > 0.55) & (sat < 0.42) & ~((g > r + 12) & (g > b + 20))
    lab, _ = ndimage.label(light)
    edge = set(np.unique(np.concatenate([lab[0], lab[:, 0], lab[:, -1], lab[:int(lab.shape[0] * 0.45), 0]]))) - {0}
    sky = np.isin(lab, list(edge))
    lawn = (g > r + 12) & (g > b + 20) & ~sky
    water = (((b > r + 18) & (b >= g)) | ((lum > 0.66) & (sat < 0.22))) & ~sky & ~lawn
    cliff = ~sky & ~lawn & ~water
    out = a.copy()

    def ramp(mask, lo, hi, lo_l, hi_l):
        t = np.clip((lum[mask] - lo_l) / (hi_l - lo_l), 0, 1)[:, None]
        out[mask] = np.array(lo, np.float32) * (1 - t) + np.array(hi, np.float32) * t

    ramp(lawn, spec[0], spec[1], 0.25, 0.75)
    ramp(cliff, spec[2], spec[3], 0.15, 0.7)
    tint, k = spec[4]
    out[sky] = out[sky] * (1 - k) + np.array(tint, np.float32) * k
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).convert("RGBA")


def build():
    island = Image.open(os.path.join(SKY_KIT, "island_iso.jpg")).convert("RGBA")
    if THEME in ISLANDS:
        island = recolour_island(island, ISLANDS[THEME])
    W, H = island.size
    fr = Frame((903, 519), (1666, 968), (143, 994))
    cw = fr.cell_w()
    tiles = [cut(q)[0] for q in quarters(os.path.join(KIT, "sheet_a.jpg"))]
    cream, gold, plot_sp, road_sp = tiles
    # White-on-white tiles can be cut away entirely; fall back to the sky kit's stone tile,
    # tinted towards this city's own tile colour.
    if solid_share(cream) < 0.3:
        sky_cream = cut(quarters(os.path.join(SKY_KIT, "sheet_a.jpg"))[0])[0]
        cream = tint_sprite(sky_cream, (232, 234, 240))
    # One building set per player colour (gold, coral, mint, sky), four levels each.
    sets = [[cut(q)[0] for q in quarters(os.path.join(KIT, "bld_%s.jpg" % c))] for c in ("gold", "coral", "mint", "blue")]
    marks = [dehalo(cut(q)[0]) for q in quarters(os.path.join(KIT, "landmarks.jpg"))]
    canvas = island.copy()
    LAWN = tuple(int(c) for c in np.asarray(island)[700, 903][:3]) + (255,)
    draw = ImageDraw.Draw(canvas, "RGBA")
    pts = loop()
    hi, lo, rw = C + EDGE, C - EDGE, 0.62

    def poly(cs, fill):
        draw.polygon([fr.p(u, v) for u, v in cs], fill=fill)

    # Road: a square ring band under the spaces, with a soft edge.
    rw = 0.52
    outer, inner = EDGE + rw, EDGE - rw
    ring_out = [(C - outer, C - outer), (C + outer, C - outer), (C + outer, C + outer), (C - outer, C + outer)]
    ring_in = [(C - inner, C - inner), (C + inner, C - inner), (C + inner, C + inner), (C - inner, C + inner)]
    o2 = EDGE + rw - 0.08
    i2 = inner - 0.1
    # Park in the middle.
    centre_sp = cut(Image.open(os.path.join(KIT, "centres", CENTRE + ".jpg")))[0]
    ci = inner - 0.2
    layout = {"image": [W, H], "spaces": [], "plots": {}, "corners": {}}
    order = sorted(range(28), key=lambda i: pts[i][0][0] + pts[i][0][1])
    rng = random.Random(7)
    owners = {}
    if BUILT:
        for i in range(28):
            if i not in SPECIAL and rng.random() < 0.55:
                owners[i] = (rng.randrange(4), rng.choice([1, 1, 2, 2, 3, 4]))
    # Draw back to front: plots and spaces interleaved by depth.
    items = []
    for i in range(28):
        (u, v), (ou, ov) = pts[i]
        items.append((u + v - 0.001, "road", i))
        items.append((u + v, "space", i))
        if i not in SPECIAL:
            items.append((u + ou * PLOT + v + ov * PLOT, "plot", i))
        if i % 7 == 0:  # the corner's landmark stands out on the lawn, past its space
            items.append((u + ou * MARK + v + ov * MARK, "mark", i))
    da = [dehalo(cut(q)[0]) for q in quarters(os.path.join(KIT, "decor_a.jpg"))]  # tree, flowers, lamp, bench
    db = [dehalo(cut(q)[0]) for q in quarters(os.path.join(KIT, "decor_b.jpg"))]  # pine, bush, sign, mushrooms
    tree, flowers, lamp, bench = da
    pine, bush, sign, shrooms = db
    decor = []
    for i in (5, 19, 25):  # the plot-less special spaces get a little garden instead
        (u, v), (ou, ov) = pts[i]
        qu, qv = u + ou * PLOT, v + ov * PLOT
        su, sv = (ov, ou) if ou == 0 else (ov, ou)  # along the side
        decor += [(tree, qu - 0.18 * abs(ov) - 0.18 * abs(ou), qv - 0.18 * abs(ou) - 0.18 * abs(ov), 0.55),
                  (flowers, qu + 0.22, qv + 0.22, 0.55)]
    # Corner gardens flank each landmark on both sides (between it and the first plot).
    for i, (a, b) in ((14, (pine, tree)), (7, (tree, bush)), (21, (bush, tree)), (0, (flowers, shrooms))):
        (u, v), (ou, ov) = pts[i]
        mu, mv = u + ou * MARK, v + ov * MARK
        tall = 0.5 if i in (7, 14, 21) else 0.4
        decor += [(a, mu + ou * 0.15, mv - ov * 0.95, tall), (b, mu - ou * 0.95, mv + ov * 0.15, tall)]
    for k, d in enumerate(decor):
        items.append((d[1] + d[2], "decor", k))
    items.append((2 * C - 0.01, "centre", -1))
    for depth, kind, i in sorted(items):
        if kind == "road":
            (u, v), _ = pts[i]
            place(canvas, road_sp, fr.p(u, v), cw * (1.6 if i % 7 == 0 else 1.1))
            continue
        if kind == "decor":
            spec = decor[i]
            place_on(canvas, spec[0], fr.p(spec[1], spec[2]), cw * spec[3])
            continue
        if kind == "mark":
            (u, v), (ou, ov) = pts[i]
            mark = {0: marks[0], 7: marks[1], 14: marks[2], 21: marks[3]}[i]
            place_on(canvas, mark, fr.p(u + ou * MARK, v + ov * MARK), cw * MARK_W)
            continue
        if kind == "centre":
            warp_onto(canvas, centre_sp, fr.p(C - ci, C - ci), fr.p(C + ci, C - ci), fr.p(C - ci, C + ci))
            continue
        (u, v), (ou, ov) = pts[i]
        if kind == "space":
            if i % 7 == 0:
                # A plain, slightly larger space: the landmark stands apart on the lawn outside it.
                place(canvas, cream, fr.p(u, v), cw * 0.98)
                slots = [fr.p(u + du * 0.24, v + dv * 0.24) for du, dv in ((-1, 0), (1, 0), (0, -1), (0, 1))]
                layout["corners"][str(i)] = [[round(x / W, 5), round(y / H, 5)] for x, y in slots]
            else:
                place(canvas, gold if i in SPECIAL else cream, fr.p(u, v), cw * 0.8)
            x, y = fr.p(u, v)
            layout["spaces"].append({"i": i, "pos": [round(x / W, 5), round(y / H, 5)], "special": SPECIAL.get(i, "")})
        else:
            q = (u + ou * PLOT, v + ov * PLOT)
            psp = tint_plot(plot_sp, PLAYERS[owners[i][0]]) if i in owners else plot_sp
            place(canvas, psp, fr.p(*q), cw * 0.96)
            x, y = fr.p(*q)
            layout["plots"][str(i)] = [round(x / W, 5), round(y / H, 5)]
            if i in owners:
                who, lvl = owners[i]
                b = sets[who][min(lvl, 4) - 1]
                place_on(canvas, b, fr.p(q[0] - 0.04, q[1] - 0.04), cw * 0.78)
    # Price chips on each plot's front edge (rent in the owner's colour once owned).
    tags = {}
    for i in range(28):
        if i in SPECIAL:
            continue
        (u, v), (ou, ov) = pts[i]
        q = (u + ou * PLOT, v + ov * PLOT)
        if ou < 0 or ov < 0:
            ru, rv = q[0] + 0.3, q[1] + 0.3
        else:
            ru, rv = q[0] + ou * 0.46, q[1] + ov * 0.46
        if i in (1, 6, 8, 20, 22, 27):
            nb = pts[i + 1 if i % 7 == 1 else i - 1][0]
            ru, rv = ru + (nb[0] - u) * 0.35, rv + (nb[1] - v) * 0.35
        tags[i] = {"price": fr.p(*q), "rent": fr.p(ru, rv), "bld": fr.p(q[0] - 0.04, q[1] - 0.04), "depth": q[0] + q[1]}
        if EXPORT:
            continue
        if i in owners:
            who, lvl = owners[i]
            # Rent: front sides on the plot's outer edge; back sides on the plot's front corner,
            # so it's never hidden by the building behind it.
            if ou < 0 or ov < 0:
                tu, tv = q[0] + 0.3, q[1] + 0.3
            else:
                tu, tv = q[0] + ou * 0.46, q[1] + ov * 0.46
            # Next to a corner landmark: slide the tag along the side, away from the corner.
            if i in (1, 6, 8, 20, 22, 27):  # neighbours of the side and front corners
                nb = pts[i + 1 if i % 7 == 1 else i - 1][0]
                du, dv = nb[0] - u, nb[1] - v
                tu, tv = tu + du * 0.35, tv + dv * 0.35
            x, y = fr.p(tu, tv)
            chip(draw, (x, y), str(int(PRICES[i] * (0.25 + 0.3 * lvl))), PLAYERS[who] + (255,), (29, 35, 64), 24)
        else:
            x, y = fr.p(*q)
            chip(draw, (x, y), "$%d" % PRICES[i], (255, 250, 240, 235), (74, 60, 50), 22)
    os.makedirs(OUT, exist_ok=True)
    if EXPORT:
        export(canvas, layout, tags, plot_sp, sets, cw, W, H)
        return
    name = "board_built" if BUILT else "board_empty"
    canvas.convert("RGB").save(os.path.join(OUT, name + ".jpg"), quality=92)
    if not BUILT:
        with open(os.path.join(OUT, "kit_layout.json"), "w") as f:
            json.dump(layout, f, indent=1)
    print(name, "spaces", len(layout["spaces"]), "plots", len(layout["plots"]), "corners", len(layout["corners"]))


def export(canvas, layout, tags, plot_sp, sets, cw, W, H):
    """Writes the game's board kit: base.jpg (static art), sprites/*.png and board.json."""
    gdir = GAME_DIR
    sdir = os.path.join(gdir, "sprites")
    os.makedirs(sdir, exist_ok=True)
    canvas.convert("RGB").save(os.path.join(gdir, "base.jpg"), quality=88)
    sprites = {}
    for who in range(4):
        sp, ox, oy = prep(tint_plot(plot_sp, PLAYERS[who]), cw * 0.96, False)
        sp.save(os.path.join(sdir, "plot_%d.png" % who))
        sprites["plot_%d" % who] = [ox, oy]
        for k in range(4):
            sp, ox, oy = prep(sets[who][k], cw * 0.78, True)
            sp.save(os.path.join(sdir, "bld_%d_%d.png" % (who, k)))
            sprites["bld_%d_%d" % (who, k)] = [ox, oy]
    n = lambda pt: [round(pt[0] / W, 5), round(pt[1] / H, 5)]
    layout["spaces"] = sorted(layout["spaces"], key=lambda sp: sp["i"])
    out = {"image": [W, H], "cell": round(cw / W, 5), "spaces": layout["spaces"], "corners": layout["corners"],
           "plots": {str(i): {"price": n(t["price"]), "rent": n(t["rent"]), "bld": n(t["bld"]), "depth": round(t["depth"], 3)}
                     for i, t in tags.items()},
           "sprites": sprites,
           # Part of the image that must stay on screen: the lawn plus the tallest landmark.
           "focus": [round(180 / W, 4), round(340 / H, 4), round(1630 / W, 4), round(1435 / H, 4)]}
    with open(os.path.join(gdir, "board.json"), "w") as f:
        json.dump(out, f, indent=1)
    print("exported", len(out["plots"]), "plots", len(sprites), "sprites")


if __name__ == "__main__":
    build()
