extends Control
## Title screen over the slowly orbiting city: logo, tycoon picker, match length, settings
## toggles and a short how-to-play card. Emits `start` when the player taps Play.

signal start(tycoon: String, rounds: int)

const Board = preload("res://core/board.gd")
const TYCOON_COLORS := {"developer": Color("ff9f43"), "shark": Color("ff5d73"),
	"broker": Color("3ddc97"), "drifter": Color("5cc8ff")}

var hud  # the HUD, for its theme, fonts and portrait helper
var _tycoon := "developer"
var _rounds := Board.ROUNDS
var _picker: HBoxContainer
var _blurb: Label
var _rules: PanelContainer
var _length_buttons := {}


func setup(hud_ref) -> void:
	hud = hud_ref
	theme = hud.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		frame.add_theme_constant_override("margin_" + side, 28)
	frame.add_theme_constant_override("margin_top", 150)
	frame.add_theme_constant_override("margin_bottom", 36)
	add_child(frame)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	frame.add_child(col)

	var logo: Label = hud._label("SKYLOOP", 168, 900, Color.WHITE)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_color_override("font_outline_color", Color("3b2a7a"))
	logo.add_theme_constant_override("outline_size", 34)
	logo.add_theme_color_override("font_shadow_color", Color(0.15, 0.1, 0.35, 0.45))
	logo.add_theme_constant_override("shadow_offset_y", 14)
	logo.add_theme_constant_override("shadow_offset_x", 0)
	col.add_child(logo)
	var tag: Label = hud._label("Build the city above the clouds", 36, 700, Color.WHITE)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_outline_color", Color("3b2a7a"))
	tag.add_theme_constant_override("outline_size", 12)
	col.add_child(tag)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var card := PanelContainer.new()
	var sb: StyleBoxFlat = hud.panel_box(hud.CARD, 44)
	sb.set_content_margin_all(34)
	card.add_theme_stylebox_override("panel", sb)
	col.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	card.add_child(v)
	v.add_child(hud._label("Choose your tycoon", 34, 800))
	_picker = HBoxContainer.new()
	_picker.add_theme_constant_override("separation", 14)
	v.add_child(_picker)
	for t: String in Board.TYCOONS:
		_picker.add_child(_tycoon_button(t))
	_blurb = hud._label("", 26, 500, hud.DIM)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size.y = 76
	v.add_child(_blurb)

	var lengths := HBoxContainer.new()
	lengths.add_theme_constant_override("separation", 12)
	v.add_child(lengths)
	for opt: Array in [[8, "Quick · 8 rounds"], [Board.ROUNDS, "Classic · 12 rounds"]]:
		var b := Button.new()
		b.text = opt[1]
		b.custom_minimum_size = Vector2(0, 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(_set_rounds.bind(int(opt[0])))
		lengths.add_child(b)
		_length_buttons[int(opt[0])] = b

	var play := Button.new()
	play.text = "PLAY"
	play.theme_type_variation = "Primary"
	play.custom_minimum_size = Vector2(0, 130)
	play.add_theme_font_override("font", hud.font(900))
	play.add_theme_font_size_override("font_size", 52)
	play.pressed.connect(func() -> void:
		Fx.play("buy")
		Fx.buzz(30)
		start.emit(_tycoon, _rounds))
	v.add_child(play)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	row.add_child(_toggle("Sound", Fx.sound, func(on: bool) -> void:
		Fx.sound = on
		Fx.save_settings()))
	row.add_child(_toggle("Vibration", Fx.haptics, func(on: bool) -> void:
		Fx.haptics = on
		Fx.save_settings()
		Fx.buzz(40)))
	var how := Button.new()
	how.text = "How to play"
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how.custom_minimum_size = Vector2(0, 84)
	how.pressed.connect(func() -> void:
		Fx.play("click")
		_rules.visible = true)
	row.add_child(how)

	_build_rules()
	_select(_tycoon)
	_set_rounds(_rounds)


func _tycoon_button(t: String) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 230)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.name = t
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(hud.portrait(t, TYCOON_COLORS[t], 140))
	v.add_child(cc)
	var n: Label = hud._label(Board.TYCOONS[t].name.replace("The ", ""), 26, 800)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	b.pressed.connect(func() -> void:
		Fx.play("click")
		Fx.buzz(15)
		_select(t))
	return b


func _select(t: String) -> void:
	_tycoon = t
	for b: Button in _picker.get_children():
		var on := b.name == t
		var c: Color = TYCOON_COLORS[b.name]
		var box: StyleBoxFlat = hud.button_box(c.lerp(Color.WHITE, 0.7) if on else Color.WHITE,
			c.darkened(0.15) if on else Color("d3d8e8"))
		if on:
			box.border_width_top = 4
			box.border_width_left = 4
			box.border_width_right = 4
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, box)
		b.scale = Vector2.ONE
	var info: Dictionary = Board.TYCOONS[t]
	_blurb.text = "%s — %s\n★ %s" % [info.name, info.passive, info.power]


func _set_rounds(n: int) -> void:
	_rounds = n
	for k: int in _length_buttons:
		var b: Button = _length_buttons[k]
		b.set_pressed_no_signal(k == n)
		b.theme_type_variation = "Primary" if k == n else ""


func _toggle(label: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 84)
	b.text = "%s %s" % [label, "on" if on else "off"]
	b.toggled.connect(func(v: bool) -> void:
		b.text = "%s %s" % [label, "on" if v else "off"]
		cb.call(v)
		Fx.play("click"))
	return b


func _build_rules() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_rules = PanelContainer.new()
	_rules.custom_minimum_size = Vector2(940, 0)
	_rules.add_theme_stylebox_override("panel", hud.panel_box(hud.CARD, 44))
	_rules.visible = false
	center.add_child(_rules)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_rules.add_child(v)
	v.add_child(hud._label("How to play", 48, 900))
	var lines := [
		"🎲  Roll two dice. Moving by the total is free; using a single die costs one steer ◆.",
		"🏠  Buy empty tiles, or send them to a sealed auction where everyone bids in secret.",
		"🏗️  Build up to level 4. Own a whole district to raise a Landmark with a special power.",
		"💸  Land on a rival's tile and you pay rent. You can buy it out for double its value.",
		"📰  Each round brings a Headline that changes the rules for everyone.",
		"🏆  Richest after the last round wins, or own three full districts to win at once.",
	]
	for line: String in lines:
		var l: Label = hud._label(line, 28, 500, hud.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	var ok := Button.new()
	ok.text = "Got it"
	ok.theme_type_variation = "Primary"
	ok.custom_minimum_size = Vector2(0, 96)
	ok.pressed.connect(func() -> void:
		Fx.play("click")
		_rules.visible = false)
	v.add_child(ok)
