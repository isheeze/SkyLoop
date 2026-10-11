extends Control
## The painted board. A static illustrated island (art/boards/<id>/base.jpg: island, road,
## spaces, empty plots, corner landmarks, centrepiece, decoration) with the live game drawn on
## top at exact positions from board.json: owned plots in their owner's colour, buildings that
## grow by level, price and rent tags, move-target glows and the players' standees.
## Mirrors game state and animates changes; it never changes the game itself.

const Board = preload("res://core/board.gd")
const Kit = preload("res://ui/kit.gd")

const TONE_COLORS := {"good": Color("3ddc97"), "bad": Color("ff5d73"), "neutral": Color("ffffff")}
## Game building level -> kit sprite (cottage, house, shop, tower) and a size boost.
const LEVEL_SPRITE := [-1, 0, 1, 2, 2, 3]
const LEVEL_SIZE := [1.0, 1.0, 1.0, 1.0, 1.12, 1.0]

var g
var colors: Array = []
var avatars: Array = []
var board_id := "sky_game"
## Screen-space rectangle the HUD leaves free; the board fits its focus area inside it.
var free_rect := Rect2()

var _art: TextureRect
var _overlay: Control
var _fx: Control
var _data := {}
var _img := Vector2(1792, 2400)  # base image size in pixels
var _focus := Rect2()  # image pixels that must stay on screen
var _cell := 100.0  # one grid cell in image pixels
var _sprites := {}  # name -> {tex, off}
var _closing := ""
var _scale := 1.0  # screen pixels per image pixel
var _origin := Vector2.ZERO  # screen position of the image's (0, 0)
var _pieces: Array = []
var _piece_tile: Array = []
var _targets: Array = []  # [{tile, tone, text, steps}]
var _shake := 0.0
var _time := 0.0
var _active := -1
var _tags := true


class Piece extends Control:
	## A board-game standee: a coloured base, a short stem and the player's round portrait.
	var color := Color.WHITE
	var size_px := 60.0
	var lift := 0.0  # extra height while hopping (pixels)
	var glow := 0.0

	func _draw() -> void:
		var base_w := size_px * 0.62
		# Shadow on the board, shrinking while the piece is in the air.
		var s := clampf(1.0 - lift / (size_px * 3.0), 0.4, 1.0)
		draw_set_transform(Vector2(0, 0), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, base_w * 1.1 * s, Color(0.12, 0.08, 0.25, 0.28 * s), true, -1.0, true)
		if glow > 0.0:
			draw_circle(Vector2.ZERO, base_w * (1.35 + 0.15 * sin(Time.get_ticks_msec() / 160.0)),
				Color(color.r, color.g, color.b, 0.35 * glow), true, -1.0, true)
		var up := -lift
		draw_set_transform(Vector2(0, up), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2(0, 8), base_w, color.darkened(0.3), true, -1.0, true)
		draw_circle(Vector2.ZERO, base_w, color, true, -1.0, true)
		draw_circle(Vector2(-base_w * 0.25, -base_w * 0.2), base_w * 0.45, Color(1, 1, 1, 0.25), true, -1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(-size_px * 0.06, up - size_px * 0.42, size_px * 0.12, size_px * 0.42), color.darkened(0.15))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The painting's own sky fades into the game's sky at its edges.
	var fade := ShaderMaterial.new()
	fade.shader = preload("res://game2d/edge_fade.gdshader")
	fade.set_shader_parameter("top_fade", 0.18)
	fade.set_shader_parameter("bottom_fade", 0.2)
	_art.material = fade
	add_child(_art)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_board)
	add_child(_overlay)
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fx)
	get_viewport().size_changed.connect(_layout)


func setup(game, player_colors: Array, board := "", seat_avatars: Array = []) -> void:
	g = game
	colors = player_colors
	if board != "" and ResourceLoader.exists("res://art/boards/%s/board.json" % board):
		board_id = board
	if not seat_avatars.is_empty():
		avatars = seat_avatars
	_load_board()
	for p in _pieces:
		p.queue_free()
	_pieces.clear()
	_piece_tile.clear()
	_targets.clear()
	for pi in g.players.size():
		var piece := Piece.new()
		piece.color = colors[pi]
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var av := Kit.avatar(avatars[pi] if pi < avatars.size() else "a%02d" % (pi + 1), 64, colors[pi], 5)
		av.name = "Face"
		piece.add_child(av)
		add_child(piece)
		_pieces.append(piece)
		_piece_tile.append(g.players[pi].pos)
	_layout()


