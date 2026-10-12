extends SceneTree
## Renders a thumbnail of every model in art/models (same light and angle as the game) into
## shots/assets/<name>.png, for reviewing the art kit. Needs a window (not --headless):
##   godot --path . -s tools/asset_sheet.gd [-- res://art/toy]

const Models = preload("res://game3d/models.gd")
const OUT := "res://shots/assets"
const SIZE := 256


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var names := []
	var src := "res://art/models"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		src = args[0]  # e.g. -- res://art/toy
	for f in DirAccess.get_files_at(src):
		if f.ends_with(".glb"):
			names.append(f.get_basename())
	names.sort()
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("eef0f6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff0e6")
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffe2c4")
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-52, -10, 0)
	vp.add_child(key)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	for n: String in names:
		var inst: Node3D = Models.instance("%s/%s.glb" % [src, n])
		vp.add_child(inst)
		await process_frame
		var box := _bounds(inst)
		var c := box.get_center()
		var r := maxf(box.size.length() * 0.62, 0.05)
		cam.size = r * 1.9
		cam.basis = Basis.from_euler(Vector3(deg_to_rad(-35), deg_to_rad(30), 0))
		cam.position = c + cam.basis * Vector3(0, 0, r * 6.0 + 2.0)
		cam.far = r * 20.0 + 10.0
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s/%s.png" % [ProjectSettings.globalize_path(OUT), n])
		inst.queue_free()
		await process_frame
	print("rendered %d models" % names.size())
	quit()


func _bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
