"""Builds the six table themes for the top-down board (art style v3).

For each theme: buildings b_l1..b_l4 (three variants each) and landmark b_l5 (three variants),
the board frame, the centrepiece filling the 5 x 7 middle, and the island rock under the board.
Plus a shared rounded tile (art/models/tile_v2.glb) whose colour the game sets.

The camera looks straight down, so roofs carry the design: every level has a different roof
silhouette and rooftop detail, and every theme its own roof palette.

Run:  blender -b --factory-startup -P tools/blender/build_themes.py -- [theme ...]
Conventions: 1 unit = 1 tile. Blender +Y is up the screen (Godot -Z). Buildings: origin on the
ground at the footprint centre, front facing -Y, footprint within 0.70 x 0.70.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cute as C  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "themes")
COLS, ROWS = 7, 9
FRAME = 0.16
INNER_W, INNER_H = 5 - 0.12, 7 - 0.12  # the centre area inside the ring


class Pal:
    """Named colours that turn into materials on use, so they survive each model's reset."""

    def __init__(self, **cols):
        self._cols = cols

    def __getattr__(self, name):
        v = self._cols[name]
        return C.M(*v) if isinstance(v, tuple) else C.M(v)


def out(theme, name):
    return os.path.join(OUT, theme, name + ".glb")


# ================================================================ shared

def build_tile():
    C.reset()
    C.rbox((0.92, 0.92, 0.12), (0, 0, 0.06), C.M("#ffffff"), r=0.05, seg=3)
    C.export(os.path.join(ROOT, "art", "models", "tile_v2.glb"))


def frame(theme, top, lip, deco=None):
    """The board slab: a rounded plate under the ring, with a lip and a theme border."""
    C.reset()
    w, h = COLS + FRAME * 2, ROWS + FRAME * 2
    C.rbox((w, h, 0.34), (0, 0, -0.17), C.M(top), r=0.14, seg=4)
    C.rbox((w + 0.08, h + 0.08, 0.14), (0, 0, -0.36), C.M(lip), r=0.1, seg=3)
    if deco:
        deco(w, h)
    C.export(out(theme, "frame"))


def island(theme, soil, rock, grass=None):
    """The floating island under the board: layered rock tapering to a point (lobby view)."""
    C.reset()
    rng = random.Random(7)
    w, h = COLS + FRAME * 2, ROWS + FRAME * 2
    if grass:
        # A grass skirt just under the frame's lip: seen only from the lobby's angled camera.
        C.rbox((w - 0.1, h - 0.1, 0.16), (0, 0, -0.5), C.M(grass), r=0.12, seg=3)
    layers = [(1.0, -0.75, soil), (0.86, -1.25, rock), (0.66, -1.8, rock), (0.42, -2.35, soil), (0.2, -2.85, rock)]
    for s, z, col in layers:
        C.rbox((w * s, h * s, 0.62), (0, 0, z), C.M(col), r=0.25, seg=3)
    for i in range(14):
        a = rng.uniform(0, math.tau)
        rx, ry = math.cos(a) * w * 0.38, math.sin(a) * h * 0.38
        C.ball(rng.uniform(0.25, 0.5), (rx, ry, rng.uniform(-1.6, -0.9)), C.M(rock), scale=(1, 1, 0.8), seg=10)
    C.cyl(0.03, 0.05, 1.2, (0.4, -0.3, -3.5), C.M(soil), verts=8)
    C.export(out(theme, "island_v2"))


def free_spot(x, y, r, paths=(), circles=(), placed=(), path_half=0.25, gap=0.55):
    """True when a prop of radius r at (x, y) clears every path, circle and earlier prop."""
    for px, py in paths:
        if px is not None and abs(x - px) < path_half + r:
            return False
        if py is not None and abs(y - py) < path_half + r:
            return False
    for cx, cy, cr in circles:
        if math.hypot(x - cx, y - cy) < cr + r:
            return False
    for qx, qy in placed:
        if math.hypot(x - qx, y - qy) < gap:
            return False
    return True


