extends Node3D
## Main scene: sunset lighting, camera, the 3D board, the title menu and the HUD, plus the
## game loop that plays engine events as animations and routes decisions to the player or
## the bots.
##
## Self-test flags (after `--`): --menu-shot PATH (screenshot the title screen),
## --auto (bots play every seat), --seed N,
## --shot PATH --shot-after N (save a screenshot at the human's first decision after N
## decisions, or at the end of the game, then quit), --tile N (open a tile card for the shot).

const Board = preload("res://core/board.gd")
const Game = preload("res://core/game.gd")
const Bot = preload("res://core/bot.gd")
const Board3D = preload("res://game3d/board3d.gd")
const Hud = preload("res://ui/hud.gd")
const Menu = preload("res://ui/menu.gd")
const Dice3D = preload("res://game3d/dice3d.gd")

const SAVE_PATH := "user://match.save"
const PLAYER_COLORS := [Color("ffc857"), Color("ff5d73"), Color("3ddc97"), Color("5cc8ff")]
const CAM_OFFSET := Vector3(0, 8.6, 3.9)
const CAM_LOOK := Vector3(0, 0, 0.35)

var g
var personas: Array = []
var bot_rng := RandomNumberGenerator.new()
var board: Node3D
var hud: Control
var menu: Control
var camera: Camera3D
var dice3d: Node3D

var auto := false
var seed_arg := -1
var shot_path := ""
var shot_after := 40
var shot_tile := -1
var decisions := 0
var _pump_session := -1
var _focus := Vector3.ZERO
var _focus_target := Vector3.ZERO
var _orbit := false
var _orbit_angle := 0.0
var _session := 0
var menu_shot := ""
var resume_shot := ""
var closeup_tile := -1
var showcase := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--auto":
				auto = true
			"--seed":
				seed_arg = int(args[i + 1])
			"--shot":
				shot_path = args[i + 1]
			"--shot-after":
				shot_after = int(args[i + 1])
			"--tile":
				shot_tile = int(args[i + 1])
			"--menu-shot":
				menu_shot = args[i + 1]
			"--showcase":
				showcase = true
			"--closeup":
				closeup_tile = int(args[i + 1])
			"--resume-shot":
				resume_shot = args[i + 1]
	_build_world()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.chosen.connect(_on_chosen)
	hud.quit_requested.connect(_show_menu)
	menu = Menu.new()
	layer.add_child(menu)
	menu.setup(hud)
	menu.start.connect(_on_start)
	menu.resume.connect(_on_resume)
	if auto or shot_path != "":
		if auto:
			Engine.time_scale = 4.0
		menu.visible = false
		_new_game("", Board.ROUNDS)
	else:
		_show_menu()
		if resume_shot != "":
			_on_start("shark", 8)
			while g.pending.player != 0 or hud._actions.get_child_count() == 0:
				await get_tree().create_timer(0.2).timeout
			var before: int = g.players[0].cash
			_save_match()
			_show_menu()
			await get_tree().create_timer(0.5).timeout
			_on_resume()
			await get_tree().create_timer(1.5).timeout
			print("RESUME cash before=%d after=%d tycoon=%s" % [before, g.players[0].cash, g.players[0].tycoon])
			shot_path = resume_shot
			await _save_shot()
		if menu_shot != "":
			await get_tree().create_timer(1.5).timeout
			shot_path = menu_shot
			await _save_shot()


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("4466b8")
	sm.sky_horizon_color = Color("ffc6a5")
	sm.ground_horizon_color = Color("f2b7a6")
	sm.ground_bottom_color = Color("8e8fc4")
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cbc4e8")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = false
	env.fog_light_color = Color("f0c4b4")
	env.fog_density = 0.004
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.light_color = Color("ffd2a6")
	key.light_energy = 2.0
	key.rotation_degrees = Vector3(-36, -38, 0)
	key.shadow_enabled = true
	key.shadow_blur = 1.6
	key.directional_shadow_max_distance = 26.0
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("9db4ff")
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(-55, 140, 0)
	add_child(fill)

	board = Board3D.new()
	add_child(board)
	dice3d = Dice3D.new()
	add_child(dice3d)

	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 52.0
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = false
	attrs.dof_blur_far_distance = 11.0
	attrs.dof_blur_far_transition = 6.0
	attrs.dof_blur_near_enabled = false
	attrs.dof_blur_near_distance = 4.5
	attrs.dof_blur_near_transition = 2.0
	attrs.dof_blur_amount = 0.025
	camera.attributes = attrs
	add_child(camera)
	_place_camera()


