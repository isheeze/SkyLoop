"""Skyloop "toy diorama" kit (docs/STYLE_GUIDE.md): tile, buildings L1-L5, corner landmarks,
pawn, for-sale sign, centre fountain, tree. Writes art/toy/*.glb.

Run:  blender -b --factory-startup -P tools/blender/build_toy.py -- <project dir>

Conventions (match game3d/board3d.gd): 1 unit = 1 Godot unit, origin on the ground at the
footprint centre, front faces -Y (Godot +Z, toward the camera). Materials named Owner and Stripe
are recoloured by the game (owner's colour, district colour).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import cute as C  # noqa: E402

ROOT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
OUT = os.path.join(ROOT, "art", "toy")

CREAM, CREAM_EDGE = "#fbf1de", "#e9d6b4"
WALL, WALL_SHADE = "#fff4e2", "#f3e2c6"
GLASS, FRAME = "#9fd8ff", "#ffffff"
WOOD, WOOD_DARK = "#b9743f", "#8a5530"
GOLD = "#ffc531"
LEAF, LEAF2, TRUNK = "#5fbf45", "#7fd35a", "#8a5a3c"


def gold():
    # Mostly a bright warm colour, a little metal: reads as gold against a painted sky too.
    return C.M("#ffcc2e", 0.3, metal=0.3)


def owner():
    return C.named("Owner", "#ff5d73", 0.55)


def wall():
    return C.named("Wall", WALL, 0.85)


def windows(face, w, d, z, cols, frame, glass, cx=0.0, cy=0.0, ww=0.085, wh=0.1):
    span = (w if face in ("front", "back") else d) * 0.62
    for k in range(cols):
        u = 0.0 if cols == 1 else -span / 2 + span * k / (cols - 1)
        C.window(face, w, d, u, z, frame, glass, ww=ww, wh=wh, cx=cx, cy=cy, sill=False)


def flag(x, y, z, h=0.2):
    C.cyl(0.008, 0.008, h, (x, y, z + h / 2), C.M("#ffffff", 0.5), verts=8, bevel=0.0)
    C.rbox((0.1, 0.012, 0.06), (x + 0.05, y, z + h - 0.035), owner(), r=0.006)
    C.ball(0.014, (x, y, z + h + 0.008), gold(), seg=10)


def base_pad(w, d):
    """A low lawn pad every building stands on, so it sits in its plot, not on the stone."""
    C.rbox((w, d, 0.03), (0, 0, 0.015), C.M(LEAF2, 0.9), r=0.014)


# ---------------------------------------------------------------- tile

def tile():
    C.reset()
    C.rbox((0.94, 0.94, 0.14), (0, 0, 0.07), C.M(CREAM_EDGE, 0.9), r=0.06, seg=4)
    C.rbox((0.88, 0.88, 0.03), (0, 0.0, 0.135), C.M(CREAM, 0.85), r=0.03, seg=3)
    # The district stripe wraps the front edge.
    C.rbox((0.92, 0.2, 0.07), (0, -0.37, 0.115), C.named("Stripe", "#ff7a6b", 0.6), r=0.035, seg=3)
    C.export(os.path.join(OUT, "tile.glb"))


def corner_tile():
    C.reset()
    C.rbox((0.94, 0.94, 0.14), (0, 0, 0.07), C.M("#e6c27a", 0.9), r=0.06, seg=4)
    C.rbox((0.88, 0.88, 0.03), (0, 0, 0.135), C.M("#ffe3a0", 0.8), r=0.03, seg=3)
    C.export(os.path.join(OUT, "corner_tile.glb"))


# ---------------------------------------------------------------- buildings

def cottage():
    C.reset()
    w, d, h = 0.4, 0.32, 0.22
    base_pad(0.6, 0.42)
    C.rbox((w, d, h), (0, 0, 0.03 + h / 2), wall(), r=0.025)
    C.gable(w, d, 0.15, 0.03 + h, owner(), fill=wall(), thick=0.045, along_x=True)
    C.door("front", w, d, -0.08, C.M(FRAME), C.M(WOOD), dw=0.08, dh=0.13)
    windows("front", w, d, 0.15, 1, C.M(FRAME), C.M(GLASS, 0.3), cx=0.09)
    C.bush(0.2, -0.14, 1.1, C.M(LEAF), flowers=C.M("#ff8fab"))
    flag(-0.24, 0.12, 0.03)
    C.export(os.path.join(OUT, "b1.glb"))


def house():
    C.reset()
    w, d, h = 0.46, 0.34, 0.36
    base_pad(0.64, 0.44)
    C.rbox((w, d, h), (0, 0, 0.03 + h / 2), wall(), r=0.025)
    C.rbox((w + 0.02, d + 0.02, 0.03), (0, 0, 0.03 + h * 0.5), C.M(WALL_SHADE, 0.85), r=0.012)
    C.gable(w, d, 0.16, 0.03 + h, owner(), fill=wall(), thick=0.045, along_x=True)
    C.chimney(0.13, 0.06, 0.03 + h + 0.04, 0.14, C.M("#e07a5f", 0.85), C.M("#5b6178"))
    C.door("front", w, d, 0.0, C.M(FRAME), C.M(WOOD), dw=0.08, dh=0.13)
    windows("front", w, d, 0.31, 2, C.M(FRAME), C.M(GLASS, 0.3))
    windows("front", w, d, 0.12, 2, C.M(FRAME), C.M(GLASS, 0.3), cx=0.0, ww=0.07) if False else None
    for u in (-0.14, 0.14):
        C.window("front", w, d, u, 0.12, C.M(FRAME), C.M(GLASS, 0.3), ww=0.075, wh=0.09, sill=False)
    flag(-0.27, 0.13, 0.03)
    C.export(os.path.join(OUT, "b2.glb"))


def shop():
    C.reset()
    w, d, h = 0.5, 0.36, 0.48
    base_pad(0.66, 0.46)
    C.rbox((w, d, h), (0, 0, 0.03 + h / 2), wall(), r=0.025)
    C.rbox((w + 0.04, d + 0.04, 0.05), (0, 0, 0.03 + h), C.M(WALL_SHADE, 0.85), r=0.02)
    C.hip(w, d, 0.14, 0.03 + h + 0.03, owner())
    # Ground floor shop front: big window, door, striped awning.
    C.rbox((0.3, 0.03, 0.12), (-0.06, -d / 2 - 0.005, 0.12), C.M(GLASS, 0.3), r=0.01)
    C.door("front", w, d, 0.16, C.M(FRAME), C.M(WOOD), dw=0.08, dh=0.14)
    C.awning_stripes("front", w, d, 0.0, 0.22, 0.48, owner(), C.M("#ffffff"), n=6)
    windows("front", w, d, 0.38, 3, C.M(FRAME), C.M(GLASS, 0.3), ww=0.075, wh=0.09)
    flag(-0.29, 0.14, 0.03)
    C.export(os.path.join(OUT, "b3.glb"))


def tower():
    C.reset()
    base_pad(0.64, 0.46)
    w, d, h = 0.48, 0.36, 0.3
    C.rbox((w, d, h), (0, 0, 0.03 + h / 2), wall(), r=0.025)
    C.door("front", w, d, 0.0, C.M(FRAME), C.M(WOOD), dw=0.09, dh=0.14)
    for u in (-0.16, 0.16):
        C.window("front", w, d, u, 0.16, C.M(FRAME), C.M(GLASS, 0.3), ww=0.075, wh=0.09, sill=False)
    C.rbox((w + 0.03, d + 0.03, 0.035), (0, 0, 0.03 + h), C.M(WALL_SHADE, 0.85), r=0.015)
    r, th = 0.15, 0.36
    z0 = 0.03 + h + 0.017
    C.cyl(r, r, th, (0, 0.0, z0 + th / 2), wall(), verts=24, bevel=0.015)
    for a in (-0.5, 0.0, 0.5):
        C.rbox((0.06, 0.03, 0.09), (math.sin(a) * (r + 0.005), -math.cos(a) * (r + 0.005), z0 + th * 0.55),
               C.M(GLASS, 0.3), r=0.01, rot=(0, 0, a))
    C.cone_roof(r, 0.24, z0 + th, owner(), tip=None)
    C.ball(0.025, (0, 0, z0 + th + 0.29), gold(), seg=12)
    C.export(os.path.join(OUT, "b4.glb"))


def landmark():
    C.reset()
    base_pad(0.7, 0.5)
    w, d, h = 0.56, 0.4, 0.32
    C.rbox((w + 0.06, d + 0.06, 0.05), (0, 0, 0.055), C.M(WALL_SHADE, 0.85), r=0.02)
    C.rbox((w, d, h), (0, 0, 0.08 + h / 2), wall(), r=0.025)
    for u in (-0.2, -0.07, 0.07, 0.2):
        C.cyl(0.025, 0.025, h - 0.02, (u, -d / 2 - 0.02, 0.08 + h / 2), C.M("#ffffff", 0.7), verts=12)
    C.rbox((w + 0.06, d + 0.06, 0.04), (0, 0, 0.08 + h + 0.02), owner(), r=0.015)
    C.cyl(0.13, 0.13, 0.08, (0, 0, 0.08 + h + 0.08), wall(), verts=24)
    C.ball(0.14, (0, 0, 0.08 + h + 0.13), gold(), scale=(1, 1, 0.95), seg=20)
    C.ball(0.03, (0, 0, 0.08 + h + 0.29), gold(), seg=10)
    flag(0.0, 0.0, 0.08 + h + 0.3, h=0.14)
    C.export(os.path.join(OUT, "b5.glb"))


def owned_plot():
    """Bought but not built yet: a fenced lawn with the owner's flag."""
    C.reset()
    base_pad(0.62, 0.46)
    white = C.M("#ffffff", 0.8)
    for side in (-1, 1):
        for k in range(5):
            C.rbox((0.022, 0.022, 0.08), (side * 0.29, -0.18 + k * 0.09, 0.07), white, r=0.006)
        C.rbox((0.016, 0.42, 0.018), (side * 0.29, 0.0, 0.09), white, r=0.005)
    for k in range(7):
        C.rbox((0.022, 0.022, 0.08), (-0.27 + k * 0.09, 0.22, 0.07), white, r=0.006)
    C.rbox((0.56, 0.016, 0.018), (0, 0.22, 0.09), white, r=0.005)
    C.bush(-0.15, 0.08, 1.3, C.M(LEAF), flowers=C.M("#ff8fab"))
    C.bush(0.14, 0.1, 1.1, C.M(LEAF), flowers=C.M("#ffd166"))
    flag(0.0, -0.02, 0.03, h=0.3)
    C.export(os.path.join(OUT, "b0.glb"))


