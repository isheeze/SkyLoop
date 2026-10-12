extends Node3D
## The board: a toy diorama on a floating island (kit in art/toy, built by
## tools/blender/build_toy.py, rules in docs/STYLE_GUIDE.md). Mirrors game state and animates
## changes; it never changes the game itself.
##
## Layout: 28 tiles on an 8 x 8 ring, Payday at the corner nearest the camera. Each tile's front
## faces the camera's side of its axis (+Z on the rows, +X on the columns): the building stands on
## the back half, pieces on the front half, the price is printed on the district stripe.

const Board = preload("res://core/board.gd")
const Models = preload("res://game3d/models.gd")
const PriceTag = preload("res://game3d/price_tag.gd")
const FONT = preload("res://art/fonts/Fredoka.ttf")

const KIT := "res://art/toy/%s.glb"
const TILE := 1.0
const TILE_TOP := 0.15  # top face of a tile slab
const BUILDING_BACK := 0.17  # building centre, behind the tile centre
const PIECE_FRONT := 0.18  # pieces stand this far in front of the tile centre
const BUILDING_SCALE := 1.25
const CORNER_SCALE := 1.12
const PAWN_SCALE := 1.3
const CORNERS := {Board.Kind.PAYDAY: "c_payday", Board.Kind.AUDIT: "c_audit", Board.Kind.JACKPOT: "c_jackpot",
	Board.Kind.TAX_RAID: "c_vault"}
const SPECIAL_PROPS := {Board.Kind.METRO: "s_metro", Board.Kind.WINDFALL: "s_windfall",
	Board.Kind.PERMIT_OFFICE: "s_permit"}
const SPECIAL_STRIPE := Color("ffd23f")
## Wall tints, varied per tile so a street doesn't look copy-pasted.
const WALLS := [Color("fff4e2"), Color("fde6d8"), Color("e8f4ea"), Color("eae6fb"), Color("e3f1fb"), Color("fff0c8")]
const INK := Color("1d2340")

var g
var colors: Array = []

var _tiles: Array = []  # per tile: {root, front, building, label}
var _tokens: Array = []
var _token_tile: Array = []
var _levels: Array = []
var _owners: Array = []
var _targets: Array = []  # [{tile, node}]
var _pot_tag: Node3D
var _time := 0.0
var _active := -1
var _life: Array = []  # balloons: [{node, t, speed, lane, h}]

static var _scenes := {}  # kit name -> PackedScene
static var _tinted := {}  # "name:rgba" -> material
static var _label_font: FontVariation


func _process(delta: float) -> void:
	_time += delta
	# The island bobs gently, as if floating.
	position.y = sin(_time * 0.6) * 0.03
	# Whose turn it is: that pawn bobs on its tile.
	if _active >= 0 and _active < _tokens.size() and _token_tile[_active] >= 0:
		var tok: Node3D = _tokens[_active]
		tok.position.y = TILE_TOP + absf(sin(_time * 4.0)) * 0.08
	for l: Dictionary in _life:
		var n: Node3D = l.node
		l.t = fposmod(l.t + delta * l.speed, 1.0)
		var a: float = l.t * TAU
		n.position = Vector3(cos(a) * l.lane, l.h + sin(_time * 0.8 + l.lane) * 0.15, sin(a) * l.lane)


func setup(game, player_colors: Array) -> void:
	g = game
	colors = player_colors
	for c in get_children():
		c.queue_free()
	_tiles.clear()
	_tokens.clear()
	_token_tile.clear()
	_targets.clear()
	_life.clear()
	_pot_tag = null
	_active = -1
	_put("island", self, Vector3.ZERO)
	_put("centre", self, Vector3.ZERO)
	for i in Board.TILE_COUNT:
		_build_tile(i)
	for pi in g.players.size():
		var t := _pawn(colors[pi])
		add_child(t)
		_tokens.append(t)
		_token_tile.append(-1)
	_spawn_balloons()
	_levels.resize(Board.TILE_COUNT)
	_owners.resize(Board.TILE_COUNT)
	_levels.fill(-2)  # nothing placed yet, so every tile builds its first look
	_owners.fill(-2)
	sync_all()


