"""Small shared props: the die.

Run:  blender -b --factory-startup -P tools/blender/build_props.py -- <project dir>

Die faces (Blender axes -> Godot axes): 1 on +Z (Godot +Y), 6 on -Z (-Y), 2 on -Y (+Z),
5 on +Y (-Z), 3 on +X (+X), 4 on -X (-X). Opposite faces add up to 7.
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402

ROOT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
OUT = os.path.join(ROOT, "art", "models")

S = 0.2  # die edge length
PIP = 0.019
FACES = {
    1: ((0, 0, 1), [(0, 0)]),
    6: ((0, 0, -1), [(-1, -1), (-1, 0), (-1, 1), (1, -1), (1, 0), (1, 1)]),
    2: ((0, -1, 0), [(-1, -1), (1, 1)]),
    5: ((0, 1, 0), [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)]),
    3: ((1, 0, 0), [(-1, -1), (0, 0), (1, 1)]),
    4: ((-1, 0, 0), [(-1, -1), (1, -1), (-1, 1), (1, 1)]),
}


def die():
    kit.reset()
    body = kit.material("DieBody", "#fbf8f2", 0.35)
    pip = kit.material("DiePip", "#e0475b", 0.4)
    gold = kit.material("DiePipGold", "#1d2340", 0.4)
    bpy.ops.mesh.primitive_cube_add(size=S, location=(0, 0, 0))
    cube = bpy.context.active_object
    cube.data.materials.append(body)
    bev = cube.modifiers.new("Bevel", "BEVEL")
    bev.width = S * 0.16
    bev.segments = 4
    kit._parts.append(cube)
    step = S * 0.25
    for value, (n, spots) in FACES.items():
        for a, b in spots:
            # Two in-face axes for each normal.
            if n[2] != 0:
                pos = (a * step, b * step, n[2] * S / 2)
            elif n[1] != 0:
                pos = (a * step, n[1] * S / 2, b * step)
            else:
                pos = (n[0] * S / 2, a * step, b * step)
            kit.sphere(PIP, pos, pip if value in (1, 4) else gold, scale=(1, 1, 1), subdiv=2)
    obj = kit.export(os.path.join(OUT, "die.glb"))
    print("exported die")


die()
