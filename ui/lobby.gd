extends Control
## The lobby over the slowly orbiting island: top bar (avatar, level, coins, gems), daily
## reward and spin icons, the tier carousel (one global ladder, city names in the player's
## country), Play / Practice, and the bottom navigation with Shop, Missions, Ranks, Profile.
## Talks to the service through the Net autoload.

signal play(tier: int)
signal practice
signal tier_changed(tier: int)  # the carousel settled on another table

const Kit = preload("res://ui/kit.gd")
const Themes = preload("res://game3d/themes.gd")
const Economy = preload("res://core/economy.gd")
const Modals = preload("res://ui/modals.gd")

const CARD_W := 800
const CARD_H := 440

var modals  # ui/modals.gd, shared with the game
var profile := {}
var tier := 1

var _home: Control
var _pages: Control
var _coins: Dictionary
var _gems: Dictionary
var _name: Label
var _level: Label
var _xp: Dictionary
var _avatar_slot: Control
var _daily_btn: Button
var _spin_btn: Button
var _daily_dot: Control
var _spin_dot: Control
var _strip: Control
var _cards: Array = []
var _dots: HBoxContainer
var _play_btn: Button
var _drag := false
var _drag_x := 0.0
var _offset := 0.0
var _nav_buttons := {}
var _page := "home"


func setup(modal_layer) -> void:
	modals = modal_layer
	theme = Kit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_home()
	_pages = Control.new()
	_pages.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pages)
	_build_nav()
	Net.profile_changed.connect(refresh)
	Net.message.connect(_on_message)
	if not Net.profile.is_empty():
		refresh(Net.profile)


# ---------------------------------------------------------------- home

