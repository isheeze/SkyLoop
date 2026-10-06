"""Renders a lineup of exported GLBs for review.

Run:  blender -b --factory-startup -P tools/blender/preview.py -- <out.png> <a.glb> <b.glb> ...
"""
import math
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
out, files = args[0], args[1:]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1600
scene.render.resolution_y = 700
scene.render.film_transparent = False
scene.view_settings.view_transform = "AgX"

world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.95, 0.72, 0.62, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9

spacing = 0.9
x0 = -spacing * (len(files) - 1) / 2
for i, f in enumerate(files):
    bpy.ops.import_scene.gltf(filepath=f)
    for o in bpy.context.selected_objects:
        if o.parent is None:
            o.location.x += x0 + i * spacing

bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
ground = bpy.context.active_object
ground.scale = (spacing * len(files) + 1, 1.6, 1)
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.82, 0.77, 0.7, 1)
ground.data.materials.append(gm)

bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(10), math.radians(-35)))
sun = bpy.context.active_object
sun.data.energy = 3.5
sun.data.color = (1.0, 0.86, 0.72)

bpy.ops.object.camera_add(location=(0.3, -4.2, 2.2), rotation=(math.radians(68), 0, math.radians(3)))
cam = bpy.context.active_object
cam.data.type = "ORTHO"
cam.data.ortho_scale = spacing * len(files) + 0.4
scene.camera = cam
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("rendered", out)
