extends Control
## Bright, chunky HUD over the 3D board: player chips with portraits, headline card,
## toasts, dice and the bottom decision sheet. Cards and buttons have a darker bottom "lip"
## so they read as tactile. Emits `chosen` with a game choice; never touches game state.

signal chosen(choice: Dictionary)
signal quit_requested

const Board = preload("res://core/board.gd")
const Kit = preload("res://ui/kit.gd")
const QUICK_CHAT := ["Nice move!", "Oops!", "Hurry up!", "Thanks!", "Good game!", "Wow!", "My street!", "Lucky!"]

const ACCENT := Color("ffc23d")
const TEXT := Color("1d2340")
const DIM := Color("6b7391")
const CARD := Color(1, 1, 1, 0.96)
const INK := Color(0.1, 0.12, 0.24, 0.92)
const PORTRAIT_MASK = preload("res://ui/circle_mask.gdshader")

var g
var colors: Array = []
var human := 0

var _fonts := {}
var _chips: Array = []
var _shown_cash: Array = []
var _headline_panel: PanelContainer
var _headline_title: Label
var _headline_text: Label
var _round_label: Label
var _next_label: Label
var _toasts: VBoxContainer
var _sheet: PanelContainer
var _dice_row: HBoxContainer
var _dice: Array = []
var _title: Label
var _subtitle: Label
var _actions: VBoxContainer
var _tile_card: PanelContainer
var _tile_card_box: VBoxContainer
var _overlay: Control
var _column: VBoxContainer


class DieFace extends Control:
	var value := 1
	var accent := Color.WHITE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var rad := int(size.x * 0.27)
		var lip := StyleBoxFlat.new()
		lip.bg_color = Color("d5daea")
		lip.set_corner_radius_all(rad)
		lip.shadow_color = Color(0.19, 0.12, 0.43, 0.18)
		lip.shadow_size = 10
		lip.shadow_offset = Vector2(0, 6)
		draw_style_box(lip, r)
		var face := StyleBoxFlat.new()
		face.bg_color = Color("fffaf2")
		face.set_corner_radius_all(rad)
		draw_style_box(face, Rect2(Vector2.ZERO, size - Vector2(0, size.y * 0.09)))
		var h := size.y * 0.91
		var pips := {1: [[0.5, 0.5]], 2: [[0.28, 0.28], [0.72, 0.72]],
			3: [[0.26, 0.26], [0.5, 0.5], [0.74, 0.74]],
			4: [[0.28, 0.28], [0.72, 0.28], [0.28, 0.72], [0.72, 0.72]],
			5: [[0.27, 0.27], [0.73, 0.27], [0.5, 0.5], [0.27, 0.73], [0.73, 0.73]],
			6: [[0.28, 0.24], [0.72, 0.24], [0.28, 0.5], [0.72, 0.5], [0.28, 0.76], [0.72, 0.76]]}
		for p: Array in pips[clampi(value, 1, 6)]:
			draw_circle(Vector2(p[0] * size.x, p[1] * h), size.x * 0.085, Color("1d2340"))


## A player's portrait in a ring. On the active player the ring is the turn timer: it drains
## clockwise from full.
class Ring extends Control:
	var color := Color.WHITE
	var active := false
	var progress := 1.0:
		set(v):
			progress = v
			queue_redraw()

	func _draw() -> void:
		var c := size / 2
		var r := size.x / 2
		if not active:
			draw_circle(c, r, color, true, -1.0, true)
			return
		draw_circle(c, r, Color("e7e9f3"), true, -1.0, true)
		if progress > 0.001:
			var pts := PackedVector2Array([c])
			var n := maxi(3, int(64 * progress))
			for k in n + 1:
				var a := -PI / 2 + TAU * progress * k / n
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, color)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	# The kit's button looks (white, Primary, Mint, Coral) on top of the HUD's own theme.
	theme.merge_with(Kit.theme())


var meta: Array = []  # per seat {name, avatar, level, country}
var _deadline_tw: Tween


func setup(game, player_colors: Array, human_index: int, players_meta: Array = []) -> void:
	g = game
	colors = player_colors
	human = human_index
	meta = players_meta
	for c in get_children():
		c.queue_free()
	_chips.clear()
	_shown_cash.clear()
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		frame.add_theme_constant_override("margin_" + side, 24)
	frame.add_theme_constant_override("margin_bottom", 0)
	frame.add_theme_constant_override("margin_top", 32)
	add_child(frame)
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", 16)
	frame.add_child(_column)
	_build_top()
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(spacer)
	_build_toasts()
	_build_sheet()
	_build_tile_card()
	refresh(false)


## Canvas space the HUD covers above and below the board (top, bottom). The bottom is a fixed
## reserve so the board doesn't jump when the action panel changes height.
const BOTTOM_RESERVE := 400.0


func board_insets() -> Vector2:
	var top := 300.0
	if _headline_panel != null and _headline_panel.is_inside_tree():
		top = _headline_panel.get_global_rect().end.y + 12.0
	return Vector2(top, BOTTOM_RESERVE)


# ---------------------------------------------------------------- theme

## Fredoka for display weights, Nunito for body text (the kit's type system).
func font(weight: int) -> FontVariation:
	return Kit.font(true, mini(weight, 700)) if weight >= 600 else Kit.font(false, maxi(weight, 600) + 100)


