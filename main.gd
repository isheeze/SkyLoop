extends Node
## Main scene: the painted sky, the painted board, the lobby and the HUD. Every
## match is played through the game service (Net autoload): the service decides, this scene
## animates what happened and sends the player's choices back.
##
## Self-test flags (after `--`): --auto (practice match, bots play my seat too, fast),
## --shot PATH --shot-after N (screenshot at my Nth decision, or the results with --auto),
## --menu-shot PATH, --page-shot NAME:PATH (lobby page or popup), --board ID, --clean.

const Board = preload("res://core/board.gd")
const Game = preload("res://core/game.gd")
const Bot = preload("res://core/bot.gd")
const Economy = preload("res://core/economy.gd")
const Board2D = preload("res://game2d/board2d.gd")
const Hud = preload("res://ui/hud.gd")
const Lobby = preload("res://ui/lobby.gd")
const Modals = preload("res://ui/modals.gd")
const Themes = preload("res://game3d/themes.gd")

const PLAYER_COLORS := [Color("ffc23d"), Color("ff5d73"), Color("3ddc97"), Color("5cc8ff")]

var g
var me := 0  # my seat in the current match
var meta: Array = []  # per seat {name, avatar, level, country}
var bot_rng := RandomNumberGenerator.new()
var board: Control
var hud: Control
var lobby: Control
var modals: Control
var _sky: TextureRect

var auto := false
var shot_path := ""
var shot_after := 1
var shot_tile := -1
var menu_shot := ""
var page_shot := ""
var board_override := ""  # --board ID: play every match on this painted board (art review)
var snap_path := ""  # with --queue: screenshot the real flow after --snap-after seconds
var snap_after := 20.0
var queue_tier := 0  # with --auto: join this table's queue instead of practice
var decisions := 0
var _drift := 0.0

var _in_match := false
var _lobby_tier := 1  # the table showing in the lobby carousel
var _practice_tier := 1  # practice matches use the look of the table picked in the lobby
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
			"--queue":
				queue_tier = int(args[i + 1])
			"--snap":
				snap_path = args[i + 1]
			"--snap-after":
				snap_after = float(args[i + 1])
			"--board":
				board_override = args[i + 1]
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
	elif queue_tier > 0 and snap_path != "":
		# Real-flow check: join a table like a player would, screenshot after N seconds.
		await Net.connected
		await get_tree().create_timer(1.0).timeout
		_on_play(queue_tier)
		await get_tree().create_timer(snap_after).timeout
		shot_path = snap_path
		await _save_shot()
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
	# The painted sky, and in front of it the painted board with the game drawn on top.
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -1
	add_child(sky_layer)
	_sky = TextureRect.new()
	_sky.texture = load("res://art/ui/sky_bg.jpg")
	_sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky_layer.add_child(_sky)
	var board_layer := CanvasLayer.new()
	board_layer.layer = 0
	add_child(board_layer)
	board = Board2D.new()
	board_layer.add_child(board)
	Engine.max_fps = 60


func _process(delta: float) -> void:
	# The sky drifts slowly behind the island.
	_drift += delta
	var vp := get_viewport().get_visible_rect().size
	_sky.pivot_offset = vp / 2
	_sky.scale = Vector2.ONE * 1.1
	_sky.position = Vector2(sin(_drift * 0.05) * 30.0, cos(_drift * 0.04) * 12.0)
	# In a match the board fits the space between the player cards and the action panel.
	if hud != null and hud.visible:
		var ins: Vector2 = hud.board_insets()
		board.set_free_rect(Rect2(0, ins.x, vp.x, maxf(vp.y - ins.x - ins.y, vp.y * 0.4)))
	else:
		board.set_free_rect(Rect2(0, vp.y * 0.18, vp.x, vp.y * 0.62))


## Kept for event code: the 2D board is always fully in view.
func _focus_on(_point: Vector2) -> void:
	pass  # the whole board is always in view


func _show_targets(pd: Dictionary) -> void:
	if pd.type != "move" and pd.type != "metro":
		return
	var list := []
	for s: int in pd.options:
		var pv: Dictionary = g.landing_preview(pd.player, s)
		pv.steps = s
		list.append(pv)
	board.show_targets(list)



func _save_shot() -> void:
	if OS.get_cmdline_user_args().has("--clean"):
		hud.visible = false
		lobby.visible = false
		modals.visible = false
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
	board.setup(g, PLAYER_COLORS, _board_for(_lobby_tier))


func _on_play(tier: int) -> void:
	modals.matchmaking(tier, Net.profile)
	Net.send({"t": "queue", "tier": tier})


## Each table has its own painted world; tables without one yet use the hill town.
func _board_for(tier: int) -> String:
	if board_override != "":
		return board_override
	var id := str(Themes.for_tier(tier).id)
	return id if ResourceLoader.exists("res://art/boards/%s/board.json" % id) else "sky_game"


func _on_practice() -> void:
	_practice_tier = _lobby_tier
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
	g = Game.from_dict(msg.snapshot)
	if g == null:
		push_error("bad snapshot")
		return
	board.setup(g, PLAYER_COLORS, _board_for(_tier if _tier > 0 else _practice_tier),
		meta.map(func(m: Dictionary) -> String: return str(m.get("avatar", "a01"))))
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
		board.set_active(int(u.pending.get("player", -1)) if not u.pending.is_empty() else -1)
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
	hud.match_over()
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
			hud.turn_status(ev.p)
			board.set_active(ev.p)
			if ev.p == me and not auto:
				Fx.play("your_turn")
				Fx.buzz(25)
			_focus_on(board.token_position(ev.p))
		"roll":
			if ev.p == me and not auto and shot_path == "":
				await hud.wait_roll()
			Fx.play("dice")
			Fx.buzz(35, 0.4)
			await hud.roll_dice(ev.dice)
		"move":
			board.clear_targets()
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
				board.shake(0.6)
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
					board.confetti(board.tile_point(14))
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
				Fx.play("celebrate")
				Fx.buzz(160, 0.8)
				board.confetti(board.tile_point(ev.tile), 110)
				hud.callout("LANDMARK!", (PLAYER_COLORS[ev.p] as Color).lightened(0.1))
				await _wait(1.0)
			elif ev.p == me:
				Fx.play("levelup", -4.0)
				board.float_text(board.tile_point(ev.tile), "LEVEL %d" % ev.level,
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
	var tile: int = board.tile_at_screen(pos)
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
	var from := Vector2.INF
	var to := Vector2.INF
	if ev.from >= 0:
		from = board.token_position(ev.from)
	if ev.to >= 0:
		to = board.token_position(ev.to)
	match ev.why:
		"salary":
			from = board.tile_point(0)
		"jackpot":
			from = board.tile_point(14)
		"windfall":
			from = board.tile_point(19)
		"tax_raid", "audit":
			to = board.tile_point(14)
	if from == Vector2.INF or to == Vector2.INF or from.distance_to(to) < 4.0:
		return
	board.coin_flight(from, to, n)
