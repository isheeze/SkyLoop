extends Control
## Greybox client: one human against three bots, plain buttons, no animation. It exists to
## prove the rules are fun before any art is made.
##
## Self-test flags (after `--`): --auto (bots play every seat), --seed N,
## --shot PATH --shot-after N (save a screenshot after N decisions and quit).

const Board = preload("res://core/board.gd")
const Game = preload("res://core/game.gd")
const Bot = preload("res://core/bot.gd")
const BoardView = preload("res://ui/board_view.gd")

const PLAYER_COLORS := [Color("ffd166"), Color("ef476f"), Color("06d6a0"), Color("4cc9f0")]
const LOG_LINES := 7

var g
var personas: Array = []
var bot_rng := RandomNumberGenerator.new()
var log_lines: Array = []
var auto := false
var seed_arg := -1
var shot_path := ""
var shot_after := 60
var decisions := 0

var header: Label
var view: Control
var log_label: Label
var prompt: Label
var buttons: HFlowContainer


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
	if shot_path != "":
		get_window().size = Vector2i(540, 960)
	_build_ui()
	_new_game()


func _build_ui() -> void:
	theme = Theme.new()
	theme.default_font_size = 30
	var bg := ColorRect.new()
	bg.color = Color("0d1119")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	header = Label.new()
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.custom_minimum_size.y = 170
	col.add_child(header)

	view = BoardView.new()
	view.custom_minimum_size = Vector2(1040, 1040)
	view.colors = PLAYER_COLORS
	col.add_child(view)

	log_label = Label.new()
	log_label.add_theme_font_size_override("font_size", 22)
	log_label.add_theme_color_override("font_color", Color("8b96ab"))
	log_label.custom_minimum_size.y = LOG_LINES * 30
	log_label.clip_text = true
	col.add_child(log_label)

	prompt = Label.new()
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(prompt)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	buttons = HFlowContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("h_separation", 12)
	buttons.add_theme_constant_override("v_separation", 12)
	scroll.add_child(buttons)


func _new_game() -> void:
	var rng := RandomNumberGenerator.new()
	if seed_arg >= 0:
		rng.seed = seed_arg
	else:
		rng.randomize()
	bot_rng.seed = rng.randi()
	var tycoons: Array = Board.TYCOONS.keys()
	var persona_keys: Array = Bot.PERSONAS.keys()
	var cfg := {"seed": rng.randi(), "players": []}
	personas = []
	log_lines = []
	decisions = 0
	for i in 4:
		var ty: String = tycoons.pop_at(rng.randi_range(0, tycoons.size() - 1))
		var pe: String = persona_keys[rng.randi_range(0, persona_keys.size() - 1)]
		personas.append(Bot.PERSONAS[pe])
		var pname := "P1 (you)" if i == 0 else "%s Bot %d" % [Bot.PERSONAS[pe].label, i]
		cfg.players.append({"name": pname, "tycoon": ty, "bot": i != 0})
	g = Game.new(cfg)
	view.g = g
	_pump()


## Runs bot decisions until the game needs the human, or ends.
func _pump() -> void:
	while true:
		_refresh()
		if g.over:
			_show_result()
			return
		var pd: Dictionary = g.pending
		var who: int = pd.player
		if shot_path != "" and decisions >= shot_after and who == 0:
			_show_choices(pd)
			await _save_shot()
			return
		if not (auto or g.players[who].is_bot):
			_show_choices(pd)
			return
		_clear_buttons()
		prompt.text = "%s is thinking…" % g.players[who].name
		if not auto:
			await get_tree().create_timer(0.6 if pd.type == "move" else 0.25).timeout
		g.submit(Bot.decide(g, personas[who], bot_rng))
		decisions += 1


func _choose(choice: Dictionary) -> void:
	_clear_buttons()
	if not g.submit(choice):
		push_warning("Rejected choice %s" % choice)
	decisions += 1
	_pump()


func _refresh() -> void:
	for ev: Dictionary in g.events:
		var line := _describe(ev)
		if line != "":
			log_lines.append(line)
	g.events.clear()
	while log_lines.size() > LOG_LINES:
		log_lines.pop_front()
	log_label.text = "\n".join(log_lines)
	header.text = "Round %d / %d\n%s — %s\nNext: %s" % [g.round_no, g.rounds, g.headline.title,
		g.headline.text, g.next_headline.title]
	view.queue_redraw()


func _show_result() -> void:
	_clear_buttons()
	var order := range(g.players.size())
	order.sort_custom(func(a: int, b: int) -> bool: return g.net_worth(a) > g.net_worth(b))
	var lines := []
	for pi: int in order:
		lines.append("%s %d" % [g.players[pi].name, g.net_worth(pi)])
	var how := "three districts" if g.win_reason == "districts" else "net worth"
	prompt.text = "%s wins on %s!   %s" % [g.players[g.winner].name, how, "  ·  ".join(lines)]
	var b := Button.new()
	b.text = "New game"
	b.custom_minimum_size = Vector2(0, 84)
	b.pressed.connect(_new_game)
	buttons.add_child(b)
	if shot_path != "":
		await _save_shot()


func _save_shot() -> void:
	_refresh()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_path)
	get_tree().quit()


# ---------------------------------------------------------------- choices