static func panel_box(bg: Color, radius := 30, lip := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = lip if lip.a > 0 else bg.darkened(0.12)
	sb.border_width_bottom = 6
	sb.shadow_color = Color(0.12, 0.1, 0.3, 0.22)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 8)
	sb.set_content_margin_all(22)
	sb.anti_aliasing = true
	return sb


static func button_box(bg: Color, lip: Color, pressed := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(28)
	sb.border_color = lip
	sb.border_width_bottom = 2 if pressed else 8
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 22 if pressed else 16
	sb.content_margin_bottom = 16
	sb.shadow_color = Color(0.12, 0.1, 0.3, 0.12 if pressed else 0.2)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	sb.anti_aliasing = true
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 30
	t.set_color("font_color", "Label", TEXT)
	var white := Color("ffffff")
	var lip := Color("d3d8e8")
	t.set_stylebox("normal", "Button", button_box(white, lip))
	t.set_stylebox("hover", "Button", button_box(Color("f7f8fc"), lip))
	t.set_stylebox("pressed", "Button", button_box(Color("eef0f7"), lip, true))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", button_box(Color("eceef4"), lip))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "Button", TEXT)
	t.set_font("font", "Button", font(700))
	# Primary buttons use the "Primary" type variation.
	t.add_type("Primary")
	t.set_type_variation("Primary", "Button")
	var plip := Color("e09a12")
	t.set_stylebox("normal", "Primary", button_box(ACCENT, plip))
	t.set_stylebox("hover", "Primary", button_box(ACCENT.lightened(0.08), plip))
	t.set_stylebox("pressed", "Primary", button_box(ACCENT.darkened(0.05), plip, true))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "Primary", Color("3a2600"))
	# Slider.
	var track := StyleBoxFlat.new()
	track.bg_color = Color("e3e6f0")
	track.set_corner_radius_all(8)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := track.duplicate()
	fill.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := Image.create(56, 56, false, Image.FORMAT_RGBA8)
	knob.fill(Color(0, 0, 0, 0))
	for y in 56:
		for x in 56:
			var dd := Vector2(x - 27.5, y - 27.5).length()
			if dd < 26:
				knob.set_pixel(x, y, Color.WHITE if dd < 20 else Color("e09a12"))
	var tex := ImageTexture.create_from_image(knob)
	t.set_icon("grabber", "HSlider", tex)
	t.set_icon("grabber_highlight", "HSlider", tex)
	return t


func _label(text: String, size: int, weight := 500, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


# ---------------------------------------------------------------- layout

func _build_top() -> void:
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(top)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 16)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(chips)
	for pi in g.players.size():
		var chip := _make_chip(pi)
		chips.add_child(chip.panel)
		_chips.append(chip)
		_shown_cash.append(g.players[pi].cash)

	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 16)
	top.add_child(hrow)
	_headline_panel = PanelContainer.new()
	var hsb := Kit.box(Color(1, 1, 1, 0.9), 42, Color(0.63, 0.59, 0.82, 0.35), 8)
	hsb.content_margin_left = 22
	hsb.content_margin_right = 26
	hsb.content_margin_top = 16
	hsb.content_margin_bottom = 16
	_headline_panel.add_theme_stylebox_override("panel", hsb)
	_headline_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_headline_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(_headline_panel)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 22)
	_headline_panel.add_child(inner)
	var pill := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Kit.INK
	psb.set_corner_radius_all(26)
	psb.content_margin_left = 20
	psb.content_margin_right = 20
	psb.content_margin_top = 6
	psb.content_margin_bottom = 8
	psb.anti_aliasing = true
	pill.add_theme_stylebox_override("panel", psb)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(pill)
	_round_label = Kit.label("R1/12", 38, Color.WHITE, true, 700)
	pill.add_child(_round_label)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(hv)
	_headline_title = Kit.label("", 37, Color("b45309"), true, 600)
	_headline_title.clip_text = true
	hv.add_child(_headline_title)
	_headline_text = Kit.label("", 30, Kit.INK, false, 800)
	_headline_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_headline_text.clip_text = true
	hv.add_child(_headline_text)
	_next_label = Kit.label("", 1, Kit.INK2, false, 700)
	_next_label.visible = false
	hv.add_child(_next_label)
	for spec: Array in [["chat-circle-dots", _open_chat], ["pause", toggle_pause]]:
		var b := Kit.button("", "", 124)
		b.custom_minimum_size = Vector2(124, 124)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.icon = load("res://art/icons/%s.svg" % spec[0])
		b.add_theme_color_override("icon_normal_color", Kit.INK)
		b.add_theme_color_override("icon_pressed_color", Kit.INK)
		b.add_theme_color_override("icon_hover_color", Kit.INK)
		b.add_theme_constant_override("icon_max_width", 54)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for st in ["normal", "hover", "pressed"]:
			var bx := Kit.button_box(Color.WHITE if st != "pressed" else Color("f4f5fa"), Kit.LIP, st == "pressed", 42)
			bx.content_margin_left = 0
			bx.content_margin_right = 0
			bx.content_margin_top = 8 if st == "pressed" else 0
			bx.content_margin_bottom = 0
			bx.border_width_bottom = 4 if st == "pressed" else 10
			b.add_theme_stylebox_override(st, bx)
		b.pressed.connect(spec[1])
		hrow.add_child(b)


