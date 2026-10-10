extends Node3D
## Main scene: the painted sky, the floating island, the camera, the lobby and the HUD. Every
## match is played through the game service (Net autoload): the service decides, this scene
## animates what happened and sends the player's choices back.
##
## Self-test flags (after `--`): --auto (practice match, bots play my seat too, fast),
## --shot PATH --shot-after N (screenshot at my Nth decision, or the results with --auto),
## --menu-shot PATH, --page-shot NAME:PATH (lobby page or popup), --closeup TILE, --clean.

const Board = preload("res://core/board.gd")
const Game = preload("res://core/game.gd")
const Bot = preload("res://core/bot.gd")
const Economy = preload("res://core/economy.gd")
const Board3D = preload("res://game3d/board3d.gd")
const Hud = preload("res://ui/hud.gd")
const Lobby = preload("res://ui/lobby.gd")
const Modals = preload("res://ui/modals.gd")
const Dice3D = preload("res://game3d/dice3d.gd")

const PLAYER_COLORS := [Color("ffc23d"), Color("ff5d73"), Color("3ddc97"), Color("5cc8ff")]
const CAM_OFFSET := Vector3(0, 6.4, 6.1)
const CAM_LOOK := Vector3(0, 0, 0.6)

var g
var me := 0  # my seat in the current match
var meta: Array = []  # per seat {name, avatar, level, country}
var bot_rng := RandomNumberGenerator.new()
var board: Node3D
var hud: Control
var lobby: Control
var modals: Control
var camera: Camera3D
var dice3d: Node3D
var _sky: TextureRect
var _env: Environment
var _key: DirectionalLight3D
var _shake := 0.0  # camera shake strength, decays to 0
var _punch := 0.0  # camera push-in for big moments, decays to 0

var auto := false
var shot_path := ""
var shot_after := 1
var shot_tile := -1
var menu_shot := ""
var page_shot := ""
var closeup_tile := -1
var queue_tier := 0  # with --auto: join this table's queue instead of practice
var decisions := 0
var _focus := Vector3.ZERO
var _focus_target := Vector3.ZERO
var _orbit := false
var _orbit_angle := 0.0

var _in_match := false
var _greeted := false
var _room := -1
var _tier := 1
var _updates: Array = []
var _playing := false
var _pending := {}
var _ended := {}
var _deadline_seat := -1
var _deadline_secs := 20.0


func _ready() -> void:
	bot_rng.randomize()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--auto":
				auto = true
			"--shot":
				shot_path = args[i + 1]
			"--shot-after":
				shot_after = int(args[i + 1])
			"--tile":
				shot_tile = int(args[i + 1])
			"--menu-shot":
				menu_shot = args[i + 1]
			"--page-shot":
				page_shot = args[i + 1]
			"--closeup":
				closeup_tile = int(args[i + 1])
			"--queue":
				queue_tier = int(args[i + 1])
	_build_world()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.chosen.connect(_on_chosen)
	hud.quit_requested.connect(_on_leave)
	hud.visible = false
	lobby = Lobby.new()
	layer.add_child(lobby)
	modals = Modals.new()
	layer.add_child(modals)
	modals.setup(lobby)
	lobby.setup(modals)
	lobby.play.connect(_on_play)
	lobby.practice.connect(_on_practice)
	modals.results_closed.connect(_on_results_closed)
	modals.matchmaking_cancelled.connect(func() -> void: pass)
	Net.connected.connect(_on_net_ready)
	Net.message.connect(_on_net_message)
	_demo_board()
	lobby.visible = true
	_orbit = true
	Net.start()
	if auto or shot_path != "":
		if auto:
			Engine.time_scale = 4.0
		await Net.connected
		lobby.visible = false
		if queue_tier > 0:
			_on_play(queue_tier)
		else:
			Net.send({"t": "practice"})
	elif menu_shot != "" or page_shot != "":
		await Net.connected
		await get_tree().create_timer(1.2).timeout
		if page_shot != "":
			var parts := page_shot.split(":", true, 1)
			_show_page_for_shot(parts[0])
			await get_tree().create_timer(1.0).timeout
			shot_path = parts[1]
		else:
			shot_path = menu_shot
		await _save_shot()


