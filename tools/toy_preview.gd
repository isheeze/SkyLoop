extends Node
## Design review: lays out the toy kit (art/toy) as a full board and renders it offscreen with
## the planned camera and light, no game logic. Writes shots/toy_board.png and shots/toy_side.png.
##   godot --path . res://tools/toy_preview.tscn

const KIT := "res://art/toy/%s.glb"
const STRIPES := [Color("ff7a6b"), Color("ffa94d"), Color("ffd23f"), Color("3ddc97"), Color("2ec4c6"),
	Color("4dabff"), Color("9b6bff")]
const PLAYERS := [Color("ffc23d"), Color("ff5d73"), Color("3ddc97"), Color("5cc8ff")]
const TILE_TOP := 0.15
## Wall tints, varied per tile so a street doesn't look copy-pasted.
const WALLS := [Color("fff4e2"), Color("fde6d8"), Color("e8f4ea"), Color("eae6fb"), Color("e3f1fb"), Color("fff0c8")]
const PITCH := -35.0
const YAW := 45.0

var _scene: Node3D


func _ready() -> void:
	await get_tree().process_frame
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 1300)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	_light(vp)
	_scene = Node3D.new()
	vp.add_child(_scene)
	_build()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 100.0
	vp.add_child(cam)
	_aim(cam, Vector3(0, -0.6, 0), 13.6)
	await _save(vp, "res://shots/toy_board.png")
	vp.size = Vector2i(1080, 760)
	_aim(cam, Vector3(1.8, 0, 3.4), 5.0)
	await _save(vp, "res://shots/toy_side.png")
	get_tree().quit()


func _aim(cam: Camera3D, look: Vector3, width: float) -> void:
	cam.size = width
	cam.basis = Basis.from_euler(Vector3(deg_to_rad(PITCH), deg_to_rad(YAW), 0))
	cam.position = look + cam.basis * Vector3(0, 0, 40)


func _save(vp: SubViewport, path: String) -> void:
	for k in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)


func _light(vp: SubViewport) -> void:
	var env := Environment.new()
	# The game's painted sky, as a 2D layer behind the scene.
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	var layer := CanvasLayer.new()
	layer.layer = -1
	vp.add_child(layer)
	var sky := TextureRect.new()
	sky.texture = load("res://art/ui/sky_bg.jpg")
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.size = Vector2(1080, 1300)
	layer.add_child(sky)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dcecff")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("fff0d6")
	key.light_energy = 1.15
	key.rotation_degrees = Vector3(-50, -10, 0)
	key.shadow_enabled = true
	key.shadow_opacity = 0.7
	key.shadow_blur = 1.5
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 30.0
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("b9d4ff")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-30, 150, 0)
	vp.add_child(fill)


static func cell_of(i: int) -> Vector2i:
	if i <= 7:
		return Vector2i(7 - i, 7)
	if i <= 14:
		return Vector2i(0, 14 - i)
	if i <= 21:
		return Vector2i(i - 14, 0)
	return Vector2i(7, i - 21)


## Which way a tile's front faces: toward the camera's side of its axis (+Z on the rows, +X on
## the columns), so every building shows its face and every stripe is on the visible edge.
static func front_of(i: int) -> Vector3:
	var c := cell_of(i)
	return Vector3(1, 0, 0) if (c.x == 0 or c.x == 7) and c.y != 0 and c.y != 7 else Vector3(0, 0, 1)


static func centre_of(i: int) -> Vector3:
	var c := cell_of(i)
	return Vector3(c.x - 3.5, 0, c.y - 3.5)


func _put(name: String, at: Vector3, colors := {}, front := Vector3(0, 0, 1)) -> Node3D:
	var n: Node3D = (load(KIT % name) as PackedScene).instantiate()
	n.position = at
	n.rotation.y = atan2(front.x, front.z)
	_scene.add_child(n)
	_paint(n, colors)
	return n


## Recolours the kit's named materials (Owner, Stripe) and turns on baked vertex colours.
func _paint(n: Node, colors: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			if m.resource_name.begins_with("Painted"):
				m.vertex_color_use_as_albedo = true
				m.vertex_color_is_srgb = false
			for key: String in colors:
				if m.resource_name.begins_with(key):
					var o := m.duplicate() as BaseMaterial3D
					o.albedo_color = colors[key]
					mi.set_surface_override_material(s, o)
	for c in n.get_children():
		_paint(c, colors)


func _build() -> void:
	_put("island", Vector3.ZERO)
	var levels := [0, 1, 2, -1, 3, 4, 5, -1, 2, 1, 0, 3, 4, 1, 2, -1, 1, 5, 2, 3, 0]
	var corners := {0: "c_payday", 7: "c_audit", 14: "c_jackpot", 21: "c_vault"}
	var specials := [5, 19, 25]
	var k := 0
	for i in 28:
		var at := centre_of(i)
		if corners.has(i):
			_put(corners[i], at).scale = Vector3.ONE * 1.12
			continue
		var d := k / 3
		var f := front_of(i)
		_put("tile", at, {"Stripe": Color("ffd23f") if i in specials else STRIPES[d % 7]}, f)
		if i in specials:
			var sp: String = {5: "s_metro", 19: "s_windfall", 25: "s_permit"}[i]
			_put(sp, at - f * 0.05, {}, f).scale = Vector3.ONE * 1.3
			continue
		var lvl: int = levels[k % levels.size()]
		var who := (k * 3 + 1) % 4
		k += 1
		var top := at + Vector3(0, TILE_TOP, 0) - f * 0.17
		if lvl < 0:
			_put("sale", top, {}, f).scale = Vector3.ONE * 1.4
		else:
			_put("b%d" % lvl, top, {"Owner": PLAYERS[who], "Wall": WALLS[(i * 5) % WALLS.size()]}, f).scale = Vector3.ONE * 1.25
		_label(at, f, "$%d" % (60 + i * 10))
	_put("centre", Vector3(0, 0.0, 0))
	for p in [[2, 0], [3, 2], [24, 3]]:
		_put("pawn", centre_of(p[0]) + Vector3(0, TILE_TOP, 0) + front_of(p[0]) * 0.18, {"Owner": PLAYERS[p[1]]})


## The price printed on a tile's stripe, facing the camera.
func _label(at: Vector3, f: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	var fv := FontVariation.new()
	fv.base_font = load("res://art/fonts/Fredoka.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650}
	l.font = fv
	l.font_size = 84
	l.pixel_size = 0.0028
	l.outline_size = 0
	l.modulate = Color("1d2340")
	l.position = at + Vector3(0, TILE_TOP + 0.01, 0) + f * 0.385
	l.rotation = Vector3(deg_to_rad(-90), atan2(f.x, f.z), 0)
	_scene.add_child(l)
