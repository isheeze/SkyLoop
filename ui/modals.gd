extends Control
## Popups over everything: daily reward calendar, spin wheel, reward fly-ins, out-of-coins,
## matchmaking, match results and level-up. Listens for "reward" messages from Net.

signal results_closed(play_again: bool)
signal matchmaking_cancelled
signal welcomed

const Kit = preload("res://ui/kit.gd")
const Economy = preload("res://core/economy.gd")

var lobby  # for the coin/gem pill positions
var _wheel: Control
var _wheel_pending := false
var _mm: Control
var _mm_seats: Array = []


class Wheel extends Control:
	var angle := 0.0  # degrees, clockwise
	var coin_tex: Texture2D = load("res://art/ui/icons3d/coin.png")
	var gem_tex: Texture2D = load("res://art/ui/icons3d/gem.png")
	const COLORS := [Color("ff8a5c"), Color("38b6ff"), Color("8e6ce0"), Color("ffb21f"), Color("3ddc97"),
		Color("ff5d73"), Color("ffc23d"), Color("4f7fe0")]
	const FONT = preload("res://art/fonts/Fredoka.ttf")

	func _draw() -> void:
		var c := size / 2
		var r := minf(size.x, size.y) / 2 - 8
		draw_circle(c + Vector2(0, 12), r + 26, Color(0.19, 0.12, 0.43, 0.2))
		draw_circle(c, r + 26, Color.WHITE)
		var n := Economy.SPIN.size()
		var step := TAU / n
		for i in n:
			var a0 := -PI / 2 + deg_to_rad(angle) + i * step
			var pts := PackedVector2Array([c])
			for k in 25:
				pts.append(c + Vector2.from_angle(a0 + step * k / 24.0) * r)
			draw_colored_polygon(pts, COLORS[i % COLORS.size()])
			var mid := a0 + step / 2
			draw_set_transform(c + Vector2.from_angle(mid) * r * 0.66, mid + PI / 2, Vector2.ONE)
			var prize: Dictionary = Economy.SPIN[i]
			var tex: Texture2D = gem_tex if prize.kind == "g" else coin_tex
			draw_texture_rect(tex, Rect2(-40, -88, 80, 80), false)
			var txt := str(prize.amount)
			var f: Font = FONT
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
			draw_string_outline(f, Vector2(-w / 2, 34), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, 10, Color(0, 0, 0, 0.25))
			draw_string(f, Vector2(-w / 2, 34), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color.WHITE)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		for k in 16:
			var a := k * TAU / 16
			draw_circle(c + Vector2.from_angle(a) * (r + 13), 9, Color("fff4c4"))
		draw_circle(c, 84, Color.WHITE)
		draw_circle(c, 70, Color("ffc23d"))


func setup(lobby_ref) -> void:
	lobby = lobby_ref
	theme = Kit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Net.message.connect(_on_message)


# ---------------------------------------------------------------- frame

func _open(width := 900, dim := true) -> VBoxContainer:
	var veil := ColorRect.new()
	veil.color = Color(0.12, 0.09, 0.28, 0.55 if dim else 0.0)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(width, 0)
	var sb := Kit.box(Kit.CARD, 64)
	sb.set_content_margin_all(52)
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 30)
	card.add_child(v)
	card.pivot_offset = Vector2(width / 2.0, 400)
	card.scale = Vector2(0.85, 0.85)
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel()
	tw.tween_property(card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.15)
	veil.modulate.a = 0.0
	veil.create_tween().tween_property(veil, "modulate:a", 1.0, 0.15)
	return v


func _close(v: Control) -> void:
	var veil := v.get_parent().get_parent().get_parent()
	if not is_instance_valid(veil):
		return
	var tw := veil.create_tween()
	tw.tween_property(veil, "modulate:a", 0.0, 0.15)
	tw.tween_callback(veil.queue_free)


func close_all() -> void:
	for c in get_children():
		c.queue_free()
	_wheel = null
	_mm = null


func _head(v: VBoxContainer, text: String, icon := "") -> void:
	if icon != "":
		var ic := Kit.icon3d(icon, 220)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
	var l := Kit.label(text, 70, Kit.INK, true, 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)