func _make_chip(pi: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	var ring := Ring.new()
	ring.color = colors[pi]
	ring.custom_minimum_size = Vector2(124, 124)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ring)
	var av := str(meta[pi].avatar) if pi < meta.size() else "a%02d" % (pi + 1)
	var face := Kit.avatar(av, 104, Color.WHITE, 0)
	face.position = Vector2(10, 10)
	var fsb: StyleBoxFlat = face.get_theme_stylebox("panel").duplicate()
	fsb.shadow_size = 0
	face.add_theme_stylebox_override("panel", fsb)
	ring.add_child(face)
	var name_l := Kit.label(_short_name(pi), 33, Kit.INK, true, 600)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(name_l)
	var cash := Kit.label("0", 40, Kit.INK, true, 700)
	cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cash)
	# One status pill under the cash: IN DEBT, FROZEN, SHIELD or PERMIT (most important first).
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.modulate.a = 0.0  # space stays reserved so cards never change height
	var info := Kit.label("", 21, Color.WHITE, true, 700)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_child(info)
	v.add_child(pill)
	return {"panel": panel, "cash": cash, "info": info, "pill": pill, "ring": ring}


func _short_name(pi: int) -> String:
	if pi == human:
		return "You"
	return str(meta[pi].name) if pi < meta.size() else g.players[pi].name


var _toast_layer: MarginContainer


func _build_toasts() -> void:
	_toast_layer = MarginContainer.new()
	_toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_layer.add_theme_constant_override("margin_top", 330)
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_layer)
	_toasts = VBoxContainer.new()
	_toasts.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 10)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(_toasts)


var _steer_box: VBoxContainer
var _steer_pips: HBoxContainer


func _build_sheet() -> void:
	_sheet = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Kit.CARD
	sb.corner_radius_top_left = 70
	sb.corner_radius_top_right = 70
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 34
	sb.content_margin_bottom = 52
	sb.shadow_color = Color(0.19, 0.12, 0.43, 0.22)
	sb.shadow_size = 28
	sb.anti_aliasing = true
	_sheet.add_theme_stylebox_override("panel", sb)
	_column.add_child(_sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 26)
	_sheet.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 26)
	v.add_child(head)
	_dice_row = HBoxContainer.new()
	_dice_row.add_theme_constant_override("separation", 16)
	_dice_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_dice_row)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(tv)
	_title = Kit.label("", 54, Kit.INK, true, 700)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(_title)
	_subtitle = Kit.label("", 31, Kit.INK2, false, 700)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(_subtitle)
	_steer_box = VBoxContainer.new()
	_steer_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_steer_box.add_theme_constant_override("separation", 2)
	_steer_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_steer_box)
	_steer_pips = HBoxContainer.new()
	_steer_pips.add_theme_constant_override("separation", 4)
	_steer_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_steer_box.add_child(_steer_pips)
	var sl := Kit.label("STEER", 28, Kit.INK2, false, 800)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_steer_box.add_child(sl)
	_steer_box.visible = false
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 18)
	v.add_child(_actions)


## Shows my steer tokens as violet diamonds (grey for empty slots).
func _show_steer(count: int, cap: int) -> void:
	for c in _steer_pips.get_children():
		c.queue_free()
	for k in maxi(cap, count):
		var d := Label.new()
		d.text = "◆"
		d.add_theme_font_override("font", Kit.font(true, 700))
		d.add_theme_font_size_override("font_size", 40)
		d.add_theme_color_override("font_color", Kit.VIOLET if k < count else Kit.LIP)
		_steer_pips.add_child(d)
	_steer_box.visible = true


func _build_tile_card() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_tile_card = PanelContainer.new()
	_tile_card.custom_minimum_size = Vector2(680, 0)
	_tile_card.add_theme_stylebox_override("panel", panel_box(CARD, 34))
	_tile_card.visible = false
	center.add_child(_tile_card)
	_tile_card_box = VBoxContainer.new()
	_tile_card_box.add_theme_constant_override("separation", 8)
	_tile_card.add_child(_tile_card_box)


# ---------------------------------------------------------------- updates