func _build_home() -> void:
	_home = MarginContainer.new()
	_home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		_home.add_theme_constant_override("margin_" + side, 36)
	_home.add_theme_constant_override("margin_top", 54)
	_home.add_theme_constant_override("margin_bottom", 250)
	add_child(_home)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(col)

	# Top bar.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var who := Button.new()
	who.flat = true
	who.custom_minimum_size = Vector2(150, 150)
	who.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	who.pressed.connect(func() -> void: open_page("profile"))
	top.add_child(who)
	_avatar_slot = Control.new()
	_avatar_slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(_avatar_slot)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(info)
	_name = Kit.title("Player", 46)
	info.add_child(_name)
	var lv := HBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(lv)
	_level = _badge("Lv 1", Kit.VIOLET)
	lv.add_child(_level.get_parent())
	_xp = Kit.bar(170, 24, 0.0)
	_xp.root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv.add_child(_xp.root)
	var money := VBoxContainer.new()
	money.add_theme_constant_override("separation", 12)
	money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(money)
	_coins = Kit.pill("coins", 0, func() -> void: open_page("shop"))
	_gems = Kit.pill("gems", 0, func() -> void: open_page("shop"))
	money.add_child(_coins.panel)
	money.add_child(_gems.panel)

	# Logo between the two reward rails.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 6)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rail)
	var d := _rail_button("gift", "Daily", func() -> void: modals.daily(profile))
	_daily_btn = d.button
	_daily_dot = d.dot
	rail.add_child(_daily_btn)
	var s := _rail_button("wheel", "Spin", func() -> void: modals.spin(profile))
	_spin_btn = s.button
	_spin_dot = s.dot
	rail.add_child(_spin_btn)
	var logo := TextureRect.new()
	logo.texture = load("res://art/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 240)
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(logo)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 160
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	right.add_child(_rail_button("trophy", "Missions", func() -> void: open_page("missions")).button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	# Tier carousel: the centred card is full size, its neighbours peek in from the sides.
	_strip = Control.new()
	_strip.custom_minimum_size = Vector2(0, CARD_H + 30)
	_strip.clip_contents = false
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.gui_input.connect(_carousel_input)
	col.add_child(_strip)
	for i in Economy.TIERS.size():
		var card := _tier_card(i + 1)
		_strip.add_child(card)
		_cards.append(card)
	_dots = HBoxContainer.new()
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.add_theme_constant_override("separation", 12)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_dots)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(buttons)
	var prac := Kit.button("Practice", "", 170)
	prac.size_flags_stretch_ratio = 0.55
	prac.icon = load("res://art/icons/target.svg")
	prac.add_theme_color_override("icon_normal_color", Kit.INK)
	prac.add_theme_constant_override("icon_max_width", 56)
	prac.pressed.connect(func() -> void: practice.emit())
	buttons.add_child(prac)
	_play_btn = Kit.button("PLAY", "Primary", 170)
	_play_btn.add_theme_font_override("font", Kit.font(true, 700))
	_play_btn.add_theme_font_size_override("font_size", 66)
	_play_btn.pressed.connect(_on_play)
	buttons.add_child(_play_btn)
	_layout_cards()


func _badge(text: String, color: Color) -> Label:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 2
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Kit.label(text, 30, Color.WHITE, true, 600)
	p.add_child(l)
	return l


func _rail_button(icon: String, text: String, cb: Callable) -> Dictionary:
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size = Vector2(160, 186)
	for st in ["focus", "hover", "pressed", "normal"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.pressed.connect(func() -> void:
		Fx.play("click")
		Fx.buzz(12, 0.3)
		cb.call())
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := Kit.icon3d(icon, 140)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := Kit.title(text, 34)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var dot := Kit.dot()
	dot.position = Vector2(108, 4)
	dot.visible = false
	b.add_child(dot)
	# A gentle idle bob so the eye finds rewards.
	ic.pivot_offset = Vector2(70, 70)
	var tw := ic.create_tween().set_loops()
	tw.tween_property(ic, "rotation", 0.08, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ic, "rotation", -0.08, 0.9).set_trans(Tween.TRANS_SINE)
	return {"button": b, "dot": dot}


func _tier_card(t: int) -> Control:
	var spec: Dictionary = Economy.TIERS[t - 1]
	var color: Color = Kit.TIER_COLORS[t - 1]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.size = Vector2(CARD_W, CARD_H)
	var sb := Kit.box(Color.WHITE, 56)
	sb.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	# Banner: a window onto the city's painted board, with its name over a soft shade.
	var theme: Dictionary = Themes.for_tier(t)
	var banner := Panel.new()
	banner.custom_minimum_size = Vector2(0, 236)
	banner.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var bs := StyleBoxFlat.new()
	bs.bg_color = color
	bs.corner_radius_top_left = 56
	bs.corner_radius_top_right = 56
	bs.anti_aliasing = true
	banner.add_theme_stylebox_override("panel", bs)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(banner)
	var bdir := "sky_game" if str(theme.id) == "town" else str(theme.id) + "_game"
	var art_path := "res://art/boards/%s/base.jpg" % bdir
	if ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = load(art_path)
		at.region = Rect2(380, 620, 1040, 470)  # the board's heart: centrepiece and inner loop
		art.texture = at
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(art)
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0.11, 0.13, 0.25, 0.0), Color(0.11, 0.13, 0.25, 0.72)])
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0.2)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(shade)
	var pill := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.11, 0.13, 0.25, 0.72)
	ps.set_corner_radius_all(24)
	ps.content_margin_left = 20
	ps.content_margin_right = 20
	ps.content_margin_top = 6
	ps.content_margin_bottom = 8
	pill.add_theme_stylebox_override("panel", ps)
	pill.position = Vector2(34, 26)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(Kit.label(str(theme.name).to_upper(), 26, Color.WHITE, true, 600))
	banner.add_child(pill)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", -8)
	bv.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bv.offset_left = 40
	bv.offset_top = -132
	bv.offset_bottom = -18
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bv)
	var city := Kit.title(Economy.tier_name(t, Net.country).to_upper(), 78)
	city.name = "City"
	city.add_theme_constant_override("outline_size", 14)
	city.add_theme_color_override("font_outline_color", Color(0.11, 0.13, 0.25, 0.85))
	bv.add_child(city)
	var sub := Kit.label("TABLE %d  ·  %s" % [t, Economy.COUNTRY_NAMES.get(Net.country, "World").to_upper()],
		28, Color(1, 1, 1, 0.95), true, 600)
	bv.add_child(sub)
	# Body: twist, entry and prize.
	var body := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 34)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	var bb := VBoxContainer.new()
	bb.add_theme_constant_override("separation", 18)
	bb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(bb)
	var tw := HBoxContainer.new()
	tw.add_theme_constant_override("separation", 12)
	tw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bb.add_child(tw)
	tw.add_child(Kit.icon("lightning", 44, color.darkened(0.25)))
	var twist := Kit.label("%s: %s" % [spec.twist, spec.desc], 32, Kit.INK2, false, 800)
	twist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	twist.custom_minimum_size.x = CARD_W - 140
	twist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tw.add_child(twist)
	var stakes := HBoxContainer.new()
	stakes.add_theme_constant_override("separation", 18)
	stakes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bb.add_child(stakes)
	stakes.add_child(_stake("ENTRY", spec.entry, Kit.CREAM))
	stakes.add_child(_stake("WIN", Economy.prize(t), Color("eafbf3")))
	# Lock veil for tables above the player's level.
	var veil := PanelContainer.new()
	veil.name = "Veil"
	var vs := StyleBoxFlat.new()
	vs.bg_color = Color(0.11, 0.13, 0.25, 0.62)
	vs.set_corner_radius_all(56)
	veil.add_theme_stylebox_override("panel", vs)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vc := VBoxContainer.new()
	vc.alignment = BoxContainer.ALIGNMENT_CENTER
	vc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(vc)
	var lk := Kit.icon("lock", 110, Color.WHITE)
	lk.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vc.add_child(lk)
	var ll := Kit.title("Unlocks at level %d" % spec.level, 46)
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vc.add_child(ll)
	card.add_child(veil)
	return card