def for_sale():
    C.reset()
    C.cyl(0.014, 0.016, 0.22, (0, 0, 0.11), C.M(WOOD, 0.85), verts=10)
    C.rbox((0.24, 0.03, 0.12), (0, -0.012, 0.21), C.M("#ffffff", 0.8), r=0.014)
    C.rbox((0.19, 0.035, 0.06), (0, -0.016, 0.21), C.M("#3ddc97", 0.6), r=0.01)
    C.export(os.path.join(OUT, "sale.glb"))


# ---------------------------------------------------------------- corners

def coins(x, y, n, s=1.0, z=0.15):
    for k in range(n):
        C.cyl(0.06 * s, 0.06 * s, 0.024 * s, (x + (k % 2) * 0.005, y, z + 0.012 * s + k * 0.026 * s), gold(), verts=20,
              bevel=0.005)


def corner_base(col="#e6c27a"):
    C.rbox((1.0, 1.0, 0.14), (0, 0, 0.07), C.M(col, 0.85), r=0.07, seg=4)
    C.rbox((0.92, 0.92, 0.03), (0, 0, 0.135), C.M("#ffe3a0", 0.8), r=0.03)


def payday():
    """A chunky golden start gate: two stone-footed gold pillars, a thick arch, a red banner."""
    C.reset()
    corner_base()
    z = 0.15
    for x in (-0.3, 0.3):
        C.rbox((0.16, 0.16, 0.1), (x, 0.1, z + 0.05), C.M(WALL, 0.85), r=0.025)
        C.cyl(0.065, 0.065, 0.46, (x, 0.1, z + 0.1 + 0.23), gold(), verts=20)
        C.ball(0.075, (x, 0.1, z + 0.6), gold(), seg=16)
    bpy_arch(0.3, 0.07, (0, 0.1, z + 0.56))
    C.rbox((0.44, 0.05, 0.12), (0, 0.08, z + 0.58), C.M("#ff5d73", 0.6), r=0.03)
    C.ball(0.06, (0, 0.1, z + 0.92), gold(), seg=14)
    coins(-0.3, -0.26, 5)
    coins(-0.17, -0.32, 3)
    coins(0.3, -0.26, 4)
    coins(0.18, -0.33, 2)
    for k in range(7):
        x = -0.24 + k * 0.08
        C.cyl(0.028, 0.0, 0.06, (x, 0.07, z + 0.47 - 0.03 * math.sin(k / 6 * math.pi)),
              C.M(["#ff5d73", "#ffd23f", "#4dabff", "#3ddc97"][k % 4], 0.6), verts=3, bevel=0.0, rot=(math.pi, 0, 0))
    pot(-0.4, 0.35, z, "#ff8fab")
    pot(0.4, 0.35, z, "#ffd166")
    sparkle(-0.2, -0.1, z + 0.8)
    sparkle(0.25, 0.0, z + 0.95, 0.8)
    C.export(os.path.join(OUT, "c_payday.glb"))


