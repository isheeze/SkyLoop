"""Skyloop's "cute diorama" modelling helpers (art style v2).

Everything is chunky and soft: generous bevels with several segments, smooth shading with
weighted normals, thick roof slabs, round trees. Conventions match the game:
- 1 Blender unit = 1 Godot unit. A tile is 0.95 wide; tokens walk on the ring road, so a
  building may use up to 0.72 (x) by 0.62 (y).
- Origin on the ground at the centre of the footprint.
- The street front faces -Y (it becomes +Z in Godot, toward the ring road).
"""
import math
import os
import random

import bpy

_parts = []
_mats = {}


def reset():
    global _parts, _mats
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _parts = []
    _mats = {}


def lin(hexstr):
    hexstr = hexstr.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(hexstr[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def M(hexcol, rough=0.85, metal=0.0, emit=0.0, alpha=1.0):
    """Material cache keyed by look, so a model never carries duplicate materials."""
    key = (hexcol.lower(), rough, metal, emit, alpha)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("c_%s_%d" % (hexcol.strip("#"), len(_mats)))
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*lin(hexcol), 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*lin(hexcol), 1.0)
        b.inputs["Emission Strength"].default_value = emit
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    _mats[key] = m
    return m


def _add(obj, mat, bevel=0.0, seg=3, weighted=True):
    obj.data.materials.append(mat)
    if bevel > 0:
        b = obj.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = seg
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(35)
    for p in obj.data.polygons:
        p.use_smooth = True
    if weighted:
        w = obj.modifiers.new("wn", "WEIGHTED_NORMAL")
        w.keep_sharp = True
        w.mode = "FACE_AREA"
        w.weight = 50
    _parts.append(obj)
    return obj


# ---------------------------------------------------------------- primitives

def rbox(size, loc, mat, r=0.025, rot=(0, 0, 0), seg=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    # Small details (windows, sills, fences) only need a single chamfer: it reads the same
    # from the game camera at a fraction of the triangles.
    if min(size) < 0.06 and max(size) < 0.2:
        seg = 1
    return _add(o, mat, min(r, min(size) * 0.45), seg)


def cyl(r1, r2, h, loc, mat, verts=20, bevel=0.012, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=h, location=loc, rotation=rot)
    return _add(bpy.context.active_object, mat, min(bevel, h * 0.4), 2)


def ball(r, loc, mat, scale=(1, 1, 1), seg=14):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=max(8, seg // 2), radius=r, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return _add(o, mat, 0, weighted=False)


def torus(R, r, loc, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=loc, rotation=rot,
                                     major_segments=32, minor_segments=10)
    return _add(bpy.context.active_object, mat, 0, weighted=False)


# ---------------------------------------------------------------- roofs

def gable(w, d, h, z, mat, fill=None, thick=0.04, over=0.045, along_x=True, cx=0.0, cy=0.0):
    """Two thick roof slabs meeting at a ridge, plus triangular gable walls in `fill`."""
    a = math.atan2(h, d / 2 if along_x else w / 2)
    run = (d if along_x else w) / 2
    L = math.hypot(h, run) + over
    span = (w if along_x else d) + 2 * over
    for s in (-1, 1):
        if along_x:
            c = (cx, cy + s * (math.cos(a) * L / 2 - 0.01), z + h - math.sin(a) * L / 2 + thick * 0.5)
            rbox((span, L, thick), c, mat, r=0.016, rot=(-s * a, 0, 0))
        else:
            c = (cx + s * (math.cos(a) * L / 2 - 0.01), cy, z + h - math.sin(a) * L / 2 + thick * 0.5)
            rbox((L, span, thick), c, mat, r=0.016, rot=(0, s * a, 0))
    if along_x:
        cyl(thick * 0.75, thick * 0.75, span, (cx, cy, z + h + thick * 0.55), mat, verts=12, rot=(0, math.pi / 2, 0))
    else:
        cyl(thick * 0.75, thick * 0.75, span, (cx, cy, z + h + thick * 0.55), mat, verts=12, rot=(math.pi / 2, 0, 0))
    if fill is not None:
        _gable_fill(w, d, h, z, fill, along_x, cx, cy)


def _gable_fill(w, d, h, z, mat, along_x, cx, cy):
    mesh = bpy.data.meshes.new("fill")
    hw, hd = w / 2 - 0.005, d / 2 - 0.005
    if along_x:
        v = [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0), (-hw, 0, h), (hw, 0, h)]
        f = [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]
    else:
        v = [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0), (0, -hd, h), (0, hd, h)]
        f = [(1, 2, 5, 4), (3, 0, 4, 5), (0, 1, 4), (2, 3, 5), (0, 3, 2, 1)]
    mesh.from_pydata(v, [], f)
    mesh.update()
    o = bpy.data.objects.new("fill", mesh)
    o.location = (cx, cy, z)
    bpy.context.collection.objects.link(o)
    _add(o, mat, 0.01, 2)


def hip(w, d, h, z, mat, over=0.04, cx=0.0, cy=0.0):
    rbox((w + 2 * over, d + 2 * over, 0.04), (cx, cy, z + 0.02), mat, r=0.018)
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=1, radius2=0.08, depth=h, location=(cx, cy, z + 0.04 + h / 2),
                                    rotation=(0, 0, math.pi / 4))
    o = bpy.context.active_object
    o.scale = ((w + 2 * over) / math.sqrt(2), (d + 2 * over) / math.sqrt(2), 1)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    _add(o, mat, 0.02, 3)