def lot(theme, ground, fence, leaf, post):
    """An empty lot: a patch of theme ground, fence corners and a little sign."""
    C.reset()
    C.rbox((0.74, 0.74, 0.025), (0, 0, 0.0125), C.M(ground), r=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            C.rbox((0.16, 0.025, 0.05), (sx * 0.29, sy * 0.35, 0.05), C.M(fence), r=0.008)
            C.rbox((0.025, 0.16, 0.05), (sx * 0.35, sy * 0.29, 0.05), C.M(fence), r=0.008)
    C.bush(-0.18, 0.18, 1.6, C.M(leaf))
    C.bush(0.2, -0.05, 1.3, C.M(leaf))
    C.cyl(0.012, 0.012, 0.22, (0.16, 0.2, 0.11), C.M(post), verts=8)
    C.rbox((0.2, 0.025, 0.12), (0.16, 0.2, 0.22), C.M(fence), r=0.01)
    C.rbox((0.16, 0.03, 0.03), (0.16, 0.2, 0.23), C.M("#ff5d73"), r=0.006)
    C.export(out(theme, "lot"))


def win_top(x, y, z, w, d, glass, frame_m):
    """A skylight seen from above."""
    C.rbox((w + 0.03, d + 0.03, 0.02), (x, y, z + 0.01), frame_m, r=0.008)
    C.rbox((w, d, 0.025), (x, y, z + 0.015), glass, r=0.006)


def windows_around(w, d, z0, z1, rows, glass, frame_m, cols=2):
    C.window_grid(["front", "left", "right", "back"], w, d, z0, z1, cols, rows, frame_m, glass, ww=0.07, wh=0.085)


# ================================================================ small town

def town():
    T = "town"
    wall = ["#fff3df", "#ffe2c8", "#e9f1ff", "#fde7ef"]
    roof = ["#e0704f", "#5f86c9", "#d95561", "#5fa86b"]
    P = Pal(wood="#a86b45", glass=("#9fd3ff", 0.3), white="#ffffff", grass="#8fd06a", hedge="#5fae55")
    for v in range(3):
        P._cols["wl"], P._cols["rf"] = wall[v], roof[v]
        # L1: a cottage with a garden and picket fence
        C.reset()
        C.rbox((0.66, 0.66, 0.02), (0, 0, 0.01), P.grass, r=0.02)
        C.rbox((0.34, 0.28, 0.2), (0, 0.06, 0.1), P.wl, r=0.02)
        C.gable(0.34, 0.28, 0.15, 0.2, P.rf, fill=P.wl, along_x=(v != 1), cy=0.06)
        C.chimney(0.09, 0.12, 0.28, 0.08, C.M("#c97a5a"), P.white)
        C.door("front", 0.34, 0.28, 0.0, P.white, P.wood, cy=0.06)
        for x in (-0.3, -0.15, 0.15, 0.3):
            C.rbox((0.02, 0.02, 0.07), (x, -0.3, 0.035), P.white, r=0.005)
        C.rbox((0.62, 0.012, 0.015), (0, -0.3, 0.05), P.white, r=0.004)
        C.bush(-0.22, -0.16, 1.2, P.hedge, flowers=C.M("#ff8fb1"))
        C.tree(0.24, -0.18, 1.0, P.hedge, P.wood)
        C.export(out(T, "b_l1_v%d" % v))
        # L2: a two-storey house with a garage and garden path
        C.reset()
        C.rbox((0.68, 0.68, 0.02), (0, 0, 0.01), P.grass, r=0.02)
        C.rbox((0.4, 0.3, 0.36), (-0.05, 0.08, 0.18), P.wl, r=0.02)
        C.gable(0.4, 0.3, 0.17, 0.36, P.rf, fill=P.wl, along_x=True, cx=-0.05, cy=0.08)
        C.rbox((0.2, 0.22, 0.17), (0.22, 0.04, 0.085), P.wl, r=0.02)
        C.rbox((0.24, 0.26, 0.04), (0.22, 0.04, 0.19), P.rf, r=0.015)
        C.window_grid(["front"], 0.4, 0.3, 0.12, 0.32, 2, 2, P.white, P.glass, cx=-0.05, cy=0.08)
        C.chimney(-0.18, 0.16, 0.42, 0.1, C.M("#c97a5a"), P.white)
        C.rbox((0.1, 0.24, 0.006), (-0.05, -0.2, 0.023), C.M("#f2dfc0"), r=0.01)
        C.tree(0.24, -0.22, 1.1, P.hedge, P.wood)
        C.export(out(T, "b_l2_v%d" % v))
        # L3: a shop row with striped awnings and a roof terrace
        C.reset()
        C.rbox((0.7, 0.7, 0.02), (0, 0, 0.01), C.M("#efe2c8"), r=0.02)
        C.rbox((0.6, 0.38, 0.5), (0, 0.08, 0.25), P.wl, r=0.02)
        C.hip(0.6, 0.38, 0.14, 0.5, P.rf, cx=0, cy=0.08)
        C.window_grid(["front"], 0.6, 0.38, 0.3, 0.46, 3, 1, P.white, P.glass, cy=0.08)
        C.awning_stripes("front", 0.6, 0.38, -0.15, 0.2, 0.22, C.M(roof[(v + 1) % 4]), P.white, cy=0.08)
        C.awning_stripes("front", 0.6, 0.38, 0.15, 0.2, 0.22, C.M(roof[(v + 2) % 4]), P.white, cy=0.08)
        C.chimney(0.2, 0.18, 0.56, 0.09, C.M("#c97a5a"), P.white)
        for x in (-0.24, 0.0, 0.24):
            C.ball(0.03, (x, -0.24, 0.05), C.M("#ff8fb1"), seg=8)
        C.export(out(T, "b_l3_v%d" % v))
        # L4: an inn with a corner tower and a courtyard tree
        C.reset()
        C.rbox((0.72, 0.72, 0.02), (0, 0, 0.01), C.M("#efe2c8"), r=0.02)
        C.rbox((0.52, 0.44, 0.6), (-0.06, 0.06, 0.3), P.wl, r=0.02)
        C.gable(0.52, 0.44, 0.2, 0.6, P.rf, fill=P.wl, along_x=(v % 2 == 0), cx=-0.06, cy=0.06)
        C.cyl(0.11, 0.11, 0.8, (0.22, -0.18, 0.4), C.M(wall[(v + 1) % 4]), verts=20)
        C.cone_roof(0.11, 0.22, 0.8, P.rf, cx=0.22, cy=-0.18, tip=C.M("#f2c14e"))
        windows_around(0.52, 0.44, 0.15, 0.55, 2, P.glass, P.white)
        C.tree(-0.24, -0.24, 1.0, P.hedge, P.wood)
        C.export(out(T, "b_l4_v%d" % v))
    # L5 landmarks: clock tower, town hall, windmill
    C.reset()
    C.rbox((0.74, 0.74, 0.04), (0, 0, 0.02), C.M("#efe2c8"), r=0.03)
    C.rbox((0.3, 0.3, 1.0), (0, 0.05, 0.5), C.M("#fff3df"), r=0.03)
    C.rbox((0.34, 0.34, 0.06), (0, 0.05, 1.0), P.white, r=0.02)
    C.hip(0.3, 0.3, 0.3, 1.02, C.M("#d95561"), cx=0, cy=0.05)
    for f in ("front", "left", "right", "back"):
        C.cyl(0.07, 0.07, 0.02, C._at(f, 0.3, 0.3, 0, 0.8, 0.01, 0, 0.05), P.white, verts=24,
              rot=(math.pi / 2, 0, 0) if f in ("front", "back") else (0, math.pi / 2, 0))
    C.ball(0.04, (0, 0.05, 1.38), C.M("#f2c14e", 0.3, 0.8))
    for x in (-0.26, 0.26):
        C.tree(x, -0.24, 1.0, P.hedge, P.wood)
    C.export(out(T, "b_l5_v0"))
    C.reset()
    C.rbox((0.74, 0.74, 0.04), (0, 0, 0.02), C.M("#efe2c8"), r=0.03)
    C.rbox((0.64, 0.4, 0.5), (0, 0.1, 0.25), C.M("#fff3df"), r=0.03)
    C.hip(0.64, 0.4, 0.18, 0.5, C.M("#5f86c9"), cy=0.1)
    C.cyl(0.12, 0.12, 0.3, (0, 0.1, 0.78), P.white, verts=24)
    C.ball(0.12, (0, 0.1, 0.93), C.M("#f2c14e", 0.3, 0.8), scale=(1, 1, 0.8))
    for x in (-0.22, -0.07, 0.07, 0.22):
        C.cyl(0.025, 0.025, 0.36, (x, -0.13, 0.2), P.white, verts=12)
    C.rbox((0.6, 0.12, 0.04), (0, -0.13, 0.4), P.white, r=0.01)
    C.export(out(T, "b_l5_v1"))
    C.reset()
    C.rbox((0.74, 0.74, 0.04), (0, 0, 0.02), P.grass, r=0.03)
    C.cyl(0.2, 0.13, 0.75, (0, 0, 0.4), C.M("#fde7ef"), verts=24)
    C.cone_roof(0.14, 0.22, 0.77, C.M("#d95561"), tip=P.white)
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        C.rbox((0.06, 0.012, 0.5), (math.cos(a) * 0.17, -0.2, 0.7 + math.sin(a) * 0.17), C.M("#fff3df"),
               r=0.004, rot=(0, a, 0))
    C.export(out(T, "b_l5_v2"))
    # Centrepiece: the village green with a fountain, pond, market and bunting
    C.reset()
    rng = random.Random(1)
    C.rbox((INNER_W, INNER_H, 0.04), (0, 0, 0.02), P.grass, r=0.08)
    path = C.M("#f2e2c0")
    C.rbox((0.5, INNER_H - 0.4, 0.012), (0, 0, 0.046), path, r=0.08)
    C.rbox((INNER_W - 0.4, 0.5, 0.012), (0, 0, 0.046), path, r=0.08)
    C.cyl(1.0, 1.0, 0.014, (0, 0, 0.048), path, verts=48)
    C.cyl(0.55, 0.55, 0.12, (0, 0, 0.1), C.M("#e9e2d3"), verts=40)
    C.cyl(0.47, 0.47, 0.03, (0, 0, 0.15), C.M("#7fd0f0", 0.25), verts=40)
    C.cyl(0.08, 0.06, 0.3, (0, 0, 0.3), C.M("#e9e2d3"), verts=16)
    C.cyl(0.18, 0.18, 0.04, (0, 0, 0.42), C.M("#e9e2d3"), verts=24)
    # pond with ducks, top right
    C.cyl(0.8, 0.8, 0.02, (1.3, 2.2, 0.045), C.M("#7fd0f0", 0.25), verts=40)
    for (x, y) in ((1.1, 2.0), (1.4, 2.4)):
        C.ball(0.05, (x, y, 0.08), C.M("#ffffff"), seg=10)
    # market stalls, bottom left
    for k, col in enumerate(["#d95561", "#5f86c9", "#f2c14e"]):
        x, y = -1.6 + k * 0.5, -2.4
        C.rbox((0.36, 0.26, 0.16), (x, y, 0.1), C.M("#a86b45"), r=0.01)
        C.rbox((0.42, 0.32, 0.04), (x, y, 0.22), C.M(col), r=0.015)
    # gazebo bottom right
    C.cyl(0.35, 0.35, 0.06, (1.4, -2.2, 0.06), P.white, verts=8)
    C.cone_roof(0.32, 0.22, 0.36, C.M("#d95561"), cx=1.4, cy=-2.2)
    for k in range(6):
        a = k * math.tau / 6
        C.cyl(0.02, 0.02, 0.3, (1.4 + math.cos(a) * 0.28, -2.2 + math.sin(a) * 0.28, 0.21), P.white, verts=8)
    # trees and flowers around the edges
    spots = []
    for _ in range(140):
        x, y = rng.uniform(-2.0, 2.0), rng.uniform(-2.95, 2.95)
        if not free_spot(x, y, 0.45, paths=[(0, None), (None, 0)], circles=[(0, 0, 1.0), (1.3, 2.2, 0.8),
                         (1.4, -2.2, 0.38), (-1.1, -2.4, 0.8)], placed=spots):
            continue
        spots.append((x, y))
        if rng.random() < 0.7:
            C.tree(x, y, rng.uniform(2.8, 3.8), C.M(rng.choice(["#5cb84f", "#4fa548", "#73c35a"])), P.wood)
        else:
            C.bush(x, y, 3.5, P.hedge, flowers=C.M(rng.choice(["#ff8fb1", "#ffd166", "#ffffff"])))
    for (x, y) in ((-0.4, 1.2), (0.4, 1.2), (-0.4, -1.2), (0.4, -1.2)):
        C.lamp(x, y, C.M("#3a3f4c"), C.M("#ffe6a6"))
    C.export(out(T, "centre"))
    lot(T, "#9ad57a", "#ffffff", "#5fae55", "#a86b45")
    frame(T, "#a87a52", "#7a5638")
    island(T, "#b07a4f", "#8f6a55", grass="#7fc35f")


def scatter(rng, tries, bounds, r, avoid, place, gap=0.5, spots=None):
    """Places props at random free spots: bounds (x0, x1, y0, y1); avoid = (paths, circles, rects)."""
    paths, circles, rects = avoid
    spots = spots if spots is not None else []
    for _ in range(tries):
        x, y = rng.uniform(bounds[0], bounds[1]), rng.uniform(bounds[2], bounds[3])
        if not free_spot(x, y, r, paths=paths, circles=circles, placed=spots, gap=gap):
            continue
        if any(x0 - r < x < x1 + r and y0 - r < y < y1 + r for x0, x1, y0, y1 in rects):
            continue
        spots.append((x, y))
        place(x, y)
    return spots


def pine(x, y, s, leaf, trunk, z=0.0):
    C.cyl(0.03 * s, 0.035 * s, 0.1 * s, (x, y, z + 0.05 * s), trunk, verts=8)
    for k, (r, h) in enumerate(((0.16, 0.2), (0.12, 0.18), (0.08, 0.15))):
        C.cyl(r * s, 0.01 * s, h * s, (x, y, z + (0.12 + k * 0.1) * s + h * s / 2), leaf, verts=12, bevel=0.01)


def palm(x, y, s, leaf, trunk, z=0.0, lean=0.0):
    for k in range(5):
        C.cyl(0.03 * s, 0.026 * s, 0.07 * s, (x + lean * k * 0.012 * s, y, z + (0.035 + k * 0.065) * s), trunk, verts=8)
    top = (x + lean * 0.06 * s, y, z + 0.36 * s)
    for k in range(6):
        a = k * math.tau / 6
        C.rbox((0.2 * s, 0.05 * s, 0.015 * s), (top[0] + math.cos(a) * 0.09 * s, top[1] + math.sin(a) * 0.09 * s, top[2]),
               leaf, r=0.006, rot=(0, 0.25, a))
    C.ball(0.03 * s, top, trunk, seg=8)


# ================================================================ forest

def forest():
    T = "forest"
    P = Pal(log="#a0673f", dark="#7a4a2a", stone="#b9b2a6", moss="#5f9e4f", moss2="#4f8a42", leaf="#3f8f4a",
            leaf2="#57a85a", glass=("#ffe6a6", 0.4), white="#f4efe4", water=("#5fc0e0", 0.25), red="#e0563f",
            ground="#7cc46a", path="#d9c39a")
    roofs = ["#5f9e4f", "#c25a3c", "#4f7fae"]
    for v in range(3):
        rf = roofs[v]
        # L1: a log cabin with a woodpile
        C.reset()
        C.rbox((0.6, 0.6, 0.02), (0, 0, 0.01), P.ground, r=0.02)
        C.rbox((0.36, 0.28, 0.2), (0, 0.04, 0.1), P.log, r=0.03)
        for z in (0.04, 0.1, 0.16):
            C.cyl(0.012, 0.012, 0.38, (0, -0.105, z), P.dark, verts=8, rot=(0, math.pi / 2, 0))
        C.gable(0.36, 0.28, 0.16, 0.2, C.M(rf), fill=P.log, along_x=True, cy=0.04)
        C.chimney(-0.1, 0.1, 0.28, 0.1, P.stone, P.stone)
        C.door("front", 0.36, 0.28, 0.06, P.dark, P.dark, cy=0.04)
        for k in range(3):
            C.cyl(0.018, 0.018, 0.12, (0.24, -0.2 + k * 0.03, 0.02 + (k % 2) * 0.03), P.log, verts=8, rot=(0, math.pi / 2, 0))
        pine(-0.24, -0.2, 0.9, P.leaf, P.dark)
        C.export(out(T, "b_l1_v%d" % v))
        # L2: a cabin on stilts with a porch
        C.reset()
        C.rbox((0.66, 0.66, 0.02), (0, 0, 0.01), P.ground, r=0.02)
        for sx in (-1, 1):
            for sy in (-1, 1):
                C.cyl(0.02, 0.02, 0.12, (sx * 0.17, 0.06 + sy * 0.12, 0.06), P.dark, verts=8)
        C.rbox((0.42, 0.32, 0.03), (0, 0.06, 0.13), P.dark, r=0.01)
        C.rbox((0.34, 0.26, 0.22), (0, 0.08, 0.255), P.log, r=0.03)
        C.gable(0.34, 0.26, 0.17, 0.365, C.M(rf), fill=P.log, along_x=False, cy=0.08)
        C.window("front", 0.34, 0.26, -0.08, 0.27, P.dark, P.glass, cy=0.08)
        C.rbox((0.42, 0.012, 0.06), (0, -0.1, 0.17), P.dark, r=0.004)
        pine(0.25, -0.22, 1.0, P.leaf2, P.dark)
        C.bush(-0.24, -0.22, 1.3, P.leaf)
        C.export(out(T, "b_l2_v%d" % v))
        # L3: a treehouse in a big round tree
        C.reset()
        C.rbox((0.68, 0.68, 0.02), (0, 0, 0.01), P.ground, r=0.02)
        C.cyl(0.07, 0.09, 0.5, (0, 0, 0.25), P.dark, verts=12)
        C.ball(0.32, (0, 0.04, 0.62), P.leaf, scale=(1, 1, 0.75))
        C.ball(0.2, (0.18, -0.1, 0.55), P.leaf2)
        C.rbox((0.3, 0.26, 0.18), (-0.04, -0.12, 0.62), P.log, r=0.02)
        C.gable(0.3, 0.26, 0.12, 0.71, C.M(rf), fill=P.log, along_x=True, cx=-0.04, cy=-0.12)
        C.rbox((0.04, 0.012, 0.5), (0.2, -0.26, 0.28), P.log, r=0.004, rot=(0.2, 0, 0))
        C.export(out(T, "b_l3_v%d" % v))
        # L4: a timber lodge with a stone base and two wings
        C.reset()
        C.rbox((0.72, 0.72, 0.02), (0, 0, 0.01), P.ground, r=0.02)
        C.rbox((0.6, 0.36, 0.12), (0, 0.06, 0.06), P.stone, r=0.02)
        C.rbox((0.56, 0.32, 0.34), (0, 0.06, 0.29), P.log, r=0.03)
        C.gable(0.56, 0.32, 0.2, 0.46, C.M(rf), fill=P.log, along_x=True, cy=0.06)
        C.rbox((0.2, 0.22, 0.3), (0.0, -0.16, 0.15), P.log, r=0.02)
        C.gable(0.2, 0.22, 0.12, 0.3, C.M(rf), fill=P.white, along_x=False, cy=-0.16)
        C.window_grid(["front"], 0.56, 0.32, 0.2, 0.4, 3, 1, P.dark, P.glass, cy=0.06)
        C.chimney(0.2, 0.14, 0.6, 0.1, P.stone, P.stone)
        pine(-0.28, -0.26, 1.0, P.leaf, P.dark)
        C.export(out(T, "b_l4_v%d" % v))
    # L5: a lookout tower, a great mushroom house, a waterfall mill
    C.reset()
    C.rbox((0.74, 0.74, 0.04), (0, 0, 0.02), P.ground, r=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            C.cyl(0.025, 0.035, 1.0, (sx * 0.16, sy * 0.16, 0.5), P.dark, verts=8)
    C.rbox((0.46, 0.46, 0.05), (0, 0, 1.0), P.log, r=0.02)
    C.rbox((0.36, 0.36, 0.18), (0, 0, 1.12), P.log, r=0.02)
    C.hip(0.36, 0.36, 0.18, 1.21, C.M("#c25a3c"))
    C.ball(0.03, (0, 0, 1.45), C.M("#f2c14e", 0.3, 0.8))
    pine(-0.28, -0.28, 1.1, P.leaf, P.dark)
    C.export(out(T, "b_l5_v0"))
    C.reset()
    C.rbox((0.74, 0.74, 0.04), (0, 0, 0.02), P.ground, r=0.03)
    C.cyl(0.16, 0.2, 0.5, (0, 0, 0.27), P.white, verts=24)
    C.ball(0.36, (0, 0, 0.55), P.red, scale=(1, 1, 0.6))
    for k in range(7):
        a = k * math.tau / 7
        C.ball(0.05, (math.cos(a) * 0.24, math.sin(a) * 0.24, 0.68), P.white, scale=(1, 1, 0.4), seg=10)
    C.ball(0.06, (0, 0, 0.77), P.white, scale=(1, 1, 0.5), seg=10)
    C.door("front", 0.36, 0.36, 0, P.dark, P.dark)
    C.export(out(T, "b_l5_v1"))
    C.reset()
    C.rbox((0.74, 0.74, 0.04), (0, 0, 0.02), P.ground, r=0.03)
    C.rbox((0.42, 0.36, 0.42), (-0.06, 0.08, 0.21), P.stone, r=0.03)
    C.gable(0.42, 0.36, 0.2, 0.42, C.M("#4f7fae"), fill=P.log, along_x=True, cx=-0.06, cy=0.08)
    C.torus(0.18, 0.03, (0.2, -0.1, 0.22), P.log, rot=(0, math.pi / 2, 0))
    for k in range(8):
        a = k * math.tau / 8
        C.rbox((0.025, 0.06, 0.012), (0.24, -0.1 + math.cos(a) * 0.18, 0.22 + math.sin(a) * 0.18), P.dark, r=0.004,
               rot=(a, 0, 0))
    C.rbox((0.1, 0.3, 0.012), (0.24, -0.25, 0.006), P.water, r=0.01)
    C.export(out(T, "b_l5_v2"))
    # Centrepiece: a lake with a dock, a winding creek, campfire, deer and a pine forest
    C.reset()
    rng = random.Random(2)
    C.rbox((INNER_W, INNER_H, 0.04), (0, 0, 0.02), P.ground, r=0.08)
    C.ball(1.25, (0.1, 0.7, 0.0), P.water, scale=(1.0, 1.25, 0.04), seg=40)
    C.ball(1.35, (0.1, 0.7, -0.005), P.path, scale=(1.0, 1.25, 0.035), seg=40)
    for k in range(10):
        t = k / 9.0
        C.ball(0.22, (0.4 + math.sin(t * 3.0) * 0.5, -0.6 - t * 2.4, 0.0), P.water, scale=(1, 1, 0.12), seg=16)
    C.rbox((0.7, 0.16, 0.04), (-0.7, 0.4, 0.07), P.log, r=0.01)
    C.rbox((0.3, 0.14, 0.05), (0.2, 1.2, 0.08), P.red, r=0.04)
    for k in range(6):
        a = k * math.tau / 6
        C.cyl(0.03, 0.03, 0.18, (-1.2 + math.cos(a) * 0.12, -1.6 + math.sin(a) * 0.12, 0.06), P.log, verts=8,
              rot=(0.6 * math.cos(a), 0.6 * math.sin(a), 0))
    C.ball(0.08, (-1.2, -1.6, 0.1), C.M("#ffb347", 0.4, 0, 2.0), seg=10)
    for k in range(4):
        a = k * math.tau / 4 + 0.4
        C.cyl(0.08, 0.08, 0.1, (-1.2 + math.cos(a) * 0.35, -1.6 + math.sin(a) * 0.35, 0.05), P.log, verts=10)
    C.rbox((0.4, 0.3, 0.2), (1.4, -2.4, 0.12), P.log, r=0.03)
    C.gable(0.4, 0.3, 0.14, 0.22, P.moss, fill=P.log, cx=1.4, cy=-2.4)
    lake = (0.1, 0.7, 1.45)
    scatter(rng, 400, (-2.05, 2.05, -3.0, 3.0), 0.32, ([], [lake, (-1.2, -1.6, 0.55), (1.4, -2.4, 0.35)],
            [(0.0, 0.9, -3.0, -0.6)]),
            lambda x, y: pine(x, y, rng.uniform(2.0, 2.9), C.M(rng.choice(["#3f8f4a", "#2f7a3e", "#57a85a"])), P.dark),
            gap=0.42)
    C.export(out(T, "centre"))
    lot(T, "#8fcf72", "#a0673f", "#3f8f4a", "#7a4a2a")
    frame(T, "#6b8a4a", "#4a6634")
    island(T, "#8a5a3c", "#6f6a60", grass="#6fbf5a")


# ================================================================ desert

def desert():
    T = "desert"
    P = Pal(sand="#f2c98f", sand2="#e9b27a", adobe="#f6dcb0", clay="#d98a4e", white="#fff4e0", blue="#3f7fcf",
            gold=("#f2c14e", 0.3, 0.8), palm="#4fa35a", trunk="#a0673f", water=("#5fc8e8", 0.2), wood="#8a5a3c",
            dark="#6b4a33", red="#d95561", tent="#fff0d6")
    walls = ["#f6dcb0", "#f2c98f", "#fbe6c4"]
    accents = ["#3f7fcf", "#d95561", "#2fa58a"]
    for v in range(3):
        P._cols["wl"], P._cols["ac"] = walls[v], accents[v]
        # L1: an adobe hut with a blue door and a clay pot
        C.reset()
        C.rbox((0.6, 0.6, 0.02), (0, 0, 0.01), P.sand, r=0.02)
        C.rbox((0.32, 0.3, 0.2), (0, 0.04, 0.1), P.wl, r=0.04)
        C.rbox((0.34, 0.32, 0.03), (0, 0.04, 0.215), P.clay, r=0.02)
        C.door("front", 0.32, 0.3, 0, P.wl, P.ac, cy=0.04)
        for x in (-0.12, 0.0, 0.12):
            C.cyl(0.012, 0.012, 0.08, (x, 0.2, 0.17), P.wood, verts=6, rot=(math.pi / 2, 0, 0))
        C.ball(0.05, (0.22, -0.2, 0.05), P.clay, seg=10)
        palm(-0.22, -0.2, 0.7, P.palm, P.trunk)
        C.export(out(T, "b_l1_v%d" % v))
        # L2: a two-storey house with a roof terrace and awning
        C.reset()
        C.rbox((0.66, 0.66, 0.02), (0, 0, 0.01), P.sand, r=0.02)
        C.rbox((0.42, 0.34, 0.3), (-0.04, 0.06, 0.15), P.wl, r=0.04)
        C.rbox((0.22, 0.2, 0.16), (0.08, 0.1, 0.38), P.wl, r=0.03)
        C.rbox((0.44, 0.36, 0.025), (-0.04, 0.06, 0.31), P.clay, r=0.015)
        C.rbox((0.2, 0.12, 0.012), (-0.12, -0.02, 0.33), P.ac, r=0.004, rot=(0.2, 0, 0))
        C.window_grid(["front"], 0.42, 0.34, 0.08, 0.24, 2, 1, P.white, P.ac, arch=True, cx=-0.04, cy=0.06)
        palm(0.26, -0.22, 0.8, P.palm, P.trunk, lean=1.0)
        C.export(out(T, "b_l2_v%d" % v))
        # L3: a courtyard house with a small dome
        C.reset()
        C.rbox((0.7, 0.7, 0.02), (0, 0, 0.01), P.sand, r=0.02)
        for (x, y, w, d) in ((0, 0.24, 0.62, 0.16), (0, -0.24, 0.62, 0.16), (-0.24, 0, 0.16, 0.32), (0.24, 0, 0.16, 0.32)):
            C.rbox((w, d, 0.32), (x, y, 0.16), P.wl, r=0.03)
            C.rbox((w + 0.02, d + 0.02, 0.025), (x, y, 0.33), P.clay, r=0.012)
        C.cyl(0.12, 0.12, 0.02, (0, 0, 0.03), P.water, verts=20)
        palm(0, 0, 0.7, P.palm, P.trunk)
        C.ball(0.1, (0.24, 0.24, 0.36), P.ac, scale=(1, 1, 0.9))
        C.export(out(T, "b_l3_v%d" % v))
        # L4: a riad tower with a big dome and arches
        C.reset()
        C.rbox((0.72, 0.72, 0.02), (0, 0, 0.01), P.sand, r=0.02)
        C.rbox((0.56, 0.44, 0.44), (0, 0.06, 0.22), P.wl, r=0.04)
        C.rbox((0.58, 0.46, 0.03), (0, 0.06, 0.45), P.clay, r=0.015)
        C.cyl(0.16, 0.16, 0.08, (-0.06, 0.08, 0.5), P.wl, verts=24)
        C.ball(0.16, (-0.06, 0.08, 0.54), P.ac, scale=(1, 1, 1.05))
        C.ball(0.025, (-0.06, 0.08, 0.72), P.gold, seg=8)
        C.rbox((0.12, 0.12, 0.3), (0.2, -0.1, 0.6), P.wl, r=0.02)
        C.rbox((0.14, 0.14, 0.03), (0.2, -0.1, 0.76), P.clay, r=0.01)
        C.window_grid(["front"], 0.56, 0.44, 0.1, 0.36, 3, 2, P.white, P.ac, arch=True, cy=0.06)
        C.export(out(T, "b_l4_v%d" % v))
    # L5: a palace with a golden dome, a pyramid, a caravan market
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.sand2, r=0.03)
    C.rbox((0.62, 0.5, 0.36), (0, 0.04, 0.2), P.white, r=0.04)
    C.cyl(0.2, 0.2, 0.14, (0, 0.04, 0.45), P.white, verts=28)
    C.ball(0.2, (0, 0.04, 0.52), P.gold, scale=(1, 1, 1.15))
    for (x, y) in ((-0.28, -0.22), (0.28, -0.22), (-0.28, 0.3), (0.28, 0.3)):
        C.cyl(0.05, 0.05, 0.7, (x, y, 0.35), P.white, verts=14)
        C.ball(0.055, (x, y, 0.72), P.gold, seg=10)
    C.export(out(T, "b_l5_v0"))
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.sand2, r=0.03)
    import bpy
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.48, radius2=0.0, depth=0.62, location=(0, 0.02, 0.35),
                                    rotation=(0, 0, math.pi / 4))
    C._add(bpy.context.active_object, P.sand, 0.02, 2)
    C.rbox((0.12, 0.04, 0.12), (0, -0.3, 0.1), P.dark, r=0.01)
    C.ball(0.04, (0, 0.02, 0.68), P.gold, seg=8)
    C.export(out(T, "b_l5_v1"))
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.sand2, r=0.03)
    for k, col in enumerate(["#d95561", "#3f7fcf", "#f2c14e", "#2fa58a"]):
        x, y = -0.18 + (k % 2) * 0.36, -0.16 + (k // 2) * 0.34
        C.cyl(0.15, 0.02, 0.32, (x, y, 0.2), C.M(col), verts=6, bevel=0.01)
        C.cyl(0.15, 0.15, 0.06, (x, y, 0.05), P.tent, verts=6)
    palm(0, 0, 1.0, P.palm, P.trunk)
    C.export(out(T, "b_l5_v2"))
    # Centrepiece: an oasis, dunes, a caravan, pyramids and palm groves
    C.reset()
    rng = random.Random(3)
    C.rbox((INNER_W, INNER_H, 0.04), (0, 0, 0.02), P.sand, r=0.08)
    for (x, y, s) in ((-1.4, 2.2, 1.0), (1.5, -2.5, 0.8), (-1.6, -1.6, 0.7), (1.6, 1.0, 0.6)):
        C.ball(0.9 * s, (x, y, -0.05), P.sand2, scale=(1.3, 0.8, 0.22), seg=24)
    C.ball(1.0, (0.2, 0.3, 0.0), P.water, scale=(1.0, 1.3, 0.05), seg=40)
    C.ball(1.15, (0.2, 0.3, -0.006), C.M("#9fd06a"), scale=(1.0, 1.3, 0.045), seg=40)
    import bpy
    for (x, y, s) in ((-1.3, 2.3, 1.0), (-0.6, 2.6, 0.6)):
        bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.7 * s, radius2=0.0, depth=0.9 * s, location=(x, y, 0.45 * s),
                                        rotation=(0, 0, math.pi / 4))
        C._add(bpy.context.active_object, P.sand2, 0.02, 2)
    for k in range(4):
        x, y = -1.2 + k * 0.32, -2.5 + k * 0.08
        C.ball(0.08, (x, y, 0.12), C.M("#c98b52"), scale=(1.6, 0.8, 0.8), seg=10)
        C.ball(0.05, (x + 0.06, y, 0.16), C.M("#d9a066"), seg=8)
        C.ball(0.035, (x + 0.12, y, 0.2), C.M("#c98b52"), seg=8)
    for k, col in enumerate(["#d95561", "#3f7fcf", "#f2c14e"]):
        C.cyl(0.22, 0.02, 0.35, (1.2 + k * 0.4, 2.6 - (k % 2) * 0.3, 0.2), C.M(col), verts=6, bevel=0.01)
    oasis = (0.2, 0.3, 1.4)
    scatter(rng, 300, (-2.05, 2.05, -3.0, 3.0), 0.3, ([], [(-1.3, 2.3, 0.9), (1.6, 2.4, 0.6)], [(-1.4, 0.0, -2.7, -2.3)]),
            lambda x, y: palm(x, y, rng.uniform(2.0, 2.7), C.M(rng.choice(["#4fa35a", "#3f9450", "#63b36a"])), P.trunk,
                              lean=rng.uniform(-1, 1)) if math.hypot(x - 0.2, (y - 0.3) / 1.3) < 1.6 or rng.random() < 0.25
            else C.ball(0.1, (x, y, 0.04), C.M("#c9a46a"), scale=(1.4, 1, 0.4), seg=8),
            gap=0.45)
    C.export(out(T, "centre"))
    lot(T, "#f6dcb0", "#c98b52", "#7fb35a", "#8a5a3c")
    frame(T, "#d09a62", "#a8744a")
    island(T, "#d9a066", "#b9834f", grass="#f2c98f")


