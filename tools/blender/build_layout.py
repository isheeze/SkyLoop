"""Skyloop board layout v4: the terraced floating island seen from the game camera.

Builds the exact geometry the painted board is traced from:
  - an island with three terraces (front, middle, back) and cliff walls,
  - one closed road with exactly 28 evenly spaced stepping stones,
  - an empty lot beside every property stone (buildings grow there in the game),
  - massing for the special landmarks and district set dressing,
and renders it from the fixed game camera. Also writes art/board/layout.json with every
stone's and lot's position and the camera, so the game lines its live pieces up exactly.

Run:  blender -b --factory-startup -P tools/blender/build_layout.py
Out:  art/board/layout_guide.png (clay render for the paint-over), art/board/layout.json
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cute as C  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "board")
STONES = 28

# Board order (core/board.gd): specials and which district each property belongs to.
SPECIAL = {0: "payday", 5: "metro", 7: "audit", 14: "jackpot", 19: "windfall", 21: "tax_raid", 25: "permit"}
DISTRICT = {1: 0, 2: 0, 3: 0, 4: 1, 6: 1, 8: 1, 9: 2, 10: 2, 11: 2, 12: 3, 13: 3, 15: 3, 16: 4, 17: 4, 18: 4,
            20: 5, 22: 5, 23: 5, 24: 6, 26: 6, 27: 6}

# The loop, in island coordinates (x right, y away from the camera), clockwise seen from above:
# start at the front centre-right, along the front to the docks, up the left side with an inward
# bend, across the back, down the right side with an inward bend, back to the start.
CONTROL = [(1.6, -6.6), (-1.0, -6.9), (-3.6, -6.4), (-5.3, -4.8), (-5.6, -2.6), (-4.4, -0.9), (-2.9, 0.2),
           (-3.4, 1.6), (-5.0, 2.8), (-5.0, 4.8), (-3.4, 6.3), (-0.8, 6.9), (1.8, 6.7), (4.0, 5.8), (5.3, 4.2),
           (5.0, 2.4), (3.2, 1.2), (2.9, -0.3), (4.4, -1.6), (5.5, -3.4), (5.0, -5.4), (3.6, -6.4)]


def height(x, y):
    """Terrace height: front 0, middle 1.3, back 2.6, with steep (cliff) steps between."""
    def step(a, b, t):
        t = max(0.0, min(1.0, (t - a) / (b - a)))
        return t * t * (3 - 2 * t)
    return 1.3 * step(-2.7, -2.1, y) + 1.3 * step(2.8, 3.4, y)


def catmull(pts, n):
    """Closed Catmull-Rom spline sampled densely."""
    out = []
    m = len(pts)
    for i in range(m):
        p0, p1, p2, p3 = (Vector(pts[(i + k - 1) % m]) for k in range(4))
        for s in range(n):
            t = s / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                              (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return out


def even_points(path, count):
    """`count` points spaced evenly by arc length along the closed path, with tangents."""
    seg = [(path[i], path[(i + 1) % len(path)]) for i in range(len(path))]
    lengths = [(b - a).length for a, b in seg]
    total = sum(lengths)
    out = []
    for k in range(count):
        target = total * k / count
        acc = 0.0
        for (a, b), L in zip(seg, lengths):
            if acc + L >= target:
                t = (target - acc) / max(L, 1e-6)
                p = a.lerp(b, t)
                out.append((p, (b - a).normalized()))
                break
            acc += L
    return out, total


def island_mesh():
    """Terrain grid inside a rounded outline, displaced into terraces; plus a rock underside."""
    res = 140
    rx, ry = 7.6, 9.0
    verts, faces, idx = [], [], {}
    for j in range(res + 1):
        for i in range(res + 1):
            x = -rx + 2 * rx * i / res
            y = -ry + 2 * ry * j / res
            if (abs(x) / rx) ** 2.6 + (abs(y) / ry) ** 2.6 > 1.0:
                continue
            idx[(i, j)] = len(verts)
            verts.append((x, y, height(x, y) + 0.02))
    for j in range(res):
        for i in range(res):
            q = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            if all(k in idx for k in q):
                faces.append([idx[k] for k in q])
    me = bpy.data.meshes.new("terrain")
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new("terrain", me)
    bpy.context.collection.objects.link(o)
    C._add(o, C.M("#8fd06a"), 0, weighted=False)
    # Cliff skirt and rock underside.
    C.rbox((rx * 1.8, ry * 1.8, 0.9), (0, 0, -0.47), C.M("#9a7356"), r=0.9, seg=4)
    for s, z in ((0.82, -1.3), (0.6, -2.2), (0.36, -3.0), (0.16, -3.6)):
        C.rbox((rx * 2 * s, ry * 2 * s, 0.9), (0, 0, z), C.M("#7d6a5c"), r=0.5, seg=3)


def build():
    C.reset()
    island_mesh()
    path = catmull(CONTROL, 40)
    stones, total = even_points(path, STONES)
    # Road ribbon under the stones.
    for k in range(len(path)):
        a, b = path[k], path[(k + 1) % len(path)]
        mid = (a + b) / 2
        d = b - a
        C.rbox((d.length + 0.05, 1.25, 0.06), (mid.x, mid.y, height(mid.x, mid.y) + 0.03), C.M("#a9adbb"),
               r=0.02, rot=(0, 0, math.atan2(d.y, d.x)))
    data = {"stones": [], "lots": {}, "camera": {}}
    centre = Vector((0, 0))
    for i, (p, t) in enumerate(stones):
        z = height(p.x, p.y)
        ang = math.atan2(t.y, t.x)
        special = i in SPECIAL
        C.rbox((0.92, 0.8, 0.14), (p.x, p.y, z + 0.1), C.M("#ffd98a" if special else "#eef0f6"), r=0.12, seg=3,
               rot=(0, 0, ang))
        data["stones"].append({"i": i, "x": round(p.x, 4), "y": round(p.y, 4), "z": round(z + 0.17, 4),
                               "dir": round(ang, 4), "special": SPECIAL.get(i, ""), "district": DISTRICT.get(i, -1)})
        if not special:
            # The lot sits beside the road on the outer side of the loop.
            n = Vector((t.y, -t.x))
            if (p + n).length < p.length:
                n = -n
            lot = p + n * 1.15
            lz = height(lot.x, lot.y)
            C.rbox((0.95, 0.95, 0.05), (lot.x, lot.y, lz + 0.03), C.M("#c9b48f"), r=0.1, seg=2, rot=(0, 0, ang))
            data["lots"][str(i)] = {"x": round(lot.x, 4), "y": round(lot.y, 4), "z": round(lz + 0.06, 4)}
    landmarks(stones)
    camera_and_light(data)
    return data


def landmarks(stones):
    """Rough massing for set pieces: enough for the paint-over to know what goes where."""
    def at(i):
        return stones[i][0]
    gold, stone, glass, water = C.M("#f2c14e"), C.M("#b9b2a6"), C.M("#bfe7ff"), C.M("#6fc6e8")
    # Payday: a start plaza in front of stone 0.
    p = at(0)
    C.rbox((2.4, 1.3, 0.08), (p.x, p.y - 1.1, 0.05), C.M("#e9dcc0"), r=0.1)
    # Metro: a rock arch with a tunnel over stone 5.
    p = at(5)
    C.ball(1.1, (p.x - 0.9, p.y, height(p.x, p.y) + 0.4), stone, scale=(0.8, 1.3, 1.0))
    # Jackpot: a raised fountain plaza behind stone 14.
    p = at(14)
    C.cyl(1.0, 1.0, 0.25, (p.x, p.y + 1.3, height(p.x, p.y) + 0.12), C.M("#e9dcc0"), verts=40)
    C.cyl(0.35, 0.25, 0.7, (p.x, p.y + 1.3, height(p.x, p.y) + 0.6), gold, verts=24)
    # Windfall: a vault door in the cliff beside stone 19.
    p = at(19)
    C.cyl(0.55, 0.55, 0.12, (p.x + 1.1, p.y, height(p.x, p.y) + 0.6), C.M("#9aa3b5"), verts=32, rot=(0, math.pi / 2, 0))
    # Centre: the dice fountain and the lake with a bridge.
    C.cyl(1.1, 1.1, 0.12, (0, 1.0, 0.95), C.M("#e9dcc0"), verts=48)
    C.cyl(0.7, 0.7, 0.1, (0, 1.0, 1.02), water, verts=40)
    C.ball(1.2, (0.3, -3.6, 0.0), water, scale=(1.4, 0.8, 0.05), seg=32)
    C.rbox((1.4, 0.4, 0.1), (0.3, -3.6, 0.15), C.M("#a0673f"), r=0.05)
    # District dressing: docks, greenhouses, stadium, bank, skyline.
    C.rbox((1.6, 1.2, 0.08), (-5.6, -6.6, 0.0), C.M("#a0673f"), r=0.04)
    for k in range(3):
        C.rbox((0.7, 0.5, 0.45), (-5.9 + k * 0.8, 6.4, 1.95), glass, r=0.05)
    C.cyl(1.2, 1.1, 0.5, (3.6, 7.0, 2.0), C.M("#e8eef8"), verts=48)
    C.rbox((1.0, 0.8, 0.7), (5.9, -1.0, 0.9 + 0.35), C.M("#f4f0e6"), r=0.04)
    for k, h in enumerate((1.6, 2.2, 1.3)):
        C.rbox((0.5, 0.5, h), (5.4 + k * 0.5, -6.0 + (k % 2) * 0.4, h / 2), C.M("#9fc3e6"), r=0.03)


def camera_and_light(data):
    cam = bpy.data.cameras.new("cam")
    cam.lens_unit = "FOV"
    cam.sensor_fit = "HORIZONTAL"
    cam.angle = math.radians(38.0)
    obj = bpy.data.objects.new("cam", cam)
    bpy.context.collection.objects.link(obj)
    # 50 degrees down, from the front, centred on the island.
    pitch = math.radians(54.0)
    dist = 24.5
    target = Vector((0, 0.4, 0.6))
    obj.location = target + Vector((0, -math.cos(pitch) * dist, math.sin(pitch) * dist))
    obj.rotation_euler = (math.radians(90) - pitch, 0, 0)
    bpy.context.scene.camera = obj
    sc = bpy.context.scene
    sc.render.resolution_x = 1536
    sc.render.resolution_y = 2048
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.0
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(40), math.radians(-25), math.radians(30))
    bpy.context.collection.objects.link(so)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.95, 0.8, 0.82, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sc.world = world
    data["camera"] = {"pos": [round(v, 4) for v in obj.location], "pitch_deg": 54.0, "hfov_deg": 38.0,
                      "target": [round(v, 4) for v in target], "aspect": [3, 4]}


def render(data):
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.view_settings.view_transform = "Standard"
    os.makedirs(OUT, exist_ok=True)
    sc.render.filepath = os.path.join(OUT, "layout_guide.png")
    bpy.ops.render.render(write_still=True)
    with open(os.path.join(OUT, "layout.json"), "w") as f:
        json.dump(data, f, indent=1)


if __name__ == "__main__":
    d = build()
    # Apply modifiers isn't needed for rendering; render straight away.
    render(d)
    print("layout written", len(d["stones"]), "stones")
