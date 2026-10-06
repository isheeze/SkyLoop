"""Docklands kit (district 0): a harbour neighbourhood of brick warehouses and slate roofs.

Run:  blender -b --factory-startup -P tools/blender/build_docklands.py -- <project dir>
Writes art/models/d0_l1.glb .. d0_l5.glb (level 5 is the Lighthouse landmark).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402

ROOT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
OUT = os.path.join(ROOT, "art", "models")


def palette():
    return {
        "brick": kit.material("Brick", "#b8644a", 0.85),
        "brick_dark": kit.material("BrickDark", "#8f4a38", 0.85),
        "cream": kit.material("Cream", "#f1e6d2", 0.8),
        "slate": kit.material("Slate", "#2f6170", 0.7),
        "trim": kit.material("Trim", "#fbf7ef", 0.6),
        "wood": kit.material("Wood", "#8a5a3c", 0.8),
        "teal": kit.material("Teal", "#4fb6c9", 0.55),
        "metal": kit.material("Metal", "#8a96a3", 0.4, metal=0.6),
        "lit": kit.material("WindowLit", "#ffd27f", 0.4, emit="#ffc36a", strength=4.0),
        "dark": kit.material("WindowDark", "#26394c", 0.15, metal=0.2),
        "red": kit.material("Red", "#e04e4e", 0.6),
        "rock": kit.material("Rock", "#8d877f", 0.95),
        "glass": kit.material("Glass", "#cfeaf5", 0.05, alpha=0.45),
        "lamp": kit.material("Lamp", "#fff1b8", 0.3, emit="#ffe28a", strength=12.0),
    }


def crates(P, x, y, n=3):
    for i in range(n):
        kit.box((0.06, 0.06, 0.06), (x + (i % 2) * 0.065, y, 0.03 + (i // 2) * 0.062), P["wood"], bevel=0.006)


def level1(P):
    """Fisherman's cottage with a slate gable roof."""
    w, d, h = 0.42, 0.32, 0.2
    kit.box((w, d, h), (0, 0, h / 2), P["cream"])
    kit.box((w + 0.02, d + 0.02, 0.035), (0, 0, 0.0175), P["brick_dark"])
    kit.gable(w, d, 0.15, (0, 0, h), P["slate"], overhang=0.035, along_x=True)
    kit.box((0.05, 0.05, 0.12), (0.12, 0.06, h + 0.1), P["brick"])
    kit.box((0.075, 0.012, 0.12), (-0.08, -d / 2 - 0.006, 0.06), P["wood"], bevel=0.004)
    kit.windows_on_face("-y", 0.0, 0.2, 0.06, 0.16, 2, 1, -d / 2, (P["lit"], P["dark"]), [1, 0],
                        frame=P["trim"])
    kit.windows_on_face("+x", -0.08, 0.08, 0.06, 0.16, 1, 1, w / 2, (P["lit"], P["dark"]), [1], frame=P["trim"])
    kit.windows_on_face("+y", -0.14, 0.14, 0.06, 0.16, 2, 1, d / 2, (P["lit"], P["dark"]), [0, 1], frame=P["trim"])
    kit.box((0.09, 0.03, 0.02), (-0.08, -d / 2 - 0.02, 0.13), P["teal"], bevel=0.004)
    crates(P, -0.27, -0.12, 3)
    kit.cyl(0.03, 0.03, 0.08, (0.27, -0.12, 0.04), P["teal"], verts=10)