func set_active(pi: int) -> void:
	if _active >= 0 and _active < _tokens.size() and _token_tile[_active] >= 0:
		(_tokens[_active] as Node3D).position.y = TILE_TOP
	_active = pi


# ---------------------------------------------------------------- geometry

static func cell_of(i: int) -> Vector2i:
	if i <= 7:
		return Vector2i(7 - i, 7)
	if i <= 14:
		return Vector2i(0, 14 - i)
	if i <= 21:
		return Vector2i(i - 14, 0)
	return Vector2i(7, i - 21)


static func tile_center(i: int) -> Vector3:
	var c := cell_of(i)
	return Vector3((c.x - 3.5) * TILE, TILE_TOP, (c.y - 3.5) * TILE)


## The way a tile's front faces: +X on the side columns, +Z on the rows and corners.
static func front_of(i: int) -> Vector3:
	var c := cell_of(i)
	var column := (c.x == 0 or c.x == 7) and c.y != 0 and c.y != 7
	return Vector3(1, 0, 0) if column else Vector3(0, 0, 1)


static func tile_at(world: Vector3) -> int:
	var col := int(floor(world.x / TILE + 4.0))
	var row := int(floor(world.z / TILE + 4.0))
	if col < 0 or col > 7 or row < 0 or row > 7:
		return -1
	if row == 7:
		return 7 - col
	if col == 0:
		return 14 - row
	if row == 0:
		return 14 + col
	if col == 7:
		return 21 + row
	return -1


## Pieces stand on the front half of their tile, side by side when they share it. On a corner
## they wait in front of the landmark.
func token_slot(i: int, k: int, n: int) -> Vector3:
	var f := front_of(i)
	var across := Vector3(f.z, 0, f.x)
	var spread := (k - (n - 1) / 2.0) * (0.2 if n > 2 else 0.28)
	var front := 0.3 if CORNERS.has(Board.TILES[i].kind) else PIECE_FRONT
	return tile_center(i) + f * front + across * spread


# ---------------------------------------------------------------- kit

## Instances a kit model, recoloured: colors_by_name maps material names (Owner, Stripe, Wall)
## to colours.
func _put(name: String, parent: Node, at: Vector3, colors_by_name := {}, front := Vector3(0, 0, 1)) -> Node3D:
	if not _scenes.has(name):
		_scenes[name] = load(KIT % name)
	var n: Node3D = (_scenes[name] as PackedScene).instantiate()
	n.position = at
	n.rotation.y = atan2(front.x, front.z)
	parent.add_child(n)
	_paint(n, colors_by_name)
	return n


