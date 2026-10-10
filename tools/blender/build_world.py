"""The floating island, ring road, centre park, corner props, tile lot and token (style v2).

Run:  blender -b --factory-startup -P tools/blender/build_world.py -- <project dir>

Board layout (Godot units, matching game3d/board3d.gd):
- tile centres at +-3.5, tiles span |x| 3.0..4.0 on each side;
- ring road between half-extents 2.42 and 2.98 (tokens drive on it);
- park inside 2.36; island top edge at 4.6.
"""
import math
import os
import random
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import cute as C  # noqa: E402

ROOT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
OUT = os.path.join(ROOT, "art", "models")
GOLD = "#f2c14e"


def superellipse(n_pts, half, power=5.0):
    """Points around a rounded square."""
    pts = []
    for i in range(n_pts):
        a = i * math.tau / n_pts
        c, s = math.cos(a), math.sin(a)
        r = (abs(c) ** power + abs(s) ** power) ** (-1.0 / power)
        pts.append((c * r * half, s * r * half))
    return pts


# ---------------------------------------------------------------- island

def island():
    C.reset()
    rnd = random.Random(3)
    grass, grass_dark = C.M("#7cc35b", 0.95), C.M("#69ad4e", 0.95)
    soils = [C.M("#a8784f", 0.95), C.M("#93653f", 0.95), C.M("#b4855a", 0.95), C.M("#8a5e3b", 0.95)]
    rock = C.M("#9b8f86", 0.95)
    rings = [(0.0, 1.0, 0), (-0.09, 1.012, 0), (-0.2, 1.0, 1), (-0.26, 0.99, 2), (-0.62, 0.975, 3),
             (-1.05, 0.9, 4), (-1.6, 0.76, 5), (-2.3, 0.56, 6), (-3.0, 0.34, 7), (-3.6, 0.14, 7), (-4.0, 0.02, 7)]
    mats = [grass, grass_dark, soils[0], soils[1], soils[2], soils[3], soils[0], rock]
    N = 80
    base = superellipse(N, 4.6)
    phase = [rnd.random() * math.tau for _ in range(4)]

    def wob(i, depth):
        a = i * math.tau / N
        k = min(1.0, max(0.0, (-depth - 0.25) / 0.6))
        return 1.0 + k * (0.035 * math.sin(a * 5 + phase[0]) + 0.025 * math.sin(a * 11 + phase[1])
                          + 0.02 * math.sin(a * 17 + phase[2]))

    mesh = bpy.data.meshes.new("island")
    bm = bmesh.new()
    vrings = []
    for z, sc, _ in rings:
        ring = []
        for i, (x, y) in enumerate(base):
            w = wob(i, z)
            zz = z + (0 if z > -0.3 else 0.06 * math.sin(i * 0.9 + phase[3]))
            ring.append(bm.verts.new((x * sc * w, y * sc * w, zz)))
        vrings.append(ring)
    for m in mats:
        mesh.materials.append(m)
    top = bm.faces.new(vrings[0])
    top.material_index = 0
    for r in range(len(rings) - 1):
        mi = rings[r][2] if r > 0 else 1
        for i in range(N):
            f = bm.faces.new((vrings[r][i], vrings[r][(i + 1) % N], vrings[r + 1][(i + 1) % N], vrings[r + 1][i]))
            f.material_index = mats.index(mats[mi])
    bottom = bm.faces.new(list(reversed(vrings[-1])))
    bottom.material_index = 7
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("island", mesh)
    bpy.context.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = True
    sub = obj.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    C._parts.append(obj)
    # Boulders on the underside and hanging roots.
    for k in range(26):
        a = rnd.random() * math.tau
        depth = rnd.uniform(-2.8, -0.5)
        sc = [s for z, s, _ in rings]
        frac = max(0.2, 1.0 - (-depth) / 4.2)
        r = 4.6 * frac * rnd.uniform(0.86, 0.96)
        C.ball(rnd.uniform(0.18, 0.42), (math.cos(a) * r, math.sin(a) * r, depth), rock if k % 3 else soils[1],
               scale=(1.0, 1.0, 0.75), seg=14)
    root = C.M("#6e4a32", 0.95)
    for k in range(18):
        a = rnd.random() * math.tau
        depth = rnd.uniform(-1.3, -0.4)
        frac = 1.0 - (-depth) / 4.6
        r = 4.6 * frac * 0.98
        x, y = math.cos(a) * r, math.sin(a) * r
        length = rnd.uniform(0.6, 1.6)
        curve = bpy.data.curves.new("root", "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = rnd.uniform(0.025, 0.045)
        curve.bevel_resolution = 2
        sp = curve.splines.new("BEZIER")
        sp.bezier_points.add(2)
        for j, bp in enumerate(sp.bezier_points):
            t = j / 2
            bp.co = (x * (1 + 0.02 * t), y * (1 + 0.02 * t), depth - length * t)
            bp.handle_left_type = bp.handle_right_type = "AUTO"
            bp.co.x += math.sin(j * 2.1 + k) * 0.08
        o = bpy.data.objects.new("root", curve)
        bpy.context.collection.objects.link(o)
        o.data.materials.append(root)
        C._parts.append(o)
    # Bushes, flowers and little fences around the rim, outside the tiles.
    leaf = C.M("#6dbb65", 0.9)
    for k in range(64):
        a = k * math.tau / 64 + rnd.uniform(-0.03, 0.03)
        p = superellipse(1, 1)  # unused, keeps API symmetric
        c, s = math.cos(a), math.sin(a)
        rr = (abs(c) ** 5 + abs(s) ** 5) ** (-0.2) * 4.35
        x, y = c * rr, s * rr
        if max(abs(x), abs(y)) < 4.15:
            continue
        flower = C.M(rnd.choice(["#ff8fab", "#ffd166", "#ffffff", "#c9a7ff"]), 0.8)
        C.bush(x, y, rnd.uniform(1.1, 1.6), leaf, flowers=flower if k % 2 else None)
    C.export(os.path.join(OUT, "island.glb"))
    print("island done")


# ---------------------------------------------------------------- road and park

def ring_mesh(name, outer, inner, z, mat, power=8.0, n=160, thick=0.0):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    o = superellipse(n, outer, power)
    i = superellipse(n, inner, power)
    vo = [bm.verts.new((x, y, z)) for x, y in o]
    vi = [bm.verts.new((x, y, z)) for x, y in i]
    for k in range(n):
        bm.faces.new((vo[k], vo[(k + 1) % n], vi[(k + 1) % n], vi[k]))
    if thick > 0:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    return C._add(ob, mat, 0, weighted=False)


def board():
    C.reset()
    rnd = random.Random(11)
    asphalt = C.M("#727892", 0.9)
    curb = C.M("#f1e8da", 0.85)
    paint = C.M("#fffaf0", 0.6)
    ring_mesh("road", 2.98, 2.42, 0.012, asphalt, thick=0.0)
    ring_mesh("curb_out", 3.0, 2.96, 0.03, curb, thick=0.03)
    ring_mesh("curb_in", 2.44, 2.38, 0.03, curb, thick=0.03)
    # Dashed centre line.
    n = 96
    for k in range(n):
        if k % 2:
            continue
        a = (k + 0.5) * math.tau / n
        c, s = math.cos(a), math.sin(a)
        r = (abs(c) ** 8 + abs(s) ** 8) ** (-1 / 8) * 2.7
        C.rbox((0.1, 0.022, 0.004), (c * r, s * r, 0.016), paint, r=0.002, rot=(0, 0, a + math.pi / 2))
    # Park: path loop, pond with stone rim, bridges, trees, flower beds, benches, gazebo, lamps.
    path = C.M("#f0dcb4", 0.95)
    ring_mesh("path", 1.75, 1.5, 0.018, path, power=4.0)
    for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
        C.rbox((0.26, 0.9, 0.012), (math.cos(a) * 1.95, math.sin(a) * 1.95, 0.014), path, r=0.004,
               rot=(0, 0, a + math.pi / 2))
    stone = C.M("#e9ddc9", 0.9)
    water = C.M("#72c7e8", 0.4, metal=0.0)
    for (x, y, r) in ((0.25, 0.1, 0.62), (-0.42, -0.25, 0.4)):
        C.cyl(r + 0.07, r + 0.07, 0.05, (x, y, 0.025), stone, verts=48)
        C.cyl(r, r, 0.054, (x, y, 0.03), water, verts=48, bevel=0.0)
    for (x, y, rot, span) in ((-0.12, -0.08, 0.6, 0.62), (0.82, 0.12, 0.0, 0.5)):
        _bridge(x, y, rot, C.M("#fffaf2", 0.8), C.M("#c98d5a", 0.85), span=span)
    leaves = [C.M(h, 0.9) for h in ("#78c460", "#6ab85a", "#8bd06e", "#5fae54")]
    trunk = C.M("#8a5a3c", 0.9)
    spots = [(-1.6, 1.6), (-1.2, 1.9), (1.7, 1.5), (1.95, 1.0), (-1.9, -1.4), (-1.5, -1.85), (1.55, -1.65),
             (1.95, -1.25), (-0.9, 1.3), (1.0, -1.15), (0.2, 1.25), (-1.25, 0.55), (-0.2, -1.3), (1.25, 0.95)]
    for (x, y) in spots:
        C.tree(x, y, rnd.uniform(1.6, 2.3), rnd.choice(leaves), trunk, kind="round")
    for (x, y) in ((-2.0, 0.4), (2.05, -0.2), (0.55, 1.95), (-0.6, -2.0)):
        C.tree(x, y, 1.5, leaves[1], trunk, kind="cone")
    bed = C.M("#7b5b45", 0.95)
    for (x, y, col) in ((-1.05, 1.05, "#ff8fab"), (1.15, -0.6, "#ffd166"), (-1.2, -0.95, "#c9a7ff"),
                        (0.95, 1.55, "#ff9f6e"), (-0.45, 1.75, "#ffffff")):
        hedge = C.M("#5fae54", 0.9)
        C.torus(0.17, 0.045, (x, y, 0.04), hedge)
        C.cyl(0.15, 0.15, 0.05, (x, y, 0.025), C.M("#6dbb65", 0.9), verts=24)
        fm = C.M(col, 0.8)
        for k in range(10):
            a = k * 0.63
            rr = 0.03 + (k % 3) * 0.04
            C.ball(0.034, (x + math.cos(a) * rr, y + math.sin(a) * rr, 0.075), fm, seg=10)
    wood = C.M("#c98d5a", 0.85)
    for (x, y, a) in ((1.62, 0.0, math.pi / 2), (-1.62, 0.1, -math.pi / 2), (0.0, 1.62, 0.0)):
        _bench(x, y, a, wood, C.M("#5b6178", 0.7))
    _gazebo(-1.35, 1.15, C.M("#fffaf2", 0.8), C.M("#e07a5f", 0.8))
    post, light = C.M("#4a4f6a", 0.6), C.M("#fff1b8", 0.3, emit=3.0)
    for k in range(8):
        a = k * math.tau / 8 + 0.4
        C.lamp(math.cos(a) * 2.2, math.sin(a) * 2.2, post, light)
    for k in range(5):
        C.ball(rnd.uniform(0.06, 0.11), (rnd.uniform(-2, 2), rnd.uniform(-2, 2), 0.02), C.M("#b5aca2", 0.95),
               scale=(1.2, 1.0, 0.7), seg=12)
    C.export(os.path.join(OUT, "board.glb"))
    print("board done")


def _bridge(x, y, rot, rail, deck, span=0.7, rise=0.13, width=0.2):
    """An arched footbridge: one smooth curved deck with continuous rails and posts."""
    n = 18

    def arch(t):
        # Parabolic arch from bank to bank, lifted slightly above the water.
        px = (t - 0.5) * span
        pz = 0.055 + rise * (1.0 - (2.0 * t - 1.0) ** 2)
        return px, pz

    def world(px, py, pz):
        return (x + px * math.cos(rot) - py * math.sin(rot), y + px * math.sin(rot) + py * math.cos(rot), pz)

    # Deck: a curved slab built as a strip of quads, then given thickness.
    mesh = bpy.data.meshes.new("bridge")
    bm = bmesh.new()
    rows = []
    for k in range(n + 1):
        px, pz = arch(k / n)
        rows.append([bm.verts.new(world(px, -width / 2, pz)), bm.verts.new(world(px, width / 2, pz))])
    for k in range(n):
        bm.faces.new((rows[k][0], rows[k + 1][0], rows[k + 1][1], rows[k][1]))
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.03)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new("bridge", mesh)
    bpy.context.collection.objects.link(ob)
    C._add(ob, deck, 0.006, 2)
    # Rails: smooth tubes following the arch, with posts every few steps.
    for side in (-1, 1):
        curve = bpy.data.curves.new("rail", "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = 0.011
        curve.bevel_resolution = 3
        sp = curve.splines.new("POLY")
        sp.points.add(n)
        for k in range(n + 1):
            px, pz = arch(k / n)
            wx, wy, wz = world(px, side * (width / 2 - 0.01), pz + 0.075)
            sp.points[k].co = (wx, wy, wz, 1.0)
        o = bpy.data.objects.new("rail", curve)
        bpy.context.collection.objects.link(o)
        o.data.materials.append(rail)
        C._parts.append(o)
        for k in range(0, n + 1, 3):
            px, pz = arch(k / n)
            C.cyl(0.011, 0.011, 0.08, world(px, side * (width / 2 - 0.01), pz + 0.035), rail, verts=8, bevel=0.003)


def _bench(x, y, a, wood, metal):
    C.rbox((0.22, 0.07, 0.02), (x, y, 0.06), wood, r=0.006, rot=(0, 0, a))
    dx, dy = math.cos(a), math.sin(a)
    C.rbox((0.22, 0.02, 0.06), (x - dy * 0.035, y + dx * 0.035, 0.1), wood, r=0.006, rot=(0, 0, a))
    for s in (-1, 1):
        C.rbox((0.015, 0.06, 0.05), (x + dx * 0.09 * s, y + dy * 0.09 * s, 0.025), metal, r=0.004, rot=(0, 0, a))


def _gazebo(x, y, wall, roof):
    C.cyl(0.24, 0.24, 0.05, (x, y, 0.025), wall, verts=6)
    for k in range(6):
        a = k * math.tau / 6
        C.cyl(0.015, 0.015, 0.22, (x + math.cos(a) * 0.2, y + math.sin(a) * 0.2, 0.16), wall, verts=10)
    C.cyl(0.29, 0.03, 0.17, (x, y, 0.355), roof, verts=6, bevel=0.015)
    C.ball(0.03, (x, y, 0.45), C.M(GOLD, 0.35, metal=0.6))


# ---------------------------------------------------------------- corners and specials

def corners():
    W = "#fffaf2"
    gold = C.M(GOLD, 0.3, metal=0.7)
    jobs = {}

    def payday():
        for (x, y, n) in ((-0.15, 0.05, 6), (0.08, -0.1, 4), (0.2, 0.15, 7), (-0.05, -0.25, 3)):
            for k in range(n):
                C.cyl(0.11, 0.11, 0.035, (x + (k % 2) * 0.008, y, 0.02 + k * 0.038), gold, verts=24, bevel=0.008)
        C.ball(0.05, (0.3, -0.25, 0.04), gold, scale=(1, 1, 0.4))
    jobs["payday"] = payday

    def audit():
        wall, roof = C.M("#f6ead8", 0.9), C.M("#6c7fa8", 0.8)
        C.rbox((0.6, 0.42, 0.3), (0, 0.05, 0.15), wall, r=0.03)
        C.hip(0.6, 0.42, 0.14, 0.3, roof, cy=0.05)
        C.rbox((0.16, 0.16, 0.28), (0, -0.05, 0.5), wall, r=0.02)
        C.cyl(0.05, 0.05, 0.02, (0, -0.135, 0.56), C.M(W, 0.7), verts=24, rot=(math.pi / 2, 0, 0))
        C.rbox((0.006, 0.01, 0.035), (0, -0.147, 0.575), C.M("#4a4f6a", 0.6), r=0.002)
        C.hip(0.16, 0.16, 0.12, 0.64, roof, cy=-0.05)
        for u in (-0.2, 0.2):
            C.window("front", 0.6, 0.42, u, 0.17, C.M(W, 0.7), C.M("#ffe9a8", 0.3, emit=0.6), cy=0.05)
        C.door("front", 0.6, 0.42, 0.0, C.M(W, 0.7), C.M("#e07a5f", 0.7), cy=0.05)
        C.cyl(0.006, 0.006, 0.3, (0.27, -0.12, 0.6), C.M("#4a4f6a", 0.6), verts=8)
        C.rbox((0.01, 0.12, 0.07), (0.27, -0.06, 0.71), C.M("#ff5d73", 0.7), r=0.006)
    jobs["audit"] = audit

    def jackpot():
        stone, water = C.M("#f1e8da", 0.85), C.M("#72c7e8", 0.1, metal=0.1)
        C.cyl(0.38, 0.4, 0.1, (0, 0, 0.05), stone, verts=40)
        C.cyl(0.33, 0.33, 0.104, (0, 0, 0.052), water, verts=40, bevel=0.0)
        C.cyl(0.07, 0.09, 0.28, (0, 0, 0.18), stone, verts=20)
        C.cyl(0.17, 0.12, 0.05, (0, 0, 0.33), stone, verts=28)
        C.cyl(0.14, 0.14, 0.052, (0, 0, 0.335), water, verts=28, bevel=0.0)
        C.ball(0.08, (0, 0, 0.42), gold)
        for k in range(8):
            a = k * math.tau / 8
            C.cyl(0.03, 0.03, 0.012, (math.cos(a) * 0.24, math.sin(a) * 0.24, 0.11), gold, verts=14)
    jobs["jackpot"] = jackpot

    def tax_raid():
        blue, white, red = C.M("#4f6fb8", 0.7), C.M(W, 0.7), C.M("#ff5d73", 0.6)
        C.rbox((0.2, 0.2, 0.36), (-0.15, 0.1, 0.18), blue, r=0.025)
        C.hip(0.2, 0.2, 0.08, 0.36, blue, cx=-0.15, cy=0.1)
        C.ball(0.03, (-0.15, 0.1, 0.48), C.M("#7fd0ff", 0.3, emit=3.0), seg=12)
        C.rbox((0.12, 0.02, 0.14), (-0.15, -0.005, 0.22), C.M("#ffe9a8", 0.3, emit=0.6), r=0.01)
        for x in (0.02, 0.38):
            C.rbox((0.05, 0.05, 0.2), (x, -0.15, 0.1), white, r=0.012)
        for k in range(6):
            C.rbox((0.065, 0.035, 0.05), (0.04 + k * 0.06, -0.15, 0.17), red if k % 2 == 0 else white, r=0.008)
    jobs["tax_raid"] = tax_raid

    def metro():
        teal, white = C.M("#37c2c9", 0.6), C.M(W, 0.75)
        rail = C.M("#8b93a3", 0.4, metal=0.6)
        for y in (-0.06, 0.06):
            C.rbox((0.86, 0.015, 0.015), (0, y, 0.01), rail, r=0.003)
        for k in range(7):
            C.rbox((0.03, 0.18, 0.01), (-0.36 + k * 0.12, 0, 0.005), C.M("#9b6a45", 0.9), r=0.002)
        C.rbox((0.42, 0.2, 0.16), (0.02, 0, 0.1), teal, r=0.05)
        for u in (-0.12, 0.0, 0.12):
            C.rbox((0.07, 0.205, 0.05), (0.02 + u, 0, 0.13), C.M("#ffe9a8", 0.3, emit=0.6), r=0.012)
        C.rbox((0.44, 0.04, 0.02), (0.02, 0.12, 0.19), white, r=0.008)
        for x in (-0.18, 0.22):
            C.cyl(0.012, 0.012, 0.2, (x, 0.2, 0.1), white, verts=8)
        C.rbox((0.5, 0.16, 0.025), (0.02, 0.2, 0.21), teal, r=0.012)
    jobs["metro"] = metro

    def windfall():
        C.tree(0, 0.05, 2.4, C.M(GOLD, 0.45, metal=0.3), C.M("#8a5a3c", 0.9))
        for k in range(6):
            a = k * 1.1
            C.cyl(0.05, 0.05, 0.015, (math.cos(a) * 0.25, -0.1 + math.sin(a) * 0.12, 0.008), gold, verts=16)
    jobs["windfall"] = windfall

    def permit():
        wall, roof = C.M("#e7f0fb", 0.9), C.M("#6f8cf0", 0.8)
        C.rbox((0.44, 0.34, 0.24), (0, 0.04, 0.12), wall, r=0.03)
        C.gable(0.44, 0.34, 0.14, 0.24, roof, fill=wall, cy=0.04)
        C.door("front", 0.44, 0.34, -0.1, C.M(W, 0.7), C.M("#ff8fab", 0.7), cy=0.04)
        C.window("front", 0.44, 0.34, 0.1, 0.14, C.M(W, 0.7), C.M("#ffe9a8", 0.3, emit=0.6), cy=0.04)
        C.rbox((0.12, 0.02, 0.07), (0.1, -0.14, 0.27), C.M("#ff5d73", 0.6), r=0.01)
    jobs["permit"] = permit

    for name, fn in jobs.items():
        C.reset()
        gold = C.M(GOLD, 0.3, metal=0.7)  # materials do not survive reset; the closures read this
        fn()
        C.export(os.path.join(OUT, "corner_%s.glb" % name))
    print("corners done")


def lot_and_token():
    C.reset()
    C.rbox((0.9, 0.9, 0.05), (0, 0, 0.025), C.M("#ffffff", 0.9), r=0.06)
    C.export(os.path.join(OUT, "lot.glb"))
    C.reset()
    m = C.M("#ffffff", 0.35)
    C.cyl(0.13, 0.14, 0.05, (0, 0, 0.025), m, verts=32, bevel=0.02)
    C.cyl(0.05, 0.1, 0.2, (0, 0, 0.15), m, verts=32, bevel=0.01)
    C.torus(0.06, 0.02, (0, 0, 0.25), m)
    C.ball(0.085, (0, 0, 0.33), m, seg=24)
    C.export(os.path.join(OUT, "token.glb"))
    print("lot and token done")


if "--only-corners" not in sys.argv:
    island()
    board()
corners()
lot_and_token()


def plot_and_sign():
    """Owned-but-unbuilt lot (a fenced garden plot) and the unowned "for sale" sign."""
    C.reset()
    C.rbox((0.56, 0.46, 0.03), (0, 0, 0.015), C.M("#86cf6a", 0.95), r=0.04)
    white = C.M("#fffaf2", 0.8)
    for side in (-1, 1):
        for k in range(6):
            C.rbox((0.018, 0.018, 0.08), (side * 0.27, -0.2 + k * 0.08, 0.055), white, r=0.005)
        C.rbox((0.014, 0.46, 0.016), (side * 0.27, 0, 0.075), white, r=0.004)
    for k in range(7):
        C.rbox((0.018, 0.018, 0.08), (-0.24 + k * 0.08, 0.22, 0.055), white, r=0.005)
    C.rbox((0.54, 0.014, 0.016), (0, 0.22, 0.075), white, r=0.004)
    leaf = C.M("#5fae54", 0.9)
    C.bush(-0.14, 0.08, 1.3, leaf, flowers=C.M("#ff8fab", 0.8))
    C.bush(0.13, 0.1, 1.1, leaf, flowers=C.M("#ffd166", 0.8))
    C.cyl(0.03, 0.03, 0.06, (0.0, -0.1, 0.03), C.M("#c98d5a", 0.85), verts=12)
    C.export(os.path.join(OUT, "plot.glb"))
    C.reset()
    wood = C.M("#c98d5a", 0.85)
    C.cyl(0.012, 0.014, 0.26, (0, 0, 0.13), wood, verts=10)
    C.rbox((0.2, 0.025, 0.11), (0, -0.012, 0.22), C.M("#fffaf2", 0.8), r=0.012)
    C.rbox((0.16, 0.03, 0.05), (0, -0.016, 0.22), C.M("#3ddc97", 0.6), r=0.008)
    C.export(os.path.join(OUT, "sale.glb"))
    print("plot and sign done")


if "--plot" in sys.argv:
    plot_and_sign()
