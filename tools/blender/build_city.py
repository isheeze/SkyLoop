"""Builds every district building (style v2): 7 districts x 4 levels x 3 variants, plus the
7 landmarks. Writes art/models/d<d>_l<level>_v<k>.glb and d<d>_l5.glb.

Run:  blender -b --factory-startup -P tools/blender/build_city.py -- <project dir> [district ...]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import cute as C  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ROOT = ARGS[0] if ARGS else os.getcwd()
ONLY = [int(a) for a in ARGS[1:]]
OUT = os.path.join(ROOT, "art", "models")

WHITE = "#fffaf2"
GLASS = "#ffe9a8"
STONE = "#d8cfc2"
PETALS = ["#ff8fab", "#ffd166", "#ffffff"]

STYLES = [
    # 0 Docklands: harbour cottages, slate-blue roofs, brick and sky-blue walls.
    {"walls": ["#f3e7d3", "#cfe4f2", "#e9b9a0"], "roofs": ["#5b8fb0", "#4f7f9e", "#6aa3c0"],
     "accent": "#4fb6c9", "roof1": "gable", "roof2": "gable", "roof3": "gable", "top4": "hip", "arch": False,
     "extras": ["chimney", "crates"]},
    # 1 Old Quarter: pink and peach walls, terracotta roofs, turrets and flower boxes.
    {"walls": ["#f8d3c6", "#fbe2c2", "#f3c9d6"], "roofs": ["#e07a5f", "#d9694f", "#e98b6b"],
     "accent": "#e07a5f", "roof1": "gable", "roof2": "hip", "roof3": "gable", "top4": "cone", "arch": True,
     "extras": ["flowers", "turret"]},
    # 2 Garden Row: mint cottages with green roofs, hedges and blossoms.
    {"walls": ["#d7efdc", "#eef3d4", "#f6ead8"], "roofs": ["#6fb86a", "#5aa45f", "#86c46b"],
     "accent": "#f4a3b4", "roof1": "gable", "roof2": "gable", "roof3": "hip", "top4": "cone", "arch": True,
     "extras": ["flowers", "garden"]},
    # 3 Midtown: coral and apricot shops with striped awnings and a clock.
    {"walls": ["#ffd6b8", "#ffe4c7", "#f9c4b2"], "roofs": ["#f08a6a", "#e8735c", "#f4a261"],
     "accent": "#e8735c", "roof1": "hip", "roof2": "flat", "roof3": "flat", "top4": "clock", "arch": False,
     "extras": ["awning"]},
    # 4 Arena District: lilac walls, violet roofs, neon trims.
    {"walls": ["#e3d6f5", "#f1dcf2", "#d9dcf7"], "roofs": ["#9a7bd6", "#b07cc6", "#8b84d8"],
     "accent": "#c77ad9", "roof1": "gable", "roof2": "hip", "roof3": "flat", "top4": "neon", "arch": False,
     "extras": ["neon"]},
    # 5 Finance Row: cream stone, gold trims, slate-blue roofs, columns.
    {"walls": ["#fbf3e1", "#f4ecd9", "#efe6d6"], "roofs": ["#6c7fa8", "#5d6f96", "#7a8bb2"],
     "accent": "#e8b94a", "roof1": "hip", "roof2": "hip", "roof3": "flat", "top4": "dome", "arch": True,
     "extras": ["columns"]},
    # 6 Skyline Heights: sky-blue glass and white, rounded modern towers, rooftop gardens.
    {"walls": ["#dbe9fb", "#eef4fb", "#cfe0f7"], "roofs": ["#6f8cf0", "#7aa2e0", "#5d7bd8"],
     "accent": "#6f8cf0", "roof1": "flat", "roof2": "flat", "roof3": "flat", "top4": "glass", "arch": False,
     "extras": ["garden_roof"]},
]


def pal(S, v):
    rnd = random.Random(v * 31 + 7)
    return {
        "wall": C.M(S["walls"][v % 3], 0.9),
        "wall2": C.M(S["walls"][(v + 1) % 3], 0.9),
        "roof": C.M(S["roofs"][v % 3], 0.8),
        "trim": C.M(WHITE, 0.7),
        "glass": C.M(GLASS, 0.3, emit=0.6),
        "stone": C.M(STONE, 0.95),
        "accent": C.M(S["accent"], 0.7),
        "wood": C.M("#9b6a45", 0.85),
        "leaf": C.M(rnd.choice(["#7cc66a", "#6dbb65", "#8fd078"]), 0.9),
        "trunk": C.M("#8a5a3c", 0.9),
        "petals": [C.M(p, 0.8) for p in PETALS],
        "gold": C.M("#f2c14e", 0.35, metal=0.6),
        "dark": C.M("#4a4f6a", 0.6),
    }


def base(w, d, P):
    C.rbox((w + 0.04, d + 0.04, 0.045), (0, 0, 0.022), P["stone"], r=0.015)


def roof(kind, w, d, z, P, h=0.17):
    if kind == "gable":
        C.gable(w, d, h, z, P["roof"], fill=P["wall"], along_x=True)
    elif kind == "gable_y":
        C.gable(w, d, h, z, P["roof"], fill=P["wall"], along_x=False)
    elif kind == "hip":
        C.hip(w, d, h, z, P["roof"])
    else:
        C.flat_roof(w, d, z, P["roof"], P["trim"])


def extras(S, w, d, z_top, P, v, level):
    ex = S["extras"]
    if "chimney" in ex:
        C.chimney(w * 0.25 * (1 if v % 2 else -1), d * 0.15, z_top, 0.12, C.M("#c0705a", 0.9), P["dark"])
    if "crates" in ex and level <= 2:
        for i in range(3):
            C.rbox((0.055, 0.055, 0.055), (w / 2 + 0.03, -d / 2 + 0.06 + (i % 2) * 0.06, 0.028 + (i // 2) * 0.057),
                   P["wood"], r=0.008)
    if "garden" in ex:
        C.bush(-w / 2 - 0.02, -d / 2 + 0.02, 1.0, P["leaf"], flowers=P["petals"][0])
        C.bush(w / 2 + 0.02, -d / 2 + 0.03, 0.9, P["leaf"], flowers=P["petals"][1])
    if "flowers" in ex:
        C.bush(-w / 2 - 0.01, -d / 2 + 0.01, 0.8, P["leaf"], flowers=P["petals"][0])


def level1(S, v, P):
    w, d, h = 0.48, 0.4, 0.24
    base(w, d, P)
    C.rbox((w, d, h), (0, 0, 0.045 + h / 2), P["wall"], r=0.03)
    z = 0.045 + h
    roof(S["roof1"], w, d, z, P, 0.18)
    du = -0.11 if v % 2 == 0 else 0.11
    C.door("front", w, d, du, P["trim"], P["accent"], awning=P["roof"])
    C.window("front", w, d, -du, 0.16, P["trim"], P["glass"], arch=S["arch"])
    for f in ("left", "right"):
        C.window(f, w, d, 0.0, 0.16, P["trim"], P["glass"], arch=S["arch"])
    C.window("back", w, d, -0.1, 0.16, P["trim"], P["glass"])
    C.window("back", w, d, 0.1, 0.16, P["trim"], P["glass"])
    if "flowers" in S["extras"]:
        C.flower_box("front", w, d, -du, 0.095, P["accent"], P["petals"])
    extras(S, w, d, z + 0.05, P, v, 1)


def level2(S, v, P):
    w, d, h = 0.58, 0.46, 0.42
    base(w, d, P)
    C.rbox((w, d, h), (0, 0, 0.045 + h / 2), P["wall"], r=0.03)
    C.rbox((w + 0.012, d + 0.012, 0.03), (0, 0, 0.045 + 0.2), P["trim"], r=0.01)
    z = 0.045 + h
    roof(S["roof2"], w, d, z, P, 0.2)
    du = 0.0 if v == 1 else (-0.15 if v == 0 else 0.15)
    C.door("front", w, d, du, P["trim"], P["accent"], awning=P["roof"] if "awning" not in S["extras"] else None)
    if "awning" in S["extras"]:
        C.awning_stripes("front", w, d, 0.0, 0.2, w - 0.08, P["accent"], P["trim"])
    for u in (-0.17, 0.0, 0.17):
        if abs(u - du) > 0.05:
            C.window("front", w, d, u, 0.13, P["trim"], P["glass"], arch=S["arch"])
        C.window("front", w, d, u, 0.34, P["trim"], P["glass"], arch=S["arch"])
    C.window_grid(["left", "right", "back"], w, d, 0.07, 0.45, 3, 2, P["trim"], P["glass"])
    if "flowers" in S["extras"]:
        for u in (-0.17, 0.17):
            C.flower_box("front", w, d, u, 0.27, P["accent"], P["petals"])
    if "neon" in S["extras"]:
        C.rbox((0.2, 0.02, 0.05), (0, -d / 2 - 0.015, 0.29), C.M("#ff7ad9", 0.4, emit=3.0), r=0.012)
    extras(S, w, d, z + 0.05, P, v, 2)


def turret(x, y, r, h, P, roof_m, tip):
    C.cyl(r, r, h, (x, y, h / 2), P["wall2"], verts=24, bevel=0.01)
    for k in range(3):
        a = k * 2.1 + 0.4
        C.window("front", r * 2, r * 2, 0, 0, P["trim"], P["glass"]) if False else None
    C.cone_roof(r, r * 2.4, h, roof_m, cx=x, cy=y, tip=tip)
    C.rbox((0.05, 0.02, 0.07), (x, y - r - 0.005, h * 0.7), P["glass"], r=0.012)


def level3(S, v, P):
    w, d, h = 0.6, 0.5, 0.6
    base(w, d, P)
    C.rbox((w, d, 0.2), (0, 0, 0.045 + 0.1), P["wall2"], r=0.03)
    C.rbox((w - 0.02, d - 0.02, h - 0.2), (0, 0, 0.245 + (h - 0.2) / 2), P["wall"], r=0.03)
    z = 0.045 + h
    roof(S["roof3"], w - 0.02, d - 0.02, z, P, 0.2)
    C.door("front", w, d, 0.0, P["trim"], P["accent"])
    if "awning" in S["extras"] or "neon" in S["extras"]:
        C.awning_stripes("front", w, d, 0.0, 0.19, w - 0.06, P["accent"], P["trim"])
    C.window("front", w, d, -0.18, 0.12, P["trim"], P["glass"], ww=0.1, wh=0.1)
    C.window("front", w, d, 0.18, 0.12, P["trim"], P["glass"], ww=0.1, wh=0.1)
    C.window_grid(["front"], w - 0.02, d - 0.02, 0.27, 0.62, 3, 2, P["trim"], P["glass"], arch=S["arch"])
    C.window_grid(["left", "right", "back"], w - 0.02, d - 0.02, 0.08, 0.62, 3, 3, P["trim"], P["glass"])
    # Balcony on the middle floor.
    C.rbox((0.26, 0.07, 0.02), (0, -d / 2 - 0.035, 0.36), P["trim"], r=0.008)
    C.rbox((0.26, 0.012, 0.05), (0, -d / 2 - 0.068, 0.39), P["accent"], r=0.005)
    if "turret" in S["extras"]:
        turret(w / 2 - 0.02, -d / 2 + 0.05, 0.1, 0.72, P, P["roof"], P["gold"])
    if "columns" in S["extras"]:
        for u in (-0.22, -0.11, 0.11, 0.22):
            C.cyl(0.018, 0.018, 0.2, (u, -d / 2 - 0.03, 0.145), P["trim"], verts=12)
    if "garden_roof" in S["extras"]:
        for i in range(3):
            C.bush(-0.15 + i * 0.15, 0.0, 0.8, P["leaf"], z=z + 0.06)
    extras(S, w, d, z + 0.05, P, v, 3)


def level4(S, v, P):
    w, d = 0.64, 0.54
    base(w, d, P)
    C.rbox((w, d, 0.4), (0, 0, 0.045 + 0.2), P["wall2"], r=0.03)
    C.rbox((w + 0.014, d + 0.014, 0.035), (0, 0, 0.445), P["trim"], r=0.012)
    C.door("front", w, d, 0.0, P["trim"], P["accent"], awning=P["roof"])
    C.window_grid(["front"], w, d, 0.07, 0.4, 4, 2, P["trim"], P["glass"], skip=(("front", 0, 1), ("front", 0, 2)))
    C.window_grid(["left", "right", "back"], w, d, 0.07, 0.4, 3, 2, P["trim"], P["glass"])
    top = S["top4"]
    uw, ud, uh = 0.46, 0.4, 0.5
    if top in ("cone",):
        # Fairy-tale tower: a round keep with a tall pointed roof.
        r = 0.2
        C.cyl(r, r, uh + 0.1, (0, 0.02, 0.46 + (uh + 0.1) / 2), P["wall"], verts=28)
        for k in range(4):
            a = -math.pi / 2 + (k - 1.5) * 0.55
            for zz in (0.62, 0.84):
                C.rbox((0.05, 0.03, 0.075), (math.cos(a) * r, 0.02 + math.sin(a) * r, zz), P["glass"], r=0.012,
                       rot=(0, 0, a + math.pi / 2))
        C.cone_roof(r, 0.42, 0.46 + uh + 0.1, P["roof"], cy=0.02, tip=P["gold"])
        return
    if top == "glass":
        C.cyl(0.22, 0.19, 0.62, (0, 0.02, 0.46 + 0.31), C.M("#a9cdf5", 0.15, metal=0.2), verts=32)
        for i in range(5):
            C.torus(0.205 - i * 0.006, 0.01, (0, 0.02, 0.52 + i * 0.12), P["trim"])
        C.cyl(0.2, 0.2, 0.04, (0, 0.02, 1.1), P["trim"], verts=32)
        for i in range(3):
            C.bush(-0.08 + i * 0.08, 0.02, 0.7, P["leaf"], z=1.12)
        return
    C.rbox((uw, ud, uh), (0, 0.02, 0.46 + uh / 2), P["wall"], r=0.03)
    C.window_grid(["front", "back", "left", "right"], uw, ud, 0.5, 0.94, 3, 3, P["trim"], P["glass"], arch=S["arch"],
                  cy=0.02)
    z = 0.46 + uh
    if top == "hip":
        C.hip(uw, ud, 0.2, z, P["roof"], cy=0.02)
    elif top == "clock":
        C.flat_roof(uw, ud, z, P["roof"], P["trim"], cy=0.02)
        C.rbox((0.18, 0.16, 0.2), (0, 0.02, z + 0.15), P["wall2"], r=0.02)
        C.cyl(0.06, 0.06, 0.02, (0, 0.02 - 0.085, z + 0.16), P["trim"], verts=24, rot=(math.pi / 2, 0, 0))
        C.rbox((0.006, 0.01, 0.045), (0, 0.02 - 0.1, z + 0.175), P["dark"], r=0.002)
        C.rbox((0.035, 0.01, 0.006), (0.015, 0.02 - 0.1, z + 0.16), P["dark"], r=0.002)
        C.hip(0.18, 0.16, 0.1, z + 0.25, P["roof"], cy=0.02)
    elif top == "neon":
        C.flat_roof(uw, ud, z, P["roof"], P["trim"], cy=0.02)
        C.rbox((0.3, 0.03, 0.1), (0, 0.02, z + 0.11), C.M("#ff7ad9", 0.4, emit=3.0), r=0.02)
        C.rbox((0.012, 0.012, 0.08), (-0.1, 0.02, z + 0.04), P["dark"], r=0.003)
        C.rbox((0.012, 0.012, 0.08), (0.1, 0.02, z + 0.04), P["dark"], r=0.003)
    elif top == "dome":
        C.flat_roof(uw, ud, z, P["roof"], P["trim"], cy=0.02)
        C.ball(0.13, (0, 0.02, z + 0.06), P["gold"], scale=(1, 1, 0.85))
        C.cyl(0.006, 0.01, 0.1, (0, 0.02, z + 0.21), P["gold"], verts=8)
    else:
        C.flat_roof(uw, ud, z, P["roof"], P["trim"], cy=0.02)


# ---------------------------------------------------------------- landmarks

def landmark(d, P):
    if d == 0:
        _lighthouse(P)
    elif d == 1:
        _bazaar(P)
    elif d == 2:
        _conservatory(P)
    elif d == 3:
        _transit(P)
    elif d == 4:
        _arena(P)
    elif d == 5:
        _bank(P)
    else:
        _spire(P)


def _lighthouse(P):
    rock = C.M("#a39a8f", 0.95)
    for (x, y, r) in ((0, 0, 0.26), (0.2, -0.12, 0.13), (-0.21, 0.08, 0.14), (0.15, 0.18, 0.11)):
        C.ball(r, (x, y, 0.02), rock, scale=(1, 1, 0.5), seg=14)
    red, white = C.M("#e8505b", 0.7), C.M(WHITE, 0.7)
    n, h = 5, 1.0
    for i in range(n):
        z0 = 0.1 + h * i / n
        r0, r1 = 0.18 - 0.05 * i / n, 0.18 - 0.05 * (i + 1) / n
        C.cyl(r0, r1, h / n, (0, 0, z0 + h / n / 2), red if i % 2 else white, verts=28, bevel=0.006)
    top = 0.1 + h
    C.cyl(0.17, 0.17, 0.035, (0, 0, top + 0.017), C.M("#3e4a66", 0.6), verts=28)
    C.torus(0.155, 0.008, (0, 0, top + 0.1), C.M("#3e4a66", 0.6))
    C.cyl(0.09, 0.09, 0.15, (0, 0, top + 0.11), C.M("#fff4c4", 0.3, emit=4.0), verts=20)
    C.cone_roof(0.1, 0.13, top + 0.185, red, tip=P["gold"])
    C.door("front", 0.34, 0.34, 0.0, P["trim"], C.M("#5b8fb0", 0.7), dw=0.06, dh=0.1)
    # Keeper's cottage.
    C.rbox((0.2, 0.16, 0.13), (0.24, -0.16, 0.085), C.M("#cfe4f2", 0.9), r=0.02)
    C.gable(0.2, 0.16, 0.09, 0.15, C.M("#5b8fb0", 0.8), fill=C.M("#cfe4f2", 0.9), cx=0.24, cy=-0.16, along_x=False)


def _bazaar(P):
    w, d = 0.66, 0.54
    base(w, d, P)
    C.rbox((w, d, 0.34), (0, 0, 0.215), C.M("#f8d3c6", 0.9), r=0.035)
    C.rbox((w + 0.02, d + 0.02, 0.04), (0, 0, 0.405), P["trim"], r=0.012)
    for u in (-0.2, 0.0, 0.2):
        C.window("front", w, d, u, 0.25, P["trim"], P["glass"], ww=0.09, wh=0.12, arch=True)
    C.door("front", w, d, 0.0, P["trim"], C.M("#e07a5f", 0.7), dw=0.1, dh=0.13) if False else None
    C.ball(0.2, (0, 0, 0.44), P["gold"], scale=(1, 1, 1.15))
    C.cyl(0.0, 0.035, 0.12, (0, 0, 0.72), P["gold"], verts=16)
    C.ball(0.025, (0, 0, 0.79), P["gold"])
    for x in (-0.3, 0.3):
        for y in (-0.24, 0.24):
            C.cyl(0.05, 0.05, 0.56, (x, y, 0.28), C.M("#fbe2c2", 0.9), verts=20)
            C.cone_roof(0.05, 0.14, 0.56, C.M("#e07a5f", 0.8), cx=x, cy=y, tip=P["gold"])


def _conservatory(P):
    w, d = 0.66, 0.56
    base(w, d, P)
    C.rbox((w, d, 0.1), (0, 0, 0.095), P["trim"], r=0.03)
    for i in range(7):
        x = -0.24 + i * 0.08
        C.ball(0.05 + (i % 3) * 0.01, (x, (i % 2) * 0.1 - 0.05, 0.2), C.M("#6dbb65", 0.9))
    C.ball(0.08, (0, 0, 0.26), C.M("#ff8fab", 0.8), seg=14)
    C.ball(0.3, (0, 0, 0.13), C.M("#cdeff5", 0.05, alpha=0.38), scale=(1.05, 0.88, 1.0), seg=28)
    for k in range(6):
        a = k * math.pi / 6
        C.torus(0.3, 0.008, (0, 0, 0.13), P["trim"], rot=(math.pi / 2, 0, a))
    C.ball(0.03, (0, 0, 0.44), P["gold"])
    C.bush(-0.36, -0.24, 1.0, P["leaf"], flowers=P["petals"][0])
    C.bush(0.36, -0.24, 1.0, P["leaf"], flowers=P["petals"][1])


def _transit(P):
    w, d = 0.7, 0.5
    base(w, d, P)
    C.rbox((w, d, 0.24), (0, 0, 0.165), C.M("#ffd6b8", 0.9), r=0.03)
    C.cyl(0.24, 0.24, w - 0.04, (0, 0, 0.285), C.M("#bfe3f5", 0.1, alpha=0.5), verts=32, rot=(0, math.pi / 2, 0))
    for x in (-0.3, -0.1, 0.1, 0.3):
        C.torus(0.24, 0.01, (x, 0, 0.285), P["trim"], rot=(0, math.pi / 2, 0))
    C.rbox((0.16, 0.16, 0.58), (0, -0.12, 0.29), C.M("#e8735c", 0.8), r=0.02)
    C.cyl(0.055, 0.055, 0.02, (0, -0.205, 0.5), P["trim"], verts=24, rot=(math.pi / 2, 0, 0))
    C.rbox((0.006, 0.01, 0.04), (0, -0.218, 0.515), P["dark"], r=0.002)
    C.hip(0.16, 0.16, 0.12, 0.58, C.M("#f4a261", 0.8), cy=-0.12)
    for u in (-0.25, 0.25):
        C.door("front", w, d, u, P["trim"], C.M("#6f8cf0", 0.7))


def _arena(P):
    wall = C.M("#e3d6f5", 0.9)
    C.cyl(0.36, 0.33, 0.24, (0, 0, 0.12), wall, verts=36)
    C.cyl(0.29, 0.29, 0.02, (0, 0, 0.235), C.M("#5fbf6a", 0.9), verts=36)
    C.torus(0.34, 0.025, (0, 0, 0.245), C.M("#9a7bd6", 0.6))
    for k in range(12):
        a = k * math.tau / 12
        C.rbox((0.06, 0.02, 0.08), (math.cos(a) * 0.35, math.sin(a) * 0.35, 0.12), P["glass"], r=0.012,
               rot=(0, 0, a + math.pi / 2))
    for k in range(4):
        a = k * math.tau / 4 + math.pi / 4
        x, y = math.cos(a) * 0.36, math.sin(a) * 0.36
        C.cyl(0.012, 0.016, 0.5, (x, y, 0.25), P["trim"], verts=10)
        C.rbox((0.08, 0.04, 0.05), (x, y, 0.51), C.M("#fff4c4", 0.3, emit=5.0), r=0.01)


def _bank(P):
    w, d = 0.66, 0.54
    C.rbox((w + 0.06, d + 0.06, 0.05), (0, 0, 0.025), P["stone"], r=0.015)
    C.rbox((w + 0.02, d + 0.02, 0.04), (0, 0, 0.07), P["stone"], r=0.012)
    C.rbox((w - 0.06, d - 0.14, 0.32), (0, 0.04, 0.25), C.M("#fbf3e1", 0.9), r=0.02)
    for i in range(6):
        C.cyl(0.026, 0.026, 0.3, (-0.25 + i * 0.1, -d / 2 + 0.07, 0.24), P["trim"], verts=16)
    C.rbox((w, d - 0.04, 0.04), (0, 0, 0.41), P["trim"], r=0.012)
    C.gable(w - 0.02, d - 0.06, 0.12, 0.43, C.M("#fbf3e1", 0.9), fill=P["trim"], along_x=False)
    C.ball(0.13, (0, 0.06, 0.5), P["gold"], scale=(1, 1, 0.9))
    C.cyl(0.05, 0.05, 0.012, (0, -d / 2 + 0.02, 0.49), P["gold"], verts=24, rot=(math.pi / 2, 0, 0))


def _spire(P):
    glass = C.M("#a9cdf5", 0.12, metal=0.25)
    C.rbox((0.6, 0.5, 0.12), (0, 0, 0.085), P["trim"], r=0.03)
    for i, (r1, r2, h) in enumerate(((0.22, 0.19, 0.5), (0.18, 0.14, 0.5), (0.13, 0.08, 0.45))):
        z = 0.145 + sum(x[2] for x in ((0.22, 0.19, 0.5), (0.18, 0.14, 0.5), (0.13, 0.08, 0.45))[:i])
        C.cyl(r1, r2, h, (0, 0, z + h / 2), glass, verts=32)
        C.torus(r2 + 0.01, 0.012, (0, 0, z + h), P["trim"])
    C.torus(0.24, 0.018, (0, 0, 1.15), P["gold"], rot=(0.25, 0, 0))
    C.cyl(0.004, 0.02, 0.4, (0, 0, 1.79), P["trim"], verts=10)
    C.ball(0.03, (0, 0, 2.0), C.M("#bfe6ff", 0.3, emit=6.0))
    for i in range(3):
        C.bush(-0.2 + i * 0.2, -0.2, 0.8, P["leaf"], z=0.14)


def main():
    builders = {1: level1, 2: level2, 3: level3, 4: level4}
    for d, S in enumerate(STYLES):
        if ONLY and d not in ONLY:
            continue
        for lvl, fn in builders.items():
            for v in range(3):
                C.reset()
                P = pal(S, v)
                fn(S, v, P)
                C.export(os.path.join(OUT, "d%d_l%d_v%d.glb" % (d, lvl, v)))
        C.reset()
        landmark(d, pal(S, 0))
        C.export(os.path.join(OUT, "d%d_l5.glb" % d))
        print("district %d done" % d)


main()