# ================================================================ city

def city():
    T = "city"
    P = Pal(glass=("#9fd3ff", 0.3), white="#ffffff", grey="#9aa3b5", dark="#5c6486", green="#7fca62", leaf="#5fae55",
            trunk="#8a5a3c", path="#e9e2d3", water=("#6fc6e8", 0.25), road="#6b7391")
    walls = ["#e8775f", "#f2e8d8", "#c9d3e6"]
    roofs = ["#9aa3b5", "#d95561", "#5f86c9"]
    for v in range(3):
        P._cols["wl"], P._cols["rf"] = walls[v], roofs[v]
        # L1: a corner shop with a striped awning
        C.reset()
        C.rbox((0.62, 0.62, 0.02), (0, 0, 0.01), P.path, r=0.02)
        C.rbox((0.4, 0.34, 0.24), (0, 0.06, 0.12), P.wl, r=0.02)
        C.flat_roof(0.4, 0.34, 0.24, P.rf, P.white, cy=0.06)
        C.awning_stripes("front", 0.4, 0.34, 0, 0.17, 0.34, C.M("#ff5d73"), P.white, cy=0.06)
        C.rbox((0.08, 0.08, 0.06), (0.1, 0.12, 0.3), P.grey, r=0.01)
        C.tree(-0.24, -0.22, 1.0, P.leaf, P.trunk)
        C.export(out(T, "b_l1_v%d" % v))
        # L2: a brownstone with a rooftop garden
        C.reset()
        C.rbox((0.66, 0.66, 0.02), (0, 0, 0.01), P.path, r=0.02)
        C.rbox((0.48, 0.4, 0.42), (0, 0.04, 0.21), P.wl, r=0.02)
        C.flat_roof(0.48, 0.4, 0.42, P.rf, P.white, cy=0.04)
        C.rbox((0.22, 0.16, 0.03), (-0.08, 0.06, 0.48), P.green, r=0.01)
        C.bush(-0.12, 0.06, 1.0, P.leaf)
        C.bush(0.0, 0.08, 0.9, P.leaf, flowers=C.M("#ff8fb1"))
        C.rbox((0.1, 0.1, 0.08), (0.14, 0.12, 0.5), P.grey, r=0.01)
        windows_around(0.48, 0.4, 0.08, 0.38, 2, P.glass, P.white)
        C.export(out(T, "b_l2_v%d" % v))
        # L3: an apartment block with water tank and solar panels
        C.reset()
        C.rbox((0.7, 0.7, 0.02), (0, 0, 0.01), P.path, r=0.02)
        C.rbox((0.56, 0.48, 0.62), (0, 0.02, 0.31), P.wl, r=0.02)
        C.flat_roof(0.56, 0.48, 0.62, P.rf, P.white, cy=0.02)
        C.cyl(0.07, 0.07, 0.12, (0.15, 0.1, 0.74), C.M("#a86b45"), verts=14)
        C.cone_roof(0.07, 0.05, 0.8, C.M("#a86b45"), cx=0.15, cy=0.1)
        for k in range(3):
            C.rbox((0.1, 0.16, 0.012), (-0.18 + k * 0.11, -0.06, 0.69), C.M("#3f5fa8"), r=0.004, rot=(0.25, 0, 0))
        windows_around(0.56, 0.48, 0.08, 0.58, 3, P.glass, P.white, cols=3)
        C.export(out(T, "b_l3_v%d" % v))
        # L4: an office tower with a setback crown
        C.reset()
        C.rbox((0.72, 0.72, 0.02), (0, 0, 0.01), P.path, r=0.02)
        C.rbox((0.5, 0.5, 0.8), (0, 0, 0.4), P.wl, r=0.02)
        C.rbox((0.36, 0.36, 0.14), (0, 0, 0.87), C.M(walls[(v + 1) % 3]), r=0.02)
        C.flat_roof(0.36, 0.36, 0.94, P.rf, P.white)
        C.cyl(0.06, 0.06, 0.02, (0, 0, 1.0), C.M("#ffd166"), verts=16)
        windows_around(0.5, 0.5, 0.08, 0.76, 4, P.glass, P.white, cols=3)
        C.export(out(T, "b_l4_v%d" % v))
    # L5: a domed museum, a stadium, a clock tower
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.path, r=0.03)
    C.rbox((0.64, 0.5, 0.36), (0, 0.06, 0.2), P.white, r=0.03)
    C.cyl(0.18, 0.18, 0.1, (0, 0.06, 0.43), P.white, verts=28)
    C.ball(0.18, (0, 0.06, 0.48), C.M("#5fae8b"), scale=(1, 1, 1.1))
    for x in (-0.24, -0.08, 0.08, 0.24):
        C.cyl(0.025, 0.025, 0.3, (x, -0.22, 0.17), P.white, verts=12)
    C.rbox((0.64, 0.08, 0.04), (0, -0.22, 0.34), P.white, r=0.01)
    C.export(out(T, "b_l5_v0"))
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.path, r=0.03)
    C.cyl(0.36, 0.33, 0.3, (0, 0, 0.17), C.M("#e8eef8"), verts=36)
    C.cyl(0.26, 0.26, 0.02, (0, 0, 0.33), P.green, verts=36)
    C.rbox((0.2, 0.12, 0.004), (0, 0, 0.345), P.white, r=0.002)
    C.torus(0.34, 0.025, (0, 0, 0.34), C.M("#ff5d73"))
    C.export(out(T, "b_l5_v1"))
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.path, r=0.03)
    C.rbox((0.3, 0.3, 1.1), (0, 0, 0.55), C.M("#e8775f"), r=0.02)
    C.rbox((0.34, 0.34, 0.2), (0, 0, 1.0), P.white, r=0.02)
    C.hip(0.3, 0.3, 0.26, 1.1, C.M("#5fae8b"))
    for f in ("front", "left", "right", "back"):
        C.cyl(0.08, 0.08, 0.02, C._at(f, 0.34, 0.34, 0, 1.0, 0.012), C.M("#fff8e6"), verts=24,
              rot=(math.pi / 2, 0, 0) if f in ("front", "back") else (0, math.pi / 2, 0))
    C.export(out(T, "b_l5_v2"))
    # Centrepiece: a city park with a lake, bridges, a bandstand and tree-lined avenues
    C.reset()
    rng = random.Random(4)
    C.rbox((INNER_W, INNER_H, 0.04), (0, 0, 0.02), P.green, r=0.08)
    for k in range(2):
        C.rbox((INNER_W - 0.3, 0.32, 0.012), (0, -2.0 + k * 4.0, 0.046), P.path, r=0.08)
        C.rbox((0.32, INNER_H - 0.3, 0.012), (-1.6 + k * 3.2, 0, 0.046), P.path, r=0.08)
    C.ball(1.0, (0, 0.2, 0.0), P.water, scale=(1.0, 1.45, 0.05), seg=40)
    C.ball(1.08, (0, 0.2, -0.004), P.path, scale=(1.0, 1.45, 0.045), seg=40)
    for y in (-0.6, 1.0):
        C.rbox((1.0, 0.16, 0.04), (0, y, 0.09), C.M("#c98b52"), r=0.02)
        C.rbox((1.0, 0.02, 0.06), (0, y - 0.08, 0.12), P.white, r=0.006)
        C.rbox((1.0, 0.02, 0.06), (0, y + 0.08, 0.12), P.white, r=0.006)
    C.cyl(0.3, 0.3, 0.06, (0, -2.6, 0.06), P.white, verts=8)
    C.cone_roof(0.28, 0.2, 0.3, C.M("#ff5d73"), cy=-2.6)
    for k in range(8):
        a = k * math.tau / 8
        C.cyl(0.015, 0.015, 0.24, (math.cos(a) * 0.24, -2.6 + math.sin(a) * 0.24, 0.18), P.white, verts=8)
    C.cyl(0.3, 0.3, 0.08, (0, 2.6, 0.06), P.path, verts=24)
    C.cyl(0.22, 0.22, 0.03, (0, 2.6, 0.11), P.water, verts=24)
    C.cyl(0.05, 0.04, 0.2, (0, 2.6, 0.2), P.white, verts=12)
    for x in (-1.6, 1.6):
        for k in range(9):
            C.tree(x - 0.28 if x < 0 else x + 0.28, -3.0 + k * 0.75, 2.2, C.M(rng.choice(["#5fae55", "#73c35a"])), P.trunk)
    scatter(rng, 300, (-1.2, 1.2, -3.0, 3.0), 0.3, ([(None, -2.0), (None, 2.0)], [(0, 0.2, 1.3), (0, -2.6, 0.4), (0, 2.6, 0.35)],
            []), lambda x, y: C.tree(x, y, rng.uniform(2.2, 3.0), C.M(rng.choice(["#5fae55", "#73c35a", "#4f9e4c"])), P.trunk),
            gap=0.45)
    C.export(out(T, "centre"))
    lot(T, "#9ad57a", "#ffffff", "#5fae55", "#6b7391")
    frame(T, "#7d86a8", "#5c6486")
    island(T, "#a07a5a", "#8a8f9f", grass="#7fc35f")


