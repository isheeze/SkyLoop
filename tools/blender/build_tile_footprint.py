"""Modular board tile footprint: a raised dirt plinth with a cobblestone driveway (where the
pawn stands) and a chunky wooden price signpost on the right.

Cute, soft, low-poly. No materials are assigned: every part lives in a clearly named collection
so shaders can be assigned per collection later. Geometry rules:
  - every mesh is quads and triangles only (any n-gon left by bevels or caps is triangulated),
  - smooth shading with a Weighted Normal modifier (face-area weighting, sharp edges kept),
  - one hierarchy: TileFootprint (empty) -> Plinth, Driveway, Signpost (empty) -> Post, Plaque.

Run:  blender -b --factory-startup -P tools/blender/build_tile_footprint.py [-- out.blend]
Units: 1 Blender unit = 1 tile. Origin at the centre of the plinth's base. Front faces -Y.
"""
import math
import random
import sys

import bmesh
import bpy
from mathutils import Matrix

# ---------------------------------------------------------------- tunables

TILE = 1.0              # plinth width and depth
PLINTH_H = 0.16         # plinth height
PLINTH_BEVEL = 0.05     # soft rounded edge
DRIVE_DEPTH = 0.46      # the cobbled front half
COBBLE = 0.085          # cobble size
COBBLE_GAP = 0.012
POST_R = 0.026
POST_H = 0.36
PLAQUE = (0.24, 0.035, 0.13)  # width, thickness, height
SIGN_X = TILE / 2 - 0.13      # signpost position (right side)
SIGN_Y = -0.06
SEED = 7

COLLECTIONS = {
    "root": "Tile_Footprint",
    "plinth": "Tile_Plinth",
    "driveway": "Tile_Driveway",
    "signpost": "Tile_Signpost",
}


# ---------------------------------------------------------------- helpers

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_collections():
    scene_root = bpy.context.scene.collection
    root = bpy.data.collections.new(COLLECTIONS["root"])
    scene_root.children.link(root)
    out = {"root": root}
    for key in ("plinth", "driveway", "signpost"):
        c = bpy.data.collections.new(COLLECTIONS[key])
        root.children.link(c)
        out[key] = c
    return out


def link(obj, collection):
    collection.objects.link(obj)
    return obj


def no_ngons(bm):
    """Triangulate only faces with more than four corners; quads and tris are kept."""
    ngons = [f for f in bm.faces if len(f.verts) > 4]
    if ngons:
        bmesh.ops.triangulate(bm, faces=ngons, quad_method="BEAUTY", ngon_method="BEAUTY")


def finish_mesh(obj, sharp_angle=40.0):
    """Smooth shading plus a Weighted Normal modifier, so bevelled shapes read soft but flat
    faces stay flat."""
    for p in obj.data.polygons:
        p.use_smooth = True
    wn = obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    wn.mode = "FACE_AREA"
    wn.weight = 50
    wn.keep_sharp = True
    # Mark edges sharper than the angle as sharp so the modifier keeps hard creases.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    lim = math.radians(sharp_angle)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim:
            e.smooth = False
    bm.to_mesh(obj.data)
    bm.free()