func _process(delta: float) -> void:
	if _orbit:
		_orbit_angle += delta * 0.07
		var r := Vector3(0, 11.5, 9.5).rotated(Vector3.UP, _orbit_angle)
		camera.position = r
		camera.look_at(Vector3(0, -1.2, 0), Vector3.UP)
		return
	_focus = _focus.lerp(_focus_target, 1.0 - exp(-3.0 * delta / maxf(Engine.time_scale, 1.0)))
	_place_camera()


## Title screen: a bot-only match is fast-forwarded so the city has buildings, then the
## camera circles it.
func _show_menu() -> void:
	_session += 1
	var cfg := {"seed": randi(), "players": []}
	personas = []
	for i in 4:
		cfg.players.append({"name": "Bot", "tycoon": Board.TYCOONS.keys()[i], "bot": true})
		personas.append(Bot.PERSONAS.values()[i % 3])
	g = Game.new(cfg)
	while not g.over and g.round_no < 8:
		g.submit(Bot.decide(g, personas[g.pending.player], bot_rng))
	g.events.clear()
	board.setup(g, PLAYER_COLORS)
	hud.visible = false
	menu.visible = true
	menu.set_can_resume(FileAccess.file_exists(SAVE_PATH))
	_orbit = true


func _on_resume() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = f.get_var() if f != null else null
	var restored = Game.from_dict(data.game) if data is Dictionary and data.has("game") else null
	if restored == null:
		DirAccess.remove_absolute(SAVE_PATH)
		menu.set_can_resume(false)
		return
	_session += 1
	_orbit = false
	menu.visible = false
	hud.visible = true
	g = restored
	personas = data.personas
	bot_rng.seed = data.bot_rng[0]
	bot_rng.state = data.bot_rng[1]
	board.setup(g, PLAYER_COLORS)
	hud.setup(g, PLAYER_COLORS, 0)
	hud.show_headline(g.headline, g.next_headline)
	_focus_on(board.token_position(g.turn))
	if g.pending.get("type", "") == "move":
		await hud.roll_dice(g.dice)
	_pump()


## Autosave, taken whenever the game waits on the human, so a match survives the app being
## closed or killed.
func _save_match() -> void:
	if g == null or g.over or auto or shot_path != "":
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_var({"game": g.to_dict(), "personas": personas, "bot_rng": [bot_rng.seed, bot_rng.state]})


func _on_start(tycoon: String, rounds: int) -> void:
	_orbit = false
	menu.visible = false
	hud.visible = true
	_new_game(tycoon, rounds)


func _place_camera() -> void:
	# Taller phones have spare height, so come in closer and let the board fill it.
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.y / maxf(vp.x, 1.0)
	var zoom := clampf(1.0 - (aspect - 1.78) * 0.3, 0.86, 1.0)
	var look := CAM_LOOK + _focus
	if closeup_tile >= 0:
		# Review mode: a low, close camera on one tile.
		look = Board3D.tile_center(closeup_tile) + Vector3(0, 0.3, 0)
		camera.position = look + Vector3(-1.2, 1.5, 2.2)
		camera.look_at(look, Vector3.UP)
		return
	camera.position = look + CAM_OFFSET * zoom
	camera.look_at(look, Vector3.UP)


## Drifts the camera a little toward the action without losing the whole board.
func _focus_on(world: Vector3) -> void:
	_focus_target = Vector3(clampf(world.x * 0.6, -1.8, 1.8), 0, clampf(world.z * 0.45, -1.3, 1.3))