def level2(P):
    """Two-storey brick warehouse with a loading door and a little crane."""
    w, d, h = 0.56, 0.42, 0.4
    kit.box((w, d, h), (0, 0, h / 2), P["brick"])
    kit.box((w + 0.03, d + 0.03, 0.04), (0, 0, h + 0.02), P["trim"])
    kit.box((w - 0.04, d - 0.04, 0.02), (0, 0, h + 0.045), P["slate"])
    kit.box((0.16, 0.014, 0.2), (0, -d / 2 - 0.007, 0.1), P["teal"], bevel=0.005)
    kit.box((0.13, 0.016, 0.17), (0, -d / 2 - 0.012, 0.09), P["wood"], bevel=0.004)
    kit.windows_on_face("-y", -0.25, 0.25, 0.22, 0.36, 4, 1, -d / 2, (P["lit"], P["dark"]),
                        kit.stagger(2, 4), frame=P["trim"])
    for face, at in (("+x", w / 2), ("-x", -w / 2)):
        kit.windows_on_face(face, -0.15, 0.15, 0.08, 0.34, 3, 2, at, (P["lit"], P["dark"]),
                            kit.stagger(3 if face == "+x" else 4, 6), frame=P["trim"])
    kit.windows_on_face("+y", -0.25, 0.25, 0.08, 0.36, 4, 2, d / 2, (P["lit"], P["dark"]),
                        kit.stagger(12, 8), frame=P["trim"])
    # Roof crane.
    kit.box((0.03, 0.03, 0.22), (0.2, 0.12, h + 0.15), P["teal"], bevel=0.004)
    kit.box((0.24, 0.025, 0.025), (0.1, 0.12, h + 0.25), P["teal"], bevel=0.004)
    kit.box((0.006, 0.006, 0.1), (0.0, 0.12, h + 0.19), P["metal"], bevel=0.0)
    crates(P, 0.2, -0.27, 4)


def level3(P):
    """Harbour apartments: brick ground floor, cream upper floors, balconies, water tank."""
    w, d = 0.52, 0.44
    kit.box((w, d, 0.2), (0, 0, 0.1), P["brick"])
    kit.box((w - 0.02, d - 0.02, 0.5), (0, 0, 0.45), P["cream"])
    kit.box((w + 0.02, d + 0.02, 0.035), (0, 0, 0.71), P["trim"])
    kit.box((0.11, 0.012, 0.13), (0, -d / 2 - 0.006, 0.065), P["teal"], bevel=0.004)
    kit.windows_on_face("-y", -0.24, 0.24, 0.24, 0.66, 3, 4, -d / 2 + 0.01, (P["lit"], P["dark"]),
                        kit.stagger(5, 12), frame=P["trim"])
    for face, at in (("+x", w / 2 - 0.01), ("-x", -w / 2 + 0.01)):
        kit.windows_on_face(face, -0.18, 0.18, 0.24, 0.66, 2, 4, at, (P["lit"], P["dark"]),
                            kit.stagger(6 if face == "+x" else 7, 8), frame=P["trim"])
    kit.windows_on_face("+y", -0.24, 0.24, 0.24, 0.66, 3, 4, d / 2 - 0.01, (P["lit"], P["dark"]),
                        kit.stagger(13, 12), frame=P["trim"])
    kit.windows_on_face("+y", -0.2, 0.2, 0.05, 0.17, 3, 1, d / 2, (P["lit"], P["dark"]), [1, 0, 1], frame=P["trim"])
    for z in (0.34, 0.5):
        kit.box((0.36, 0.06, 0.012), (0, -d / 2 - 0.03, z), P["trim"], bevel=0.003)
        kit.box((0.36, 0.006, 0.04), (0, -d / 2 - 0.058, z + 0.025), P["teal"], bevel=0.0)
    # Water tank on stilts.
    for x, y in ((-0.07, 0.05), (0.03, 0.05), (-0.07, 0.15), (0.03, 0.15)):
        kit.box((0.012, 0.012, 0.08), (x + 0.1, y, 0.77), P["metal"], bevel=0.0)
    kit.cyl(0.07, 0.07, 0.11, (0.08, 0.1, 0.865), P["wood"], verts=12)
    kit.cyl(0.075, 0.0, 0.05, (0.08, 0.1, 0.945), P["slate"], verts=12)