func _show_page_for_shot(name: String) -> void:
	match name:
		"daily":
			modals.daily(Net.profile)
		"spin":
			modals.spin(Net.profile)
		"matchmaking":
			modals.matchmaking(2, Net.profile)
		"reward":
			modals.reward(300, 5, "Daily reward!")
		"levelup":
			modals.level_up(3)
		_:
			lobby.open_page(name)


func _build_world() -> void:
	# The painted sky is a 2D layer behind the 3D scene.
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff0e6")
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -1
	add_child(sky_layer)
	_sky = TextureRect.new()
	_sky.texture = load("res://art/ui/sky_bg.jpg")
	_sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky_layer.add_child(_sky)

	# Soft late-afternoon sun: warm, low contrast, light shadows.
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffe2c4")
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-48, -32, 0)
	key.shadow_enabled = true
	key.shadow_opacity = 0.55
	key.shadow_blur = 2.5
	key.directional_shadow_max_distance = 22.0
	# The board is small: one orthogonal shadow map instead of four cascades keeps the shadow
	# pass from re-drawing the whole city four times on phones.
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(key)
	_env = env
	_key = key
	_apply_quality()
	Fx.graphics_changed.connect(_apply_quality)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("c9d6ff")
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-35, 150, 0)
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
		var r := Vector3(0, 4.4, 9.6).rotated(Vector3.UP, _orbit_angle)
		camera.position = r
		camera.look_at(Vector3(0, -1.6, 0), Vector3.UP)
		return
	_focus = _focus.lerp(_focus_target, 1.0 - exp(-3.0 * delta / maxf(Engine.time_scale, 1.0)))
	_shake = move_toward(_shake, 0.0, delta * 0.9)
	_punch = move_toward(_punch, 0.0, delta * 0.5)
	_place_camera()


## High: shadows, glow, 2x MSAA. Low: none of those and 3D at 75% resolution.
func _apply_quality() -> void:
	var low := Fx.low_graphics()
	_key.shadow_enabled = not low
	_env.glow_enabled = not low
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	vp.scaling_3d_scale = 0.75 if low else 1.0
	Engine.max_fps = 60


func _parallax() -> void:
	if _sky == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_sky.pivot_offset = vp / 2
	_sky.scale = Vector2.ONE * 1.12
	_sky.position = Vector2(-_focus.x * 14.0 - sin(_orbit_angle) * 40.0, -_focus.z * 10.0)


func _place_camera() -> void:
	_parallax()
	# The camera keeps its width, so the whole board fits across every phone; taller phones
	# just show more sky and island. Wider (tablet-like) screens can come in a little.
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.y / maxf(vp.x, 1.0)
	var zoom := clampf(1.12 - (1.9 - aspect) * 0.15, 1.0, 1.12)
	var look := CAM_LOOK + _focus
	if closeup_tile >= 0:
		# Review mode: a low, close camera on one tile.
		look = (Board3D.tile_center(closeup_tile) if closeup_tile < 28 else Vector3.ZERO) + Vector3(0, 0.3, 0)
		camera.position = look + Vector3(-1.2, 1.5, 2.2)
		camera.look_at(look, Vector3.UP)
		return
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.12
	# Tall phones: lift the board into the space between the top bar and the action panel.
	camera.v_offset = 0.0 if _orbit else -clampf((aspect - 1.78) * 0.8, 0.0, 0.4)
	var tall := clampf((aspect - 1.78) / 0.45, 0.0, 1.0)
	var offset := CAM_OFFSET + Vector3(0, 2.2, -1.2) * tall
	offset = offset.normalized() * CAM_OFFSET.length() * (1.0 + 0.05 * tall)
	camera.position = look + offset * zoom * (1.0 - 0.35 * ease(_punch, 0.5)) + jitter
	camera.look_at(look + jitter * 0.5, Vector3.UP)


## Drifts the camera a little toward the action without losing the whole board.
func _focus_on(world: Vector3) -> void:
	_focus_target = Vector3(clampf(world.x * 0.08, -0.2, 0.2), 0, clampf(world.z * 0.15, -0.4, 0.4))


func _show_targets(pd: Dictionary) -> void:
	if pd.type != "move" and pd.type != "metro":
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


func _save_shot() -> void:
	if OS.get_cmdline_user_args().has("--clean"):
		hud.visible = false
		board.clear_targets()
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("PERF draw_calls=%d objects=%d primitives=%d fps=%d" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.TIME_FPS)])
	get_viewport().get_texture().get_image().save_png(shot_path)
	get_tree().quit()