static func _paint(n: Node, colors_by_name: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			if m.resource_name.begins_with("Painted") and not m.vertex_color_use_as_albedo:
				m.vertex_color_use_as_albedo = true
				m.vertex_color_is_srgb = false
			for key: String in colors_by_name:
				if m.resource_name.begins_with(key):
					mi.set_surface_override_material(s, _tint(m, colors_by_name[key]))
	for c in n.get_children():
		_paint(c, colors_by_name)


## One shared material per (material, colour), so a board full of red roofs is one material.
static func _tint(m: BaseMaterial3D, c: Color) -> BaseMaterial3D:
	var key := "%s:%s" % [m.resource_name, c.to_html()]
	if not _tinted.has(key):
		var o := m.duplicate() as BaseMaterial3D
		o.albedo_color = c
		_tinted[key] = o
	return _tinted[key]


func _pawn(color: Color) -> Node3D:
	var holder := Node3D.new()
	var p := _put("pawn", holder, Vector3.ZERO, {"Owner": color})
	p.scale = Vector3.ONE * PAWN_SCALE
	return holder


func _stripe_color(i: int) -> Color:
	var t: Dictionary = Board.TILES[i]
	if t.kind != Board.Kind.PROPERTY:
		return SPECIAL_STRIPE
	return (Board.DISTRICTS[t.district].color as Color).lightened(0.08)


# ---------------------------------------------------------------- construction

func _build_tile(i: int) -> void:
	var t: Dictionary = Board.TILES[i]
	var root := Node3D.new()
	root.position = tile_center(i) - Vector3(0, TILE_TOP, 0)
	add_child(root)
	var f := front_of(i)
	var entry := {"root": root, "front": f, "building": null, "label": null}
	if CORNERS.has(t.kind):
		_put(CORNERS[t.kind], root, Vector3.ZERO).scale = Vector3.ONE * CORNER_SCALE
		if t.kind == Board.Kind.JACKPOT:
			_pot_tag = PriceTag.new()
			_pot_tag.position = Vector3(0, 1.15, 0)
			_pot_tag.scale = Vector3.ONE * 1.3
			root.add_child(_pot_tag)
	else:
		_put("tile", root, Vector3.ZERO, {"Stripe": _stripe_color(i)}, f)
		if SPECIAL_PROPS.has(t.kind):
			_put(SPECIAL_PROPS[t.kind], root, -f * 0.05, {}, f).scale = Vector3.ONE * 1.3
		else:
			entry.label = _stripe_label(root, f)
	_tiles.append(entry)


## The price (or rent) printed flat on a tile's stripe, reading along the tile's front edge.
func _stripe_label(root: Node3D, f: Vector3) -> Label3D:
	if _label_font == null:
		_label_font = FontVariation.new()
		_label_font.base_font = FONT
		_label_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650}
	var l := Label3D.new()
	l.font = _label_font
	l.font_size = 96
	l.pixel_size = 0.0031
	l.outline_size = 0
	l.modulate = INK
	l.position = Vector3(0, TILE_TOP + 0.01, 0) + f * 0.385
	l.rotation = Vector3(deg_to_rad(-90), atan2(f.x, f.z), 0)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(l)
	return l


func _spawn_balloons() -> void:
	for k in 2:
		var path := "res://art/models/balloon_%s.glb" % ["pink", "blue"][k]
		if not ResourceLoader.exists(path):
			continue
		var n: Node3D = Models.instance(path)
		n.scale = Vector3.ONE * 1.6
		add_child(n)
		_life.append({"node": n, "t": k * 0.5, "speed": 0.012, "lane": 6.4 + k * 0.9, "h": 1.6 + k * 0.9})


# ---------------------------------------------------------------- state sync

## Snaps every visual to the current game state without animation.
func sync_all() -> void:
	for i in Board.TILE_COUNT:
		_apply_tile(i, false)
	for pi in g.players.size():
		_token_tile[pi] = g.players[pi].pos
	for i in Board.TILE_COUNT:
		_layout_tokens(i, false)
	refresh_labels()


func refresh_labels() -> void:
	if _pot_tag != null:
		_pot_tag.show_text("$%d" % g.pot, Color("ffc857"))
	for i in Board.TILE_COUNT:
		var l: Label3D = _tiles[i].label
		if l == null:
			continue
		var o: int = g.owner_of[i]
		# For sale: "$price". Owned: the rent a visitor pays (the roof and flag say whose it is).
		l.text = "$%d" % g.price_of(i) if o == -1 else "%d" % g.rent_for(i)