def bpy_arch(r, t, at):
    """A half-torus arch standing in the XZ plane."""
    import bpy
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=t, location=at, rotation=(math.pi / 2, 0, 0),
                                     major_segments=40, minor_segments=14)
    o = bpy.context.active_object
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if (o.matrix_world @ v.co).z < at[2] - 0.001], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    C._add(o, gold(), 0, weighted=False)


def sparkle(x, y, z, s=1.0):
    """A little four-point gold star that catches the glow."""
    m = C.M("#fff1a8", 0.3, emit=2.5)
    C.rbox((0.012 * s, 0.012 * s, 0.09 * s), (x, y, z), m, r=0.004)
    C.rbox((0.09 * s, 0.012 * s, 0.012 * s), (x, y, z), m, r=0.004)


def pot(x, y, z, flower):
    C.cyl(0.05, 0.04, 0.07, (x, y, z + 0.035), C.M("#d9774a", 0.85), verts=14)
    C.bush(x, y, 1.1, C.M(LEAF, 0.9), z=z + 0.06, flowers=C.M(flower, 0.8))


def jackpot():
    """Two-tier golden coin fountain, coins spilling into the pool."""
    C.reset()
    corner_base()
    z = 0.15
    C.cyl(0.43, 0.45, 0.12, (0, 0.04, z + 0.06), C.M(WALL, 0.85), verts=36)
    C.torus(0.43, 0.025, (0, 0.04, z + 0.12), gold())
    C.cyl(0.38, 0.38, 0.06, (0, 0.04, z + 0.1), C.M("#5fd0ff", 0.2), verts=36, bevel=0.0)
    C.cyl(0.08, 0.11, 0.26, (0, 0.04, z + 0.25), C.M(WALL, 0.85), verts=16)
    C.cyl(0.22, 0.17, 0.07, (0, 0.04, z + 0.4), gold(), verts=28)
    C.cyl(0.05, 0.06, 0.14, (0, 0.04, z + 0.5), C.M(WALL, 0.85), verts=14)
    C.cyl(0.12, 0.09, 0.05, (0, 0.04, z + 0.58), gold(), verts=22)
    C.ball(0.075, (0, 0.04, z + 0.68), gold(), seg=16)
    for k in range(9):
        a = k * math.tau / 9
        C.cyl(0.045, 0.045, 0.016, (math.cos(a) * 0.27, 0.04 + math.sin(a) * 0.27, z + 0.135), gold(), verts=16,
              rot=(0.4 * math.sin(a), 0.4 * math.cos(a), 0))
    coins(0.12, 0.08, 3, 1.0, z=z + 0.44)
    for (x, y, h) in ((-0.3, -0.3, 0.75), (0.32, 0.25, 0.85), (0.1, -0.2, 0.95)):
        sparkle(x, y, z + h)
    C.export(os.path.join(OUT, "c_jackpot.glb"))