func _stake(caption: String, amount: int, bg: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(30)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	h.add_child(Kit.icon3d("coin", 64))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(Kit.label(caption, 26, Kit.INK2, false, 900))
	v.add_child(Kit.label(Kit.money(amount), 50, Kit.INK, true, 700))
	return p


# ---------------------------------------------------------------- carousel

func _carousel_input(ev: InputEvent) -> void:
	var press := false
	var release := false
	var x := 0.0
	if ev is InputEventScreenTouch:
		press = ev.pressed
		release = not ev.pressed
		x = ev.position.x
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		press = ev.pressed
		release = not ev.pressed
		x = ev.position.x
	elif (ev is InputEventScreenDrag or ev is InputEventMouseMotion) and _drag:
		_offset += ev.relative.x
		_layout_cards()
		return
	if press:
		_drag = true
		_drag_x = x
	elif release and _drag:
		_drag = false
		var moved := x - _drag_x
		if absf(moved) < 20.0:
			# A tap: tapping a neighbour moves to it.
			var w := _strip.size.x
			if x < w / 2 - CARD_W / 2:
				_go(tier - 1)
			elif x > w / 2 + CARD_W / 2:
				_go(tier + 1)
			else:
				_go(tier)
			return
		_go(tier - 1 if moved > 120 else (tier + 1 if moved < -120 else tier))


func _go(t: int) -> void:
	var changed := clampi(t, 1, Economy.TIERS.size()) != tier
	tier = clampi(t, 1, Economy.TIERS.size())
	if changed:
		Fx.play("toast", -4.0)
		Fx.buzz(10, 0.2)
		tier_changed.emit(tier)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_offset = v
		_layout_cards(), _offset, 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_update_play()


func _layout_cards() -> void:
	if _strip == null:
		return
	var w := _strip.size.x if _strip.size.x > 0 else 1008.0
	var step := CARD_W + 36.0
	for i in _cards.size():
		var c: Control = _cards[i]
		var rel := (i + 1 - tier) * step + _offset
		var k := clampf(1.0 - absf(rel) / step * 0.12, 0.86, 1.0)
		c.pivot_offset = Vector2(CARD_W / 2.0, CARD_H / 2.0)
		c.scale = Vector2(k, k)
		c.position = Vector2(w / 2.0 - CARD_W / 2.0 + rel, 10)
		c.modulate.a = clampf(1.2 - absf(rel) / step * 0.45, 0.4, 1.0)
	if _dots != null:
		for ch in _dots.get_children():
			ch.queue_free()
		for i in _cards.size():
			var dpan := Panel.new()
			var on := i + 1 == tier
			dpan.custom_minimum_size = Vector2(52 if on else 18, 18)
			var ds := StyleBoxFlat.new()
			ds.bg_color = Kit.GOLD if on else Color(1, 1, 1, 0.7)
			ds.set_corner_radius_all(9)
			dpan.add_theme_stylebox_override("panel", ds)
			dpan.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_dots.add_child(dpan)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_cards.call_deferred()


func _update_play() -> void:
	if _play_btn == null:
		return
	var spec: Dictionary = Economy.TIERS[tier - 1]
	var level := int(profile.get("level", 1))
	var coins := int(profile.get("coins", 0))
	if level < int(spec.level):
		_play_btn.text = "LOCKED"
		_play_btn.disabled = true
	else:
		_play_btn.disabled = false
		_play_btn.text = "PLAY · %s" % Kit.money(spec.entry) if coins >= int(spec.entry) else "GET COINS"


func _on_play() -> void:
	var spec: Dictionary = Economy.TIERS[tier - 1]
	if int(profile.get("coins", 0)) < int(spec.entry):
		modals.out_of_coins(profile)
		return
	play.emit(tier)


# ---------------------------------------------------------------- refresh

func refresh(p: Dictionary) -> void:
	var first := profile.is_empty()
	profile = p
	_name.text = str(p.get("name", "Player"))
	_level.text = "Lv %d" % int(p.get("level", 1))
	var frac := float(p.get("xp", 0)) / maxf(1.0, float(p.get("xp_next", 100)))
	_xp.fill.size.x = maxf(24.0, _xp.width * clampf(frac, 0.0, 1.0))
	_count(_coins.label, int(p.get("coins", 0)), first)
	_count(_gems.label, int(p.get("gems", 0)), first)
	for c in _avatar_slot.get_children():
		c.queue_free()
	_avatar_slot.add_child(Kit.avatar(str(p.get("avatar", "a01")), 150, Kit.GOLD, 8))
	_daily_dot.visible = bool(p.get("daily_ready", false))
	_spin_dot.visible = bool(p.get("spin_ready", false))
	for i in _cards.size():
		var veil: Control = _cards[i].get_node("Veil")
		veil.visible = int(p.get("level", 1)) < int(Economy.TIERS[i].level)
	if first:
		# Start on the best table the player can afford.
		for i in range(Economy.TIERS.size(), 0, -1):
			var s: Dictionary = Economy.TIERS[i - 1]
			if int(p.level) >= int(s.level) and int(p.coins) >= int(s.entry) * 3:
				tier = i
				break
		_layout_cards()
	_update_play()
	if _page != "home":
		_render_page(_page)


func _count(l: Label, to: int, instant: bool) -> void:
	var from := int(l.text.replace(",", "")) if l.text != "" else 0
	if instant or from == to:
		l.text = Kit.money(to)
		return
	create_tween().tween_method(func(v: float) -> void: l.text = Kit.money(int(v)), float(from), float(to), 0.8) \
		.set_trans(Tween.TRANS_QUAD)
	var pill: Control = l.get_parent().get_parent()
	pill.pivot_offset = pill.size / 2
	var tw := create_tween()
	tw.tween_property(pill, "scale", Vector2(1.12, 1.12), 0.12)
	tw.tween_property(pill, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		"leaderboard":
			if _page == "ranks":
				_ranks_rows = msg.rows
				_render_page("ranks")
		"error":
			match str(msg.msg):
				"coins":
					modals.out_of_coins(profile)
				"locked":
					modals.notice("Table locked", "Level up to sit at this table.")


func coin_pill_center() -> Vector2:
	return _coins.panel.get_global_rect().get_center()


func gem_pill_center() -> Vector2:
	return _gems.panel.get_global_rect().get_center()


# ---------------------------------------------------------------- navigation and pages

func _build_nav() -> void:
	var nav := PanelContainer.new()
	nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -230
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.corner_radius_top_left = 64
	sb.corner_radius_top_right = 64
	sb.shadow_color = Color(0.19, 0.12, 0.43, 0.15)
	sb.shadow_size = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 40
	nav.add_theme_stylebox_override("panel", sb)
	add_child(nav)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	nav.add_child(h)
	for item: Array in [["home", "house", "Home"], ["shop", "storefront", "Shop"], ["missions", "target", "Missions"],
			["ranks", "ranking", "Ranks"], ["profile", "user-circle", "Profile"]]:
		var b := Button.new()
		b.flat = true
		b.custom_minimum_size = Vector2(196, 170)
		for st in ["focus", "hover", "pressed", "normal"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var pad := PanelContainer.new()
		pad.custom_minimum_size = Vector2(124, 100)
		pad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(pad)
		var ic := Kit.icon(item[1], 60, Kit.INK2)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pad.add_child(ic)
		var l := Kit.label(item[2], 30, Kit.INK2, true, 600)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		var id: String = item[0]
		b.pressed.connect(func() -> void:
			Fx.play("click")
			Fx.buzz(10, 0.2)
			open_page(id))
		h.add_child(b)
		_nav_buttons[id] = {"pad": pad, "icon": ic, "label": l}
	_style_nav()


func _style_nav() -> void:
	for id in _nav_buttons:
		var n: Dictionary = _nav_buttons[id]
		var on: bool = id == _page
		var sb := StyleBoxFlat.new()
		sb.bg_color = Kit.GOLD if on else Color(0, 0, 0, 0)
		sb.border_color = Kit.GOLD_LIP
		sb.border_width_bottom = 10 if on else 0
		sb.set_corner_radius_all(34)
		n.pad.add_theme_stylebox_override("panel", sb)
		n.icon.modulate = Kit.GOLD_INK if on else Kit.INK2
		n.label.add_theme_color_override("font_color", Kit.INK if on else Kit.INK2)


func open_page(id: String) -> void:
	_page = id
	_style_nav()
	_home.visible = id == "home"
	for c in _pages.get_children():
		c.queue_free()
	if id != "home":
		if id == "ranks":
			_ranks_rows = []
			Net.send({"t": "leaderboard", "scope": _ranks_scope})
		_render_page(id)


func _render_page(id: String) -> void:
	for c in _pages.get_children():
		c.queue_free()
	var page := MarginContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		page.add_theme_constant_override("margin_" + side, 36)
	page.add_theme_constant_override("margin_top", 54)
	page.add_theme_constant_override("margin_bottom", 250)
	_pages.add_child(page)
	var veil := ColorRect.new()
	veil.color = Color(1, 0.96, 0.93, 0.35)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pages.add_child(veil)
	_pages.move_child(veil, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)
	page.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	col.add_child(head)
	var titles := {"shop": "Shop", "missions": "Missions", "ranks": "This week", "profile": "Profile"}
	var t := Kit.title(titles.get(id, ""), 76)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 12)
	head.add_child(money)
	money.add_child(Kit.pill("coins", int(profile.get("coins", 0))).panel)
	money.add_child(Kit.pill("gems", int(profile.get("gems", 0))).panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	match id:
		"shop":
			_page_shop(body)
		"missions":
			_page_missions(body)
		"ranks":
			_page_ranks(body)
		"profile":
			_page_profile(body)


func _card() -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(Kit.CARD, 52))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	p.add_child(v)
	return v


func _section(parent: Control, text: String) -> void:
	parent.add_child(Kit.title(text, 54))


# ---------------------------------------------------------------- shop

func _page_shop(body: VBoxContainer) -> void:
	_section(body, "Pawns")
	body.add_child(_shop_grid("token"))
	_section(body, "Dice")
	body.add_child(_shop_grid("dice"))
	_section(body, "Coins")
	body.add_child(_shop_grid("coins"))
	var note := Kit.label("Earn gems from daily rewards, the spin wheel and missions.", 34, Color.WHITE, false, 800)
	note.add_theme_color_override("font_outline_color", Color("3b2a7a"))
	note.add_theme_constant_override("outline_size", 10)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)


func _shop_grid(kind: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 22)
	for it: Dictionary in Economy.SHOP:
		if it.kind != kind:
			continue
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Kit.box(Kit.CARD, 44))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 12)
		p.add_child(v)
		var swatch: Control
		if kind == "coins":
			swatch = Kit.icon3d("coins", 150)
		else:
			swatch = _swatch(Color(it.color), kind)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(swatch)
		var n := Kit.label(it.name, 34, Kit.INK, true, 600)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
		var owned: bool = profile.get("owned", []).has(it.id)
		var equipped: bool = profile.get("equipped", {}).get(kind, "") == it.id
		var b: Button
		if owned:
			b = Kit.button("Equipped" if equipped else "Use", "Mint" if not equipped else "", 104)
			b.disabled = equipped
			var item_id: String = it.id
			b.pressed.connect(func() -> void: Net.send({"t": "equip", "item": item_id}))
		else:
			b = Kit.button("", "SkyBtn", 104)
			var bh := HBoxContainer.new()
			bh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bh.offset_bottom = -12
			bh.alignment = BoxContainer.ALIGNMENT_CENTER
			bh.add_theme_constant_override("separation", 6)
			bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(bh)
			bh.add_child(Kit.icon3d("gem", 58))
			bh.add_child(Kit.label(str(it.gems), 42, Color("04263f"), true, 700))
			b.disabled = int(profile.get("gems", 0)) < int(it.gems)
			var item_id: String = it.id
			b.pressed.connect(func() -> void: Net.send({"t": "buy", "item": item_id}))
		v.add_child(b)
		grid.add_child(p)
	return grid