func _show_choices(pd: Dictionary) -> void:
	_clear_buttons()
	var p = g.players[pd.player]
	match pd.type:
		"move":
			prompt.text = "Your move. The sum is free; a single die costs a steer token (%d left)." % p.steer
			for s: int in pd.options:
				var tag := "" if pd.free.has(s) else "  ◆steer"
				_add("%d → %s%s" % [s, _dest_name(p.pos, s), tag], {"steps": s})
			if pd.can_shortcut:
				_add("★ Shortcut…", {}, _show_shortcut)
		"metro":
			prompt.text = "Metro: ride 1 to 6 stops."
			for s: int in pd.options:
				_add("%d → %s" % [s, _dest_name(p.pos, s)], {"steps": s})
		"perk":
			prompt.text = "Payday! Salary collected. Pick a perk."
			_add("+%d cash" % Board.PERK_CASH, {"perk": "cash"})
			_add("Permit: next build half price", {"perk": "permit"})
			_add("Shield: next rent halved", {"perk": "shield"})
		"buy":
			prompt.text = "%s is for sale." % Board.TILES[pd.tile].name
			_add("Buy for $%d" % pd.price, {"buy": true})
			_add("Send to auction", {"buy": false})
		"bid":
			var t: Dictionary = Board.TILES[pd.tile]
			prompt.text = "Blind auction: %s (list $%d). Highest sealed bid wins." % [t.name, t.price]
			_add("Pass", {"bid": 0})
			var seen := []
			for f: float in [0.5, 0.65, 0.8, 1.0, 1.2, 1.5]:
				var amount: int = clampi(int(t.price * f / 5.0) * 5, pd.min_bid, pd.max_bid)
				if not seen.has(amount):
					seen.append(amount)
					_add("$%d" % amount, {"bid": amount})
		"audit":
			prompt.text = "Audit! Pay the fee, or collect no rent until your next turn."
			_add("Pay $%d" % pd.fee, {"pay": true})
			_add("Take the freeze", {"pay": false})
		"takeover":
			prompt.text = "Hostile takeover: buy out %s from %s?" % [Board.TILES[pd.tile].name,
				g.players[g.owner_of[pd.tile]].name]
			_add("Buy out for $%d" % pd.cost, {"accept": true})
			_add("Leave it", {"accept": false})
		"manage":
			prompt.text = "Build, use your power, or end your turn."
			_add("End turn", {"a": "end"})
			for act: Dictionary in pd.actions:
				match act.a:
					"upgrade":
						var lvl: int = g.level_of[act.tile] + 1
						var what: String = Board.DISTRICTS[Board.TILES[act.tile].district].landmark \
							if lvl == Board.LANDMARK_LEVEL else "L%d" % lvl
						_add("Build %s %s  $%d" % [Board.TILES[act.tile].name, what, act.cost], act)
					"power":
						_add("★ " + _power_label(p.tycoon, act), act)


func _show_shortcut() -> void:
	_clear_buttons()
	prompt.text = "Shortcut: jump to which tile?"
	for t in Board.TILE_COUNT:
		if g.is_property(t) and t != g.players[g.turn].pos:
			_add(Board.TILES[t].name, {"shortcut": t})
	_add("Back", {}, func() -> void: _show_choices(g.pending))


func _power_label(tycoon: String, act: Dictionary) -> String:
	match tycoon:
		"developer":
			return "Free build: %s" % Board.TILES[act.tile].name
		"shark":
			return "Squeeze (double next rent)"
		"broker":
			return "Swap %s for %s" % [Board.TILES[act.give].name, Board.TILES[act.take].name]
	return "Power"


func _add(text: String, choice: Dictionary, custom: Callable = Callable()) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 84)
	if custom.is_valid():
		b.pressed.connect(custom)
	else:
		b.pressed.connect(_choose.bind(choice))
	buttons.add_child(b)


func _clear_buttons() -> void:
	for c in buttons.get_children():
		buttons.remove_child(c)
		c.queue_free()


func _dest_name(from: int, steps: int) -> String:
	return Board.TILES[(from + steps) % Board.TILE_COUNT].name


# ---------------------------------------------------------------- log

func _name(pi: int) -> String:
	if pi == Game.BANK:
		return "Bank"
	if pi == Game.POT:
		return "Jackpot"
	return g.players[pi].name


func _describe(ev: Dictionary) -> String:
	match ev.t:
		"turn":
			return "— %s —" % _name(ev.p)
		"move":
			return "%s %s %s" % [_name(ev.p), "jumps to" if ev.get("jump", false) else "moves to",
				Board.TILES[ev.to].name]
		"pay":
			return "%s pays %s $%d (%s)" % [_name(ev.from), _name(ev.to), ev.amount, ev.why]
		"own":
			return "%s gets %s for $%d (%s)" % [_name(ev.p), Board.TILES[ev.tile].name, ev.paid, ev.how]
		"build":
			return "%s builds level %d on %s" % [_name(ev.p), ev.level, Board.TILES[ev.tile].name]
		"bailout":
			return "%s is bailed out: $%d short" % [_name(ev.p), ev.amount]
		"frozen":
			return "%s is frozen by the audit" % _name(ev.p)
		"power":
			return "%s uses their power!" % _name(ev.p)
		"swap":
			return "%s swaps %s for %s's %s" % [_name(ev.p), Board.TILES[ev.give].name,
				_name(ev.rival), Board.TILES[ev.take].name]
		"auction_end":
			if ev.winner == -1:
				return "Auction: no bids for %s" % Board.TILES[ev.tile].name
			return "Auction bids: %s" % str(ev.bids.values())
		"headline":
			return "HEADLINE: %s" % ev.headline.title
		"no_rent":
			return "%s pays no rent on %s" % [_name(ev.p), Board.TILES[ev.tile].name]
	return ""