def audit():
    """A police booth with a striped barrier, traffic cones and a flashing light."""
    C.reset()
    corner_base("#bcc8e6")
    z = 0.15
    blue, dark = C.M("#4d7cff", 0.7), C.M("#2f4fbf", 0.7)
    C.rbox((0.4, 0.36, 0.08), (-0.12, 0.12, z + 0.04), C.M(WALL, 0.85), r=0.02)
    C.rbox((0.34, 0.3, 0.44), (-0.12, 0.12, z + 0.08 + 0.22), blue, r=0.035)
    C.rbox((0.24, 0.03, 0.16), (-0.12, -0.035, z + 0.36), C.M(GLASS, 0.3), r=0.012)
    C.rbox((0.36, 0.035, 0.06), (-0.12, -0.04, z + 0.18), C.M("#ffffff", 0.7), r=0.012)
    C.hip(0.34, 0.3, 0.1, z + 0.52, dark)
    C.cyl(0.05, 0.05, 0.06, (-0.12, 0.12, z + 0.69), C.M("#ff3b3b", 0.3, emit=3.0), verts=16)
    C.cyl(0.035, 0.035, 0.26, (0.26, -0.2, z + 0.13), C.M("#ffffff", 0.7), verts=12)
    C.rbox((0.06, 0.08, 0.08), (0.26, -0.2, z + 0.27), C.M("#ff3b3b", 0.6), r=0.015)
    for k in range(5):
        C.rbox((0.09, 0.035, 0.055), (0.19 - k * 0.09, -0.2, z + 0.26), C.M("#ff3b3b" if k % 2 == 0 else "#ffffff", 0.6),
               r=0.012)
    for (x, y) in ((0.3, 0.25), (0.18, 0.33)):
        C.cyl(0.05, 0.012, 0.13, (x, y, z + 0.075), C.M("#ff7a2e", 0.6), verts=14)
        C.cyl(0.06, 0.06, 0.012, (x, y, z + 0.006), C.M("#ff7a2e", 0.6), verts=14)
        C.cyl(0.033, 0.024, 0.025, (x, y, z + 0.08), C.M("#ffffff", 0.6), verts=14, bevel=0.0)
    pot(-0.36, -0.3, z, "#ff8fab")
    C.export(os.path.join(OUT, "c_audit.glb"))


def vault():
    """A chunky red safe with gold trim, gold bars and money bags."""
    C.reset()
    corner_base("#e2c0bc")
    z = 0.15
    C.rbox((0.66, 0.54, 0.06), (0, 0.12, z + 0.03), C.M("#5b6178", 0.7), r=0.02)
    C.rbox((0.6, 0.48, 0.52), (0, 0.12, z + 0.06 + 0.26), C.M("#e6474f", 0.55), r=0.07, seg=4)
    for zz in (z + 0.1, z + 0.54):
        C.rbox((0.62, 0.5, 0.03), (0, 0.12, zz), gold(), r=0.012)
    C.cyl(0.18, 0.18, 0.05, (0, -0.13, z + 0.32), C.M("#c9ced9", 0.3, metal=0.7), verts=32, rot=(math.pi / 2, 0, 0))
    C.torus(0.18, 0.02, (0, -0.155, z + 0.32), gold(), rot=(math.pi / 2, 0, 0))
    C.cyl(0.055, 0.055, 0.08, (0, -0.17, z + 0.32), gold(), verts=18, rot=(math.pi / 2, 0, 0))
    for a in range(4):
        aa = a * math.pi / 2 + math.pi / 4
        C.rbox((0.028, 0.03, 0.2), (math.cos(aa) * 0.08, -0.175, z + 0.32 + math.sin(aa) * 0.08), gold(), r=0.01,
               rot=(0, aa, 0))
    for (x, y, zz) in ((0.24, -0.3, 0), (0.36, -0.3, 0), (0.3, -0.3, 0.05)):
        C.rbox((0.11, 0.06, 0.045), (x, y, z + 0.025 + zz), gold(), r=0.012)
    for (x, y) in ((-0.3, -0.28), (-0.17, -0.33)):
        C.ball(0.075, (x, y, z + 0.07), C.M("#d9b27a", 0.9), scale=(1, 1, 0.95), seg=14)
        C.cyl(0.03, 0.04, 0.05, (x, y, z + 0.15), C.M("#d9b27a", 0.9), verts=12)
        C.torus(0.034, 0.008, (x, y, z + 0.13), C.M("#8a5530", 0.8))
    sparkle(0.33, 0.33, z + 0.72)
    C.export(os.path.join(OUT, "c_vault.glb"))