def level4(P):
    """Converted waterfront tower with a glowing harbour sign."""
    kit.box((0.6, 0.46, 0.5), (0, 0, 0.25), P["brick"])
    kit.box((0.62, 0.48, 0.03), (0, 0, 0.515), P["trim"])
    kit.box((0.44, 0.36, 0.62), (0, 0.02, 0.84), P["cream"])
    kit.box((0.46, 0.38, 0.03), (0, 0.02, 1.165), P["trim"])
    kit.box((0.28, 0.22, 0.12), (0, 0.04, 1.24), P["slate"])
    kit.cyl(0.006, 0.01, 0.28, (0.08, 0.04, 1.44), P["metal"], verts=6, bevel=0.0)
    kit.sphere(0.018, (0.08, 0.04, 1.585), P["red"])
    kit.windows_on_face("-y", -0.26, 0.26, 0.08, 0.46, 4, 3, -0.23, (P["lit"], P["dark"]),
                        kit.stagger(8, 12), frame=P["trim"])
    kit.windows_on_face("-y", -0.18, 0.18, 0.58, 1.12, 3, 5, -0.16, (P["lit"], P["dark"]),
                        kit.stagger(9, 15), frame=P["trim"])
    for face, at in (("+x", 0.22), ("-x", -0.22)):
        kit.windows_on_face(face, -0.12, 0.16, 0.58, 1.12, 2, 5, at, (P["lit"], P["dark"]),
                            kit.stagger(10 if face == "+x" else 11, 10), frame=P["trim"])
    kit.windows_on_face("+y", -0.26, 0.26, 0.08, 0.46, 4, 3, 0.23, (P["lit"], P["dark"]),
                        kit.stagger(14, 12), frame=P["trim"])
    kit.windows_on_face("+y", -0.18, 0.18, 0.58, 1.12, 3, 5, 0.2, (P["lit"], P["dark"]),
                        kit.stagger(15, 15), frame=P["trim"])
    for face, at in (("+x", 0.3), ("-x", -0.3)):
        kit.windows_on_face(face, -0.18, 0.18, 0.08, 0.46, 3, 3, at, (P["lit"], P["dark"]),
                            kit.stagger(16 if face == "+x" else 17, 9), frame=P["trim"])
    kit.box((0.16, 0.02, 0.07), (0.0, -0.245, 0.49), P["teal"], bevel=0.005)
    kit.box((0.13, 0.024, 0.045), (0.0, -0.25, 0.49), kit.material("SignGlow", "#bff6ff", 0.3,
                                                                    emit="#7ff0ff", strength=6.0), bevel=0.0)


def level5(P):
    """Landmark: the Lighthouse on its rocks, with a keeper's hut."""
    for i, (x, y, r) in enumerate(((0, 0, 0.26), (0.2, -0.1, 0.12), (-0.2, 0.08, 0.13), (0.14, 0.16, 0.1))):
        kit.sphere(r, (x, y, 0.02), P["rock"], scale=(1, 1, 0.45), subdiv=1)
    bands = 6
    h = 1.05
    for i in range(bands):
        z0 = 0.08 + h * i / bands
        r0 = 0.17 - 0.06 * i / bands
        r1 = 0.17 - 0.06 * (i + 1) / bands
        kit.cyl(r0, r1, h / bands, (0, 0, z0 + h / bands / 2), P["trim"] if i % 2 == 0 else P["red"], verts=8,
                bevel=0.004)
    top = 0.08 + h
    kit.cyl(0.15, 0.15, 0.025, (0, 0, top + 0.012), P["slate"], verts=12, bevel=0.004)
    for k in range(12):
        a = k * math.tau / 12
        kit.box((0.008, 0.008, 0.07), (math.cos(a) * 0.14, math.sin(a) * 0.14, top + 0.06), P["metal"], bevel=0.0)
    kit.cyl(0.145, 0.145, 0.012, (0, 0, top + 0.1), P["metal"], verts=12, bevel=0.0)
    kit.cyl(0.085, 0.085, 0.16, (0, 0, top + 0.105), P["glass"], verts=8, bevel=0.0)
    kit.sphere(0.055, (0, 0, top + 0.1), P["lamp"])
    kit.cyl(0.1, 0.02, 0.12, (0, 0, top + 0.245), P["red"], verts=8, bevel=0.004)
    kit.sphere(0.02, (0, 0, top + 0.315), P["metal"])
    kit.box((0.05, 0.012, 0.09), (0, -0.165, 0.13), P["wood"], bevel=0.004)
    # Keeper's hut.
    kit.box((0.18, 0.14, 0.12), (0.22, -0.16, 0.1), P["cream"])
    kit.gable(0.18, 0.14, 0.08, (0.22, -0.16, 0.16), P["slate"], overhang=0.02, along_x=False)


def main():
    for lvl, fn in enumerate((level1, level2, level3, level4, level5), start=1):
        kit.reset()
        P = palette()
        fn(P)
        kit.export(os.path.join(OUT, "d0_l%d.glb" % lvl))
        print("exported d0_l%d" % lvl)


main()
