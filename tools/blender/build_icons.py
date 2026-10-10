"""Renders Skyloop's 3D UI icons (coins, gems, gift, wheel, chests, trophy, XP star, crown)
as transparent PNGs into art/ui/icons3d/.

Run:  blender -b --factory-startup -P tools/blender/build_icons.py -- <project dir>
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import cute as C  # noqa: E402

ROOT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
OUT = os.path.join(ROOT, "art", "ui", "icons3d")
SIZE = 256


def gold():
    return C.M("#ffc23d", 0.25, metal=0.6)


def coin(x=0.0, y=0.0, z=0.0, tilt=0.35):
    g = gold()
    C.cyl(0.42, 0.42, 0.12, (x, y, z), g, verts=48, bevel=0.03, rot=(math.pi / 2 - tilt, 0, 0))
    C.cyl(0.32, 0.32, 0.13, (x, y - 0.005, z), C.M("#ffd970", 0.3, metal=0.5), verts=48, bevel=0.02,
          rot=(math.pi / 2 - tilt, 0, 0))
    # A raised star on the face.
    star = []
    for k in range(10):
        r = 0.18 if k % 2 == 0 else 0.08
        a = math.pi / 2 + k * math.pi / 5
        star.append((math.cos(a) * r, math.sin(a) * r))
    mesh = bpy.data.meshes.new("star")
    verts = [(x + px, y - 0.075, z + py) for px, py in star]
    mesh.from_pydata(verts, [], [list(range(10))])
    mesh.update()
    o = bpy.data.objects.new("star", mesh)
    bpy.context.collection.objects.link(o)
    sol = o.modifiers.new("s", "SOLIDIFY")
    sol.thickness = 0.04
    o.rotation_euler = (-tilt, 0, 0)
    C._add(o, C.M("#fff1b8", 0.3, metal=0.3), 0.01, 2)


def icon_coin():
    coin()


def icon_coins():
    for k in range(5):
        C.cyl(0.36, 0.36, 0.09, (0.18, 0.1, -0.5 + k * 0.095), gold(), verts=40, bevel=0.025)
    for k in range(3):
        C.cyl(0.32, 0.32, 0.09, (-0.32, 0.25, -0.5 + k * 0.095), gold(), verts=40, bevel=0.025)
    coin(-0.12, -0.25, -0.05, tilt=0.5)


def icon_gem():
    mesh = bpy.data.meshes.new("gem")
    top, mid, n = 0.25, 0.0, 8
    verts = [(0, 0, -0.6)]
    for k in range(n):
        a = k * math.tau / n
        verts.append((math.cos(a) * 0.55, math.sin(a) * 0.55, mid))
    for k in range(n):
        a = k * math.tau / n + math.pi / n
        verts.append((math.cos(a) * 0.32, math.sin(a) * 0.32, top))
    faces = []
    for k in range(n):
        faces.append((0, 1 + (k + 1) % n, 1 + k))
        faces.append((1 + k, 1 + (k + 1) % n, 1 + n + k))
        faces.append((1 + (k + 1) % n, 1 + n + (k + 1) % n, 1 + n + k))
    faces.append(tuple(1 + n + k for k in range(n)))
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = bpy.data.objects.new("gem", mesh)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(C.M("#38b6ff", 0.08, metal=0.1))
    C._parts.append(o)


def icon_gift():
    C.rbox((0.9, 0.9, 0.7), (0, 0, -0.25), C.M("#ff5d73", 0.5), r=0.08)
    C.rbox((1.0, 1.0, 0.22), (0, 0, 0.18), C.M("#ff7a8c", 0.5), r=0.08)
    rib = C.M("#ffc23d", 0.35, metal=0.4)
    C.rbox((0.18, 1.02, 0.95), (0, 0, -0.12), rib, r=0.03)
    C.rbox((1.02, 0.18, 0.95), (0, 0, -0.12), rib, r=0.03)
    for s in (-1, 1):
        C.torus(0.17, 0.06, (s * 0.17, 0, 0.42), rib, rot=(math.pi / 2, 0, s * 0.5))
    C.ball(0.09, (0, 0, 0.36), rib)


def icon_wheel():
    cols = ["#ff8a5c", "#38b6ff", "#8e6ce0", "#ffb21f", "#3ddc97", "#ff5d73", "#ffc23d", "#4f7fe0"]
    for k, c in enumerate(cols):
        a0 = k * math.tau / 8
        mesh = bpy.data.meshes.new("slice")
        verts = [(0, 0, 0)]
        for j in range(7):
            a = a0 + j * (math.tau / 8) / 6
            verts.append((math.cos(a) * 0.7, 0, math.sin(a) * 0.7))
        faces = [(0, j + 2, j + 1) for j in range(6)]
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        o = bpy.data.objects.new("slice", mesh)
        bpy.context.collection.objects.link(o)
        sol = o.modifiers.new("s", "SOLIDIFY")
        sol.thickness = 0.12
        C._add(o, C.M(c, 0.45), 0.0, weighted=False)
    C.torus(0.72, 0.07, (0, 0.06, 0), C.M("#ffffff", 0.4), rot=(math.pi / 2, 0, 0))
    for k in range(16):
        a = k * math.tau / 16
        C.ball(0.035, (math.cos(a) * 0.72, -0.02, math.sin(a) * 0.72), C.M("#fff4c4", 0.3, emit=2.0))
    C.cyl(0.16, 0.16, 0.2, (0, -0.06, 0), C.M("#ffc23d", 0.3, metal=0.5), verts=32, rot=(math.pi / 2, 0, 0))
    C.cone_roof(0.0, 0.0, 0.0, C.M("#ffffff", 0.3)) if False else None
    C.cyl(0.13, 0.0, 0.26, (0, -0.08, 0.9), C.M("#ff5d73", 0.4), verts=24, rot=(math.pi, 0, 0))


def chest(body, trim):
    C.rbox((1.1, 0.75, 0.6), (0, 0, -0.3), C.M(body, 0.5), r=0.07)
    C.cyl(0.38, 0.38, 1.1, (0, 0, 0.0), C.M(body, 0.5), verts=32, bevel=0.03, rot=(0, math.pi / 2, 0))
    t = C.M(trim, 0.3, metal=0.6)
    for x in (-0.45, 0.45):
        C.rbox((0.1, 0.8, 0.65), (x, 0, -0.28), t, r=0.03)
        C.torus(0.385, 0.045, (x, 0, 0.0), t, rot=(0, math.pi / 2, 0))
    C.rbox((1.14, 0.79, 0.08), (0, 0, -0.02), t, r=0.03)
    C.rbox((0.22, 0.1, 0.28), (0, -0.39, -0.1), t, r=0.05)
    C.ball(0.05, (0, -0.45, -0.12), C.M("#1d2340", 0.4))


def icon_chest_silver():
    chest("#8fa3c8", "#e8eef8")


def icon_chest_gold():
    chest("#ff9f43", "#ffd970")


def icon_trophy():
    g = gold()
    C.cyl(0.45, 0.2, 0.6, (0, 0, 0.15), g, verts=40, bevel=0.03)
    C.ball(0.2, (0, 0, -0.2), g, scale=(1, 1, 0.6))
    C.cyl(0.07, 0.09, 0.3, (0, 0, -0.38), g, verts=20)
    C.rbox((0.6, 0.45, 0.16), (0, 0, -0.6), C.M("#8e6ce0", 0.5), r=0.05)
    for s in (-1, 1):
        C.torus(0.17, 0.045, (s * 0.46, 0, 0.18), g, rot=(math.pi / 2, 0, 0))
    C.cyl(0.38, 0.38, 0.02, (0, 0, 0.45), C.M("#fff1b8", 0.3, metal=0.3), verts=40, bevel=0.0)


def icon_star():
    pts = []
    for k in range(10):
        r = 0.7 if k % 2 == 0 else 0.3
        a = math.pi / 2 + k * math.pi / 5
        pts.append((math.cos(a) * r, 0, math.sin(a) * r))
    mesh = bpy.data.meshes.new("star")
    mesh.from_pydata(pts, [], [list(range(10))])
    mesh.update()
    o = bpy.data.objects.new("star", mesh)
    bpy.context.collection.objects.link(o)
    sol = o.modifiers.new("s", "SOLIDIFY")
    sol.thickness = 0.25
    sol.offset = 0
    C._add(o, C.M("#a98bff", 0.35), 0.06, 3)


def icon_crown():
    g = gold()
    C.cyl(0.55, 0.55, 0.3, (0, 0, -0.35), g, verts=40, bevel=0.03)
    for k in range(5):
        a = k * math.tau / 5 + math.pi / 2
        x, y = math.cos(a) * 0.5, math.sin(a) * 0.5
        C.cyl(0.14, 0.0, 0.5, (x, y, 0.02), g, verts=16, bevel=0.01)
        C.ball(0.07, (x, y, 0.3), C.M("#ff5d73", 0.25))
    C.ball(0.09, (0, -0.56, -0.35), C.M("#38b6ff", 0.2))


ICONS = {
    "coin": icon_coin, "coins": icon_coins, "gem": icon_gem, "gift": icon_gift, "wheel": icon_wheel,
    "chest_silver": icon_chest_silver, "chest_gold": icon_chest_gold, "trophy": icon_trophy,
    "xp": icon_star, "crown": icon_crown,
}


def render(name, fn):
    C.reset()
    fn()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1.0, 0.95, 0.92, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    bpy.ops.object.light_add(type="AREA", location=(-2.0, -3.0, 3.0))
    key = bpy.context.active_object
    key.data.energy = 260
    key.data.size = 3.0
    key.rotation_euler = (math.radians(50), 0, math.radians(-35))
    bpy.ops.object.light_add(type="AREA", location=(3.0, -1.0, 1.0))
    rim = bpy.context.active_object
    rim.data.energy = 120
    rim.data.size = 2.0
    rim.rotation_euler = (math.radians(70), 0, math.radians(70))
    # Fit an orthographic camera to the parts.
    xs, ys, zs = [], [], []
    for p in C._parts:
        for corner in p.bound_box:
            w = p.matrix_world @ __import__("mathutils").Vector(corner)
            xs.append(w.x)
            ys.append(w.y)
            zs.append(w.z)
    cx, cz = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
    span = max(max(xs) - min(xs), max(zs) - min(zs)) * 1.18
    bpy.ops.object.camera_add(location=(cx + 1.4, -5.0, cz + 1.6),
                              rotation=(math.radians(73), 0, math.radians(16)))
    cam = bpy.context.active_object
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = span
    scene.camera = cam
    os.makedirs(OUT, exist_ok=True)
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("icon", name)


for n, f in ICONS.items():
    render(n, f)