func _swatch(c: Color, kind: String) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(150, 150)
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(75 if kind == "token" else 36)
	sb.border_color = c.darkened(0.25)
	sb.border_width_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.15)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	if kind == "token":
		var ic := Kit.icon("crown", 80, Color(1, 1, 1, 0.9))
		ic.position = Vector2(35, 28)
		p.add_child(ic)
	else:
		var ic := Kit.icon("dice-five", 96, c.darkened(0.45) if c.get_luminance() > 0.6 else Color.WHITE)
		ic.position = Vector2(27, 20)
		p.add_child(ic)
	return p


# ---------------------------------------------------------------- missions

func _page_missions(body: VBoxContainer) -> void:
	var daily := _card()
	body.add_child(daily.get_parent())
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 20)
	daily.add_child(dh)
	dh.add_child(Kit.icon3d("gift", 150))
	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(dv)
	dv.add_child(Kit.label("Daily reward", 46, Kit.INK, true, 600))
	var streak := int(profile.get("daily", {}).get("streak", 0))
	dv.add_child(Kit.label("Day %d of 7 · %d-day streak" % [int(profile.get("daily_index", 0)) + 1, streak], 32, Kit.INK2, false, 800))
	var claim := Kit.button("Open" if profile.get("daily_ready", false) else "Done", "Primary" if profile.get("daily_ready", false) else "", 120)
	claim.size_flags_horizontal = Control.SIZE_SHRINK_END
	claim.custom_minimum_size.x = 230
	claim.disabled = not profile.get("daily_ready", false)
	claim.pressed.connect(func() -> void: modals.daily(profile))
	dh.add_child(claim)

	_section(body, "Today's missions")
	for m: Dictionary in profile.get("missions", {}).get("list", []):
		var spec := {}
		for s: Dictionary in Economy.MISSIONS:
			if s.id == m.id:
				spec = s
		if spec.is_empty():
			continue
		var c := _card()
		body.add_child(c.get_parent())
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 22)
		c.add_child(h)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 14)
		h.add_child(v)
		v.add_child(Kit.label(spec.text, 40, Kit.INK, false, 800))
		var done: bool = int(m.progress) >= int(spec.need)
		var b := Kit.bar(560, 30, float(m.progress) / float(spec.need), Kit.MINT if done else Kit.GOLD)
		v.add_child(b.root)
		var reward := VBoxContainer.new()
		reward.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(reward)
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 6)
		reward.add_child(rh)
		var gems := int(spec.reward.get("g", 0))
		rh.add_child(Kit.icon3d("gem" if gems > 0 else "coin", 60))
		rh.add_child(Kit.label(str(gems if gems > 0 else int(spec.reward.get("c", 0))), 44, Kit.INK, true, 700))
		if m.claimed:
			reward.add_child(Kit.label("Claimed", 30, Kit.INK2, false, 800))
		elif done:
			var cb := Kit.button("Claim", "Mint", 100)
			cb.custom_minimum_size.x = 210
			var mid: String = m.id
			cb.pressed.connect(func() -> void: Net.send({"t": "claim_mission", "id": mid}))
			reward.add_child(cb)
		else:
			reward.add_child(Kit.label("%s / %s" % [Kit.money(int(m.progress)), Kit.money(int(spec.need))], 30, Kit.INK2, false, 800))