# ---------------------------------------------------------------- special spaces (props on a normal tile)

def sp_metro():
    C.reset()
    z = 0.15
    rail = C.M("#8d94a8", 0.5, metal=0.4)
    for x in (-0.07, 0.07):
        C.rbox((0.025, 0.7, 0.025), (x, 0.05, z + 0.012), rail, r=0.006)
    for k in range(6):
        C.rbox((0.22, 0.04, 0.015), (0, -0.25 + k * 0.1, z + 0.007), C.M(WOOD, 0.9), r=0.005)
    C.rbox((0.2, 0.44, 0.2), (0, 0.06, z + 0.14), C.M("#2ec4c6", 0.6), r=0.06, seg=4)
    C.rbox((0.21, 0.36, 0.07), (0, 0.06, z + 0.17), C.M(GLASS, 0.3), r=0.025)
    C.rbox((0.22, 0.45, 0.03), (0, 0.06, z + 0.07), C.M("#ffffff", 0.7), r=0.012)
    C.cyl(0.02, 0.02, 0.06, (0, -0.17, z + 0.17), C.M("#fff1b8", 0.3, emit=2.5), verts=10, rot=(math.pi / 2, 0, 0))
    C.cyl(0.012, 0.012, 0.3, (0.27, -0.05, z + 0.15), C.M("#5b6178", 0.6), verts=8)
    C.cyl(0.07, 0.07, 0.02, (0.27, -0.06, z + 0.3), C.M("#ff5d73", 0.6), verts=20, rot=(math.pi / 2, 0, 0))
    C.export(os.path.join(OUT, "s_metro.glb"))


def sp_windfall():
    C.reset()
    z = 0.15
    bag = C.M("#d9b27a", 0.9)
    C.ball(0.15, (0, 0.05, z + 0.14), bag, scale=(1, 1, 0.95), seg=18)
    C.cyl(0.05, 0.07, 0.07, (0, 0.05, z + 0.3), bag, verts=14)
    C.torus(0.055, 0.012, (0, 0.05, z + 0.27), C.M("#3ddc97", 0.6))
    C.cyl(0.06, 0.06, 0.012, (0, -0.1, z + 0.16), gold(), verts=20, rot=(math.pi / 2, 0, 0))
    coins(0.2, -0.12, 3, z=z)
    coins(-0.2, -0.08, 2, z=z)
    sparkle(0.18, 0.15, z + 0.42)
    sparkle(-0.16, 0.1, z + 0.36, 0.8)
    C.export(os.path.join(OUT, "s_windfall.glb"))


def sp_permit():
    C.reset()
    z = 0.15
    C.rbox((0.34, 0.26, 0.16), (0, 0.08, z + 0.08), C.M(WOOD, 0.85), r=0.025)
    C.rbox((0.36, 0.28, 0.02), (0, 0.08, z + 0.17), C.M(WOOD_DARK, 0.85), r=0.01)
    C.rbox((0.2, 0.15, 0.012), (-0.04, 0.06, z + 0.186), C.M("#fff4d6", 0.9), r=0.004, rot=(0, 0, 0.15))
    C.cyl(0.03, 0.03, 0.09, (0.1, 0.12, z + 0.23), C.M(WOOD_DARK, 0.85), verts=12)
    C.ball(0.04, (0.1, 0.12, z + 0.29), C.M(WOOD_DARK, 0.85), seg=12)
    C.cyl(0.055, 0.055, 0.035, (0.1, 0.12, z + 0.195), C.M("#e6474f", 0.6), verts=18)
    C.cyl(0.03, 0.03, 0.006, (-0.04, 0.03, z + 0.193), C.M("#e6474f", 0.6), verts=16, bevel=0.0)
    C.export(os.path.join(OUT, "s_permit.glb"))


# ---------------------------------------------------------------- pawn