func _load_board() -> void:
	var dir := "res://art/boards/%s/" % board_id
	_data = JSON.parse_string(FileAccess.get_file_as_string(dir + "board.json"))
	_img = Vector2(_data.image[0], _data.image[1])
	var f: Array = _data.focus
	_focus = Rect2(f[0] * _img.x, f[1] * _img.y, (f[2] - f[0]) * _img.x, (f[3] - f[1]) * _img.y)
	_cell = float(_data.cell) * _img.x
	_art.texture = load(dir + "base.jpg")
	_sprites.clear()
	for name: String in _data.sprites:
		var off: Array = _data.sprites[name]
		_sprites[name] = {"tex": load(dir + "sprites/%s.png" % name), "off": Vector2(off[0], off[1])}


## Fits the painting's focus area into the free rectangle (or the whole screen).
func _layout() -> void:
	var vp := get_viewport_rect().size
	var area := free_rect if free_rect.size.x > 0 else Rect2(Vector2.ZERO, vp)
	_scale = minf(area.size.x / _focus.size.x, area.size.y / _focus.size.y)
	# Centred across; vertically a little above centre, so spare room goes to the cliff below.
	var spare := area.size - _focus.size * _scale
	_origin = area.position + Vector2(spare.x * 0.5, spare.y * 0.28) - _focus.position * _scale
	_art.position = _origin
	_art.size = _img * _scale
	for pi in _pieces.size():
		_place_piece(pi, false)
	_overlay.queue_redraw()


func set_free_rect(r: Rect2) -> void:
	if r != free_rect:
		free_rect = r
		_layout()


func set_active(pi: int) -> void:
	_active = pi
	for k in _pieces.size():
		(_pieces[k] as Piece).glow = 1.0 if k == pi else 0.0


func _process(delta: float) -> void:
	_time += delta
	if _shake > 0.0:
		_shake = move_toward(_shake, 0.0, delta * 1.5)
		position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 10.0
	elif position != Vector2.ZERO:
		position = Vector2.ZERO
	if not _targets.is_empty() or _active >= 0:
		_overlay.queue_redraw()
		for p in _pieces:
			p.queue_redraw()


func shake(amount := 0.6) -> void:
	_shake = amount


# ---------------------------------------------------------------- geometry

func _to_screen(norm: Array) -> Vector2:
	return _origin + Vector2(float(norm[0]) * _img.x, float(norm[1]) * _img.y) * _scale


## Screen position of a space's centre.
func tile_point(i: int) -> Vector2:
	return _to_screen(_data.spaces[clampi(i, 0, 27)].pos)


func _space_scale(_i: int) -> float:
	return _cell * _scale / 62.0


