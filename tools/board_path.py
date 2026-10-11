"""Places the 28 board spaces along a painted board's road.

The road's centre line is traced by hand (control points in a 900 x 1200 frame of the board
image), smoothed with a Catmull-Rom spline and divided into 28 equal steps. Writes
art/boards/<id>/path.json (positions normalised 0..1, plus a per-space scale for depth) and a
check image with the spaces drawn over the painting.

  python tools/board_path.py hill
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAME = (900, 1200)
SPACES = 28

# Road centre lines, from Payday (start) to the last space before the loop closes.
PATHS = {
    "hill": {
        # Bottom: from the tunnel round the greenhouses, past the docks, up the left side, along
        # the market terrace, round the stadium, past the bank and up to the castle fountain.
        "points": [(673, 783), (700, 810), (720, 850), (707, 897), (653, 930), (580, 933), (500, 917),
                   (433, 901), (367, 895), (280, 899), (220, 913), (160, 917), (127, 883), (117, 837),
                   (133, 783), (180, 737), (233, 713), (300, 710), (400, 717), (533, 710), (660, 692),
                   (690, 655), (693, 613), (680, 567), (640, 540), (580, 537), (500, 540), (433, 520),
                   (367, 500), (300, 480), (276, 460), (265, 413), (260, 363), (278, 322), (300, 300),
                   (380, 295), (450, 292)],
        # Spaces nearer the camera (bottom) draw bigger; the summit is furthest away.
        "near_y": 930, "far_y": 290, "near_scale": 1.0, "far_scale": 0.72,
        # How the loop closes: the summit's hot-air balloon flies back down to Payday.
        "closing": "balloon",
    },
}


def catmull_open(pts, n=24):
    """Open Catmull-Rom spline through the points (end points duplicated)."""
    p = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for s in range(n):
            t = s / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                                    + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3) for k in (0, 1)))
    out.append(pts[-1])
    return out


def resample(line, count):
    """`count` points evenly spaced by arc length, first and last on the line's ends."""
    seg = [math.dist(line[i], line[i + 1]) for i in range(len(line) - 1)]
    total = sum(seg)
    out = []
    for k in range(count):
        target = total * k / (count - 1)
        acc = 0.0
        for i, L in enumerate(seg):
            if acc + L >= target or i == len(seg) - 1:
                t = min(1.0, (target - acc) / max(L, 1e-6))
                a, b = line[i], line[i + 1]
                out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
                break
            acc += L
    return out, total


def build(board_id):
    spec = PATHS[board_id]
    line = catmull_open(spec["points"])
    pts, total = resample(line, SPACES)
    W, H = FRAME
    spaces = []
    for i, (x, y) in enumerate(pts):
        t = (y - spec["far_y"]) / (spec["near_y"] - spec["far_y"])
        scale = spec["far_scale"] + (spec["near_scale"] - spec["far_scale"]) * max(0.0, min(1.0, t))
        spaces.append({"i": i, "x": round(x / W, 5), "y": round(y / H, 5), "scale": round(scale, 3)})
    out_dir = os.path.join(ROOT, "art", "boards", board_id)
    with open(os.path.join(out_dir, "path.json"), "w") as f:
        json.dump({"board": board_id, "frame": FRAME, "closing": spec["closing"], "spaces": spaces,
                   "road": [[round(x / W, 5), round(y / H, 5)] for x, y in line[::3]]}, f, indent=1)
    # Check image.
    im = Image.open(os.path.join(out_dir, "board.jpg")).convert("RGB").resize(FRAME)
    d = ImageDraw.Draw(im)
    d.line(line, fill=(255, 60, 120), width=3)
    font = ImageFont.truetype(os.path.join(ROOT, "art", "fonts", "Fredoka.ttf"), 15)
    for s in spaces:
        x, y, r = s["x"] * W, s["y"] * H, 15 * s["scale"]
        d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=(255, 255, 255), outline=(29, 35, 64), width=2)
        d.text((x, y), str(s["i"]), font=font, fill=(29, 35, 64), anchor="mm")
    im.save(os.path.join(ROOT, "shots", "path_%s.jpg" % board_id), quality=90)
    print("%s: road %.0f px, step %.1f px" % (board_id, total, total / (SPACES - 1)))


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "hill")