# ================================================================ big city

def metro():
    T = "metro"
    P = Pal(glass=("#7fb3e6", 0.25), glass2=("#9fd0f0", 0.25), white="#f4f6fb", steel="#8a93ad", dark="#3b4260",
            green="#7fca62", leaf="#4f9e4c", trunk="#7a5a3c", plaza="#dfe3ec", water=("#6fc6e8", 0.25),
            heli="#ffd166", red="#ff5d73")
    bodies = ["#dfe6f2", "#c9d3e6", "#e8e2d6"]
    for v in range(3):
        P._cols["wl"] = bodies[v]
        # L1: a glass-fronted cafe with a rooftop umbrella
        C.reset()
        C.rbox((0.64, 0.64, 0.02), (0, 0, 0.01), P.plaza, r=0.02)
        C.rbox((0.44, 0.38, 0.26), (0, 0.06, 0.13), P.wl, r=0.02)
        C.rbox((0.4, 0.02, 0.18), (0, -0.135, 0.11), P.glass, r=0.005)
        C.flat_roof(0.44, 0.38, 0.26, P.steel, P.white, cy=0.06)
        C.cyl(0.1, 0.0, 0.06, (-0.08, 0.1, 0.36), C.M(["#ff5d73", "#ffd166", "#3ddc97"][v]), verts=8, bevel=0.005)
        C.cyl(0.006, 0.006, 0.08, (-0.08, 0.1, 0.32), P.dark, verts=6)
        C.tree(0.24, -0.22, 0.9, P.leaf, P.trunk)
        C.export(out(T, "b_l1_v%d" % v))
        # L2: a mid-rise with balconies
        C.reset()
        C.rbox((0.66, 0.66, 0.02), (0, 0, 0.01), P.plaza, r=0.02)
        C.rbox((0.48, 0.44, 0.6), (0, 0.04, 0.3), P.wl, r=0.02)
        C.flat_roof(0.48, 0.44, 0.6, P.steel, P.white, cy=0.04)
        for z in (0.2, 0.36, 0.52):
            C.rbox((0.4, 0.06, 0.02), (0, -0.21, z), P.white, r=0.006)
        windows_around(0.48, 0.44, 0.1, 0.56, 3, P.glass, P.white, cols=3)
        C.rbox((0.14, 0.12, 0.06), (0.1, 0.1, 0.66), P.steel, r=0.01)
        C.export(out(T, "b_l2_v%d" % v))
        # L3: a glass tower
        C.reset()
        C.rbox((0.7, 0.7, 0.02), (0, 0, 0.01), P.plaza, r=0.02)
        C.rbox((0.5, 0.5, 0.95), (0, 0, 0.475), P.glass, r=0.03)
        for z in [0.12 + k * 0.12 for k in range(7)]:
            C.rbox((0.52, 0.52, 0.018), (0, 0, z), P.wl, r=0.006)
        C.flat_roof(0.5, 0.5, 0.95, P.steel, P.white)
        C.rbox((0.16, 0.16, 0.08), (0.1, -0.1, 1.04), P.steel, r=0.01)
        C.export(out(T, "b_l3_v%d" % v))
        # L4: a skyscraper with a helipad
        C.reset()
        C.rbox((0.72, 0.72, 0.02), (0, 0, 0.01), P.plaza, r=0.02)
        C.rbox((0.56, 0.56, 0.5), (0, 0, 0.25), P.wl, r=0.03)
        C.rbox((0.46, 0.46, 0.8), (0, 0, 0.9), P.glass2 if v != 1 else P.glass, r=0.03)
        for z in [0.6 + k * 0.13 for k in range(6)]:
            C.rbox((0.48, 0.48, 0.016), (0, 0, z), P.wl, r=0.006)
        C.cyl(0.2, 0.2, 0.04, (0, 0, 1.32), P.dark, verts=28)
        C.torus(0.16, 0.012, (0, 0, 1.345), P.heli)
        C.rbox((0.04, 0.16, 0.006), (-0.04, 0, 1.345), P.white, r=0.002)
        C.rbox((0.04, 0.16, 0.006), (0.04, 0, 1.345), P.white, r=0.002)
        C.rbox((0.08, 0.04, 0.006), (0, 0, 1.345), P.white, r=0.002)
        windows_around(0.56, 0.56, 0.08, 0.46, 2, P.glass, P.white, cols=3)
        C.export(out(T, "b_l4_v%d" % v))
    # L5: a spire, twin towers with a sky bridge, an opera house
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.plaza, r=0.03)
    for k, (s, h) in enumerate(((0.5, 0.5), (0.4, 0.5), (0.3, 0.45), (0.2, 0.35))):
        z0 = sum(hh for _, hh in ((0.5, 0.5), (0.4, 0.5), (0.3, 0.45), (0.2, 0.35))[:k])
        C.rbox((s, s, h), (0, 0, z0 + h / 2), P.glass if k % 2 == 0 else P.white, r=0.02)
    C.cyl(0.03, 0.005, 0.4, (0, 0, 1.98), P.steel, verts=8)
    C.ball(0.03, (0, 0, 2.2), C.M("#ff5d73", 0.4, 0, 3.0), seg=8)
    C.export(out(T, "b_l5_v0"))
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.plaza, r=0.03)
    for x in (-0.18, 0.18):
        C.rbox((0.24, 0.3, 1.5), (x, 0, 0.75), P.glass2, r=0.03)
        for z in [0.15 + k * 0.15 for k in range(9)]:
            C.rbox((0.26, 0.32, 0.016), (x, 0, z), P.white, r=0.006)
        C.cyl(0.04, 0.0, 0.25, (x, 0, 1.62), P.steel, verts=8)
    C.rbox((0.16, 0.18, 0.08), (0, 0, 0.95), P.white, r=0.02)
    C.export(out(T, "b_l5_v1"))
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), C.M("#e9f1f8"), r=0.03)
    for k in range(4):
        C.ball(0.26 - k * 0.03, (-0.2 + k * 0.13, 0.04, 0.05), P.white, scale=(0.8, 1.2, 1.4 - k * 0.15), seg=16)
    C.rbox((0.7, 0.5, 0.04), (0, 0.04, 0.03), C.M("#c9d3e6"), r=0.02)
    C.export(out(T, "b_l5_v2"))
    # Centrepiece: a grand plaza with a stadium, fountain, towers and boulevards
    C.reset()
    rng = random.Random(5)
    C.rbox((INNER_W, INNER_H, 0.04), (0, 0, 0.02), P.plaza, r=0.08)
    C.rbox((INNER_W - 0.2, 0.36, 0.012), (0, 0, 0.046), C.M("#6b7391"), r=0.04)
    C.rbox((0.36, INNER_H - 0.2, 0.012), (0, 0, 0.046), C.M("#6b7391"), r=0.04)
    for k in range(9):
        C.rbox((0.1, 0.02, 0.004), (-2.0 + k * 0.5, 0, 0.054), P.white, r=0.002)
    C.cyl(0.62, 0.62, 0.05, (0, 0, 0.07), P.white, verts=40)
    C.cyl(0.5, 0.5, 0.04, (0, 0, 0.1), P.water, verts=40)
    C.cyl(0.12, 0.08, 0.3, (0, 0, 0.25), P.white, verts=16)
    # stadium, top
    C.cyl(1.0, 0.95, 0.4, (0, 2.1, 0.22), C.M("#e8eef8"), verts=48)
    C.ball(0.78, (0, 2.1, 0.42), P.green, scale=(1, 0.75, 0.01), seg=32)
    C.torus(0.98, 0.04, (0, 2.1, 0.42), P.red)
    # tower cluster, bottom corners
    for (x, y, h, col) in ((-1.5, -2.4, 1.6, "#7fb3e6"), (-1.0, -2.8, 1.1, "#9fd0f0"), (1.4, -2.3, 1.9, "#7fb3e6"),
                           (1.75, -1.6, 1.2, "#c9d3e6")):
        C.rbox((0.42, 0.42, h), (x, y, h / 2), C.M(col, 0.25), r=0.03)
        C.flat_roof(0.42, 0.42, h, P.steel, P.white, cx=x, cy=y)
    # tree-lined boulevards
    for k in range(12):
        y = -3.1 + k * 0.56
        if abs(y) < 0.7 or (y > 1.0) or y < -1.6:
            continue
        for x in (-0.45, 0.45):
            C.tree(x, y, 1.8, P.leaf, P.trunk)
    scatter(rng, 200, (-2.0, 2.0, -1.4, 1.0), 0.28, ([(0, None), (None, 0)], [(0, 0, 0.9)], []),
            lambda x, y: C.tree(x, y, rng.uniform(1.8, 2.4), C.M(rng.choice(["#4f9e4c", "#5fae55"])), P.trunk), gap=0.45)
    C.export(out(T, "centre"))
    lot(T, "#cdd5e4", "#f4f6fb", "#5fae55", "#3b4260")
    frame(T, "#4b5375", "#343b58")
    island(T, "#7a6a5a", "#5c6178", grass="#6fbf5a")


