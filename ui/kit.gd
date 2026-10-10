extends RefCounted
## Skyloop UI kit: fonts, colours, the chunky button/card styles and small widget builders
## shared by the lobby, the HUD and every popup. Mirrors the approved Phase A mockups.

const FREDOKA = preload("res://art/fonts/Fredoka.ttf")
const NUNITO = preload("res://art/fonts/Nunito.ttf")
const MASK = preload("res://ui/circle_mask.gdshader")

const INK := Color("1d2340")
const INK2 := Color("565d7a")
const CARD := Color(1, 1, 1, 0.97)
const LIP := Color("d5daea")
const GOLD := Color("ffc23d")
const GOLD_LIP := Color("d9890b")
const GOLD_INK := Color("3a2600")
const CORAL := Color("ff5d73")
const MINT := Color("3ddc97")
const SKY := Color("38b6ff")
const VIOLET := Color("8e6ce0")
const CREAM := Color("fff6ec")
const TIER_COLORS := [Color("38b6ff"), Color("ff8a5c"), Color("3ddc97"), Color("8e6ce0"), Color("ffb21f")]

static var _fonts := {}
static var _icons := {}


## Fredoka for display text and numbers, Nunito for body copy.
static func font(display: bool, weight: int) -> FontVariation:
	var key := "%s%d" % ["d" if display else "b", weight]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = FREDOKA if display else NUNITO
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[key] = f
	return _fonts[key]


static func label(text: String, size: int, color := INK, display := true, weight := 600) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(display, weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A big white headline with a purple outline, used over the sky.
static func title(text: String, size: int) -> Label:
	var l := label(text, size, Color.WHITE, true, 700)
	l.add_theme_color_override("font_outline_color", Color("3b2a7a"))
	l.add_theme_constant_override("outline_size", maxi(8, size / 5))
	l.add_theme_color_override("font_shadow_color", Color(0.15, 0.1, 0.35, 0.35))
	l.add_theme_constant_override("shadow_offset_y", maxi(4, size / 12))
	l.add_theme_constant_override("shadow_offset_x", 0)
	return l


static func box(bg: Color, radius := 48, lip := Color(0, 0, 0, 0), lip_px := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = lip if lip.a > 0 else bg.darkened(0.14)
	sb.border_width_bottom = lip_px
	sb.shadow_color = Color(0.19, 0.12, 0.43, 0.18)
	sb.shadow_size = 22
	sb.shadow_offset = Vector2(0, 12)
	sb.set_content_margin_all(36)
	sb.anti_aliasing = true
	return sb


static func button_box(bg: Color, lip: Color, pressed := false, radius := 44) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = lip
	sb.border_width_bottom = 5 if pressed else 16
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 34 if pressed else 22
	sb.content_margin_bottom = 22
	sb.shadow_color = Color(0.19, 0.12, 0.43, 0.12 if pressed else 0.2)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 8)
	sb.anti_aliasing = true
	return sb


## The app-wide theme: chunky white buttons; "Primary" = gold, "Sky", "Mint", "Coral" variants.
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(false, 700)
	t.default_font_size = 40
	t.set_color("font_color", "Label", INK)
	_variant(t, "Button", Color.WHITE, LIP, INK)
	t.set_font("font", "Button", font(true, 600))
	t.set_font_size("font_size", "Button", 46)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for v: Array in [["Primary", GOLD, GOLD_LIP, GOLD_INK], ["SkyBtn", SKY, Color("1a86c7"), Color("04263f")],
			["Mint", MINT, Color("1f9e68"), Color("063b25")], ["Coral", CORAL, Color("d63a52"), Color.WHITE],
			["Ghost", Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), INK]]:
		t.add_type(v[0])
		t.set_type_variation(v[0], "Button")
		_variant(t, v[0], v[1], v[2], v[3])
	var line := StyleBoxFlat.new()
	line.bg_color = Color.WHITE
	line.set_corner_radius_all(28)
	line.border_color = LIP
	line.set_border_width_all(4)
	line.set_content_margin_all(26)
	t.set_stylebox("normal", "LineEdit", line)
	t.set_stylebox("focus", "LineEdit", line)
	t.set_color("font_color", "LineEdit", INK)
	t.set_font_size("font_size", "LineEdit", 44)
	return t


