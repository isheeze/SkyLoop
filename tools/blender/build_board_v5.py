"""Board layout v5: the approved square loop, built exactly, rendered from the game camera.

28 spaces = 4 corners (0 Payday, 7 Audit, 14 Jackpot, 21 Tax raid) + 6 per side; Metro (5),
Windfall (19) and Permits (25) sit mid-side. Each of the 21 properties has one building plot
directly outside it. The render is the reference the painted board is traced from, and
art/boards/<id>/layout.json gives every space's, plot's and corner slot's exact position in the
image (0..1), so the game draws pieces and buildings exactly where the painting has them.

Run:  blender -b --factory-startup -P tools/blender/build_board_v5.py -- [--built] [--out NAME]
  --built   also put simple houses (player-colour roofs) on some plots: the mid-game mockup
"""
import json
import math
import os
import random
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cute as C  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
BUILT = "--built" in ARGS
NAME = ARGS[ARGS.index("--out") + 1] if "--out" in ARGS else ("layout_built" if BUILT else "layout_empty")
OUT = os.path.join(ROOT, "art", "boards", "v5")

PITCH = 1.0          # distance between neighbouring spaces
CORNER = 1.5         # corner pad size
EDGE = 3 * PITCH + CORNER / 2 + 0.05  # centre line of each side (3.8)
PLOT_OFF = 1.28      # plot centre distance outside its space
SPECIAL = {0: "payday", 5: "metro", 7: "audit", 14: "jackpot", 19: "windfall", 21: "tax_raid", 25: "permit"}
PLAYER_ROOFS = ["#ffc23d", "#ff5d73", "#3ddc97", "#5cc8ff"]


def space_pos(i):
    """Centre of space i and its outward direction. Front (camera side) is -Y; play runs from
    the front-right corner leftwards along the front, up the left, across the back, down the right."""
    k = i % 7
    off = (k - 3.5) * PITCH  # k = 1..6 -> -2.5..2.5
    if i == 0:
        return Vector((EDGE, -EDGE)), Vector((1, -1)).normalized()
    if i == 7:
        return Vector((-EDGE, -EDGE)), Vector((-1, -1)).normalized()
    if i == 14:
        return Vector((-EDGE, EDGE)), Vector((-1, 1)).normalized()
    if i == 21:
        return Vector((EDGE, EDGE)), Vector((1, 1)).normalized()
    if i < 7:
        return Vector((-off, -EDGE)), Vector((0, -1))
    if i < 14:
        return Vector((-EDGE, off)), Vector((-1, 0))
    if i < 21:
        return Vector((off, EDGE)), Vector((0, 1))
    return Vector((EDGE, -off)), Vector((1, 0))