def bevelled_box(name, size, location, bevel, segments, collection):
    """A box with a baked (applied) chamfer, built in bmesh; n-gon free."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, profile=0.5,
                        affect="EDGES", clamp_overlap=True)
    no_ngons(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = location
    return link(obj, collection)


def cylinder(name, radius, depth, location, verts, collection):
    """A capped cylinder whose caps are triangle fans (no n-gons), lightly bevelled top."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=verts,
                          radius1=radius, radius2=radius, depth=depth)
    top = [e for e in bm.edges if all(v.co.z > depth / 2 - 1e-5 for v in e.verts) and e.is_boundary is False
           and len(e.link_faces) == 2 and abs(e.calc_face_angle(0.0)) > math.radians(60)]
    if top:
        bmesh.ops.bevel(bm, geom=top, offset=radius * 0.3, segments=2, affect="EDGES", clamp_overlap=True)
    no_ngons(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = location
    return link(obj, collection)


def empty(name, location, collection):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = 0.2
    e.location = location
    return link(e, collection)


# ---------------------------------------------------------------- parts

def build_plinth(col):
    """The raised dirt patch: one chamfered block, soft on every edge."""
    obj = bevelled_box("Plinth", (TILE, TILE, PLINTH_H), (0, 0, PLINTH_H / 2), PLINTH_BEVEL, 3, col)
    finish_mesh(obj)
    return obj


def build_driveway(col):
    """A flat cobbled patch over the front half: rows of slightly varied, rounded cobbles laid
    in a running bond, joined into one mesh."""
    rng = random.Random(SEED)
    bm = bmesh.new()
    margin = PLINTH_BEVEL + 0.03
    # The cobbles stop short of the signpost so the post stands on bare dirt.
    x0, x1 = -TILE / 2 + margin, SIGN_X - POST_R - 0.06
    y0, y1 = -TILE / 2 + margin, -TILE / 2 + margin + DRIVE_DEPTH
    step = COBBLE + COBBLE_GAP
    row = 0
    y = y0 + COBBLE / 2
    while y + COBBLE / 2 <= y1:
        offset = (step / 2) if row % 2 else 0.0
        x = x0 + COBBLE / 2 + offset
        while x + COBBLE / 2 <= x1:
            w = COBBLE * rng.uniform(0.86, 1.0)
            d = COBBLE * rng.uniform(0.86, 1.0)
            h = rng.uniform(0.016, 0.026)
            cob = bmesh.new()
            bmesh.ops.create_cube(cob, size=1.0)
            bmesh.ops.scale(cob, vec=(w, d, h), verts=cob.verts)
            bmesh.ops.bevel(cob, geom=list(cob.edges), offset=min(w, d) * 0.3, segments=2, profile=0.65,
                            affect="EDGES", clamp_overlap=True)
            bmesh.ops.rotate(cob, verts=cob.verts, cent=(0, 0, 0),
                             matrix=Matrix.Rotation(rng.uniform(-0.08, 0.08), 3, "Z"))
            bmesh.ops.translate(cob, vec=(x, y, PLINTH_H + h / 2), verts=cob.verts)
            tmp = bpy.data.meshes.new("_cob")
            cob.to_mesh(tmp)
            cob.free()
            bm.from_mesh(tmp)
            bpy.data.meshes.remove(tmp)
            x += step
        y += step
        row += 1
    no_ngons(bm)
    me = bpy.data.meshes.new("Driveway")
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new("Driveway", me), col)
    finish_mesh(obj)
    return obj


def build_signpost(col):
    """A chunky wooden sign on the right: a round post and a flat plaque for the price."""
    root = empty("Signpost", (SIGN_X, SIGN_Y, PLINTH_H), col)
    post = cylinder("Signpost_Post", POST_R, POST_H, (0, 0, POST_H / 2), 10, col)
    finish_mesh(post, sharp_angle=60.0)
    w, t, h = PLAQUE
    plaque = bevelled_box("Signpost_Plaque", (w, t, h), (0, -POST_R - t / 2 + 0.004, POST_H - h / 2 - 0.02),
                          min(t, h) * 0.3, 2, col)
    finish_mesh(plaque)
    post.parent = root
    plaque.parent = root
    return root


# ---------------------------------------------------------------- main

def build():
    reset_scene()
    cols = make_collections()
    root = empty("TileFootprint", (0, 0, 0), cols["root"])
    plinth = build_plinth(cols["plinth"])
    drive = build_driveway(cols["driveway"])
    sign = build_signpost(cols["signpost"])
    for child in (plinth, drive, sign):
        child.parent = root
    return root


def report():
    ngons = 0
    tris = 0
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        for p in o.data.polygons:
            ngons += len(p.vertices) > 4
            tris += len(p.vertices) - 2
    print("TileFootprint: %d meshes, %d triangles, %d n-gons" % (
        sum(o.type == "MESH" for o in bpy.data.objects), tris, ngons))


if __name__ == "__main__":
    build()
    report()
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv:
        bpy.ops.wm.save_as_mainfile(filepath=argv[0])