def pawn():
    C.reset()
    body = owner()
    C.cyl(0.14, 0.15, 0.05, (0, 0, 0.025), body, verts=32, bevel=0.02)
    C.torus(0.135, 0.012, (0, 0, 0.05), C.M("#ffffff", 0.4))
    C.cyl(0.1, 0.05, 0.22, (0, 0, 0.16), body, verts=28, bevel=0.01)
    C.cyl(0.085, 0.085, 0.025, (0, 0, 0.27), body, verts=28, bevel=0.01)
    C.ball(0.085, (0, 0, 0.35), body, seg=24)
    C.export(os.path.join(OUT, "pawn.glb"))


# ---------------------------------------------------------------- park

def tree_round(x, y, s, leaf=LEAF, light=LEAF2):
    C.cyl(0.035 * s, 0.05 * s, 0.2 * s, (x, y, 0.1 * s), C.M(TRUNK), verts=10)
    C.ball(0.18 * s, (x, y, 0.36 * s), C.M(leaf, 0.9), seg=16)
    C.ball(0.13 * s, (x + 0.11 * s, y - 0.05 * s, 0.28 * s), C.M(light, 0.9), seg=14)
    C.ball(0.12 * s, (x - 0.1 * s, y + 0.06 * s, 0.3 * s), C.M(leaf, 0.9), seg=14)


def tree_pine(x, y, s):
    C.cyl(0.03 * s, 0.04 * s, 0.12 * s, (x, y, 0.06 * s), C.M(TRUNK), verts=10)
    for k, (r, h, z) in enumerate(((0.17, 0.2, 0.18), (0.13, 0.18, 0.3), (0.09, 0.16, 0.41))):
        C.cyl(r * s, 0.01 * s, h * s, (x, y, z * s), C.M("#3f9e52" if k % 2 == 0 else "#4fb35e", 0.9), verts=12,
              bevel=0.01)


def tree_blossom(x, y, s):
    C.cyl(0.03 * s, 0.045 * s, 0.18 * s, (x, y, 0.09 * s), C.M(TRUNK), verts=10)
    C.ball(0.16 * s, (x, y, 0.32 * s), C.M("#ffa8c5", 0.9), seg=16)
    C.ball(0.11 * s, (x + 0.1 * s, y, 0.26 * s), C.M("#ffc4d8", 0.9), seg=14)
    C.ball(0.1 * s, (x - 0.08 * s, y + 0.05 * s, 0.27 * s), C.M("#ff92b6", 0.9), seg=14)


def bench(x, y, a):
    wood, metal = C.M(WOOD, 0.85), C.M("#5b6178", 0.7)
    c, s = math.cos(a), math.sin(a)
    C.rbox((0.26, 0.08, 0.02), (x, y, 0.07), wood, r=0.006, rot=(0, 0, a))
    C.rbox((0.26, 0.02, 0.07), (x - s * 0.04, y + c * 0.04, 0.11), wood, r=0.006, rot=(0, 0, a))
    for k in (-1, 1):
        C.rbox((0.02, 0.08, 0.07), (x + c * 0.11 * k, y + s * 0.11 * k, 0.035), metal, r=0.005, rot=(0, 0, a))


def flower_bed(x, y, w, d, flowers):
    C.rbox((w + 0.06, d + 0.06, 0.06), (x, y, 0.03), C.M("#e9d6b4", 0.9), r=0.025)
    C.rbox((w, d, 0.05), (x, y, 0.04), C.M("#7b5b45", 0.95), r=0.02)
    nx, ny = max(2, int(w / 0.09)), max(2, int(d / 0.09))
    for i in range(nx):
        for j in range(ny):
            px = x - w / 2 + w * (i + 0.5) / nx
            py = y - d / 2 + d * (j + 0.5) / ny
            C.ball(0.035, (px, py, 0.08), C.M(LEAF, 0.9), seg=8)
            C.ball(0.022, (px + 0.01, py - 0.01, 0.11), C.M(flowers[(i + j) % len(flowers)], 0.8), seg=8)


