"""Cuts Flow's 2x2 sprite sheets into transparent tile sprites.

Each sheet holds four objects on white, one per quarter. For every quarter: flood-fill the
white background from the edges (so white inside a building stays), soften the edge, keep a
light contact shadow, trim, and centre it on a square canvas.

  python tools/cut_sprites.py art/incoming/sprites   ->  art/themes/<theme>/s_l<level>_v<k>.png
                                                          art/sprites/special_<name>.png
Input files are named <theme>_<level>.zip-extracted folders or <name>.jpg (see LAYOUT below).
"""
import os
import sys
from collections import deque

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 512
SPECIAL_A = ["payday", "metro", "audit", "jackpot"]
SPECIAL_B = ["windfall", "tax_raid", "permit", "for_sale"]


def _lum_sat(p):
    r, g, b = p[:3]
    return (r * 0.299 + g * 0.587 + b * 0.114), max(r, g, b) - min(r, g, b)


def background_alpha(img):
    """Per-pixel alpha from the outside in. The white background becomes transparent; the soft
    grey contact shadow around each object becomes a translucent dark shadow; everything the
    flood can't reach (the object itself) stays opaque."""
    w, h = img.size
    px = img.load()
    alpha = bytearray([255]) * (w * h)
    shadow = bytearray(w * h)
    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        i = y * w + x
        if seen[i]:
            continue
        lum, sat = _lum_sat(px[x, y])
        # Background and shadow: bright-ish and nearly colourless.
        if lum < 150 or sat > 30:
            continue
        seen[i] = 1
        dark = max(0.0, 250.0 - lum)
        a = int(min(160.0, dark * 2.4))
        alpha[i] = a
        shadow[i] = 1
        if x > 0:
            q.append((x - 1, y))
        if x < w - 1:
            q.append((x + 1, y))
        if y > 0:
            q.append((x, y - 1))
        if y < h - 1:
            q.append((x, y + 1))
    return alpha, shadow


def cut(img):
    img = img.convert("RGB")
    w, h = img.size
    alpha, shadow = background_alpha(img)
    rgba = img.convert("RGBA")
    rp = rgba.load()
    for y in range(h):
        row = y * w
        for x in range(w):
            i = row + x
            if shadow[i]:
                rp[x, y] = (52, 38, 82, alpha[i])
    # Soften the cut edge by a pixel so no light fringe remains.
    a = rgba.getchannel("A").filter(ImageFilter.GaussianBlur(0.8))
    rgba.putalpha(a)
    solid = Image.frombytes("L", (w, h), bytes(0 if s else 255 for s in shadow))
    box = rgba.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
    if box is None or solid.getbbox() is None:
        return None
    rgba = rgba.crop(box)
    w, h = rgba.size
    s = (SIZE - 24) / max(w, h)
    rgba = rgba.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(rgba, ((SIZE - rgba.width) // 2, (SIZE - rgba.height) // 2))
    return out


def quarters(path):
    img = Image.open(path)
    w, h = img.size
    return [img.crop((x * w // 2, y * h // 2, (x + 1) * w // 2, (y + 1) * h // 2)) for y in (0, 1) for x in (0, 1)]


def main(src):
    for name in sorted(os.listdir(src)):
        path = os.path.join(src, name)
        if not name.lower().endswith((".jpg", ".png")):
            continue
        key = os.path.splitext(name)[0]
        if key.startswith("specials_"):
            names = SPECIAL_A if key.endswith("_a") else SPECIAL_B
            os.makedirs(os.path.join(ROOT, "art", "sprites"), exist_ok=True)
            for k, q in enumerate(quarters(path)):
                c = cut(q)
                if c is not None:
                    c.save(os.path.join(ROOT, "art", "sprites", "special_%s.png" % names[k]))
            print("specials", key)
            continue
        theme, level = key.rsplit("_", 1)
        dst = os.path.join(ROOT, "art", "themes", theme)
        os.makedirs(dst, exist_ok=True)
        for k, q in enumerate(quarters(path)):
            c = cut(q)
            if c is not None:
                c.save(os.path.join(dst, "s_l%s_v%d.png" % (level, k)))
        print(theme, level)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "art", "incoming", "sprites"))