func _text(v: VBoxContainer, text: String) -> void:
	var l := Kit.label(text, 38, Kit.INK2, false, 800)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)


func notice(title: String, text: String) -> void:
	var v := _open()
	_head(v, title)
	_text(v, text)
	var ok := Kit.button("OK", "Primary")
	ok.pressed.connect(func() -> void: _close(v))
	v.add_child(ok)


# ---------------------------------------------------------------- first launch

## First launch: the player picks a name and a face before anything else.
func welcome(profile: Dictionary) -> void:
	var v := _open(980)
	var logo := TextureRect.new()
	logo.texture = load("res://art/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 220)
	v.add_child(logo)
	_text(v, "Welcome, tycoon! Pick your name and your face.")
	var name_edit := LineEdit.new()
	var start_name := str(profile.get("name", ""))
	name_edit.text = "" if start_name.begins_with("Player") else start_name
	name_edit.placeholder_text = start_name if start_name != "" else "Your name"
	name_edit.max_length = 16
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(0, 120)
	name_edit.add_theme_font_override("font", Kit.font(true, 600))
	name_edit.add_theme_font_size_override("font_size", 52)
	name_edit.add_theme_color_override("font_placeholder_color", Color(Kit.INK2, 0.55))
	v.add_child(name_edit)
	var picked := [str(profile.get("avatar", "a01"))]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	var rings: Array = []
	for i in 12:
		var id := "a%02d" % (i + 1)
		var b := Button.new()
		b.flat = true
		b.custom_minimum_size = Vector2(196, 196)
		for stn in ["focus", "hover", "pressed", "normal"]:
			b.add_theme_stylebox_override(stn, StyleBoxEmpty.new())
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(holder)
		rings.append([id, holder])
		b.pressed.connect(func() -> void:
			Fx.play("click")
			picked[0] = id
			_paint_avatars(rings, id))
		grid.add_child(b)
	_paint_avatars(rings, picked[0])
	var go := Kit.button("Let's go!", "Primary")
	go.pressed.connect(func() -> void:
		var n := name_edit.text.strip_edges()
		if n == "":
			n = name_edit.placeholder_text
		Net.set_identity(n, picked[0])
		Net.send({"t": "set_name", "name": n})
		Net.send({"t": "set_avatar", "avatar": picked[0]})
		Net.mark_onboarded()
		Fx.play("celebrate")
		_close(v)
		welcomed.emit())
	v.add_child(go)


func _paint_avatars(rings: Array, chosen: String) -> void:
	for r: Array in rings:
		var holder: Control = r[1]
		for c in holder.get_children():
			c.queue_free()
		var on: bool = r[0] == chosen
		var a := Kit.avatar(r[0], 186, Kit.GOLD if on else Color.WHITE, 12 if on else 5)
		a.position = Vector2(5, 5)
		a.modulate = Color.WHITE if on else Color(1, 1, 1, 0.82)
		holder.add_child(a)


# ---------------------------------------------------------------- daily

func daily(profile: Dictionary) -> void:
	var v := _open(960)
	_head(v, "Daily reward")
	var today := int(profile.get("daily_index", 0))
	var ready := bool(profile.get("daily_ready", false))
	_text(v, "Come back every day. Day 7 is a gold chest!" if ready else "Claimed! See you tomorrow.")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	v.add_child(grid)
	for i in 7:
		var r: Dictionary = Economy.DAILY[i]
		var cell := PanelContainer.new()
		var done := i < today or (i == today and not ready)
		var now := i == today and ready
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("fff3cf") if now else (Color("eafbf3") if done else Color("f4f5fa"))
		sb.set_corner_radius_all(36)
		sb.border_color = Kit.GOLD if now else (Color("bfe8d2") if done else Kit.LIP)
		sb.set_border_width_all(8 if now else 0)
		sb.border_width_bottom = 14 if now else 8
		sb.set_content_margin_all(14)
		cell.add_theme_stylebox_override("panel", sb)
		cell.custom_minimum_size = Vector2(196, 230)
		if i == 6:
			cell.custom_minimum_size.x = 196
		var cv := VBoxContainer.new()
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_theme_constant_override("separation", 4)
		cell.add_child(cv)
		var dl := Kit.label("DAY %d" % (i + 1), 30, Kit.INK2, true, 600)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(dl)
		var icon := "chest_gold" if r.kind == "chest" else ("gem" if r.kind == "g" else "coins")
		var ic := Kit.icon3d(icon, 110)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(ic)
		var amount := "Chest" if r.kind == "chest" else Kit.money(int(r.amount))
		var al := Kit.label(amount, 38, Kit.INK, true, 700)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(al)
		if done:
			ic.modulate = Color(1, 1, 1, 0.45)
			var ck := Kit.icon("check", 56, Color("1f9e68"))
			ck.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cv.add_child(ck)
		if now:
			cell.pivot_offset = Vector2(98, 115)
			var tw := cell.create_tween().set_loops()
			tw.tween_property(cell, "scale", Vector2(1.05, 1.05), 0.55).set_trans(Tween.TRANS_SINE)
			tw.tween_property(cell, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE)
		grid.add_child(cell)
	var b := Kit.button("Claim" if ready else "Close", "Primary" if ready else "", 160)
	b.pressed.connect(func() -> void:
		if ready:
			Net.send({"t": "claim_daily"})
		_close(v))
	v.add_child(b)


# ---------------------------------------------------------------- spin

func spin(profile: Dictionary) -> void:
	var v := _open(960)
	_head(v, "Daily spin")
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 760)
	v.add_child(holder)
	_wheel = Wheel.new()
	_wheel.size = Vector2(720, 720)
	_wheel.position = Vector2(68, 30)
	holder.add_child(_wheel)
	var pointer := Kit.icon("map-pin", 120, Kit.CORAL)
	pointer.position = Vector2(368, -40)
	pointer.rotation = PI
	pointer.pivot_offset = Vector2(60, 60)
	holder.add_child(pointer)
	var free_left: bool = int(profile.get("spin", {}).get("last", -1)) != int(floor((Time.get_unix_time_from_system() + Net.server_time_offset) / 86400.0))
	var extra := int(profile.get("spin", {}).get("extra", 0))
	var can := free_left or extra > 0
	var b := Kit.button("SPIN" if can else "Come back tomorrow", "Primary" if can else "", 160)
	b.disabled = not can
	b.pressed.connect(func() -> void:
		b.disabled = true
		_wheel_pending = true
		Fx.play("shake", -6.0)
		Net.send({"t": "spin", "ad": not free_left}))
	v.add_child(b)
	var close := Kit.button("Close", "", 120)
	close.pressed.connect(func() -> void:
		if not _wheel_pending:
			_wheel = null
			_close(v))
	v.add_child(close)