func refresh(animate := true) -> void:
	if _round_label == null:
		return
	_round_label.text = "R%d/%d" % [g.round_no, g.rounds]
	_toast_layer.add_theme_constant_override("margin_top", int(board_insets().x) + 8)
	for pi in _chips.size():
		var p = g.players[pi]
		var chip: Dictionary = _chips[pi]
		var active: bool = pi == g.turn and not g.over
		var pc: Color = colors[pi]
		var sb: StyleBoxFlat
		if active:
			sb = Kit.box(Color.WHITE, 46, pc, 14)
			sb.shadow_color = Color(0.19, 0.12, 0.43, 0.26)
			sb.shadow_size = 26
		else:
			sb = Kit.box(Color(1, 1, 1, 0.82), 46, Color(0.63, 0.59, 0.82, 0.4), 10)
			sb.shadow_size = 0
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 18
		sb.content_margin_bottom = 12
		chip.panel.add_theme_stylebox_override("panel", sb)
		var ring: Ring = chip.ring
		if ring.active != active:
			ring.active = active
			ring.progress = 1.0
			ring.queue_redraw()
		var status := ""
		var tone := Kit.INK
		if p.debt > 0:
			status = "IN DEBT"
			tone = Color("e0334d")
		elif p.frozen:
			status = "FROZEN"
			tone = Color("3f8fd9")
		elif p.shield:
			status = "SHIELD"
			tone = Color("1f9e68")
		elif p.permit:
			status = "PERMIT"
			tone = Kit.VIOLET
		chip.info.text = status
		var ps := StyleBoxFlat.new()
		ps.bg_color = tone
		ps.set_corner_radius_all(16)
		ps.content_margin_left = 14
		ps.content_margin_right = 14
		ps.content_margin_top = 1
		ps.content_margin_bottom = 3
		ps.anti_aliasing = true
		chip.pill.add_theme_stylebox_override("panel", ps)
		chip.pill.modulate.a = 1.0 if status != "" else 0.0
		# In debt, the number shows what the player owes, in red: their real position.
		if p.debt > 0:
			chip.cash.text = "−" + _num(p.debt)
			chip.cash.add_theme_color_override("font_color", Color("e0334d"))
			_shown_cash[pi] = p.cash
			continue
		chip.cash.add_theme_color_override("font_color", Kit.INK)
		if animate and _shown_cash[pi] != p.cash:
			var from: int = _shown_cash[pi]
			var lbl: Label = chip.cash
			create_tween().tween_method(func(v: float) -> void: lbl.text = _num(int(v)),
				float(from), float(p.cash), 0.6).set_trans(Tween.TRANS_QUAD)
			var flash := Color("17a35b") if p.cash > from else Color("e0334d")
			lbl.add_theme_color_override("font_color", flash)
			create_tween().tween_callback(func() -> void: lbl.add_theme_color_override("font_color", Kit.INK)) \
				.set_delay(0.7)
		else:
			chip.cash.text = _num(p.cash)
		_shown_cash[pi] = p.cash


## Cash on the player cards: plain numbers, like the mockups.
static func _num(v: int) -> String:
	return _money(v).replace("$", "")


static func _money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if v < 0 else "$") + s + out


func show_headline(h: Dictionary, next: Dictionary) -> void:
	_headline_title.text = h.title
	_headline_text.text = h.text
	_next_label.text = "next · " + next.title
	_headline_panel.pivot_offset = _headline_panel.size / 2
	_headline_panel.scale = Vector2(0.92, 0.92)
	_headline_panel.modulate = Color(1, 1, 1, 0)
	var tw := create_tween().set_parallel()
	tw.tween_property(_headline_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_headline_panel, "modulate:a", 1.0, 0.25)