static func _variant(t: Theme, type: String, bg: Color, lip: Color, ink: Color) -> void:
	t.set_stylebox("normal", type, button_box(bg, lip))
	t.set_stylebox("hover", type, button_box(bg.lightened(0.06), lip))
	t.set_stylebox("pressed", type, button_box(bg.darkened(0.05), lip, true))
	t.set_stylebox("disabled", type, button_box(bg.lerp(Color("c9cedd"), 0.6), lip))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, type, ink)
	t.set_color("font_disabled_color", type, ink.lerp(Color.WHITE, 0.4))


static func button(text: String, variant := "", height := 150) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variant
	b.custom_minimum_size = Vector2(0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void:
		Fx.play("click")
		Fx.buzz(12, 0.3))
	return b


## A Phosphor icon (white SVG) tinted to `color`.
static func icon(name: String, size: int, color := INK) -> TextureRect:
	var tr := TextureRect.new()
	if not _icons.has(name):
		_icons[name] = load("res://art/icons/%s.svg" % name)
	tr.texture = _icons[name]
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(size, size)
	tr.modulate = color
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## A rendered 3D icon (art/ui/icons3d/<name>.png).
static func icon3d(name: String, size: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load("res://art/ui/icons3d/%s.png" % name)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(size, size)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## A round player avatar with a coloured ring.
static func avatar(id: String, size: int, ring := Color.WHITE, ring_px := -1) -> Control:
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = ring
	sb.set_corner_radius_all(size / 2)
	sb.anti_aliasing = true
	sb.shadow_color = Color(0.19, 0.12, 0.43, 0.25)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	holder.add_theme_stylebox_override("panel", sb)
	var path := "res://art/avatars/%s.png" % id
	if not ResourceLoader.exists(path):
		path = "res://art/avatars/a01.png"
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := ring_px if ring_px >= 0 else maxi(4, size / 16)
	tr.offset_left = inset
	tr.offset_top = inset
	tr.offset_right = -inset
	tr.offset_bottom = -inset
	var m := ShaderMaterial.new()
	m.shader = MASK
	tr.material = m
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tr)
	return holder


## A currency pill: 3D icon, amount, optional green "+" button.
static func pill(kind: String, amount: int, plus := Callable()) -> Dictionary:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.95)
	sb.set_corner_radius_all(999)
	sb.border_color = LIP
	sb.border_width_bottom = 8
	sb.content_margin_left = 8
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(0.19, 0.12, 0.43, 0.15)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	h.add_child(icon3d("coin" if kind == "coins" else "gem", 68))
	var l := label(money(amount), 46, INK, true, 600)
	l.custom_minimum_size.x = 150
	h.add_child(l)
	if plus.is_valid():
		var b := Button.new()
		b.custom_minimum_size = Vector2(62, 62)
		b.add_theme_stylebox_override("normal", _round(MINT))
		b.add_theme_stylebox_override("hover", _round(MINT.lightened(0.08)))
		b.add_theme_stylebox_override("pressed", _round(MINT.darkened(0.08)))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.icon = load("res://art/icons/x.svg") if false else null
		b.text = "+"
		b.add_theme_font_override("font", font(true, 700))
		b.add_theme_font_size_override("font_size", 46)
		b.add_theme_color_override("font_color", Color("063b25"))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(plus)
		h.add_child(b)
	return {"panel": p, "label": l}


static func _round(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(31)
	sb.anti_aliasing = true
	return sb


static func money(v: int) -> String:
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


## A rounded progress bar; returns {root, fill} so callers can animate fill.size.
static func bar(width: int, height: int, value: float, fill_color := GOLD) -> Dictionary:
	var root := Panel.new()
	root.custom_minimum_size = Vector2(width, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("e7e9f3")
	bg.set_corner_radius_all(height / 2)
	root.add_theme_stylebox_override("panel", bg)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := Panel.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = fill_color
	fs.set_corner_radius_all(height / 2)
	fill.add_theme_stylebox_override("panel", fs)
	fill.position = Vector2.ZERO
	fill.size = Vector2(maxf(height, width * clampf(value, 0.0, 1.0)), height)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	return {"root": root, "fill": fill, "width": width}


## A red notification dot to pin on an icon button.
static func dot(text := "!") -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CORAL
	sb.set_corner_radius_all(30)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(5)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(54, 54)
	var l := label(text, 32, Color.WHITE, true, 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p