func tile_at_screen(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in 28:
		var d := tile_point(i).distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best if best_d < _cell * _scale * 0.55 else -1


## Where a piece stands: corners have four marked slots; other spaces seat up to four side by side.
func _slot(i: int, k: int, n: int) -> Vector2:
	if n <= 1:
		return tile_point(i)
	if i % 7 == 0 and _data.corners.has(str(i)):
		return _to_screen(_data.corners[str(i)][k % 4])
	var c := tile_point(i)
	var w := _cell * _scale * 0.24
	var offs := [Vector2(-w, -w * 0.4), Vector2(w, w * 0.4), Vector2(w, -w * 0.4), Vector2(-w, w * 0.4)]
	return c + offs[k % 4]


func token_position(pi: int) -> Vector2:
	return (_pieces[pi] as Control).position


func _place_piece(pi: int, animate: bool) -> void:
	var tile: int = _piece_tile[pi]
	if tile < 0:
		return
	var here := []
	for k in _pieces.size():
		if _piece_tile[k] == tile:
			here.append(k)
	for k in here.size():
		var p: Piece = _pieces[here[k]]
		_size_piece(p, tile)
		var to := _slot(tile, k, here.size())
		if animate:
			create_tween().tween_property(p, "position", to, 0.2).set_trans(Tween.TRANS_SINE)
		else:
			p.position = to
	_sort_pieces()


func _size_piece(p: Piece, _tile: int) -> void:
	p.size_px = _cell * _scale * 0.5
	var face: Control = p.get_node("Face")
	var d := p.size_px
	face.custom_minimum_size = Vector2(d, d)
	face.size = Vector2(d, d)
	face.position = Vector2(-d / 2.0, -d * 1.38 - p.lift)


## Pieces lower on screen are nearer the camera, so they draw on top.
func _sort_pieces() -> void:
	var order := range(_pieces.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _pieces[a].position.y < _pieces[b].position.y)
	for k in order.size():
		move_child(_pieces[order[k]], get_child_count() - order.size() + k)


# ---------------------------------------------------------------- drawing

func _sprite(name: String, anchor: Vector2, scale_mul := 1.0) -> void:
	var sp: Dictionary = _sprites.get(name, {})
	if sp.is_empty():
		return
	var tex: Texture2D = sp.tex
	var k := _scale * scale_mul
	_overlay.draw_texture_rect(tex, Rect2(anchor + sp.off * k, tex.get_size() * k), false)


func _draw_board() -> void:
	if g == null or _data.is_empty():
		return
	# Move-target glows on the spaces.
	for t: Dictionary in _targets:
		var c := tile_point(int(t.tile))
		var tc: Color = TONE_COLORS[t.tone]
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		var r := _cell * _scale * (0.62 if int(t.tile) % 7 else 0.95)
		_overlay.draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
		_overlay.draw_circle(Vector2.ZERO, r * (1.0 + 0.08 * pulse), Color(tc.r, tc.g, tc.b, 0.3 + 0.25 * pulse), true, -1.0, true)
		_overlay.draw_arc(Vector2.ZERO, r * (1.0 + 0.08 * pulse), 0, TAU, 48, Color(tc.r, tc.g, tc.b, 0.9), 4.0, true)
		_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Owned plots and their buildings, back to front.
	var owned := []
	for key: String in _data.plots:
		var i := int(key)
		if g.owner_of[i] >= 0:
			owned.append(i)
	owned.sort_custom(func(a: int, b: int) -> bool: return _data.plots[str(a)].depth < _data.plots[str(b)].depth)
	for i: int in owned:
		var pl: Dictionary = _data.plots[str(i)]
		var who: int = g.owner_of[i]
		_sprite("plot_%d" % who, _to_screen(pl.price))
		var lvl: int = clampi(g.level_of[i], 0, 5)
		if LEVEL_SPRITE[lvl] >= 0:
			_sprite("bld_%d_%d" % [who, LEVEL_SPRITE[lvl]], _to_screen(pl.bld), LEVEL_SIZE[lvl])
	if not _tags:
		return
	# Tags: prices on empty plots, rent in the owner's colour, the jackpot's pot.
	var target_of := {}
	for t: Dictionary in _targets:
		target_of[int(t.tile)] = t
	for key: String in _data.plots:
		var i := int(key)
		if target_of.has(i):
			continue  # the target badge speaks for this space
		var pl: Dictionary = _data.plots[key]
		var o: int = g.owner_of[i]
		if o < 0:
			_chip(_to_screen(pl.price), "$%d" % g.price_of(i), Color(1, 0.98, 0.94, 0.94), Color("4a3c32"), 0.9)
		else:
			var c: Color = colors[o]
			_chip(_to_screen(pl.rent), str(g.rent_for(i)), c, Kit.INK if c.get_luminance() > 0.55 else Color.WHITE, 1.0)
	_chip(tile_point(14) + Vector2(0, -_cell * _scale * 1.25), "$%d" % g.pot, Color("ffc23d"), Color("3a2600"), 1.05)
	# Target badges: just the step count in a round badge (the panel spells out the outcome).
	for t: Dictionary in _targets:
		var tc: Color = TONE_COLORS[t.tone]
		var ink := Color.WHITE if t.tone == "bad" else (Color("063b25") if t.tone == "good" else Kit.INK)
		var c := tile_point(int(t.tile)) + Vector2(0, -_cell * _scale * 0.18)
		var r := _cell * _scale * 0.22
		_overlay.draw_circle(c + Vector2(0, r * 0.18), r, tc.darkened(0.3), true, -1.0, true)
		_overlay.draw_circle(c, r, tc, true, -1.0, true)
		_overlay.draw_arc(c, r, 0, TAU, 32, Color.WHITE, maxf(2.0, r * 0.14), true)
		var font := Kit.font(true, 700)
		var fs := int(r * 1.15)
		var txt := str(t.steps)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_overlay.draw_string(font, Vector2(c.x - tw / 2.0, c.y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## One chip style everywhere: a rounded pill with a darker lip.
func _chip(at: Vector2, text: String, fill: Color, ink: Color, size_mul: float) -> void:
	var font := Kit.font(true, 700)
	var fs := int(clampf(_cell * _scale * 0.22, 14.0, 28.0) * size_mul)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h := fs * 1.4
	var w := tw + fs * 0.95
	var rect := Rect2(at - Vector2(w, h) / 2.0, Vector2(w, h))
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(h / 2.0))
	sb.border_color = fill.darkened(0.25)
	sb.border_width_bottom = maxi(2, int(fs * 0.12))
	sb.shadow_color = Color(0.12, 0.08, 0.25, 0.22)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	sb.anti_aliasing = true
	_overlay.draw_style_box(sb, rect)
	_overlay.draw_string(font, Vector2(rect.position.x + (w - tw) / 2.0, at.y + fs * 0.36), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


# ---------------------------------------------------------------- state

func sync_all() -> void:
	for pi in g.players.size():
		_piece_tile[pi] = g.players[pi].pos
	for pi in _pieces.size():
		_place_piece(pi, false)
	refresh_labels()


func refresh_labels() -> void:
	_overlay.queue_redraw()


func update_tile(i: int) -> void:
	_overlay.queue_redraw()
	_pop(tile_point(i), colors[g.owner_of[i]] if g.is_property(i) and g.owner_of[i] >= 0 else Color("ffc23d"))


func set_tags_visible(on: bool) -> void:
	_tags = on
	_overlay.queue_redraw()


func show_targets(options: Array) -> void:
	_targets = options.duplicate()
	_overlay.queue_redraw()


func clear_targets() -> void:
	_targets.clear()
	_overlay.queue_redraw()


func tint_token(pi: int, color: Color) -> void:
	if pi >= 0 and pi < _pieces.size():
		(_pieces[pi] as Piece).color = color
		_pieces[pi].queue_redraw()


# ---------------------------------------------------------------- animation

## Hops a piece space by space. Passing the last space, it rides a balloon back to Payday.
## Await it.
func move_token(pi: int, from: int, to: int, jump: bool) -> void:
	var p: Piece = _pieces[pi]
	_piece_tile[pi] = -1
	_place_piece_others(from)
	var path := []
	if jump:
		path.append(to)
	else:
		var i := from
		while i != to:
			i = (i + 1) % Board.TILE_COUNT
			path.append(i)
	var prev := from
	for step: int in path:
		var a := p.position
		var b := tile_point(step)
		var balloon := prev == Board.TILE_COUNT - 1 and step == 0 and _closing == "balloon" and not jump
		if balloon:
			await _balloon_ride(p, a, b, step)
		else:
			var dur := 0.6 if jump else 0.2
			var height := 120.0 * _scale if jump else 34.0 * _space_scale(step)
			var tw := create_tween()
			tw.tween_method(func(t: float) -> void:
				p.position = a.lerp(b, t)
				p.lift = sin(t * PI) * height
				_size_piece(p, step if t > 0.5 else prev)
				p.queue_redraw(), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)
			await tw.finished
		p.lift = 0.0
		Fx.play("hop")
		p.scale = Vector2(1.12, 0.86)
		create_tween().tween_property(p, "scale", Vector2.ONE, 0.12)
		prev = step
	_piece_tile[pi] = to
	_place_piece(pi, true)


func _place_piece_others(tile: int) -> void:
	for k in _pieces.size():
		if _piece_tile[k] == tile:
			_place_piece(k, true)
			return


## The summit's hot-air balloon carries the piece up and over, down to Payday.
func _balloon_ride(p: Piece, a: Vector2, b: Vector2, step: int) -> void:
	var bal := Control.new()
	bal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := 46.0 * _scale
	bal.draw.connect(func() -> void:
		bal.draw_line(Vector2(-r * 0.45, r * 0.75), Vector2(-r * 0.25, r * 1.55), Color("8a5a3c"), 2.0, true)
		bal.draw_line(Vector2(r * 0.45, r * 0.75), Vector2(r * 0.25, r * 1.55), Color("8a5a3c"), 2.0, true)
		for k in 5:
			var col: Color = [Color("ff8fb1"), Color("ffd166"), Color("8ecae6"), Color("b8f2a0"), Color("c8b6ff")][k]
			bal.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 - k * 0.19, 1.0))
			bal.draw_circle(Vector2.ZERO, r, col, true, -1.0, true)
		bal.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		bal.draw_rect(Rect2(-r * 0.3, r * 1.5, r * 0.6, r * 0.4), Color("a0673f")))
	_fx.add_child(bal)
	Fx.play("celebrate", -8.0)
	var top := Vector2((a.x + b.x) / 2.0, minf(a.y, b.y) - 260.0 * _scale)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var q := a.lerp(top, t).lerp(top.lerp(b, t), t)
		p.position = q
		p.lift = 70.0 * _scale * sin(t * PI)
		_size_piece(p, step)
		p.queue_redraw()
		bal.position = q + Vector2(0, -p.size_px * 2.6 - p.lift), 0.0, 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	await tw.finished
	bal.queue_free()


func float_text(at: Vector2, text: String, color: Color) -> void:
	var l := Kit.label(text, int(40 * _scale), color, true, 700)
	l.add_theme_constant_override("outline_size", int(12 * _scale))
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.07, 0.14, 0.9))
	_fx.add_child(l)
	l.reset_size()
	l.position = at - Vector2(l.size.x / 2.0, 120 * _scale)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 70 * _scale, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.75)
	tw.chain().tween_callback(l.queue_free)


