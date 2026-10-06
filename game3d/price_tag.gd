extends Node3D
## A rounded price chip that hovers over a tile and always faces the camera: white with dark
## text for prices, filled with the owner's colour for rents.

const FONT = preload("res://art/fonts/Outfit.ttf")

static var _chips := {}  # width in px -> texture

var _sprite: Sprite3D
var _label: Label3D


func _init() -> void:
	_sprite = Sprite3D.new()
	_sprite.texture = _chip_texture(140)
	_sprite.pixel_size = 0.0034
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.render_priority = 1
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sprite)
	_label = Label3D.new()
	var f := FontVariation.new()
	f.base_font = FONT
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	_label.font = f
	_label.font_size = 58
	_label.outline_size = 0
	_label.pixel_size = 0.0034
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.render_priority = 2
	_label.position = Vector3(0, 0, 0.001)
	add_child(_label)


func show_text(text: String, fill: Color) -> void:
	_label.text = text
	# Widen the chip to fit the text, in 20 px steps so textures are shared.
	var w := _label.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label.font_size).x
	_sprite.texture = _chip_texture(maxi(140, int(ceil((w + 44.0) / 20.0)) * 20))
	_sprite.modulate = fill
	_label.modulate = Color("1b2133") if fill.get_luminance() > 0.55 else Color.WHITE


static func _chip_texture(w: int) -> ImageTexture:
	if _chips.has(w):
		return _chips[w]
	var h := 64
	var r := 30.0
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			# Signed distance to a rounded rectangle, antialiased over one pixel.
			var qx := absf(x + 0.5 - w / 2.0) - (w / 2.0 - r)
			var qy := absf(y + 0.5 - h / 2.0) - (h / 2.0 - r)
			var d := Vector2(maxf(qx, 0), maxf(qy, 0)).length() + minf(maxf(qx, qy), 0) - r
			var a := clampf(0.5 - d, 0.0, 1.0)
			var edge := clampf(0.5 - (d + 4.0), 0.0, 1.0)
			# A thin darker rim keeps white chips readable on light tiles.
			var c := Color(1, 1, 1).lerp(Color(0.75, 0.78, 0.85), 1.0 - edge)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	_chips[w] = ImageTexture.create_from_image(img)
	return _chips[w]