def cone_roof(r, h, z, mat, cx=0.0, cy=0.0, tip=None):
    cyl(r + 0.03, r + 0.03, 0.035, (cx, cy, z + 0.017), mat, verts=28)
    cyl(r + 0.02, 0.012, h, (cx, cy, z + 0.035 + h / 2), mat, verts=28, bevel=0.01)
    if tip is not None:
        ball(0.025, (cx, cy, z + 0.035 + h + 0.015), tip)


def flat_roof(w, d, z, mat, trim, cx=0.0, cy=0.0):
    rbox((w + 0.04, d + 0.04, 0.045), (cx, cy, z + 0.022), trim, r=0.018)
    rbox((w - 0.04, d - 0.04, 0.02), (cx, cy, z + 0.05), mat, r=0.008)


# ---------------------------------------------------------------- facade details

def _face(face, w, d):
    """(axis, sign, half-extent along the face normal)."""
    return {"front": ("y", -1, d / 2), "back": ("y", 1, d / 2), "left": ("x", -1, w / 2), "right": ("x", 1, w / 2)}[face]


def _at(face, w, d, u, z, out, cx=0.0, cy=0.0):
    axis, s, half = _face(face, w, d)
    if axis == "y":
        return (cx + u, cy + s * (half + out), z)
    return (cx + s * (half + out), cy + u, z)


def _size(face, along, thick, h):
    return (along, thick, h) if face in ("front", "back") else (thick, along, h)


def window(face, w, d, u, z, frame, glass, ww=0.075, wh=0.095, arch=False, cx=0.0, cy=0.0, sill=True):
    rbox(_size(face, ww + 0.026, 0.024, wh + 0.026), _at(face, w, d, u, z, 0.006, cx, cy), frame, r=0.008)
    rbox(_size(face, ww, 0.03, wh), _at(face, w, d, u, z, 0.008, cx, cy), glass, r=0.006)
    if arch:
        rot = (math.pi / 2, 0, 0) if face in ("front", "back") else (0, math.pi / 2, 0)
        cyl((ww + 0.026) / 2, (ww + 0.026) / 2, 0.024, _at(face, w, d, u, z + wh / 2, 0.006, cx, cy), frame,
            verts=20, rot=rot, bevel=0.004)
        cyl(ww / 2, ww / 2, 0.03, _at(face, w, d, u, z + wh / 2, 0.008, cx, cy), glass, verts=20, rot=rot, bevel=0.003)
    if sill:
        rbox(_size(face, ww + 0.04, 0.035, 0.014), _at(face, w, d, u, z - wh / 2 - 0.012, 0.012, cx, cy), frame, r=0.005)


def window_grid(faces, w, d, z0, z1, cols, rows, frame, glass, arch=False, ww=0.075, wh=0.095, cx=0.0, cy=0.0,
                skip=()):
    for face in faces:
        span = w if face in ("front", "back") else d
        n = cols if face in ("front", "back") else max(1, cols - 1)
        for r in range(rows):
            z = z0 + (z1 - z0) * (r + 0.5) / rows
            for c in range(n):
                if (face, r, c) in skip:
                    continue
                u = -span / 2 + span * (c + 0.5) / n
                window(face, w, d, u, z, frame, glass, ww, wh, arch and r == rows - 1, cx, cy)


def door(face, w, d, u, frame, leaf, dw=0.085, dh=0.14, awning=None, cx=0.0, cy=0.0):
    rbox(_size(face, dw + 0.03, 0.026, dh + 0.02), _at(face, w, d, u, dh / 2 + 0.01, 0.006, cx, cy), frame, r=0.008)
    rbox(_size(face, dw, 0.032, dh), _at(face, w, d, u, dh / 2, 0.008, cx, cy), leaf, r=0.008)
    rot = (math.pi / 2, 0, 0) if face in ("front", "back") else (0, math.pi / 2, 0)
    cyl(dw / 2, dw / 2, 0.032, _at(face, w, d, u, dh, 0.008, cx, cy), leaf, verts=20, rot=rot, bevel=0.003)
    if awning is not None:
        rbox(_size(face, dw + 0.07, 0.07, 0.022), _at(face, w, d, u, dh + 0.07, 0.035, cx, cy), awning, r=0.01)


def awning_stripes(face, w, d, u, z, width, a, b, cx=0.0, cy=0.0, n=5):
    for i in range(n):
        uu = u - width / 2 + width * (i + 0.5) / n
        rbox(_size(face, width / n + 0.002, 0.09, 0.03), _at(face, w, d, uu, z, 0.045, cx, cy), a if i % 2 == 0 else b,
             r=0.008, rot=((-0.35, 0, 0) if face == "front" else (0, 0, 0)))