## Updates a tile's building to its owner and level; animates when `animate` is true.
func _apply_tile(i: int, animate: bool) -> void:
	if not g.is_property(i):
		return
	var e: Dictionary = _tiles[i]
	var o: int = g.owner_of[i]
	var want: int = g.level_of[i] if o != -1 else -1
	if want == _levels[i] and o == _owners[i]:
		return
	_levels[i] = want
	_owners[i] = o
	if e.building != null:
		var old: Node3D = e.building
		if animate:
			var tw := create_tween()
			tw.tween_property(old, "scale", Vector3(old.scale.x, 0.01, old.scale.z), 0.18)
			tw.tween_callback(old.queue_free)
		else:
			old.queue_free()
		e.building = null
	var f: Vector3 = e.front
	var at := Vector3(0, TILE_TOP, 0) - f * BUILDING_BACK
	var b: Node3D
	if want < 0:
		b = _put("sale", e.root, at, {}, f)
		b.scale = Vector3.ONE * 1.4
	else:
		var lvl := clampi(want, 0, 5)
		b = _put("b%d" % lvl, e.root, at, {"Owner": colors[o], "Wall": WALLS[(i * 5) % WALLS.size()]}, f)
		b.scale = Vector3.ONE * BUILDING_SCALE
	e.building = b
	if animate:
		var full := b.scale
		b.scale = Vector3(full.x, 0.01, full.z)
		var tw := create_tween()
		tw.tween_interval(0.12)
		tw.tween_property(b, "scale", full, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if want > 0:
			_puff(e.root.position + Vector3(0, 0.4, 0), colors[o])


## Called after an ownership or building event.
func update_tile(i: int) -> void:
	_apply_tile(i, true)
	refresh_labels()


func _layout_tokens(i: int, animate: bool) -> void:
	var here := []
	for pi in _tokens.size():
		if _token_tile[pi] == i:
			here.append(pi)
	for k in here.size():
		var tok: Node3D = _tokens[here[k]]
		var target := token_slot(i, k, here.size())
		var s := 1.0 if here.size() <= 2 else 0.85
		if animate:
			create_tween().tween_property(tok, "position", target, 0.2).set_trans(Tween.TRANS_SINE)
			create_tween().tween_property(tok, "scale", Vector3.ONE * s, 0.2)
		else:
			tok.position = target
			tok.scale = Vector3.ONE * s


# ---------------------------------------------------------------- animation

func token_position(pi: int) -> Vector3:
	return _tokens[pi].position


## Hops a pawn tile by tile (or in one arc for a jump), squashing on each landing. Await it.
func move_token(pi: int, from: int, to: int, jump: bool) -> void:
	var tok: Node3D = _tokens[pi]
	_token_tile[pi] = -1
	_layout_tokens(from, true)
	var path := []
	if jump:
		path.append(to)
	else:
		var i := from
		while i != to:
			i = (i + 1) % Board.TILE_COUNT
			path.append(i)
	for step: int in path:
		var a := tok.position
		var b := token_slot(step, 0, 1)
		var dur := 0.55 if jump else 0.17
		var height := 1.4 if jump else 0.35
		var tw := create_tween()
		tw.tween_method(func(t: float) -> void:
			tok.position = a.lerp(b, t) + Vector3(0, sin(t * PI) * height, 0)
			tok.scale = Vector3(1.0 - 0.08 * sin(t * PI), 1.0 + 0.12 * sin(t * PI), 1.0 - 0.08 * sin(t * PI)),
			0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)
		await tw.finished
		Fx.play("hop")
		tok.scale = Vector3(1.18, 0.78, 1.18)
		create_tween().tween_property(tok, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_token_tile[pi] = to
	_layout_tokens(to, true)


func float_text(at: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = PriceTag.bold_font()
	l.font_size = 72
	l.outline_size = 18
	l.outline_modulate = Color(0.03, 0.04, 0.08, 0.95)
	l.modulate = color
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.position = at + Vector3(0, 0.7, 0)
	add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y + 0.8, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)


func _puff(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = 0.035
	m.height = 0.07
	m.radial_segments = 6
	m.rings = 3
	m.material = Models.mat(color.lightened(0.3), 0.5, 0.0, 2.5)
	p.mesh = m
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- move targets

const TONE_COLORS := {"good": Color("3ddc97"), "bad": Color("ff5d73"), "neutral": Color("ffffff")}


## Highlights the tiles a move can reach, each with a round step badge (the action panel spells
## out what happens there). options: [{tile, tone, steps}]
func show_targets(options: Array) -> void:
	clear_targets()
	for o: Dictionary in options:
		var root := Node3D.new()
		root.position = tile_center(o.tile)
		add_child(root)
		var c: Color = TONE_COLORS[o.tone]
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r, c.g, c.b, 0.5)
		var glow := Models.box(root, Vector3(0.98, 0.03, 0.98), Vector3(0, 0.02, 0), m)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tw := glow.create_tween().set_loops()
		tw.tween_property(m, "albedo_color:a", 0.18, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(m, "albedo_color:a", 0.55, 0.6).set_trans(Tween.TRANS_SINE)
		var disc := Sprite3D.new()
		disc.texture = PriceTag.disc_texture()
		disc.pixel_size = 0.0042
		disc.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		disc.no_depth_test = true
		disc.render_priority = 5
		disc.shaded = false
		disc.modulate = c
		disc.position = Vector3(0, 1.05, 0)
		root.add_child(disc)
		var badge := Label3D.new()
		badge.text = str(o.steps)
		badge.font = PriceTag.bold_font()
		badge.font_size = 110
		badge.outline_size = 0
		badge.pixel_size = 0.0042
		badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		badge.no_depth_test = true
		badge.render_priority = 6
		badge.modulate = INK if o.tone == "neutral" else (Color("063b25") if o.tone == "good" else Color.WHITE)
		badge.position = Vector3(0, 1.07, 0)
		root.add_child(badge)
		root.scale = Vector3(0.6, 0.6, 0.6)
		create_tween().tween_property(root, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_targets.append({"tile": o.tile, "node": root})


func clear_targets() -> void:
	for t: Dictionary in _targets:
		var n: Node3D = t.node
		if is_instance_valid(n):
			n.queue_free()
	_targets.clear()


func set_tags_visible(on: bool) -> void:
	for e: Dictionary in _tiles:
		if e.label != null:
			(e.label as Label3D).visible = on
	if _pot_tag != null:
		_pot_tag.visible = on


## Balloons drift around the lobby's island; in a match they'd cross the tiles.
func set_life_visible(on: bool) -> void:
	for l: Dictionary in _life:
		(l.node as Node3D).visible = on


# ---------------------------------------------------------------- juice

var _coin_mesh: CylinderMesh
var _coin_mat: StandardMaterial3D


## Gold coins arc from one point to another; each landing ticks a little higher in pitch.
func coin_flight(from: Vector3, to: Vector3, count: int) -> void:
	if _coin_mesh == null:
		_coin_mesh = CylinderMesh.new()
		_coin_mesh.top_radius = 0.075
		_coin_mesh.bottom_radius = 0.075
		_coin_mesh.height = 0.022
		_coin_mesh.radial_segments = 16
		_coin_mat = Models.mat(Color("ffcc2e"), 0.3, 0.3, 0.4)
	for k in count:
		var c := MeshInstance3D.new()
		c.mesh = _coin_mesh
		c.material_override = _coin_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		var a := from + Vector3(randf_range(-0.12, 0.12), 0.4, randf_range(-0.12, 0.12))
		var b := to + Vector3(0, 0.45, 0)
		c.position = a
		c.scale = Vector3.ZERO
		var pitch := 1.0 + k * 0.05
		var tw := c.create_tween()
		tw.tween_interval(k * 0.05)
		tw.tween_property(c, "scale", Vector3.ONE, 0.08)
		tw.tween_method(func(t: float) -> void:
			c.position = a.lerp(b, t) + Vector3(0, sin(t * PI) * 1.1, 0)
			c.rotation = Vector3(t * 9.0, t * 5.0, 0.0),
			0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void:
			Fx.play("coin_tick", -8.0, 0.0, pitch)
			c.queue_free())
	await get_tree().create_timer(0.55 + count * 0.05).timeout


## A burst of confetti at a point on the board.
func confetti(at: Vector3, amount := 70) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.6
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 2.6
	p.initial_velocity_max = 3.8
	p.gravity = Vector3(0, -3.5, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.045)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	p.mesh = q
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([Color("ff5d73"), Color("ffc23d"), Color("3ddc97"), Color("5cc8ff"), Color("c77ad9")])
	p.color_initial_ramp = grad
	p.position = at + Vector3(0, 0.5, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## Repaints a player's pawn (equipped cosmetic skin).
func tint_token(pi: int, color: Color) -> void:
	if pi < 0 or pi >= _tokens.size():
		return
	var old: Node3D = _tokens[pi]
	var t := _pawn(color)
	t.position = old.position
	add_child(t)
	old.queue_free()
	_tokens[pi] = t