func _new_game(my_tycoon: String, rounds: int) -> void:
	_session += 1
	var rng := RandomNumberGenerator.new()
	if seed_arg >= 0:
		rng.seed = seed_arg
	else:
		rng.randomize()
	bot_rng.seed = rng.randi()
	var tycoons: Array = Board.TYCOONS.keys()
	if my_tycoon != "":
		tycoons.erase(my_tycoon)
	var persona_keys: Array = Bot.PERSONAS.keys()
	var names := ["You", "Vera", "Marco", "Juno"]
	var cfg := {"seed": rng.randi(), "rounds": rounds, "players": []}
	personas = []
	decisions = 0
	for i in 4:
		var ty: String = my_tycoon if i == 0 and my_tycoon != "" \
			else tycoons.pop_at(rng.randi_range(0, tycoons.size() - 1))
		var pe: String = persona_keys[rng.randi_range(0, persona_keys.size() - 1)]
		personas.append(Bot.PERSONAS[pe])
		cfg.players.append({"name": names[i], "tycoon": ty, "bot": i != 0})
	g = Game.new(cfg)
	board.setup(g, PLAYER_COLORS)
	hud.setup(g, PLAYER_COLORS, 0)
	if showcase:
		# Review staging: the whole Docklands district built up, landmark included.
		for k in 3:
			var t: int = Board.district_tiles(0)[k]
			g.owner_of[t] = 0
			g.level_of[t] = [3, 4, 5][k]
		board.setup(g, PLAYER_COLORS)
		board.set_tags_visible(false)
	# Starting deeds are already on the board; skip their announcements.
	g.events = g.events.filter(func(ev: Dictionary) -> bool: return ev.t != "own")
	_pump()


func _show_targets(pd: Dictionary) -> void:
	if showcase or (pd.type != "move" and pd.type != "metro"):
		return
	var list := []
	for s: int in pd.options:
		var pv: Dictionary = g.landing_preview(pd.player, s)
		pv.steps = s
		list.append(pv)
	board.show_targets(list)
	var mid := Vector3.ZERO
	for pv: Dictionary in list:
		mid += Board3D.tile_center(pv.tile)
	_focus_on(mid / list.size())


func _on_chosen(choice: Dictionary) -> void:
	board.clear_targets()
	if not g.submit(choice):
		push_warning("Rejected choice %s" % choice)
	decisions += 1
	_pump()


func _pump() -> void:
	# One pump loop per session; a loop from an abandoned game exits on its own.
	if _pump_session == _session:
		return
	_pump_session = _session
	var session := _session
	while true:
		await _play_events()
		if session != _session:
			break
		if g.over:
			DirAccess.remove_absolute(SAVE_PATH)
			Fx.play("win" if g.winner == 0 else "lose")
			Fx.buzz(200 if g.winner == 0 else 80, 0.8)
			hud.show_results(_show_menu)
			if shot_path != "":
				await get_tree().create_timer(0.6 * Engine.time_scale).timeout
				await _save_shot()
			break
		var pd: Dictionary = g.pending
		var who: int = pd.player
		if shot_path != "" and decisions >= shot_after and who == 0:
			Engine.time_scale = 1.0
			hud.show_decision(pd)
			_show_targets(pd)
			if shot_tile >= 0:
				hud.show_tile(shot_tile)
			await get_tree().create_timer(0.8).timeout
			await _save_shot()
			break
		if auto or g.players[who].is_bot:
			hud.waiting(who)
			if not auto:
				await get_tree().create_timer(0.45).timeout
			if session != _session:
				break
			g.submit(Bot.decide(g, personas[who], bot_rng))
			decisions += 1
			continue
		hud.show_decision(pd)
		_show_targets(pd)
		_save_match()
		break
	if _pump_session == session:
		_pump_session = -1


func _save_shot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_path)
	get_tree().quit()


# ---------------------------------------------------------------- event playback

func _play_events() -> void:
	var session := _session
	while not g.events.is_empty() and session == _session:
		var ev: Dictionary = g.events.pop_front()
		await _play(ev)
	hud.refresh()
	board.refresh_labels()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _name(pi: int) -> String:
	return "You" if pi == 0 else g.players[pi].name


