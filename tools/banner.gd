extends Node
## Renders each city's lobby table-card banner (art/ui/banners/<theme>.jpg): a mid-game board
## seen like the game camera, offscreen at full resolution. Needs a window:
##   godot --path . res://tools/banner.tscn

const Board3D = preload("res://game3d/board3d.gd")
const Board = preload("res://core/board.gd")
const Game = preload("res://core/game.gd")
const Bot = preload("res://core/bot.gd")
const Themes = preload("res://game3d/themes.gd")
const COLORS := [Color("ffc23d"), Color("ff5d73"), Color("3ddc97"), Color("5cc8ff")]


func _ready() -> void:
	await get_tree().process_frame
	var vp := SubViewport.new()
	vp.size = Vector2i(2080, 940)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9fd6ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dcecff")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffe2c4")
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-52, -10, 0)
	key.shadow_enabled = true
	key.shadow_opacity = 0.55
	vp.add_child(key)
	var cfg := {"seed": 7, "players": []}
	for i in 4:
		cfg.players.append({"name": "Demo", "tycoon": Board.TYCOONS.keys()[i], "bot": true})
	var demo = Game.new(cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	while not demo.over and demo.round_no < 7:
		demo.submit(Bot.decide(demo, Bot.PERSONAS.values()[demo.pending.player % 3], rng))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 8.4
	cam.basis = Basis.from_euler(Vector3(deg_to_rad(-40), deg_to_rad(45), 0))
	cam.position = Vector3(0.0, 0.3, 0.0) + cam.basis * Vector3(0, 0, 30)
	cam.far = 80.0
	vp.add_child(cam)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/ui/banners"))
	for id: String in Themes.THEMES:
		var board := Board3D.new()
		vp.add_child(board)
		board.setup(demo, COLORS, id)
		board.set_tags_visible(false)
		board.set_life_visible(false)
		key.light_color = Themes.THEMES[id].light
		for k in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://art/ui/banners/%s.jpg" % id), 0.88)
		print("banner saved ", id)
		board.queue_free()
		await get_tree().process_frame
	get_tree().quit()