func _spin_to(index: int, then: Callable) -> void:
	var n := Economy.SPIN.size()
	var step := 360.0 / n
	var target := 360.0 * 6.0 - (index * step + step / 2.0)
	var w: Control = _wheel
	var start: float = fposmod(w.angle, 360.0)
	w.angle = start
	var tw := w.create_tween()
	var ticks := [0]
	tw.tween_method(func(a: float) -> void:
		w.angle = a
		w.queue_redraw()
		var k := int(a / step)
		if k != ticks[0]:
			ticks[0] = k
			Fx.play("hop", -10.0, 0.1), start, target, 4.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_callback(then)


# ---------------------------------------------------------------- rewards

func _on_message(msg: Dictionary) -> void:
	if msg.get("t", "") != "reward":
		return
	var coins := int(msg.get("coins", 0))
	var gems := int(msg.get("gems", 0))
	match msg.source:
		"spin":
			if _wheel != null and is_instance_valid(_wheel):
				_spin_to(int(msg.index), func() -> void:
					_wheel_pending = false
					close_all()
					reward(coins, gems, "Spin prize!"))
			else:
				reward(coins, gems, "Spin prize!")
		"daily":
			reward(coins, gems, "Daily reward!")
		"mission":
			reward(coins, gems, "Mission complete!")
		"shop":
			if coins > 0:
				reward(coins, 0, "Coins added!")
			else:
				Fx.play("levelup")
				Fx.buzz(30)


## "You got…" card, then coins and gems fly into the top-bar pills.
func reward(coins: int, gems: int, title: String) -> void:
	Fx.play("jackpot" if coins >= 500 or gems >= 10 else "coin")
	Fx.buzz(60, 0.6)
	var v := _open(820)
	_head(v, title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	v.add_child(row)
	for item: Array in [["coins", coins], ["gem", gems]]:
		if int(item[1]) <= 0:
			continue
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		var ic := Kit.icon3d(item[0], 220)
		ic.pivot_offset = Vector2(110, 110)
		col.add_child(ic)
		var tw := ic.create_tween().set_loops()
		tw.tween_property(ic, "rotation", 0.12, 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ic, "rotation", -0.12, 0.7).set_trans(Tween.TRANS_SINE)
		var l := Kit.label("+" + Kit.money(int(item[1])), 74, Kit.INK, true, 700)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	var b := Kit.button("Collect", "Primary", 160)
	b.pressed.connect(func() -> void:
		var from := b.get_global_rect().get_center()
		_close(v)
		fly(coins, gems, from))
	v.add_child(b)


func fly(coins: int, gems: int, from: Vector2) -> void:
	if lobby == null or not lobby.is_visible_in_tree():
		return
	for item: Array in [["coin", coins, lobby.coin_pill_center()], ["gem", gems, lobby.gem_pill_center()]]:
		if int(item[1]) <= 0:
			continue
		var n := clampi(int(item[1]) / 60, 5, 14) if item[0] == "coin" else clampi(int(item[1]), 3, 10)
		for k in n:
			var ic := Kit.icon3d(item[0], 90)
			ic.position = from - Vector2(45, 45) + Vector2(randf_range(-80, 80), randf_range(-60, 60))
			add_child(ic)
			var to: Vector2 = item[2] - Vector2(45, 45)
			var mid := (ic.position + to) / 2 + Vector2(randf_range(-220, 220), -200)
			var a := ic.position
			var tw := ic.create_tween()
			tw.tween_interval(k * 0.05)
			tw.tween_method(func(t: float) -> void:
				ic.position = a.lerp(mid, t).lerp(mid.lerp(to, t), t)
				ic.scale = Vector2.ONE * lerpf(1.0, 0.6, t), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
			tw.tween_callback(func() -> void:
				Fx.play("coin_tick", -10.0, 0.0, 1.0 + k * 0.04)
				ic.queue_free())


func out_of_coins(profile: Dictionary) -> void:
	var v := _open()
	_head(v, "Need more coins", "coins")
	_text(v, "Grab your free coins, then come back to the table.")
	if profile.get("daily_ready", false):
		var d := Kit.button("Daily reward", "Primary")
		d.pressed.connect(func() -> void:
			_close(v)
			daily(profile))
		v.add_child(d)
	if profile.get("spin_ready", false):
		var s := Kit.button("Free spin", "SkyBtn")
		s.pressed.connect(func() -> void:
			_close(v)
			spin(profile))
		v.add_child(s)
	var c := Kit.button("Close")
	c.pressed.connect(func() -> void: _close(v))
	v.add_child(c)


# ---------------------------------------------------------------- matchmaking

func matchmaking(tier: int, profile: Dictionary) -> void:
	close_all()
	var v := _open(960)
	_mm = v
	var city := Economy.tier_name(tier, Net.country) if tier > 0 else "Practice"
	var t := Kit.label(city.to_upper(), 92, Kit.TIER_COLORS[maxi(tier, 1) - 1].darkened(0.1), true, 700)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_text(v, "Finding players…" if tier > 0 else "Setting up the table…")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 30)
	v.add_child(grid)
	_mm_seats = []
	for i in 4:
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 10)
		cell.custom_minimum_size = Vector2(380, 300)
		grid.add_child(cell)
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(220, 220)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(slot)
		var name := Kit.label("", 40, Kit.INK, true, 600)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name)
		_mm_seats.append({"slot": slot, "name": name})
		if i == 0:
			_fill_seat(i, str(profile.get("avatar", "a01")), "You", Kit.GOLD)
		else:
			var ring := Panel.new()
			ring.custom_minimum_size = Vector2(220, 220)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("f4f5fa")
			sb.set_corner_radius_all(110)
			sb.border_color = Color("b9bfd6")
			sb.set_border_width_all(8)
			ring.add_theme_stylebox_override("panel", sb)
			slot.add_child(ring)
			var mag := Kit.icon("users", 90, Color("8a91ab"))
			mag.position = Vector2(65, 65)
			ring.add_child(mag)
			ring.pivot_offset = Vector2(110, 110)
			var tw := ring.create_tween().set_loops()
			tw.tween_property(ring, "scale", Vector2(0.92, 0.92), 0.5 + i * 0.1).set_trans(Tween.TRANS_SINE)
			tw.tween_property(ring, "scale", Vector2.ONE, 0.5 + i * 0.1).set_trans(Tween.TRANS_SINE)
			_mm_seats[i].name.text = "Searching"
			_mm_seats[i].name.add_theme_color_override("font_color", Kit.INK2)
	if tier > 0:
		var stake := HBoxContainer.new()
		stake.alignment = BoxContainer.ALIGNMENT_CENTER
		stake.add_theme_constant_override("separation", 14)
		v.add_child(stake)
		stake.add_child(Kit.label("Prize", 44, Kit.INK2, false, 800))
		stake.add_child(Kit.icon3d("coins", 90))
		stake.add_child(Kit.label(Kit.money(Economy.prize(tier)), 64, Kit.INK, true, 700))
		var cancel := Kit.button("Cancel", "", 130)
		cancel.pressed.connect(func() -> void:
			Net.send({"t": "cancel_queue"})
			matchmaking_cancelled.emit()
			close_all())
		v.add_child(cancel)