# ================================================================ future city

def future():
    T = "future"
    P = Pal(white="#f4f8ff", pearl="#e3ecfb", teal="#4fd1c5", violet="#8e6ce0", pink="#ff7ab8", dark="#2d3263",
            glow=("#7ff3ff", 0.3, 0.0, 3.0), glowp=("#ff9be0", 0.3, 0.0, 3.0), glass=("#bfe7ff", 0.15),
            green="#7fe0b4", leaf="#3fcf9a", ground="#dfe9fb", water=("#7fe0ff", 0.1))
    accents = ["#4fd1c5", "#8e6ce0", "#ff7ab8"]
    for v in range(3):
        P._cols["ac"] = accents[v]
        # L1: a pod house with a glowing ring
        C.reset()
        C.rbox((0.62, 0.62, 0.02), (0, 0, 0.01), P.ground, r=0.02)
        C.ball(0.2, (0, 0.04, 0.12), P.white, scale=(1, 1, 0.75))
        C.torus(0.2, 0.012, (0, 0.04, 0.1), P.glow)
        C.ball(0.07, (0, 0.04, 0.27), P.glass, seg=12)
        C.cyl(0.05, 0.05, 0.02, (0.22, -0.22, 0.02), P.ac, verts=16)
        C.export(out(T, "b_l1_v%d" % v))
        # L2: twin domes linked by a tube
        C.reset()
        C.rbox((0.66, 0.66, 0.02), (0, 0, 0.01), P.ground, r=0.02)
        for x in (-0.16, 0.16):
            C.cyl(0.15, 0.15, 0.16, (x, 0.04, 0.09), P.pearl, verts=28)
            C.ball(0.15, (x, 0.04, 0.17), P.glass, scale=(1, 1, 0.8))
        C.cyl(0.04, 0.04, 0.2, (0, 0.04, 0.12), P.white, verts=12, rot=(0, math.pi / 2, 0))
        C.torus(0.155, 0.01, (-0.16, 0.04, 0.17), P.glow)
        C.torus(0.155, 0.01, (0.16, 0.04, 0.17), P.glow)
        C.bush(0.0, -0.22, 1.2, P.leaf)
        C.export(out(T, "b_l2_v%d" % v))
        # L3: a tiered tower with sky gardens
        C.reset()
        C.rbox((0.7, 0.7, 0.02), (0, 0, 0.01), P.ground, r=0.02)
        for k, (r, h) in enumerate(((0.28, 0.25), (0.23, 0.25), (0.18, 0.25))):
            z = 0.02 + k * 0.27
            C.cyl(r, r - 0.02, h, (0, 0, z + h / 2), P.white, verts=32)
            C.cyl(r + 0.02, r + 0.02, 0.025, (0, 0, z + h), P.green, verts=32)
            C.torus(r - 0.005, 0.008, (0, 0, z + h * 0.5), P.glow)
        C.ball(0.1, (0, 0, 0.86), P.ac, scale=(1, 1, 0.6))
        C.export(out(T, "b_l3_v%d" % v))
        # L4: a twisting glass spire
        C.reset()
        C.rbox((0.72, 0.72, 0.02), (0, 0, 0.01), P.ground, r=0.02)
        for k in range(8):
            C.rbox((0.42 - k * 0.02, 0.42 - k * 0.02, 0.15), (0, 0, 0.08 + k * 0.15), P.glass if k % 2 else P.white,
                   r=0.03, rot=(0, 0, k * 0.12))
        C.cyl(0.02, 0.005, 0.3, (0, 0, 1.38), P.white, verts=8)
        C.ball(0.03, (0, 0, 1.52), P.glowp if v == 2 else P.glow, seg=8)
        C.export(out(T, "b_l4_v%d" % v))
    # L5: a holo-ring tower, a sky dome, a launch pad
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.ground, r=0.03)
    C.cyl(0.14, 0.08, 1.6, (0, 0, 0.82), P.white, verts=24)
    for k, z in enumerate((0.6, 1.0, 1.4)):
        C.torus(0.3 - k * 0.06, 0.018, (0, 0, z), P.glow if k != 1 else P.glowp)
    C.ball(0.1, (0, 0, 1.66), P.glass, seg=14)
    C.export(out(T, "b_l5_v0"))
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.ground, r=0.03)
    C.cyl(0.34, 0.34, 0.06, (0, 0, 0.05), P.white, verts=40)
    C.ball(0.32, (0, 0, 0.08), P.glass, scale=(1, 1, 0.9))
    C.ball(0.16, (0, 0, 0.1), P.leaf, scale=(1, 1, 0.8))
    C.torus(0.33, 0.015, (0, 0, 0.1), P.glow)
    C.export(out(T, "b_l5_v1"))
    C.reset()
    C.rbox((0.76, 0.76, 0.04), (0, 0, 0.02), P.ground, r=0.03)
    C.cyl(0.32, 0.32, 0.05, (0, 0, 0.045), P.dark, verts=6)
    C.torus(0.26, 0.015, (0, 0, 0.075), P.glowp)
    C.cyl(0.07, 0.09, 0.8, (0, 0, 0.5), P.white, verts=20)
    C.cyl(0.09, 0.0, 0.2, (0, 0, 1.0), C.M("#ff5d73"), verts=20)
    for k in range(3):
        a = k * math.tau / 3
        C.rbox((0.03, 0.12, 0.2), (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.18), C.M("#ff5d73"), r=0.01, rot=(0, 0, a))
    C.export(out(T, "b_l5_v2"))
    # Centrepiece: a hover plaza with a holo tower, a maglev loop and glowing gardens
    C.reset()
    rng = random.Random(6)
    C.rbox((INNER_W, INNER_H, 0.04), (0, 0, 0.02), P.ground, r=0.08)
    C.cyl(1.4, 1.4, 0.03, (0, 0, 0.055), P.pearl, verts=64)
    C.torus(1.4, 0.03, (0, 0, 0.07), P.glow)
    C.torus(0.9, 0.025, (0, 0, 0.07), P.glowp)
    C.cyl(0.55, 0.55, 0.04, (0, 0, 0.08), P.water, verts=48)
    # maglev loop around the plaza (oval)
    for k in range(48):
        a = k * math.tau / 48
        x, y = math.cos(a) * 1.85, math.sin(a) * 2.75
        nx, ny = math.cos(a + math.tau / 48) * 1.85, math.sin(a + math.tau / 48) * 2.75
        C.rbox((math.hypot(nx - x, ny - y) + 0.02, 0.1, 0.04), ((x + nx) / 2, (y + ny) / 2, 0.22), P.white, r=0.01,
               rot=(0, 0, math.atan2(ny - y, nx - x)))
        if k % 6 == 0:
            C.cyl(0.03, 0.03, 0.2, (x, y, 0.1), P.pearl, verts=8)
    C.rbox((0.5, 0.12, 0.08), (1.85, 0.3, 0.28), P.teal, r=0.04, rot=(0, 0, math.pi / 2))
    # gardens in the corners
    for (cx, cy) in ((-1.5, 2.6), (1.5, 2.6), (-1.5, -2.6), (1.5, -2.6)):
        C.cyl(0.45, 0.45, 0.04, (cx, cy, 0.06), P.green, verts=32)
        C.torus(0.45, 0.012, (cx, cy, 0.08), P.glow)
        for k in range(5):
            a = k * math.tau / 5
            C.ball(0.1, (cx + math.cos(a) * 0.22, cy + math.sin(a) * 0.22, 0.14), C.M(rng.choice(["#3fcf9a", "#4fd1c5"])),
                   seg=10)
        C.ball(0.14, (cx, cy, 0.18), C.M(rng.choice(["#ff7ab8", "#8e6ce0"])), seg=12)
    for (x, y) in ((-2.0, 0.0), (2.0, -1.2), (-2.0, -1.4), (2.0, 1.4), (-2.0, 1.4)):
        C.cyl(0.02, 0.02, 0.4, (x, y, 0.2), P.white, verts=8)
        C.ball(0.05, (x, y, 0.42), P.glow, seg=10)
    C.export(out(T, "centre"))
    lot(T, "#dfe9fb", "#4fd1c5", "#3fcf9a", "#2d3263")
    frame(T, "#2d3263", "#1d2147")
    island(T, "#3b4380", "#2a2f5a", grass="#7fe0b4")


# ================================================================ main

THEMES = {"town": town, "forest": forest, "desert": desert, "city": city, "metro": metro, "future": future}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build_tile()
    for name in (argv or list(THEMES)):
        THEMES[name]()
        print("built theme", name)