func _on_net_ready() -> void:
	if auto or shot_path != "":
		return
	if not _in_match:
		_show_lobby()
		_greet()


## First launch: name and avatar. Then, once per session, the daily reward if it's waiting.
func _greet() -> void:
	if _greeted or menu_shot != "" or page_shot != "":
		return
	_greeted = true
	await get_tree().create_timer(0.6).timeout
	if not Net.is_onboarded():
		modals.welcome(Net.profile)
		await modals.welcomed
		await get_tree().create_timer(0.5).timeout
	if bool(Net.profile.get("daily_ready", false)) and not _in_match:
		modals.daily(Net.profile)


func _show_lobby() -> void:
	_in_match = false
	_room = -1
	_demo_board()
	hud.visible = false
	lobby.visible = true
	lobby.open_page("home")
	_orbit = true


## A bot match fast-forwarded to mid-game, so the lobby's island has a city on it.
func _demo_board() -> void:
	var cfg := {"seed": randi(), "players": []}
	for i in 4:
		cfg.players.append({"name": "Demo", "tycoon": Board.TYCOONS.keys()[i], "bot": true})
	var demo = Game.new(cfg)
	var rng := RandomNumberGenerator.new()
	while not demo.over and demo.round_no < 8:
		demo.submit(Bot.decide(demo, Bot.PERSONAS.values()[demo.pending.player % 3], rng))
	demo.events.clear()
	g = demo
	board.setup(g, PLAYER_COLORS)


func _on_play(tier: int) -> void:
	modals.matchmaking(tier, Net.profile)
	Net.send({"t": "queue", "tier": tier})


func _on_practice() -> void:
	modals.matchmaking(0, Net.profile)
	Net.send({"t": "practice"})