## Gold coins arc from one point to another; each landing ticks a little higher. Await it.
func coin_flight(from: Vector2, to: Vector2, count: int) -> void:
	for k in count:
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var r := 13.0 * _scale
		c.draw.connect(func() -> void:
			c.draw_circle(Vector2(0, 2), r, Color("c98a12"), true, -1.0, true)
			c.draw_circle(Vector2.ZERO, r, Color("ffc23d"), true, -1.0, true)
			c.draw_circle(Vector2.ZERO, r * 0.6, Color("ffe08a"), true, -1.0, true))
		_fx.add_child(c)
		var a := from + Vector2(randf_range(-14, 14), randf_range(-60, -40)) * _scale
		var b := to + Vector2(0, -60 * _scale)
		c.position = a
		c.scale = Vector2.ZERO
		var pitch := 1.0 + k * 0.05
		var tw := c.create_tween()
		tw.tween_interval(k * 0.05)
		tw.tween_property(c, "scale", Vector2.ONE, 0.08)
		tw.tween_method(func(t: float) -> void:
			c.position = a.lerp(b, t) + Vector2(0, -sin(t * PI) * 140.0 * _scale)
			c.scale = Vector2(absf(cos(t * 9.0)) * 0.7 + 0.3, 1.0), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void:
			Fx.play("coin_tick", -8.0, 0.0, pitch)
			c.queue_free())
	await get_tree().create_timer(0.55 + count * 0.05).timeout