# ---------------------------------------------------------------- ranks

var _ranks_rows: Array = []
var _ranks_scope := "country"


func _page_ranks(body: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 16)
	body.add_child(tabs)
	for s: Array in [["country", Economy.COUNTRY_NAMES.get(Net.country, "My country")], ["world", "World"]]:
		var b := Kit.button(s[1], "Primary" if _ranks_scope == s[0] else "", 112)
		var scope: String = s[0]
		b.pressed.connect(func() -> void:
			_ranks_scope = scope
			open_page("ranks"))
		tabs.add_child(b)
	if not Net.online:
		var c := _card()
		body.add_child(c.get_parent())
		var ic := Kit.icon3d("trophy", 220)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		c.add_child(ic)
		var l := Kit.label("Weekly rankings appear when you're connected. Your trophies this week: %d" % int(profile.get("week_trophies", 0)),
			38, Kit.INK, false, 800)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(l)
		return
	var list := _card()
	body.add_child(list.get_parent())
	if _ranks_rows.is_empty():
		list.add_child(Kit.label("Loading…", 38, Kit.INK2, false, 800))
	for r: Dictionary in _ranks_rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 22)
		list.add_child(h)
		var rank := Kit.label(str(r.rank), 44, Kit.GOLD_LIP if int(r.rank) <= 3 else Kit.INK2, true, 700)
		rank.custom_minimum_size.x = 70
		h.add_child(rank)
		h.add_child(Kit.avatar(str(r.avatar), 92, Kit.GOLD if r.me else Color.WHITE))
		var n := Kit.label(("You" if r.me else str(r.name)), 40, Kit.INK, false, 900 if r.me else 800)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(Kit.icon3d("trophy", 56))
		h.add_child(Kit.label(Kit.money(int(r.score)), 42, Kit.INK, true, 700))