func _on_net_message(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"match_start":
			_start_match(msg)
		"update":
			if int(msg.room) == _room:
				_updates.append(msg)
				_drain_updates()
		"deadline":
			if _in_match:
				_deadline_seat = int(msg.get("seat", -1))
				_deadline_secs = float(msg.seconds)
				if not _playing:
					hud.set_deadline(_deadline_seat, _deadline_secs)
		"chat":
			if _in_match:
				hud.chat_bubble(int(msg.seat), str(msg.text))
		"match_end":
			_ended = msg
			_drain_updates()


func _start_match(msg: Dictionary) -> void:
	_in_match = true
	_room = int(msg.room)
	_tier = int(msg.tier)
	me = int(msg.seat)
	meta = msg.players
	if auto:
		print("[client] match_start room=%d tier=%d seat=%d players=%s" % [_room, _tier, me, str(meta.map(func(m): return m.name))])
	_updates.clear()
	_ended = {}
	_orbit = false
	g = Game.from_dict(msg.snapshot)
	if g == null:
		push_error("bad snapshot")
		return
	board.setup(g, PLAYER_COLORS)
	_apply_cosmetics()
	hud.setup(g, PLAYER_COLORS, me, meta)
	hud.show_headline(g.headline, g.next_headline)
	if not lobby.visible:
		pass
	lobby.visible = false
	hud.visible = true
	await modals.matchmaking_found(meta, me, PLAYER_COLORS)
	_coach("welcome")
	_updates.push_front({"room": _room, "snapshot": msg.snapshot,
		"events": (msg.events as Array).filter(func(ev: Dictionary) -> bool: return ev.t != "own"), "pending": msg.pending})
	_drain_updates()


## Uses the player's equipped pawn and dice skins.
func _apply_cosmetics() -> void:
	var eq: Dictionary = Net.profile.get("equipped", {})
	var token_id := str(eq.get("token", ""))
	if token_id != "":
		var it := Economy.shop_item(token_id)
		if not it.is_empty():
			board.tint_token(me, Color(it.color))
	var dice_id := str(eq.get("dice", ""))
	dice3d.skin = Color(Economy.shop_item(dice_id).color) if dice_id != "" else Color.WHITE


## Plays queued server updates one at a time; acks each so the server keeps everyone in step.
func _drain_updates() -> void:
	if _playing:
		return
	_playing = true
	while not _updates.is_empty():
		var u: Dictionary = _updates.pop_front()
		hud.clear_deadline()
		board.clear_targets()
		var next = Game.from_dict(u.snapshot)
		if next != null:
			g = next
			board.g = g
			hud.g = g
		for ev: Dictionary in u.events:
			await _play(ev)
		hud.refresh()
		board.refresh_labels()
		Net.send({"t": "ack"})
		_pending = u.pending
		if _updates.is_empty():
			_offer_turn()
	_playing = false
	if not _ended.is_empty():
		_finish_match()


func _offer_turn() -> void:
	var pd := _pending
	if pd.is_empty() or g.over:
		return
	var who := int(pd.player)
	if who != me:
		hud.waiting(who)
		if _deadline_seat == who:
			hud.set_deadline(who, _deadline_secs)
		return
	decisions += 1
	if auto:
		var choice := Bot.decide(g, Bot.PERSONAS.builder, bot_rng)
		_send_choice.call_deferred(choice)
		return
	if shot_path != "" and decisions >= shot_after:
		Engine.time_scale = 1.0
		hud.show_decision(pd)
		_show_targets(pd)
		if shot_tile >= 0:
			hud.show_tile(shot_tile)
		await get_tree().create_timer(0.8).timeout
		await _save_shot()
		return
	hud.show_decision(pd)
	_show_targets(pd)
	_coach(pd.type)
	hud.set_deadline(me, 20.0)


func _send_choice(choice: Dictionary) -> void:
	board.clear_targets()
	hud.clear_deadline()
	_pending = {}
	Net.send({"t": "choice", "choice": choice})


func _on_chosen(choice: Dictionary) -> void:
	_send_choice(choice)


func _finish_match() -> void:
	var msg := _ended
	_ended = {}
	if auto:
		print("[client] match_end room=%d place=%d coins=%s" % [_room, int(msg.place), str(msg.get("coins", "?"))])
	_in_match = false
	hud.clear_deadline()
	board.clear_targets()
	if int(msg.place) == 0:
		hud.confetti_2d()
	Fx.buzz(200 if int(msg.place) == 0 else 80, 0.8)
	if shot_path != "" and auto:
		modals.results(msg, meta, me, PLAYER_COLORS, msg.get("profile", Net.profile))
		await get_tree().create_timer(1.2).timeout
		await _save_shot()
		return
	modals.results(msg, meta, me, PLAYER_COLORS, msg.get("profile", Net.profile))


func _on_results_closed(again: bool) -> void:
	_show_lobby()
	if again:
		if _tier == 0:
			_on_practice()
		else:
			_on_play(_tier)


func _on_leave() -> void:
	Net.send({"t": "leave"})
	_updates.clear()
	_show_lobby()


# ---------------------------------------------------------------- first-time tips

const TIPS := {
	"welcome": "Welcome to Skyloop! Buy tiles, build them up and collect rent. Richest after the last round wins.",
	"move": "Tap a glowing tile to move there. The total is free; one die costs a steer token.",
	"buy": "Buy it, or send it to a sealed auction where everyone bids in secret.",
	"bid": "Sealed bid: nobody sees your offer. Highest bid wins the tile.",
	"manage": "Build on your tiles to raise their rent. Own all three in a district for big bonuses.",
	"takeover": "You can buy out a rival's tile for double its value, buildings included.",
}


func _coach(kind: String) -> void:
	if not TIPS.has(kind) or auto or shot_path != "":
		return
	var cfg := ConfigFile.new()
	cfg.load("user://tips.cfg")
	if cfg.get_value("seen", kind, false):
		return
	cfg.set_value("seen", kind, true)
	cfg.save("user://tips.cfg")
	hud.coach(TIPS[kind])


# ---------------------------------------------------------------- event playback

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## "You use", "Sana uses".
func _verb(pi: int, third: String, second: String) -> String:
	return second if pi == me else third


func _name(pi: int) -> String:
	if pi == me:
		return "You"
	return str(meta[pi].name) if pi >= 0 and pi < meta.size() else str(g.players[pi].name)


func _play(ev: Dictionary) -> void:
	match ev.t:
		"headline":
			Fx.play("headline")
			hud.show_headline(ev.headline, g.next_headline)
			hud.refresh()
			await _wait(0.5)
		"turn":
			hud.refresh()
			if ev.p == me and not auto:
				Fx.play("your_turn")
				Fx.buzz(25)
			_focus_on(board.token_position(ev.p))
		"roll":
			if ev.p == me and not auto and shot_path == "":
				await hud.wait_roll()
			Fx.play("dice")
			Fx.buzz(35, 0.4)
			var land := Vector3(_focus.x * 0.6, 0.06, _focus.z * 0.6 + 0.4)
			if closeup_tile < 0:
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
			_coins_for(ev)
			if ev.why == "rent" and ev.from == me and amount >= 150:
				_shake = 0.6
				hud.callout("-$%d" % amount, Color("ff5d73"), 104)
			elif ev.why == "rent" and ev.to == me and amount >= 100:
				hud.callout("+$%d" % amount, Color("ffc23d"), 104)
			if ev.to == me or ev.from == me:
				Fx.play("coin" if ev.to == me else "pay")
				if ev.from == me and amount >= 50:
					Fx.buzz(45, 0.6)
			match ev.why:
				"rent":
					hud.toast("%s paid %s $%d rent" % [_name(ev.from), _name(ev.to), amount])
					await _wait(0.5)
				"jackpot":
					Fx.play("jackpot")
					Fx.buzz(150, 0.8)
					hud.callout("JACKPOT!", Color("ffc23d"))
					board.confetti(Board3D.tile_center(14))
					_punch = 1.0
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
			if ev.level == Board.LANDMARK_LEVEL:
				_focus_on(Board3D.tile_center(ev.tile))
				_punch = 1.0
				Fx.play("celebrate")
				Fx.buzz(160, 0.8)
				board.confetti(Board3D.tile_center(ev.tile), 110)
				hud.callout("LANDMARK!", (PLAYER_COLORS[ev.p] as Color).lightened(0.1))
				await _wait(1.0)
			elif ev.p == me:
				Fx.play("levelup", -4.0)
				board.float_text(Board3D.tile_center(ev.tile) + Vector3(0, 0.5, 0), "LEVEL %d" % ev.level,
					Color("ffc23d"))
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
			if ev.p == me:
				Fx.buzz(120, 0.9)
			hud.toast("%s %s bailed out — $%d in debt" % [_name(ev.p), _verb(ev.p, "is", "are"), ev.amount], Color("ff7a8a"))
		"frozen":
			hud.toast("%s %s frozen by the audit ❄" % [_name(ev.p), _verb(ev.p, "is", "are")], Color("9fd0ff"))
		"no_rent":
			hud.toast("No rent due on %s" % Board.TILES[ev.tile].name)
		"power":
			hud.toast("%s %s %s!" % [_name(ev.p), _verb(ev.p, "uses", "use"), Board.TYCOONS[ev.tycoon].power.get_slice(":", 0)],
				Color("ffc857"))
			await _wait(0.4)
		"perk":
			if ev.p != me:
				hud.toast("%s %s a %s" % [_name(ev.p), _verb(ev.p, "takes", "take"), ev.perk])


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
	var pd: Dictionary = _pending
	if tile >= 0 and _in_match and int(pd.get("player", -1)) == me and (pd.type == "move" or pd.type == "metro"):
		for s: int in pd.options:
			if (g.players[me].pos + s) % Board.TILE_COUNT == tile:
				hud.hide_tile()
				hud._emit({"steps": s})
				return
	if tile >= 0:
		hud.show_tile(tile)
	else:
		hud.hide_tile()


func _notification(what: int) -> void:
	# Android back button: in a match, the menu; in the lobby, home then quit.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _in_match:
			hud.toggle_pause()
		elif lobby._page != "home":
			lobby.open_page("home")
		else:
			get_tree().quit()


## Flies coins along a payment: payer to payee, or from the paying tile for bank money.
func _coins_for(ev: Dictionary) -> void:
	var amount: int = ev.amount
	var n := clampi(amount / 25, 3, 14)
	var from := Vector3.INF
	var to := Vector3.INF
	if ev.from >= 0:
		from = board.token_position(ev.from)
	if ev.to >= 0:
		to = board.token_position(ev.to)
	match ev.why:
		"salary":
			from = Board3D.tile_center(0)
		"jackpot":
			from = Board3D.tile_center(14)
		"windfall":
			from = Board3D.tile_center(19)
		"tax_raid", "audit":
			to = Board3D.tile_center(14)
	if from == Vector3.INF or to == Vector3.INF or from.distance_to(to) < 0.05:
		return
	board.coin_flight(from, to, n)