func confetti(at: Vector2, amount := 70) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.6
	p.explosiveness = 0.95
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 380.0 * _scale
	p.initial_velocity_max = 620.0 * _scale
	p.gravity = Vector2(0, 700.0 * _scale)
	p.damping_min = 40.0
	p.damping_max = 90.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 6.0 * _scale
	p.scale_amount_max = 10.0 * _scale
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([Color("ff5d73"), Color("ffc23d"), Color("3ddc97"), Color("5cc8ff"), Color("c77ad9")])
	p.color_initial_ramp = grad
	p.position = at + Vector2(0, -40 * _scale)
	_fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## A ring of sparkles when a space changes hands or grows.
func _pop(at: Vector2, color: Color) -> void:
	var ring := Control.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.position = at
	var t0 := Time.get_ticks_msec()
	ring.draw.connect(func() -> void:
		var t := (Time.get_ticks_msec() - t0) / 450.0
		ring.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.56))
		ring.draw_arc(Vector2.ZERO, _cell * 0.5 * _scale * (1.0 + t * 1.2), 0, TAU, 40,
			Color(color.r, color.g, color.b, 1.0 - t), 6.0 * _scale * (1.0 - t * 0.6), true))
	_fx.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_method(func(_v: float) -> void: ring.queue_redraw(), 0.0, 1.0, 0.45)
	tw.tween_callback(ring.queue_free)