# ---------------------------------------------------------------- profile

func _page_profile(body: VBoxContainer) -> void:
	var c := _card()
	body.add_child(c.get_parent())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	c.add_child(h)
	h.add_child(Kit.avatar(str(profile.get("avatar", "a01")), 200, Kit.GOLD, 10))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_edit := LineEdit.new()
	name_edit.text = str(profile.get("name", ""))
	name_edit.max_length = 16
	name_edit.placeholder_text = "Your name"
	name_edit.add_theme_font_override("font", Kit.font(true, 600))
	name_edit.text_submitted.connect(func(t: String) -> void:
		Net.set_identity(t, str(profile.get("avatar", "a01")))
		Net.send({"t": "set_name", "name": t}))
	name_edit.focus_exited.connect(func() -> void:
		if name_edit.text != str(profile.get("name", "")):
			Net.set_identity(name_edit.text, str(profile.get("avatar", "a01")))
			Net.send({"t": "set_name", "name": name_edit.text}))
	v.add_child(name_edit)
	v.add_child(Kit.label("Level %d · %s" % [int(profile.get("level", 1)), Economy.COUNTRY_NAMES.get(Net.country, "World")],
		34, Kit.INK2, false, 800))

	var stats := _card()
	body.add_child(stats.get_parent())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	stats.add_child(grid)
	var st: Dictionary = profile.get("stats", {})
	var matches := int(st.get("matches", 0))
	var wins := int(st.get("wins", 0))
	for s: Array in [["Matches", str(matches)], ["Wins", str(wins)],
			["Win rate", "%d%%" % (100 * wins / maxi(1, matches))], ["Trophies", Kit.money(int(profile.get("trophies", 0)))],
			["This week", Kit.money(int(profile.get("week_trophies", 0)))], ["Level", str(int(profile.get("level", 1)))]]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(Kit.label(s[1], 54, Kit.INK, true, 700))
		cell.add_child(Kit.label(s[0], 30, Kit.INK2, false, 800))
		grid.add_child(cell)

	_section(body, "Avatar")
	var av := GridContainer.new()
	av.columns = 4
	av.add_theme_constant_override("h_separation", 20)
	av.add_theme_constant_override("v_separation", 20)
	body.add_child(av)
	for i in 12:
		var id := "a%02d" % (i + 1)
		var b := Button.new()
		b.flat = true
		b.custom_minimum_size = Vector2(200, 200)
		for stn in ["focus", "hover", "pressed", "normal"]:
			b.add_theme_stylebox_override(stn, StyleBoxEmpty.new())
		var on: bool = str(profile.get("avatar", "a01")) == id
		var a := Kit.avatar(id, 190, Kit.GOLD if on else Color.WHITE, 12 if on else 6)
		a.position = Vector2(5, 5)
		b.add_child(a)
		b.pressed.connect(func() -> void:
			Fx.play("click")
			Net.set_identity(str(profile.get("name", "")), id)
			_set_avatar(id))
		av.add_child(b)

	_section(body, "Settings")
	var set_card := _card()
	body.add_child(set_card.get_parent())
	for s: Array in [["Sound", "speaker-high", Fx.sound], ["Vibration", "vibrate", Fx.haptics]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		set_card.add_child(row)
		row.add_child(Kit.icon(s[1], 64, Kit.INK))
		var l := Kit.label(s[0], 42, Kit.INK, false, 800)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var on: bool = s[2]
		var tg := Kit.button("On" if on else "Off", "Mint" if on else "", 100)
		tg.custom_minimum_size.x = 200
		tg.size_flags_horizontal = Control.SIZE_SHRINK_END
		var which: String = s[0]
		tg.pressed.connect(func() -> void:
			var now := not (Fx.sound if which == "Sound" else Fx.haptics)
			if which == "Sound":
				Fx.sound = now
			else:
				Fx.haptics = now
				Fx.buzz(30)
			Fx.save_settings()
			tg.text = "On" if now else "Off"
			tg.theme_type_variation = "Mint" if now else "")
		row.add_child(tg)
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 20)
	set_card.add_child(grow)
	grow.add_child(Kit.icon("lightning", 64, Kit.INK))
	var gl := Kit.label("Graphics", 42, Kit.INK, false, 800)
	gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.add_child(gl)
	var gb := Kit.button("Low" if Fx.low_graphics() else "High", "" if Fx.low_graphics() else "Mint", 100)
	gb.custom_minimum_size.x = 200
	gb.size_flags_horizontal = Control.SIZE_SHRINK_END
	gb.pressed.connect(func() -> void:
		Fx.graphics = "high" if Fx.low_graphics() else "low"
		Fx.save_settings()
		Fx.graphics_changed.emit()
		gb.text = "Low" if Fx.low_graphics() else "High"
		gb.theme_type_variation = "" if Fx.low_graphics() else "Mint")
	grow.add_child(gb)
	var ver := Kit.label("Skyloop %s · %s" % [ProjectSettings.get_setting("application/config/version", "0.2.0"),
		"online" if Net.online else "offline"], 30, Color.WHITE, false, 800)
	ver.add_theme_color_override("font_outline_color", Color("3b2a7a"))
	ver.add_theme_constant_override("outline_size", 8)
	body.add_child(ver)


func _set_avatar(id: String) -> void:
	Net.send({"t": "set_avatar", "avatar": id})