def centre():
    """The park: a fountain plaza with the golden dice, four stone paths out to the corners,
    flower beds, benches, lamps and mixed trees. Kept low near the tiles."""
    C.reset()
    stone, stone2 = C.M("#f2e2c4", 0.9), C.M("#e2cda6", 0.9)
    C.cyl(1.3, 1.34, 0.05, (0, 0, 0.025), stone, verts=56)
    C.torus(1.3, 0.025, (0, 0, 0.05), stone2)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        c, s = math.cos(a), math.sin(a)
        C.rbox((0.42, 2.0, 0.04), (c * 2.25, s * 2.25, 0.02), stone, r=0.02, rot=(0, 0, a - math.pi / 2))
    C.cyl(0.95, 0.95, 0.14, (0, 0, 0.12), C.M(WALL, 0.85), verts=56)
    C.torus(0.95, 0.03, (0, 0, 0.19), gold())
    C.cyl(0.87, 0.87, 0.06, (0, 0, 0.17), C.M("#5fd0ff", 0.15), verts=56, bevel=0.0)
    C.cyl(0.26, 0.3, 0.42, (0, 0, 0.35), C.M(WALL, 0.85), verts=28)
    C.cyl(0.36, 0.34, 0.06, (0, 0, 0.58), gold(), verts=32)
    dice = gold()
    pip = C.M("#ffffff", 0.4)
    C.rbox((0.4, 0.4, 0.4), (-0.12, 0, 0.82), dice, r=0.08, seg=4, rot=(0.0, 0.0, 0.5))
    C.rbox((0.34, 0.34, 0.34), (0.22, 0.1, 0.78), dice, r=0.07, seg=4, rot=(0.0, 0.0, -0.3))
    for (dx, dy) in ((0, 0), (0.1, 0.1), (-0.1, -0.1)):
        C.ball(0.03, (-0.12 + dx * 0.9, dy * 0.9, 1.025), pip, seg=10)
    for k in range(10):
        a = k * math.tau / 10 + 0.3
        C.ball(0.03, (math.cos(a) * 0.55, math.sin(a) * 0.55, 0.22), C.M("#bfefff", 0.2, emit=0.8), seg=8)
    # Flower beds on the axes, benches beside them, lamps by the paths.
    for k in range(4):
        a = k * math.pi / 2
        c, s = math.cos(a), math.sin(a)
        if k % 2 == 0:
            flower_bed(c * 1.75, s * 1.75, 0.36, 0.8, ["#ff8fab", "#ffd166", "#ffffff"])
        else:
            flower_bed(c * 1.75, s * 1.75, 0.8, 0.36, ["#c9a7ff", "#ff9f6e", "#ffffff"])
        bench(c * 1.4 - s * 0.55, s * 1.4 + c * 0.55, a + math.pi / 2)
    post, light = C.M("#4a4f6a", 0.6), C.M("#fff1b8", 0.3, emit=3.0)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        for r in (1.6, 2.6):
            for side in (-1, 1):
                px = math.cos(a) * r - math.sin(a) * 0.3 * side
                py = math.sin(a) * r + math.cos(a) * 0.3 * side
                if r > 2 and side > 0:
                    continue
                C.cyl(0.012, 0.016, 0.3, (px, py, 0.15), post, verts=8)
                C.ball(0.035, (px, py, 0.32), light, seg=12)
    # Trees in the four wedges between paths: a mix, tallest near the plaza.
    kinds = [tree_round, tree_pine, tree_blossom]
    k = 0
    for q in range(4):
        base = q * math.pi / 2
        for (da, r, sc) in ((0.0, 1.55, 1.35), (0.32, 2.15, 1.2), (-0.32, 2.15, 1.1), (0.15, 2.65, 0.9),
                            (-0.18, 2.6, 0.85)):
            a = base + da
            kinds[k % 3](math.cos(a) * r, math.sin(a) * r, sc)
            k += 1
    for (x, y) in ((1.0, 2.55), (-2.55, 1.0), (2.5, -1.1), (-1.1, -2.5)):
        C.bush(x, y, 1.6, C.M(LEAF, 0.9), flowers=C.M("#ffd166", 0.8))
    C.export(os.path.join(OUT, "centre.glb"))


# ---------------------------------------------------------------- island

def _superellipse(n, half, power, jitter=0.0, seed=0):
    import random
    rnd = random.Random(seed)
    pts = []
    for k in range(n):
        a = k * math.tau / n
        c, s = math.cos(a), math.sin(a)
        r = (abs(c) ** power + abs(s) ** power) ** (-1.0 / power) * half
        r *= 1.0 + rnd.uniform(-jitter, jitter)
        pts.append((c * r, s * r))
    return pts


def _slab(name, top, bottom, z_top, z_bot, mat, cap=True):
    import bpy
    import bmesh
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vt = [bm.verts.new((x, y, z_top)) for x, y in top]
    vb = [bm.verts.new((x, y, z_bot)) for x, y in bottom]
    n = len(vt)
    for k in range(n):
        bm.faces.new((vt[k], vb[k], vb[(k + 1) % n], vt[(k + 1) % n]))
    if cap:
        bm.faces.new(vt)
    bm.faces.new(list(reversed(vb)))  # winding is outward by construction (no recalc: open shells)
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    return C._add(ob, mat, 0, weighted=False)


def _ribbon(x, y, ox, oy, along_x, width, mat, shift=0.0):
    """A falling-water ribbon: a smooth curved strip from the lip (z 0) down to z -2.9."""
    import bpy
    import bmesh
    mesh = bpy.data.meshes.new("fall")
    bm = bmesh.new()
    rows = []
    for k in range(16):
        t = k / 15
        z = -0.05 - t * 2.85
        out = 0.06 + 0.42 * t ** 1.4
        w = width * (1.0 + 0.35 * t)
        row = []
        for side in (-1, 1):
            d = side * w / 2 + shift
            px = x + ox * out + (d if along_x else 0)
            py = y + oy * out + (0 if along_x else d)
            row.append(bm.verts.new((px, py, z)))
        rows.append(row)
    for k in range(15):
        a, b = rows[k], rows[k + 1]
        f = (a[0], a[1], b[1], b[0]) if along_x else (a[1], a[0], b[0], b[1])
        bm.faces.new(f)
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new("fall", mesh)
    bpy.context.collection.objects.link(ob)
    s = ob.modifiers.new("thick", "SOLIDIFY")
    s.thickness = 0.06
    return C._add(ob, mat, 0, weighted=False)


