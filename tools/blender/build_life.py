"""Ambient life: a little car and a hot-air balloon (style v2).

Run:  blender -b --factory-startup -P tools/blender/build_life.py -- <project dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import cute as C  # noqa: E402

ROOT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
OUT = os.path.join(ROOT, "art", "models")


def car(color, name):
    C.reset()
    body = C.M(color, 0.4)
    C.rbox((0.22, 0.12, 0.06), (0, 0, 0.055), body, r=0.025)
    C.rbox((0.12, 0.105, 0.055), (-0.015, 0, 0.105), body, r=0.022)
    C.rbox((0.1, 0.108, 0.035), (-0.015, 0, 0.105), C.M("#bfe6ff", 0.1, metal=0.2), r=0.012)
    tyre = C.M("#3b3f52", 0.8)
    for x in (-0.07, 0.07):
        for y in (-0.06, 0.06):
            C.cyl(0.026, 0.026, 0.02, (x, y, 0.026), tyre, verts=16, rot=(math.pi / 2, 0, 0))
    for y in (-0.035, 0.035):
        C.ball(0.012, (0.11, y, 0.06), C.M("#fff4c4", 0.3, emit=2.0), seg=8)
    C.export(os.path.join(OUT, name))


def balloon(a, b, name):
    C.reset()
    ma, mb = C.M(a, 0.6), C.M(b, 0.6)
    for k in range(8):
        ang = k * math.tau / 8
        C.ball(0.3, (math.cos(ang) * 0.015, math.sin(ang) * 0.015, 0.75), ma if k % 2 == 0 else mb,
               scale=(0.35, 1.0, 1.15) if False else (1.0, 1.0, 1.15), seg=24) if k == 0 else None
    C.ball(0.3, (0, 0, 0.75), ma, scale=(1.0, 1.0, 1.15), seg=24)
    for k in range(4):
        ang = k * math.pi / 4
        C.torus(0.301, 0.012, (0, 0, 0.75), mb, rot=(math.pi / 2, 0, ang))
    C.cyl(0.12, 0.05, 0.12, (0, 0, 0.36), ma, verts=16)
    rope = C.M("#8a5a3c", 0.9)
    for k in range(4):
        ang = k * math.pi / 2 + math.pi / 4
        C.cyl(0.004, 0.004, 0.26, (math.cos(ang) * 0.06, math.sin(ang) * 0.06, 0.18), rope, verts=6)
    C.rbox((0.14, 0.14, 0.09), (0, 0, 0.045), C.M("#b5835a", 0.9), r=0.02)
    C.export(os.path.join(OUT, name))


car("#ff6b6b", "car_red.glb")
car("#5cc8ff", "car_blue.glb")
car("#ffd166", "car_yellow.glb")
balloon("#ff8fab", "#fffaf2", "balloon_pink.glb")
balloon("#7cc6ff", "#ffd166", "balloon_blue.glb")
print("life done")