func _fill_seat(i: int, avatar_id: String, name: String, ring: Color) -> void:
	var s: Dictionary = _mm_seats[i]
	for c in s.slot.get_children():
		c.queue_free()
	var a := Kit.avatar(avatar_id, 220, ring, 12)
	a.pivot_offset = Vector2(110, 110)
	s.slot.add_child(a)
	s.name.text = name
	s.name.add_theme_color_override("font_color", Kit.INK)
	a.scale = Vector2(0.3, 0.3)
	a.create_tween().tween_property(a, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Seats pop in one by one with the real table, then the popup clears for the game.
func matchmaking_found(players: Array, my_seat: int, colors: Array) -> void:
	if _mm == null or _mm_seats.is_empty():
		return
	var order := [my_seat]
	for i in players.size():
		if i != my_seat:
			order.append(i)
	for k in range(1, order.size()):
		await get_tree().create_timer(0.28).timeout
		if _mm == null:
			return
		var p: Dictionary = players[order[k]]
		_fill_seat(k, str(p.avatar), str(p.name), colors[order[k]])
		Fx.play("click")
		Fx.buzz(10, 0.2)
	await get_tree().create_timer(0.5).timeout
	if _mm != null:
		_close(_mm)
		_mm = null


# ---------------------------------------------------------------- results

func results(msg: Dictionary, players: Array, my_seat: int, colors: Array, profile: Dictionary) -> void:
	close_all()
	var place := int(msg.place)
	var rw: Dictionary = msg.rewards
	var won := place == 0
	var v := _open(940)
	var me: Dictionary = players[my_seat] if my_seat < players.size() else {"avatar": "a01"}
	# The winner's avatar wears the crown: set on the ring's top edge, tipped a little to one side.
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 260 + (128 if won else 0))
	v.add_child(top)
	var av := Kit.avatar(str(me.avatar), 260, Kit.GOLD if won else Color.WHITE, 14)
	av.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	av.position = Vector2(-130, -260)
	top.add_child(av)
	if won:
		var crown := Kit.icon3d("crown", 176)
		crown.set_anchors_preset(Control.PRESET_CENTER_TOP)
		crown.position = Vector2(-88 + 30, 0)
		crown.pivot_offset = Vector2(88, 88)
		crown.rotation = deg_to_rad(14)
		top.add_child(crown)
	var head: String = ["VICTORY!", "2nd place", "3rd place", "4th place"][place]
	var hl := Kit.label(head, 104 if won else 84, Kit.GOLD_LIP if won else Kit.INK, true, 700)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hl)
	for i in msg.standings.size():
		var r: Dictionary = msg.standings[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		v.add_child(row)
		row.add_child(Kit.label(str(i + 1), 44, Kit.INK2, true, 700))
		row.add_child(Kit.avatar(str(r.avatar), 84, colors[int(r.seat)], 6))
		var n := Kit.label("You" if int(r.seat) == my_seat else str(r.name), 40, Kit.INK, false, 900 if int(r.seat) == my_seat else 800)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(Kit.label("$" + Kit.money(int(r.worth)), 40, Kit.INK, true, 600))
	var gains := HBoxContainer.new()
	gains.alignment = BoxContainer.ALIGNMENT_CENTER
	gains.add_theme_constant_override("separation", 22)
	v.add_child(gains)
	for item: Array in [["coins", int(rw.coins), "COINS", Kit.CREAM], ["xp", int(rw.xp), "XP", Color("f3efff")],
			["trophy", int(rw.trophies), "TROPHIES", Color("eafbf3")]]:
		if item[0] == "coins" and int(msg.get("tier", 1)) == 0:
			continue
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = item[3]
		sb.set_corner_radius_all(40)
		sb.set_content_margin_all(18)
		p.add_theme_stylebox_override("panel", sb)
		p.custom_minimum_size = Vector2(250, 0)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		p.add_child(col)
		var ic := Kit.icon3d(item[0], 100)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
		var amount: int = item[1]
		var al := Kit.label(("+" if amount >= 0 else "") + Kit.money(amount), 52, Kit.INK, true, 700)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(al)
		var cl := Kit.label(item[2], 26, Kit.INK2, false, 900)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(cl)
		gains.add_child(p)
	var lvl := int(rw.level)
	var lv := HBoxContainer.new()
	lv.add_theme_constant_override("separation", 18)
	v.add_child(lv)
	lv.add_child(Kit.label("Level %d" % lvl, 42, Kit.VIOLET, true, 700))
	var frac := float(profile.get("xp", 0)) / maxf(1.0, float(profile.get("xp_next", 100)))
	var bar := Kit.bar(560, 34, 0.0, Kit.VIOLET)
	bar.root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv.add_child(bar.root)
	bar.fill.create_tween().tween_property(bar.fill, "size:x", maxf(34.0, 560.0 * frac), 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_delay(0.4)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 20)
	v.add_child(row2)
	var again := Kit.button("Play again", "", 160)
	again.pressed.connect(func() -> void:
		_close(v)
		results_closed.emit(true))
	row2.add_child(again)
	var cont := Kit.button("Continue", "Primary", 160)
	cont.pressed.connect(func() -> void:
		_close(v)
		results_closed.emit(false)
		if int(rw.coins) > 0:
			fly.call_deferred(int(rw.coins), 0, get_viewport_rect().get_center()))
	row2.add_child(cont)
	if won:
		Fx.play("win")
		Fx.play("celebrate", -2.0)
	else:
		Fx.play("lose")
	if int(rw.level) > int(rw.level_before):
		await get_tree().create_timer(1.4).timeout
		level_up(int(rw.level))


func level_up(level: int) -> void:
	var v := _open(820)
	_head(v, "Level %d!" % level, "xp")
	var unlocked := ""
	for t: Dictionary in Economy.TIERS:
		if int(t.level) == level:
			unlocked = "New table unlocked: %s" % Economy.tier_name(int(t.id), Net.country)
	_text(v, unlocked if unlocked != "" else "Keep climbing to unlock bigger tables.")
	Fx.play("levelup")
	Fx.buzz(120, 0.7)
	var b := Kit.button("Awesome!", "Primary", 160)
	b.pressed.connect(func() -> void: _close(v))
	v.add_child(b)