def build():
    C.reset()
    grass, soil, rock = C.M("#86c95e"), C.M("#8f6a4b"), C.M("#7d6a5c")
    road, slab, gold = C.M("#b9b6bf"), C.M("#f6efe2"), C.M("#ffcf6b")
    plot, fence, water = C.M("#c8a26e"), C.M("#ffffff"), C.M("#69c3e8")
    half = EDGE + PLOT_OFF + 0.75
    # Island: a rounded grass slab with a soil band and a rock underside.
    C.rbox((half * 2, half * 2, 0.5), (0, 0, -0.25), grass, r=0.6, seg=4)
    C.rbox((half * 2 - 0.1, half * 2 - 0.1, 0.6), (0, 0, -0.75), soil, r=0.6, seg=3)
    for s, z in ((0.85, -1.4), (0.62, -2.1), (0.38, -2.8), (0.16, -3.4)):
        C.rbox((half * 2 * s, half * 2 * s, 0.8), (0, 0, z), rock, r=0.4, seg=3)
    # Road: a square ring under the spaces.
    w = 1.15
    for sx, sy, lx, ly in ((0, -EDGE, EDGE * 2 + w, w), (0, EDGE, EDGE * 2 + w, w),
                           (-EDGE, 0, w, EDGE * 2 + w), (EDGE, 0, w, EDGE * 2 + w)):
        C.rbox((lx, ly, 0.06), (sx, sy, 0.03), road, r=0.05)
    data = {"spaces": [], "plots": {}, "corners": {}}
    rng = random.Random(4)
    for i in range(28):
        p, out = space_pos(i)
        if i % 7 == 0:
            C.rbox((CORNER, CORNER, 0.16), (p.x, p.y, 0.1), gold, r=0.16, seg=3)
        else:
            C.rbox((0.84, 0.84, 0.14), (p.x, p.y, 0.09), gold if i in SPECIAL else slab, r=0.18, seg=3)
        data["spaces"].append({"i": i, "p": (p.x, p.y, 0.17), "special": SPECIAL.get(i, "")})
        if i in SPECIAL:
            continue
        q = p + out * PLOT_OFF
        C.rbox((0.86, 0.86, 0.05), (q.x, q.y, 0.025), plot, r=0.06)
        for a in range(4):
            ang = a * math.pi / 2
            d = Vector((math.cos(ang), math.sin(ang)))
            C.rbox((0.9 if a % 2 else 0.05, 0.05 if a % 2 else 0.9, 0.09),
                   (q.x + d.x * 0.45, q.y + d.y * 0.45, 0.07), fence, r=0.015)
        data["plots"][str(i)] = (q.x, q.y, 0.05)
        if BUILT and rng.random() < 0.55:
            lvl = rng.choice([1, 1, 2, 2, 3])
            roof = C.M(rng.choice(PLAYER_ROOFS))
            h = 0.22 + lvl * 0.16
            C.rbox((0.5, 0.45, h), (q.x, q.y, 0.05 + h / 2), C.M("#fff6e6"), r=0.04)
            C.hip(0.5, 0.45, 0.2, 0.05 + h, roof, cx=q.x, cy=q.y)
    # Corner landmarks on each corner's back half (placeholders the paint-over turns into art).
    for i, col in ((0, "#ffd34d"), (7, "#9aa3b5"), (14, "#f2c14e"), (21, "#d95561")):
        p, out = space_pos(i)
        back = p + out * 0.38
        C.rbox((0.7, 0.55, 0.55), (back.x, back.y, 0.45), C.M(col), r=0.08)
        data["corners"][str(i)] = {"slots": [tuple(p - out * 0.25 + Vector((dx, dy)) * 0.28) + (0.18,)
                                             for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1))]}
    # Centre park: pond, dice fountain, trees.
    C.rbox((5.0, 5.0, 0.04), (0, 0, 0.02), C.M("#9fd67a"), r=0.4)
    C.ball(1.0, (0.9, 0.7, 0.0), water, scale=(1.3, 0.9, 0.06), seg=28)
    C.cyl(0.6, 0.6, 0.12, (-0.6, -0.5, 0.06), C.M("#e9dcc0"), verts=32)
    C.cyl(0.42, 0.42, 0.1, (-0.6, -0.5, 0.12), water, verts=32)
    for k in range(14):
        x, y = rng.uniform(-2.1, 2.1), rng.uniform(-2.1, 2.1)
        if math.hypot(x - 0.9, y - 0.7) < 1.3 or math.hypot(x + 0.6, y + 0.5) < 0.9:
            continue
        C.tree(x, y, 2.2, C.M("#5fae55"), C.M("#8a5a3c"))
    return data


def camera(data):
    cam = bpy.data.cameras.new("cam")
    cam.lens_unit = "FOV"
    cam.sensor_fit = "VERTICAL"
    cam.angle = math.radians(40.0)
    obj = bpy.data.objects.new("cam", cam)
    bpy.context.collection.objects.link(obj)
    pitch = math.radians(52.0)
    dist = 27.0
    target = Vector((0, -0.6, -0.6))
    obj.location = target + Vector((0, -math.cos(pitch) * dist, math.sin(pitch) * dist))
    obj.rotation_euler = (math.radians(90) - pitch, 0, 0)
    sc = bpy.context.scene
    sc.camera = obj
    sc.render.resolution_x = 1536
    sc.render.resolution_y = 2048
    bpy.context.view_layer.update()

    def proj(p):
        v = world_to_camera_view(sc, obj, Vector(p))
        return [round(v.x, 5), round(1.0 - v.y, 5)]

    out = {"image": [1536, 2048], "spaces": [], "plots": {}, "corners": {}}
    for s in data["spaces"]:
        out["spaces"].append({"i": s["i"], "pos": proj(s["p"]), "special": s["special"]})
    for k, p in data["plots"].items():
        out["plots"][k] = proj(p)
    for k, c in data["corners"].items():
        out["corners"][k] = [proj(p) for p in c["slots"]]
    return out


def light_and_render(layout):
    sc = bpy.context.scene
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.2
    sun.angle = math.radians(10)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(42), math.radians(-20), math.radians(35))
    bpy.context.collection.objects.link(so)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.98, 0.84, 0.86, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    sc.world = world
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.view_settings.view_transform = "Standard"
    os.makedirs(OUT, exist_ok=True)
    sc.render.filepath = os.path.join(OUT, NAME + ".png")
    bpy.ops.render.render(write_still=True)
    with open(os.path.join(OUT, "layout.json"), "w") as f:
        json.dump(layout, f, indent=1)


if __name__ == "__main__":
    d = build()
    lay = camera(d)
    light_and_render(lay)
    print("v5 layout:", len(lay["spaces"]), "spaces,", len(lay["plots"]), "plots,", len(lay["corners"]), "corners")