func _play(ev: Dictionary) -> void:
	match ev.t:
		"headline":
			Fx.play("headline")
			hud.show_headline(ev.headline, g.next_headline)
			hud.refresh()
			await _wait(0.5)
		"turn":
			hud.refresh()
			if ev.p == 0 and not auto:
				Fx.play("your_turn")
				Fx.buzz(25)
			_focus_on(board.token_position(ev.p))
		"roll":
			Fx.play("dice")
			Fx.buzz(35, 0.4)
			var land := Vector3(_focus.x * 0.6, 0.06, _focus.z * 0.6 + 0.4)
			dice3d.throw(ev.dice, land)
			await hud.roll_dice(ev.dice)
		"move":
			board.clear_targets()
			dice3d.clear()
			_focus_on(Board3D.tile_center(ev.to))
			await board.move_token(ev.p, ev.from, ev.to, ev.get("jump", false))
			Fx.play("land")
			Fx.buzz(15, 0.3)
		"pay":
			var amount: int = ev.amount
			if ev.from >= 0:
				board.float_text(board.token_position(ev.from), "-$%d" % amount, Color("ff7a8a"))
			if ev.to >= 0:
				board.float_text(board.token_position(ev.to), "+$%d" % amount, Color("7dffb0"))
			hud.refresh()
			if ev.to == 0 or ev.from == 0:
				Fx.play("coin" if ev.to == 0 else "pay")
				if ev.from == 0 and amount >= 50:
					Fx.buzz(45, 0.6)
			match ev.why:
				"rent":
					hud.toast("%s paid %s $%d rent" % [_name(ev.from), _name(ev.to), amount])
					await _wait(0.5)
				"jackpot":
					Fx.play("jackpot")
					Fx.buzz(150, 0.8)
					hud.toast("JACKPOT! %s takes $%d" % [_name(ev.to), amount], Color("ffd35c"))
					await _wait(0.7)
				"tax_raid":
					hud.toast("Tax raid: %s pays $%d" % [_name(ev.from), amount], Color("ff7a8a"))
				"wealth_tax":
					hud.toast("Wealth tax: %s → %s $%d" % [_name(ev.from), _name(ev.to), amount])
				"windfall":
					hud.toast("Windfall! +$%d" % amount, Color("7dffb0"))
		"own":
			Fx.play("buy")
			Fx.buzz(25)
			board.update_tile(ev.tile)
			var how := {"buy": "bought", "auction": "won the auction for", "takeover": "took over"}
			hud.toast("%s %s %s · $%d" % [_name(ev.p), how.get(ev.how, "got"), Board.TILES[ev.tile].name, ev.paid],
				(PLAYER_COLORS[ev.p] as Color).lightened(0.2))
			await _wait(0.45)
		"build":
			Fx.play("landmark" if ev.level == Board.LANDMARK_LEVEL else "build")
			Fx.buzz(30)
			board.update_tile(ev.tile)
			var what: String = Board.DISTRICTS[Board.TILES[ev.tile].district].landmark \
				if ev.level == Board.LANDMARK_LEVEL else "level %d" % ev.level
			hud.toast("%s built %s on %s" % [_name(ev.p), what, Board.TILES[ev.tile].name],
				(PLAYER_COLORS[ev.p] as Color).lightened(0.2))
			await _wait(0.55)
		"swap":
			board.update_tile(ev.give)
			board.update_tile(ev.take)
		"auction_start":
			Fx.play("auction")
			hud.toast("Sealed auction: %s" % Board.TILES[ev.tile].name, Color("ffc857"))
		"auction_end":
			if ev.winner == -1:
				hud.toast("No bids. %s stays on the market." % Board.TILES[ev.tile].name)
		"bailout":
			Fx.play("bailout")
			if ev.p == 0:
				Fx.buzz(120, 0.9)
			hud.toast("%s is bailed out — $%d in debt" % [_name(ev.p), ev.amount], Color("ff7a8a"))
		"frozen":
			hud.toast("%s is frozen by the audit ❄" % _name(ev.p), Color("9fd0ff"))
		"no_rent":
			hud.toast("No rent due on %s" % Board.TILES[ev.tile].name)
		"power":
			hud.toast("%s uses %s!" % [_name(ev.p), Board.TYCOONS[ev.tycoon].power.get_slice(":", 0)],
				Color("ffc857"))
			await _wait(0.4)
		"perk":
			if ev.p != 0:
				hud.toast("%s takes a %s" % [_name(ev.p), ev.perk])


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	else:
		return
	var origin := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	if absf(dir.y) < 0.001:
		return
	var hit := origin + dir * ((Board3D.TILE_TOP - origin.y) / dir.y)
	var tile := Board3D.tile_at(hit)
	# Tapping a highlighted destination makes that move.
	var pd: Dictionary = g.pending if g != null else {}
	if tile >= 0 and not menu.visible and pd.get("player", -1) == 0 and (pd.type == "move" or pd.type == "metro"):
		for s: int in pd.options:
			if (g.players[0].pos + s) % Board.TILE_COUNT == tile:
				hud.hide_tile()
				hud._emit({"steps": s})
				return
	if tile >= 0:
		hud.show_tile(tile)
	else:
		hud.hide_tile()


func _notification(what: int) -> void:
	# Android back button: from a game, open the pause menu; from the title screen, quit.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if menu != null and not menu.visible:
			_save_match()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if menu.visible:
			get_tree().quit()
		else:
			hud.toggle_pause()