def island():
    """The floating island: a thick grass top with a soft lip, layered cliffs tapering to a point,
    boulders, and two waterfalls on the faces the camera sees."""
    C.reset()
    n = 96
    grass, lip = C.M("#6cc04a", 0.95), C.M("#4f9c3a", 0.95)
    C_top = _superellipse(n, 4.72, 6.0)
    _slab("grass", C_top, _superellipse(n, 4.76, 6.0), 0.0, -0.16, grass)
    _slab("lip", _superellipse(n, 4.78, 6.0), _superellipse(n, 4.66, 6.0, 0.012, 3), -0.16, -0.3, lip, cap=False)
    # (half-size at the bottom of the band, band top, band bottom, colour, jitter): steep walls
    # first (seen from the camera), then the taper underneath.
    layers = [(4.62, -0.3, -0.85, "#b07a4f", 0.006), (4.5, -0.85, -1.45, "#a06d47", 0.012),
              (4.15, -1.45, -2.05, "#8f6141", 0.025), (3.4, -2.05, -2.6, "#80573b", 0.04),
              (2.1, -2.6, -3.1, "#714c34", 0.06), (0.3, -3.1, -3.55, "#664430", 0.08)]
    prev = _superellipse(n, 4.66, 6.0, 0.012, 3)
    for k, (half, zt, zb, col, jit) in enumerate(layers):
        bottom = _superellipse(n, half, max(6.0 - k * 0.8, 2.2), jit, k + 7)
        _slab("cliff%d" % k, prev, bottom, zt, zb, C.M(col, 0.95), cap=False)
        prev = bottom
        # A darker ledge line between bands reads as rock strata.
        _slab("ledge%d" % k, _superellipse(n, half + 0.04, max(6.0 - k * 0.8, 2.2), jit, k + 7),
              _superellipse(n, half - 0.02, max(6.0 - k * 0.8, 2.2), jit, k + 7), zb + 0.03, zb - 0.03,
              C.M("#5e3e2a", 0.95), cap=False)
    import random
    rnd = random.Random(5)
    rock = [C.M(h, 0.95) for h in ("#a07a62", "#8d6a55", "#b8957b")]
    for k in range(26):
        a = rnd.uniform(0, math.tau)
        z = rnd.uniform(-2.3, -0.5)
        half = 4.62 if z > -1.45 else 4.45 + (z + 1.45) * 0.6
        c, s = math.cos(a), math.sin(a)
        r = (abs(c) ** 4 + abs(s) ** 4) ** (-0.25) * half
        C.ball(rnd.uniform(0.13, 0.24), (c * r * 0.985, s * r * 0.985, z), rock[k % 3], scale=(1.2, 1.0, 0.8), seg=10)
    # Waterfalls on the two faces the camera sees: a smooth ribbon that leaves the grass lip,
    # curves out and falls, with foam where it leaves and a cloud of spray at the bottom.
    water, light, foam = C.M("#7fd3ff", 0.15, emit=0.2), C.M("#d4f3ff", 0.2, emit=0.4), C.M("#ffffff", 0.6)
    for (x, y, along_x) in ((1.6, -4.7, True), (4.7, -1.4, False)):
        ox, oy = (0.0, -1.0) if along_x else (1.0, 0.0)
        _ribbon(x, y, ox, oy, along_x, 0.46, water)
        _ribbon(x + (0.0 if along_x else 0.03), y + (-0.03 if along_x else 0.0), ox, oy, along_x, 0.14, light,
                shift=0.08)
        for k in range(5):
            d = 0.11 * (k - 2)
            C.ball(0.075 + 0.02 * (k % 2), (x + ox * 0.12 + (d if along_x else 0), y + oy * 0.12 + (0 if along_x else d),
                                            -0.1), foam, seg=10)
        for k in range(5):
            d = 0.17 * (k - 2)
            C.ball(0.17 + 0.04 * (k % 2), (x + ox * 0.5 + (d if along_x else 0), y + oy * 0.5 + (0 if along_x else d),
                                           -2.9 + 0.05 * (k % 2)), foam, seg=12)
    # Grass edge: small bushes and flowers around the rim.
    for k in range(44):
        a = (k + 0.5) * math.tau / 44
        c, s = math.cos(a), math.sin(a)
        r = (abs(c) ** 6 + abs(s) ** 6) ** (-1 / 6) * 4.45
        if k % 3 == 0:
            C.bush(c * r, s * r, 1.3, C.M(LEAF, 0.9), flowers=C.M(["#ff8fab", "#ffd166", "#ffffff"][k % 3], 0.8))
    C.export(os.path.join(OUT, "island.glb"))


for f in (tile, corner_tile, owned_plot, cottage, house, shop, tower, landmark, for_sale, payday, jackpot, audit, vault, sp_metro,
          sp_windfall, sp_permit, pawn, centre, island):
    f()
    print("built", f.__name__)