## A dark pill under the round bar: "[face] Ayesha paid you +120". `seat` adds that player's
## portrait; a trailing "+N"/"-N"/"$N" amount is drawn in gold.
func toast(text: String, color := Color.WHITE, seat := -1) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.114, 0.137, 0.251, 0.9)
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 16 if seat >= 0 else 36
	sb.content_margin_right = 38
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	p.add_child(row)
	if seat >= 0 and seat < meta.size():
		row.add_child(Kit.avatar(str(meta[seat].avatar), 70, colors[seat], 4))
	var words := text
	var amount := ""
	var parts := text.rsplit(" ", true, 1)
	if parts.size() == 2 and (parts[1].begins_with("+") or parts[1].begins_with("-") or parts[1].begins_with("$")):
		words = parts[0]
		amount = parts[1]
	var l := Kit.label(words, 35, color if color != Color.WHITE else Color.WHITE, false, 800)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	if amount != "":
		var a := Kit.label(amount, 38, Color("ffd56a"), true, 700)
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(a)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 2:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	p.modulate.a = 0.0
	p.pivot_offset = Vector2(200, 40)
	p.scale = Vector2(0.9, 0.9)
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(p, "modulate:a", 1.0, 0.16)
	tw.tween_property(p, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(2.2)
	tw.chain().tween_property(p, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(p.queue_free)


## Tumbles the dice faces and settles on the rolled values. Await it.
func roll_dice(values: Array) -> void:
	for c in _dice_row.get_children():
		c.queue_free()
	_dice.clear()
	_sheet.visible = true
	_clear_actions()
	_subtitle.text = ""
	for v: int in values:
		var d := DieFace.new()
		d.custom_minimum_size = Vector2(118, 118)
		d.pivot_offset = Vector2(59, 59)
		_dice_row.add_child(d)
		_dice.append(d)
	for k in 9:
		for d: DieFace in _dice:
			d.value = randi_range(1, 6)
			d.rotation = randf_range(-0.35, 0.35)
			d.queue_redraw()
		await get_tree().create_timer(0.05).timeout
	for i in _dice.size():
		var d: DieFace = _dice[i]
		d.value = values[i]
		d.rotation = 0
		d.scale = Vector2(1.2, 1.2)
		create_tween().tween_property(d, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		d.queue_redraw()


func hide_dice() -> void:
	for c in _dice_row.get_children():
		c.queue_free()
	_dice.clear()


## Whose turn it is, shown while their dice roll and their piece moves, so the panel is
## never blank between decisions.
func turn_status(who: int) -> void:
	_clear_actions()
	_title.text = "Your turn" if who == human else "%s's turn" % _short_name(who)
	_subtitle.text = "" if who == human else "Watch the board"


func waiting(who: int) -> void:
	_clear_actions()
	_title.text = "%s is thinking…" % _short_name(who)
	_subtitle.text = ""


## The match is over: empty the action panel so nothing reads "thinking" under the results.
func match_over() -> void:
	_clear_actions()
	_title.text = "Game over"
	_subtitle.text = ""


# ---------------------------------------------------------------- decisions

func show_decision(pd: Dictionary) -> void:
	_clear_actions()
	var p = g.players[pd.player]
	match pd.type:
		"move":
			_title.text = "Where to?"
			_subtitle.text = "Tap a glowing tile or a choice below"
			_show_steer(p.steer, 5 if p.tycoon == "drifter" else 3)
			var grid := _grid(mini(3, pd.options.size()))
			for s: int in pd.options:
				grid.add_child(_move_button(pd, s))
			if pd.can_shortcut:
				_add_custom("★  Shortcut anywhere", _show_shortcut)
		"metro":
			_title.text = "Metro"
			_subtitle.text = "Ride 1 to 6 stops."
			var grid := _grid(3)
			for s: int in pd.options:
				grid.add_child(_button("%d · %s" % [s, Board.TILES[(p.pos + s) % Board.TILE_COUNT].name], {"steps": s}))
		"perk":
			_title.text = "Payday!"
			_subtitle.text = "Salary is in. Pick a perk."
			_add_button("+$%d cash" % Board.PERK_CASH, {"perk": "cash"}, true)
			_add_button("✦ Permit — next build half price", {"perk": "permit"})
			_add_button("⛨ Shield — next rent halved", {"perk": "shield"})
		"buy":
			var t: Dictionary = Board.TILES[pd.tile]
			_title.text = t.name
			_subtitle.text = "%s · base rent %d · you have %s" % [Board.DISTRICTS[t.district].name,
				_base_rent(pd.tile), _money(p.cash)]
			var row := _grid(2)
			row.add_child(_button("Buy  %s" % _money(pd.price), {"buy": true}, true))
			row.add_child(_button("Auction it", {"buy": false}))
		"bid":
			_show_bid(pd)
		"audit":
			_title.text = "Audit!"
			_subtitle.text = "Pay the fee, or your tiles collect no rent until your next turn."
			var row := _grid(2)
			row.add_child(_button("Pay %s" % _money(pd.fee), {"pay": true}, true))
			row.add_child(_button("Take the freeze", {"pay": false}))
		"takeover":
			var t: Dictionary = Board.TILES[pd.tile]
			_title.text = "Hostile takeover?"
			_subtitle.text = "Buy %s from %s, buildings included." % [t.name, _short_name(g.owner_of[pd.tile])]
			var row := _grid(2)
			row.add_child(_button("Buy out  %s" % _money(pd.cost), {"accept": true}, true))
			row.add_child(_button("Leave it", {"accept": false}))
		"manage":
			hide_dice()
			_title.text = "Your city"
			_subtitle.text = "Build up, use your power, or end the turn."
			var builds := []
			for act: Dictionary in pd.actions:
				if act.a == "upgrade":
					builds.append(act)
			var powers := (pd.actions as Array).filter(func(act: Dictionary) -> bool: return act.a == "power")
			# Keep the panel short: four builds at most, and powers behind one button when
			# there are several, so the board stays visible.
			if not builds.is_empty():
				var grid := _grid(2)
				for act: Dictionary in builds.slice(0, 4):
					grid.add_child(_build_button(act))
				if builds.size() > 4:
					_add_custom("More builds (%d)" % (builds.size() - 4), func() -> void:
						_show_list("Build", "Pick a tile to build on.", builds.map(func(act: Dictionary) -> Button:
							return _build_button(act)), pd))
			if powers.size() == 1:
				_add_button("★  " + _power_label(p.tycoon, powers[0]), powers[0])
			elif powers.size() > 1:
				_add_custom("★  %s (%d)" % [_power_name(p.tycoon), powers.size()], func() -> void:
					_show_list(_power_name(p.tycoon), "Your tycoon power. Pick one.", powers.map(func(act: Dictionary) -> Button:
						return _button(_power_label(p.tycoon, act), act)), pd))
			_add_button("End turn", {"a": "end"}, true)


## A destination button: the step count big, what happens there underneath, coloured by
## whether it's good (mint), costly (coral) or neutral (white). Steered moves show a ◆.
func _move_button(pd: Dictionary, steps: int) -> Button:
	var pv: Dictionary = g.landing_preview(pd.player, steps)
	var free: bool = pd.free.has(steps)
	var tone: String = pv.get("tone", "neutral")
	var variant: String = {"good": "Mint", "bad": "Coral"}.get(tone, "")
	var ink: Color = {"good": Color("063b25"), "bad": Color.WHITE}.get(tone, Kit.INK)
	var b := Kit.button("", variant, 186)
	b.pressed.connect(_emit.bind({"steps": steps}))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_bottom = -14
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var n := Kit.label("%d%s" % [steps, "" if free else " ◆"], 56, ink, true, 700)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var what := Kit.label(str(pv.get("text", Board.TILES[pv.tile].name)), 33, ink, true, 600)
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	what.clip_text = true
	what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(what)
	return b


func _show_bid(pd: Dictionary) -> void:
	var t: Dictionary = Board.TILES[pd.tile]
	_title.text = "Sealed auction · %s" % t.name
	_subtitle.text = "List %s. Highest secret bid wins. Minimum %s." % [_money(t.price), _money(pd.min_bid)]
	var amount := _label(_money(pd.min_bid), 56, 700, ACCENT)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_actions.add_child(amount)
	var slider := HSlider.new()
	slider.min_value = pd.min_bid
	slider.max_value = pd.max_bid
	slider.step = 5
	slider.value = mini(pd.max_bid, int(t.price * 0.8 / 5.0) * 5)
	slider.custom_minimum_size = Vector2(0, 70)
	_actions.add_child(slider)
	amount.text = _money(int(slider.value))
	var row := _grid(2)
	var bid_btn := _button("Bid %s" % _money(int(slider.value)), {}, true)
	slider.value_changed.connect(func(v: float) -> void:
		amount.text = _money(int(v))
		bid_btn.text = "Bid %s" % _money(int(v)))
	bid_btn.pressed.connect(func() -> void: _emit({"bid": int(slider.value)}))
	row.add_child(_button("Pass", {"bid": 0}))
	row.add_child(bid_btn)


func _show_shortcut() -> void:
	_clear_actions()
	_title.text = "Shortcut"
	_subtitle.text = "Jump to any district tile."
	var grid := _grid(2)
	for t in Board.TILE_COUNT:
		if g.is_property(t) and t != g.players[g.turn].pos:
			grid.add_child(_button(Board.TILES[t].name, {"shortcut": t}))
	_add_custom("Back", func() -> void: show_decision(g.pending))


func _build_button(act: Dictionary) -> Button:
	var lvl: int = g.level_of[act.tile] + 1
	var what: String = Board.DISTRICTS[Board.TILES[act.tile].district].landmark \
		if lvl == Board.LANDMARK_LEVEL else "Lv %d" % lvl
	return _button("%s → %s\n%s" % [Board.TILES[act.tile].name, what, _money(act.cost)], act)


## A sub-list of choices (all builds, all power targets) with a way back.
func _show_list(title: String, sub: String, buttons: Array, pd: Dictionary) -> void:
	_clear_actions()
	_title.text = title
	_subtitle.text = sub
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, mini(buttons.size(), 5) * 102)
	_actions.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for b: Button in buttons:
		grid.add_child(b)
	_add_custom("Back", func() -> void: show_decision(pd))


func _power_name(tycoon: String) -> String:
	match tycoon:
		"developer":
			return "Overnight Build"
		"shark":
			return "Squeeze"
		"broker":
			return "Swap tiles"
	return "Power"


func _power_label(tycoon: String, act: Dictionary) -> String:
	match tycoon:
		"developer":
			return "Overnight Build · %s" % Board.TILES[act.tile].name
		"shark":
			return "Squeeze · double your next rent"
		"broker":
			return "Swap %s ⇄ %s" % [Board.TILES[act.give].name, Board.TILES[act.take].name]
	return "Power"


func _base_rent(tile: int) -> int:
	return int(Board.TILES[tile].price * Board.RENT_RATE)


func _grid(cols: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_actions.add_child(grid)
	return grid


func _button(text: String, choice: Dictionary, primary := false) -> Button:
	var b := Kit.button(text, "Primary" if primary else "", 150)
	b.add_theme_font_size_override("font_size", 40)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if not choice.is_empty():
		b.pressed.connect(_emit.bind(choice))
	return b


func _add_button(text: String, choice: Dictionary, primary := false) -> void:
	_actions.add_child(_button(text, choice, primary))


func _add_custom(text: String, cb: Callable) -> void:
	var b := _button(text, {})
	b.pressed.connect(cb)
	_actions.add_child(b)


func _emit(choice: Dictionary) -> void:
	_clear_actions()
	chosen.emit(choice)


func _clear_actions() -> void:
	if _steer_box != null:
		_steer_box.visible = false
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()


# ---------------------------------------------------------------- tile card & results

func show_tile(i: int) -> void:
	for c in _tile_card_box.get_children():
		c.queue_free()
	var t: Dictionary = Board.TILES[i]
	if t.kind == Board.Kind.PROPERTY:
		var d: Dictionary = Board.DISTRICTS[t.district]
		var bar := ColorRect.new()
		bar.color = d.color
		bar.custom_minimum_size = Vector2(0, 12)
		_tile_card_box.add_child(bar)
		_tile_card_box.add_child(_label(t.name, 42, 700))
		_tile_card_box.add_child(_label(d.name.to_upper(), 22, 700, (d.color as Color).darkened(0.3)))
		var o: int = g.owner_of[i]
		var owner_txt := "Unowned · %s" % _money(g.price_of(i)) if o == -1 \
			else "Owned by %s · level %d · rent %d" % [_short_name(o), g.level_of[i], g.rent_for(i)]
		_tile_card_box.add_child(_label(owner_txt, 26, 500, TEXT))
		var base: float = t.price * Board.RENT_RATE
		var rows := []
		for k in Board.LEVEL_MULT.size():
			rows.append("%s %d" % ["L%d" % k if k < Board.LANDMARK_LEVEL else "★", int(base * Board.LEVEL_MULT[k])])
		_tile_card_box.add_child(_label("Base rents  " + "   ".join(rows), 22, 400, DIM))
		var lm := _label("Landmark · %s: %s" % [d.landmark, d.power], 22, 400, DIM)
		lm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tile_card_box.add_child(lm)
	else:
		_tile_card_box.add_child(_label(t.name, 42, 700))
		var help := {
			Board.Kind.PAYDAY: "Pass for $%d salary, a perk and a steer token." % Board.SALARY,
			Board.Kind.AUDIT: "Pay $%d or collect no rent until your next turn." % Board.AUDIT_FEE,
			Board.Kind.JACKPOT: "Land here to take the whole pot: %s." % _money(g.pot),
			Board.Kind.TAX_RAID: "Pay 15% of your cash into the Jackpot.",
			Board.Kind.METRO: "Ride on 1 to 6 stops, your choice.",
			Board.Kind.WINDFALL: "Collect 40 + 10 × the round number.",
			Board.Kind.PERMIT_OFFICE: "Get a Permit: your next build is half price.",
		}
		var l := _label(help[t.kind], 26, 400, DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tile_card_box.add_child(l)
	_tile_card.visible = true
	_tile_card.modulate.a = 0
	create_tween().tween_property(_tile_card, "modulate:a", 1.0, 0.15)


func hide_tile() -> void:
	_tile_card.visible = false


func show_results(on_again: Callable) -> void:
	_sheet.visible = false
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0.1, 0.08, 0.25, 0.45)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(800, 0)
	card.add_theme_stylebox_override("panel", panel_box(CARD, 44))
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	var win: int = g.winner
	v.add_child(_centered(portrait(g.players[win].tycoon, colors[win], 180)))
	var head := _label("%s %s!" % [_short_name(win), "win" if win == human else "wins"], 58, 800, (colors[win] as Color).darkened(0.3))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var how := _label("Three full districts" if g.win_reason == "districts" else "Highest net worth after %d rounds" % g.rounds,
		24, 500, DIM)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(how)
	var order := range(g.players.size())
	order.sort_custom(func(a: int, b: int) -> bool: return g.net_worth(a) > g.net_worth(b))
	for rank in order.size():
		var pi: int = order[rank]
		var row := HBoxContainer.new()
		row.add_child(_label("%d" % (rank + 1), 34, 700, DIM))
		row.add_child(portrait(g.players[pi].tycoon, colors[pi], 54))
		var n := _label("  " + _short_name(pi), 34, 700, TEXT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(_label(_money(g.net_worth(pi)), 34, 700))
		v.add_child(row)
	var again := _button("Continue", {}, true)
	again.pressed.connect(on_again)
	v.add_child(again)
	card.pivot_offset = Vector2(400, 300)
	card.scale = Vector2(0.85, 0.85)
	create_tween().tween_property(card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- portraits

## Round tycoon portrait with a coloured ring; falls back to a plain disc when the art is
## missing.
func portrait(tycoon: String, ring: Color, size: int) -> Control:
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = ring
	sb.set_corner_radius_all(size / 2)
	sb.anti_aliasing = true
	holder.add_theme_stylebox_override("panel", sb)
	var path := "res://art/tycoons/%s.png" % tycoon
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var inset := maxi(3, size / 18)
		tr.offset_left = inset
		tr.offset_top = inset
		tr.offset_right = -inset
		tr.offset_bottom = -inset
		var m := ShaderMaterial.new()
		m.shader = PORTRAIT_MASK
		tr.material = m
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	return holder


func _centered(c: Control) -> Control:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc


# ---------------------------------------------------------------- pause

var _pause: Control


func toggle_pause() -> void:
	if _pause != null:
		_pause.queue_free()
		_pause = null
		return
	# The match keeps running (other players are waiting), so this is a menu, not a pause.
	Fx.play("click")
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0.1, 0.08, 0.25, 0.45)
	_pause.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_pause)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(700, 0)
	card.add_theme_stylebox_override("panel", panel_box(CARD, 44))
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	var title := _label("Menu", 52, 900)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var resume := _button("Back to the game", {}, true)
	resume.pressed.connect(toggle_pause)
	v.add_child(resume)
	var snd := _button("Sound: %s" % ("on" if Fx.sound else "off"), {})
	snd.pressed.connect(func() -> void:
		Fx.sound = not Fx.sound
		Fx.save_settings()
		snd.text = "Sound: %s" % ("on" if Fx.sound else "off"))
	v.add_child(snd)
	var vib := _button("Vibration: %s" % ("on" if Fx.haptics else "off"), {})
	vib.pressed.connect(func() -> void:
		Fx.haptics = not Fx.haptics
		Fx.save_settings()
		vib.text = "Vibration: %s" % ("on" if Fx.haptics else "off"))
	v.add_child(vib)
	var quit := _button("Leave match", {})
	quit.pressed.connect(func() -> void:
		toggle_pause()
		quit_requested.emit())
	v.add_child(quit)


# ---------------------------------------------------------------- juice

signal rolled


## Shows a big "hold to roll" button and waits until the player lets go of it.
func wait_roll() -> void:
	_clear_actions()
	hide_dice()
	_sheet.visible = true
	_title.text = "Your turn"
	_subtitle.text = "Hold to shake the dice, let go to throw."
	var b := _button("HOLD TO ROLL", {}, true)
	b.custom_minimum_size = Vector2(0, 150)
	b.add_theme_font_override("font", font(900))
	b.add_theme_font_size_override("font_size", 46)
	b.pivot_offset = Vector2(470, 75)
	var pulse := b.create_tween().set_loops()
	pulse.tween_property(b, "scale", Vector2(1.03, 1.03), 0.5).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(b, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	var shaking := [false]
	b.button_down.connect(func() -> void:
		shaking[0] = true
		pulse.kill()
		Fx.play("shake")
		while shaking[0] and is_instance_valid(b):
			b.rotation = randf_range(-0.03, 0.03)
			Fx.buzz(18, 0.3)
			await get_tree().create_timer(0.07).timeout)
	b.button_up.connect(func() -> void:
		shaking[0] = false
		rolled.emit())
	_actions.add_child(b)
	await rolled
	_clear_actions()


## A big bouncy word in the middle of the screen ("JACKPOT!", "+$420").
func callout(text: String, color: Color, size := 120) -> void:
	var l := _label(text, size, 900, color)
	l.add_theme_color_override("font_outline_color", Color("3b2a7a"))
	l.add_theme_constant_override("outline_size", 26)
	l.add_theme_color_override("font_shadow_color", Color(0.15, 0.1, 0.35, 0.4))
	l.add_theme_constant_override("shadow_offset_y", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.offset_left = -540
	l.offset_right = 540
	l.offset_top = -260
	l.offset_bottom = -60
	l.pivot_offset = Vector2(540, 100)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.scale = Vector2(0.3, 0.3)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(0.7)
	tw.parallel().tween_property(l, "position:y", l.position.y - 60, 0.5).set_delay(0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


## Confetti raining over the whole screen.
func confetti_2d() -> void:
	var p := CPUParticles2D.new()
	p.amount = 160
	p.lifetime = 3.0
	p.one_shot = true
	p.explosiveness = 0.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(560, 10)
	p.direction = Vector2(0, 1)
	p.spread = 25.0
	p.gravity = Vector2(0, 520)
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 380.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 10.0
	p.scale_amount_max = 18.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([Color("ff5d73"), Color("ffc23d"), Color("3ddc97"), Color("5cc8ff"), Color("c77ad9")])
	p.color_initial_ramp = grad
	p.position = Vector2(get_viewport_rect().size.x / 2, -20)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(3.5).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- online: timers and chat

## Drains the active player's timer bar over `seconds`.
func set_deadline(seat: int, seconds: float) -> void:
	clear_deadline()
	if seat < 0 or seat >= _chips.size():
		return
	var ring: Ring = _chips[seat].ring
	ring.active = true
	ring.progress = 1.0
	_deadline_tw = create_tween()
	_deadline_tw.tween_property(ring, "progress", 0.0, seconds)


func clear_deadline() -> void:
	if _deadline_tw != null and _deadline_tw.is_valid():
		_deadline_tw.kill()
	for chip: Dictionary in _chips:
		(chip.ring as Ring).progress = 1.0


func _open_chat() -> void:
	Fx.play("click")
	var veil := ColorRect.new()
	veil.color = Color(0.12, 0.09, 0.28, 0.35)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(760, 0)
	card.add_theme_stylebox_override("panel", panel_box(CARD, 40))
	center.add_child(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	card.add_child(grid)
	for t: String in QUICK_CHAT:
		var b := _button(t, {})
		b.custom_minimum_size = Vector2(340, 88)
		b.pressed.connect(func() -> void:
			Net.send({"t": "chat", "text": t})
			veil.queue_free())
		grid.add_child(b)
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			veil.queue_free())


## A speech bubble under a player's card.
func chat_bubble(seat: int, text: String) -> void:
	if seat < 0 or seat >= _chips.size():
		return
	var chip: Dictionary = _chips[seat]
	var bubble := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(26)
	sb.border_color = colors[seat]
	sb.set_border_width_all(4)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0.19, 0.12, 0.43, 0.25)
	sb.shadow_size = 10
	bubble.add_theme_stylebox_override("panel", sb)
	bubble.add_child(_label(text, 26, 700, TEXT))
	add_child(bubble)
	var r: Rect2 = chip.panel.get_global_rect()
	bubble.position = Vector2(clampf(r.position.x, 10, get_viewport_rect().size.x - 300), r.end.y + 10)
	bubble.scale = Vector2(0.4, 0.4)
	var tw := bubble.create_tween()
	tw.tween_property(bubble, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(2.2)
	tw.tween_property(bubble, "modulate:a", 0.0, 0.3)
	tw.tween_callback(bubble.queue_free)
	Fx.play("toast", -6.0)


## A friendly first-time tip at the top of the board; tap or wait to dismiss.
func coach(text: String) -> void:
	var p := PanelContainer.new()
	var sb := panel_box(Color("fff8e6"), 32, Color("f0c46a"))
	sb.set_content_margin_all(20)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	p.offset_left = -470
	p.offset_right = 470
	p.offset_top = 330
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	h.add_child(Kit.icon3d("xp", 72))
	var l := _label(text, 28, 700, TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(6.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and is_instance_valid(p):
			p.queue_free())
