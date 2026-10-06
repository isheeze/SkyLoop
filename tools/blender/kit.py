"""Shared helpers for Skyloop's scripted Blender kits.

Conventions (so models drop straight onto a Godot tile):
- 1 Blender unit = 1 Godot unit; a board tile is 0.95 wide.
- Origin at the centre of the footprint, on the ground (z = 0).
- The street-facing front looks down -Y (it becomes +Z in Godot, toward the ring road).
- Footprint stays within 0.70 (x) by 0.50 (y) so tokens have room in front.
- Flat shading with a one-segment bevel: soft highlights on every edge, stylised and cheap.
"""
import math
import os

import bmesh
import bpy

BEVEL = 0.012


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, rough=0.75, metal=0.0, emit=None, strength=0.0, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*srgb(color), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*srgb(emit), 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    return m


def srgb(hexstr):
    """Hex colour to linear RGB, the way Blender stores colours."""
    hexstr = hexstr.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(hexstr[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def _finish(obj, mat, bevel):
    obj.data.materials.append(mat)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
    _parts.append(obj)
    return obj


_parts = []


def box(size, loc, mat, bevel=BEVEL, rot_z=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=(0, 0, rot_z))
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _finish(obj, mat, min(bevel, min(size) * 0.3))


def cyl(r_bottom, r_top, h, loc, mat, verts=12, bevel=BEVEL, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r_bottom, radius2=r_top, depth=h,
                                    location=loc, rotation=rot)
    return _finish(bpy.context.active_object, mat, min(bevel, h * 0.3))


def sphere(r, loc, mat, scale=(1, 1, 1), subdiv=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=r, location=loc)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return _finish(obj, mat, 0)


def gable(w, d, h, loc, mat, overhang=0.03, along_x=True):
    """A triangular roof prism. Ridge runs along X when along_x, else along Y."""
    mesh = bpy.data.meshes.new("roof")
    bm = bmesh.new()
    hw, hd = w / 2 + overhang, d / 2 + overhang
    if along_x:
        pts = [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0), (-hw, 0, h), (hw, 0, h)]
        faces = [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]
    else:
        pts = [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0), (0, -hd, h), (0, hd, h)]
        faces = [(1, 2, 5, 4), (3, 0, 4, 5), (0, 1, 4), (2, 3, 5), (0, 3, 2, 1)]
    vs = [bm.verts.new(p) for p in pts]
    for f in faces:
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("roof", mesh)
    obj.location = loc
    bpy.context.collection.objects.link(obj)
    return _finish(obj, mat, 0.008)


def windows_on_face(face, x0, x1, z0, z1, cols, rows, depth_at, mats, lit_pattern, w=0.055, h=0.075,
                    frame=None):
    """Lays a grid of windows on one facade. `face` is '-y', '+y', '-x' or '+x'.
    depth_at is the facade coordinate (y for ±y faces, x for ±x faces)."""
    lit, dark = mats
    k = 0
    for r in range(rows):
        z = z0 + (z1 - z0) * (r + 0.5) / rows
        for c in range(cols):
            u = x0 + (x1 - x0) * (c + 0.5) / cols
            m = lit if lit_pattern[k % len(lit_pattern)] else dark
            k += 1
            if face in ("-y", "+y"):
                s = -1 if face == "-y" else 1
                if frame:
                    box((w + 0.018, 0.01, h + 0.018), (u, depth_at + s * 0.004, z), frame, bevel=0.003)
                box((w, 0.012, h), (u, depth_at + s * 0.008, z), m, bevel=0.0)
            else:
                s = -1 if face == "-x" else 1
                if frame:
                    box((0.01, w + 0.018, h + 0.018), (depth_at + s * 0.004, u, z), frame, bevel=0.003)
                box((0.012, w, h), (depth_at + s * 0.008, u, z), m, bevel=0.0)


def export(path):
    """Applies modifiers, joins the parts into one object and writes a GLB."""
    global _parts
    bpy.ops.object.select_all(action="DESELECT")
    for p in _parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = _parts[0]
    for p in _parts:
        bpy.context.view_layer.objects.active = p
        for mod in list(p.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active = _parts[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    bpy.ops.object.shade_flat()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)
    _parts = []
    return obj


def stagger(seed, n, ratio=0.6):
    """Deterministic lit/dark pattern for windows."""
    out = []
    x = seed * 9301 + 49297
    for _ in range(n):
        x = (x * 9301 + 49297) % 233280
        out.append(x / 233280.0 < ratio)
    return out