def flower_box(face, w, d, u, z, box, petals, cx=0.0, cy=0.0):
    rbox(_size(face, 0.1, 0.035, 0.03), _at(face, w, d, u, z, 0.02, cx, cy), box, r=0.008)
    for i, p in enumerate(petals):
        x = u - 0.035 + i * 0.035
        ball(0.017, _at(face, w, d, x, z + 0.025, 0.02, cx, cy), p, seg=10)


def chimney(x, y, z, h, mat, cap):
    rbox((0.055, 0.055, h), (x, y, z + h / 2), mat, r=0.01)
    rbox((0.07, 0.07, 0.02), (x, y, z + h + 0.01), cap, r=0.006)


# ---------------------------------------------------------------- nature

def tree(x, y, s, leaf, trunk, z=0.0, kind="round"):
    cyl(0.022 * s, 0.03 * s, 0.14 * s, (x, y, z + 0.07 * s), trunk, verts=10)
    if kind == "round":
        ball(0.1 * s, (x, y, z + 0.2 * s), leaf)
        ball(0.075 * s, (x + 0.06 * s, y - 0.02 * s, z + 0.17 * s), leaf)
        ball(0.07 * s, (x - 0.05 * s, y + 0.03 * s, z + 0.16 * s), leaf)
    else:
        cyl(0.11 * s, 0.0, 0.26 * s, (x, y, z + 0.25 * s), leaf, verts=14, bevel=0.01)


def bush(x, y, s, leaf, z=0.0, flowers=None):
    ball(0.05 * s, (x, y, z + 0.03 * s), leaf, scale=(1.2, 1.0, 0.8))
    ball(0.04 * s, (x + 0.04 * s, y, z + 0.025 * s), leaf, scale=(1.1, 1.0, 0.8))
    if flowers is not None:
        for i in range(3):
            a = i * 2.1
            ball(0.012 * s, (x + math.cos(a) * 0.035 * s, y + math.sin(a) * 0.03 * s, z + 0.06 * s), flowers, seg=8)


def lamp(x, y, post, light, z=0.0):
    cyl(0.008, 0.01, 0.2, (x, y, z + 0.1), post, verts=8)
    ball(0.022, (x, y, z + 0.21), light, seg=12)


# ---------------------------------------------------------------- export

def export(path):
    """Applies modifiers, joins all parts into one mesh and writes a GLB."""
    global _parts
    bpy.ops.object.select_all(action="DESELECT")
    for p in _parts:
        bpy.context.view_layer.objects.active = p
        p.select_set(True)
        if p.type == "CURVE":
            bpy.ops.object.convert(target="MESH")
        for mod in list(p.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        p.select_set(False)
    for p in _parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = _parts[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    _bake_vertex_colors(obj)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_vertex_color="ACTIVE")
    _parts = []


## Materials the game recolours at runtime stay separate (named slots): Owner (roof, flag,
## pawn), Stripe (district colour on a tile), Wall (a building's wall tint, varied per tile).
KEEP = ("Owner", "Stripe", "Wall")


def named(name, hexcol, rough=0.6):
    """A material the game finds by name and recolours (see KEEP)."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*lin(hexcol), 1.0)
    b.inputs["Roughness"].default_value = rough
    _mats[name] = m
    return m


def _is_plain(m):
    if m.name.startswith(KEEP):
        return False
    b = m.node_tree.nodes["Principled BSDF"]
    return (b.inputs["Metallic"].default_value < 0.05 and b.inputs["Emission Strength"].default_value <= 0
            and b.inputs["Alpha"].default_value >= 1.0)


def _bake_vertex_colors(obj):
    """Moves every plain (matte, opaque, non-glowing) material's colour into a vertex colour
    and replaces them all with one shared material, so a building draws in one or two calls
    instead of eight. Glowing, glass and metal materials stay separate (painted white)."""
    me = obj.data
    mats = list(me.materials)
    plain = [m is not None and _is_plain(m) for m in mats]
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    shared = bpy.data.materials.get("Painted") or bpy.data.materials.new("Painted")
    shared.use_nodes = True
    bsdf = shared.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    node = shared.node_tree.nodes.new("ShaderNodeVertexColor")
    node.layer_name = "Col"
    shared.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    new_mats = [shared] + [m for m, p in zip(mats, plain) if not p]
    remap = {}
    for i, (m, p) in enumerate(zip(mats, plain)):
        remap[i] = 0 if p else new_mats.index(m)
    colors = []
    for m, p in zip(mats, plain):
        if p:
            c = m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value
            colors.append((c[0], c[1], c[2], 1.0))
        else:
            colors.append((1.0, 1.0, 1.0, 1.0))
    original = [poly.material_index for poly in me.polygons]
    for poly in me.polygons:
        col = colors[poly.material_index]
        for li in poly.loop_indices:
            attr.data[li].color = col
    # Swap the slots first: clearing materials resets every polygon's index to 0.
    me.materials.clear()
    for m in new_mats:
        me.materials.append(m)
    for poly, idx in zip(me.polygons, original):
        poly.material_index = remap[idx]
    me.color_attributes.active_color = attr
