extends Node3D
## The board, seen from straight above: 28 equal tiles in a 7 x 9 ring shaped like a phone
## screen, a themed centrepiece in the middle, and players as pucks with their faces on top.
## Mirrors game state and animates changes; it never changes the game itself.

const Board = preload("res://core/board.gd")
const Models = preload("res://game3d/models.gd")
const Themes = preload("res://game3d/themes.gd")
const PriceTag = preload("res://game3d/price_tag.gd")
const FONT = preload("res://art/fonts/Outfit.ttf")
const AVATAR_SHADER = preload("res://game3d/avatar_disc.gdshader")

const COLS := 7
const ROWS := 9
const TILE := 1.0
const TILE_SIZE := 0.92  # the raised tile; the rest of the cell is the groove between tiles
const TILE_H := 0.12
const TILE_TOP := TILE_H
const FRAME := 0.16  # board rim around the ring
const TOKEN_Y := 1.5  # pucks hover over the rooftops, so a building never hides a player
const CHIP_Y := 1.2
## The board's footprint in world units, rim included (for camera framing).
const SIZE := Vector2(COLS * TILE + FRAME * 2.0, ROWS * TILE + FRAME * 2.0)
const CORNER_MODELS := {
	Board.Kind.PAYDAY: "payday", Board.Kind.AUDIT: "audit", Board.Kind.JACKPOT: "jackpot",
	Board.Kind.TAX_RAID: "tax_raid", Board.Kind.METRO: "metro", Board.Kind.WINDFALL: "windfall",
	Board.Kind.PERMIT_OFFICE: "permit",
}
const SPECIAL_LABELS := {
	Board.Kind.PAYDAY: "Payday", Board.Kind.AUDIT: "Audit", Board.Kind.TAX_RAID: "Tax raid",
	Board.Kind.METRO: "Metro", Board.Kind.WINDFALL: "Windfall", Board.Kind.PERMIT_OFFICE: "Permits",
}

var g
var colors: Array = []
var theme: Dictionary = Themes.get_theme("city")
var avatars: Array = []  # per seat, avatar id ("a01"...)

var _tiles: Array = []  # per tile: {root, lot, flag, building, tag}
var _tokens: Array = []
var _token_tile: Array = []
var _levels: Array = []
var _owners: Array = []
var _targets: Array = []  # [{tile, node}]
var _time := 0.0
var _active := -1


func _process(delta: float) -> void:
	_time += delta
	# The active player's puck breathes so it's easy to spot.
	for pi in _tokens.size():
		var tok: Node3D = _tokens[pi]
		var face: Node3D = tok.get_node_or_null("Face")
		if face != null:
			face.scale = Vector3.ONE * (1.0 + (0.06 * sin(_time * 5.0) if pi == _active else 0.0))
	_update_life(delta)


func setup(game, player_colors: Array, theme_id := "", seat_avatars: Array = []) -> void:
	g = game
	colors = player_colors
	if theme_id != "":
		theme = Themes.get_theme(theme_id)
	if not seat_avatars.is_empty():
		avatars = seat_avatars
	for c in get_children():
		c.queue_free()
	_tiles.clear()
	_tokens.clear()
	_token_tile.clear()
	_targets.clear()
	_build_static()
	_spawn_life()
	for i in Board.TILE_COUNT:
		_build_tile(i)
	for pi in g.players.size():
		var av: String = avatars[pi] if pi < avatars.size() else "a%02d" % (pi + 1)
		var t := puck(colors[pi], av)
		add_child(t)
		_tokens.append(t)
		_token_tile.append(-1)
	_levels.resize(Board.TILE_COUNT)
	_owners.resize(Board.TILE_COUNT)
	_levels.fill(-2)  # nothing placed yet, so every tile builds its first look
	_owners.fill(-2)
	sync_all()


func set_active(pi: int) -> void:
	_active = pi


# ---------------------------------------------------------------- geometry

## Grid cell of a tile: Payday at the bottom right, play runs clockwise (left along the bottom).
static func cell_of(i: int) -> Vector2i:
	if i <= 6:
		return Vector2i(6 - i, 8)
	if i <= 14:
		return Vector2i(0, 8 - (i - 6))
	if i <= 20:
		return Vector2i(i - 14, 0)
	return Vector2i(6, i - 20)


static func tile_center(i: int) -> Vector3:
	var c := cell_of(i)
	return Vector3((c.x - 3) * TILE, TILE_TOP, (c.y - 4) * TILE)


## Unit vector from the tile toward the middle of the board.
static func inner_dir(i: int) -> Vector3:
	var c := cell_of(i)
	var d := Vector3((3 - c.x) if (c.x == 0 or c.x == 6) else 0, 0, (4 - c.y) if (c.y == 0 or c.y == 8) else 0)
	return d.normalized()


static func tile_at(world: Vector3) -> int:
	var col := int(round(world.x / TILE + 3.0))
	var row := int(round(world.z / TILE + 4.0))
	if col < 0 or col > 6 or row < 0 or row > 8:
		return -1
	for i in Board.TILE_COUNT:
		if cell_of(i) == Vector2i(col, row):
			return i
	return -1


## Where a puck sits on its tile: alone in the middle, or sharing in a 2 x 2 cluster. The chip
## sits on the tile's lower edge, so pucks keep to the upper part.
func token_slot(i: int, k: int, n: int) -> Vector3:
	var c := tile_center(i)
	var at := Vector3(c.x, TOKEN_Y, c.z - 0.08)
	if n <= 1:
		return at
	if n == 2:
		return at + Vector3((k - 0.5) * 0.42, 0, 0)
	return at + Vector3(((k % 2) - 0.5) * 0.42, 0, (int(k / 2) - 0.5) * 0.38)


# ---------------------------------------------------------------- construction

func _build_static() -> void:
	var frame_path := "res://art/themes/%s/frame.glb" % theme.id
	if ResourceLoader.exists(frame_path):
		add_child(Models.instance(frame_path))
	else:
		var w := SIZE.x
		var h := SIZE.y
		Models.box(self, Vector3(w, 0.35, h), Vector3(0, -0.175, 0), Models.mat(theme.frame, 0.85))
		Models.box(self, Vector3(w + 0.06, 0.12, h + 0.06), Vector3(0, -0.36, 0), Models.mat(theme.frame_lip, 0.9))
	# The centre: the theme's painted mat (a top-down illustration), else its 3D centrepiece,
	# else plain theme ground.
	var mat_path := "res://art/themes/%s/centre.jpg" % theme.id
	var piece := "res://art/themes/%s/centre.glb" % theme.id
	if ResourceLoader.exists(mat_path):
		var plane := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2((COLS - 2) * TILE - 0.12, (ROWS - 2) * TILE - 0.12)
		plane.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(mat_path)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		plane.material_override = m
		plane.position.y = 0.02
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(plane)
	elif ResourceLoader.exists(piece):
		add_child(Models.instance(piece))
	else:
		var inner := Vector3((COLS - 2) * TILE - 0.12, 0.06, (ROWS - 2) * TILE - 0.12)
		Models.box(self, inner, Vector3(0, 0.03, 0), Models.mat(theme.centre, 0.95))
	# Under the board: the floating island's rock, seen from the lobby's angled camera.
	var island := "res://art/themes/%s/island_v2.glb" % theme.id
	if ResourceLoader.exists(island):
		add_child(Models.instance(island))


static var _tile_mesh: Mesh


## The rounded tile mesh from Blender (its colour comes from the game), or a plain box.
static func _tile_shape() -> Mesh:
	if _tile_mesh == null:
		if ResourceLoader.exists("res://art/models/tile_v2.glb"):
			var n: Node3D = (load("res://art/models/tile_v2.glb") as PackedScene).instantiate()
			var mi := _first_mesh(n)
			if mi != null:
				_tile_mesh = mi.mesh
			n.free()
		if _tile_mesh == null:
			var b := BoxMesh.new()
			b.size = Vector3(TILE_SIZE, TILE_H, TILE_SIZE)
			_tile_mesh = b
	return _tile_mesh


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


func _build_tile(i: int) -> void:
	var t: Dictionary = Board.TILES[i]
	var root := Node3D.new()
	root.position = tile_center(i) - Vector3(0, TILE_TOP, 0)
	add_child(root)
	var inner := inner_dir(i)
	var entry := {"root": root, "lot": null, "flag": null, "building": null, "tag": null}
	var special: bool = t.kind != Board.Kind.PROPERTY
	var base: Color = theme.special if special else theme.tile
	var lot := MeshInstance3D.new()
	lot.mesh = _tile_shape()
	if lot.mesh is BoxMesh:
		lot.position.y = TILE_H / 2.0
	lot.material_override = Models.mat(base, 0.85)
	root.add_child(lot)
	entry.lot = lot
	var facing := atan2(inner.x, inner.z)
	if not special:
		var flag := Models.flag()
		flag.position = Vector3(0.34, TILE_TOP, -0.34)
		flag.visible = false
		root.add_child(flag)
		entry.flag = flag
	else:
		var path := Themes.model(theme.id, "corner_%s" % CORNER_MODELS[t.kind])
		var prop: Node3D = flat_sprite("res://art/sprites/special_%s.png" % CORNER_MODELS[t.kind], 0.8)
		if prop == null:
			prop = Models.instance(path) if ResourceLoader.exists(path) else Models.corner_prop(t.kind)
		prop.position = Vector3(0, TILE_TOP, -0.06)
		if not prop.has_meta("flat"):
			prop.rotation.y = _facing(i)
			prop.scale = Vector3.ONE * 0.85
		root.add_child(prop)
	var tag := PriceTag.new()
	# The chip sits on the tile's lower edge, above the rooftops, always the same way up.
	tag.position = Vector3(0, CHIP_Y, 0.3)
	root.add_child(tag)
	entry.tag = tag
	if special and t.kind != Board.Kind.JACKPOT:
		tag.show_text(SPECIAL_LABELS[t.kind], Color("1d2340"))
	_tiles.append(entry)


## Which way a tile's model faces: toward the middle, square to the board (corners face up
## or down the screen rather than diagonally).
static func _facing(i: int) -> float:
	var c := cell_of(i)
	if c.y == 8:
		return PI
	if c.y == 0:
		return 0.0
	return PI / 2.0 if c.x == 0 else -PI / 2.0


## A player's piece: a chunky puck in their colour with their portrait on top.
func puck(color: Color, avatar_id: String) -> Node3D:
	var root := Node3D.new()
	var lip := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.24
	cm.height = 0.12
	cm.radial_segments = 32
	cm.rings = 1
	lip.mesh = cm
	lip.material_override = Models.mat(color.darkened(0.25), 0.5)
	lip.position = Vector3(0, -0.06, 0)
	root.add_child(lip)
	var top := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.235
	tm.bottom_radius = 0.25
	tm.height = 0.06
	tm.radial_segments = 32
	tm.rings = 1
	top.mesh = tm
	top.material_override = Models.mat(color, 0.4)
	top.position = Vector3(0, 0.03, 0)
	root.add_child(top)
	var face := MeshInstance3D.new()
	face.name = "Face"
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	q.orientation = PlaneMesh.FACE_Y
	face.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = AVATAR_SHADER
	var tex_path := "res://art/avatars/%s.png" % avatar_id
	if ResourceLoader.exists(tex_path):
		sm.set_shader_parameter("portrait", load(tex_path))
	sm.set_shader_parameter("ring_color", Color.WHITE)
	face.material_override = sm
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.position = Vector3(0, 0.065, 0)
	root.add_child(face)
	return root


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
	for i in Board.TILE_COUNT:
		var tag = _tiles[i].tag
		if tag == null:
			continue
		var kind: int = Board.TILES[i].kind
		if kind == Board.Kind.JACKPOT:
			tag.show_text("$%d" % g.pot, Color("ffc857"))
			continue
		if kind != Board.Kind.PROPERTY:
			continue
		var o: int = g.owner_of[i]
		if o == -1:
			tag.show_text("$%d" % g.price_of(i), Color.WHITE)
		else:
			tag.show_text("%d" % g.rent_for(i), colors[o])


## Updates ownership and building on a tile; animates when `animate` is true.
func _apply_tile(i: int, animate: bool) -> void:
	if not g.is_property(i):
		return
	var e: Dictionary = _tiles[i]
	var o: int = g.owner_of[i]
	var lvl: int = g.level_of[i]
	var d: int = Board.TILES[i].district
	if o != _owners[i]:
		_owners[i] = o
		var lot: MeshInstance3D = e.lot
		var flag: Node3D = e.flag
		flag.visible = o != -1
		if o == -1:
			lot.material_override = Models.mat(theme.tile, 0.85)
		else:
			var c: Color = colors[o]
			lot.material_override = Models.mat(c.lerp(Color.WHITE, 0.12), 0.75)
			Models.paint_flag(flag, c)
			if animate:
				lot.scale = Vector3(0.6, 1, 0.6)
				create_tween().tween_property(lot, "scale", Vector3.ONE, 0.4) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				flag.scale = Vector3(1, 0.01, 1)
				create_tween().tween_property(flag, "scale", Vector3.ONE, 0.45).set_delay(0.15) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var want := lvl if o != -1 else -1
	if want != _levels[i]:
		_levels[i] = want
		if e.building != null:
			var old: Node3D = e.building
			if animate:
				var tw := create_tween()
				tw.tween_property(old, "scale", Vector3(1, 0.01, 1), 0.18)
				tw.tween_callback(old.queue_free)
			else:
				old.queue_free()
			e.building = null
		var inner := inner_dir(i)
		var variant: int = (i * 7 + d) % 4  # neighbours rarely repeat a look
		var b: Node3D = _building(d, want, variant)
		b.position = Vector3(0, TILE_TOP, -0.06)
		b.rotation.y = 0.0 if b.has_meta("flat") else _facing(i)
		var full := Vector3.ONE * (1.0 if b.has_meta("prescaled") else 1.0)
		b.scale = full
		e.root.add_child(b)
		e.building = b
		if animate:
			b.scale = Vector3.ONE * 0.25 if b.has_meta("flat") else Vector3(full.x, 0.01, full.z)
			var tw := create_tween()
			tw.tween_interval(0.12)
			tw.tween_property(b, "scale", full, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if want > 0:
				_puff(e.root.position + Vector3(0, 0.3, 0), Board.DISTRICTS[d].color)


## A painted sprite lying flat on a tile (the camera looks straight down), or null.
static func flat_sprite(path: String, size := 0.86) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var holder := Node3D.new()
	var sp := Sprite3D.new()
	sp.texture = load(path)
	sp.axis = Vector3.AXIS_Y
	sp.pixel_size = size / float(sp.texture.get_width())
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.render_priority = 1
	sp.position.y = 0.012
	holder.add_child(sp)
	holder.set_meta("prescaled", true)
	holder.set_meta("flat", true)
	return holder


func _building(d: int, level: int, variant: int) -> Node3D:
	# Painted art first: s_l<level>_v<k>.png per theme, a for-sale sign on empty lots.
	if level >= 1:
		var art := flat_sprite("res://art/themes/%s/s_l%d_v%d.png" % [theme.id, level, variant % 4])
		if art != null:
			return art
	elif level < 0:
		var sign := flat_sprite("res://art/sprites/special_for_sale.png", 0.62)
		if sign != null:
			return sign
	if level == 0:
		# Bought but not built: the owner's colour and flag say it all.
		return Node3D.new()
	if level < 0:
		# For sale: an empty lot in the theme's style.
		var lot := "res://art/themes/%s/lot.glb" % theme.id
		if ResourceLoader.exists(lot):
			var n: Node3D = Models.instance(lot)
			n.set_meta("prescaled", true)
			return n
		return Models.for_sale(d) if level < 0 else Models.building(d, 0, variant)
	if level >= 1:
		var name := "b_l%d_v%d" % [level, variant % 3]
		var path := "res://art/themes/%s/%s.glb" % [theme.id, name]
		if ResourceLoader.exists(path):
			var n: Node3D = Models.instance(path)
			n.set_meta("prescaled", true)
			return n
	return Models.building(d, level, variant)


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
		var s := 1.0 if here.size() <= 2 else 0.82
		if animate:
			create_tween().tween_property(tok, "position", target, 0.2).set_trans(Tween.TRANS_SINE)
			create_tween().tween_property(tok, "scale", Vector3.ONE * s, 0.2)
		else:
			tok.position = target
			tok.scale = Vector3.ONE * s


# ---------------------------------------------------------------- animation

func token_position(pi: int) -> Vector3:
	return _tokens[pi].position


## Hops a puck tile by tile (or in one arc for a jump). Seen from above, a hop is a swell and
## a squash, with the shadow shrinking beneath it. Await it.
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
		var dur := 0.6 if jump else 0.19
		var lift := 0.55 if jump else 0.22
		var tw := create_tween()
		tw.tween_method(func(t: float) -> void:
			var s := sin(t * PI)
			tok.position = a.lerp(b, t) + Vector3(0, s * 1.2, 0)
			tok.scale = Vector3.ONE * (1.0 + lift * s),
			0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)
		await tw.finished
		Fx.play("hop")
		tok.scale = Vector3(1.12, 0.8, 1.12)
		create_tween().tween_property(tok, "scale", Vector3.ONE, 0.12)
	_token_tile[pi] = to
	_layout_tokens(to, true)


func float_text(at: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = FONT
	l.font_size = 72
	l.outline_size = 18
	l.outline_modulate = Color(0.03, 0.04, 0.08, 0.95)
	l.modulate = color
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.position = Vector3(at.x, 2.4, at.z)
	add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:z", l.position.z - 0.8, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)


func _puff(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
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


## Highlights the tiles a move can reach, each with a badge saying what happens there.
## options: [{tile, text, tone, steps}]
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
		m.no_depth_test = true
		m.render_priority = 3
		var glow := Models.box(root, Vector3(TILE_SIZE + 0.06, 0.02, TILE_SIZE + 0.06), Vector3(0, 0.02, 0), m)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tw := glow.create_tween().set_loops()
		tw.tween_property(m, "albedo_color:a", 0.18, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(m, "albedo_color:a", 0.55, 0.6).set_trans(Tween.TRANS_SINE)
		# A round step badge over the tile; the action panel spells out what happens there.
		var badge := Label3D.new()
		badge.text = str(o.steps)
		badge.font = PriceTag.bold_font()
		badge.font_size = 96
		badge.outline_size = 0
		badge.pixel_size = 0.0034
		badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		badge.no_depth_test = true
		badge.render_priority = 6
		badge.modulate = Color("1d2340") if o.tone == "neutral" else (Color("063b25") if o.tone == "good" else Color.WHITE)
		badge.position = Vector3(0, CHIP_Y + 0.42, 0.0)
		root.add_child(badge)
		var disc := Sprite3D.new()
		disc.texture = PriceTag.disc_texture()
		disc.pixel_size = 0.0034
		disc.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		disc.no_depth_test = true
		disc.render_priority = 5
		disc.shaded = false
		disc.modulate = c
		disc.position = Vector3(0, CHIP_Y + 0.4, 0.0)
		root.add_child(disc)
		root.scale = Vector3(0.6, 1, 0.6)
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
		if e.tag != null:
			e.tag.visible = on


# ---------------------------------------------------------------- juice

var _coin_mesh: CylinderMesh
var _coin_mat: StandardMaterial3D
var _life: Array = []  # [{node, kind, t, speed, lane, h}]


## Gold coins arc from one point to another; each landing ticks a little higher in pitch.
func coin_flight(from: Vector3, to: Vector3, count: int) -> void:
	if _coin_mesh == null:
		_coin_mesh = CylinderMesh.new()
		_coin_mesh.top_radius = 0.08
		_coin_mesh.bottom_radius = 0.08
		_coin_mesh.height = 0.022
		_coin_mesh.radial_segments = 16
		_coin_mat = Models.mat(Color("f2c14e"), 0.3, 0.7, 0.4)
	for k in count:
		var c := MeshInstance3D.new()
		c.mesh = _coin_mesh
		c.material_override = _coin_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		var a := Vector3(from.x, TOKEN_Y, from.z) + Vector3(randf_range(-0.15, 0.15), 0, randf_range(-0.15, 0.15))
		var b := Vector3(to.x, TOKEN_Y + 0.2, to.z)
		c.position = a
		c.scale = Vector3.ZERO
		var pitch := 1.0 + k * 0.05
		var tw := c.create_tween()
		tw.tween_interval(k * 0.05)
		tw.tween_property(c, "scale", Vector3.ONE, 0.08)
		tw.tween_method(func(t: float) -> void:
			c.position = a.lerp(b, t) + Vector3(0, sin(t * PI) * 1.4, 0)
			c.scale = Vector3.ONE * (1.0 + 0.6 * sin(t * PI))
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
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -4.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.05)
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
	p.position = at + Vector3(0, 1.0, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## Ambient life: balloons drifting over the board (each theme can add its own later).
func _spawn_life() -> void:
	_life.clear()
	var balloons := ["balloon_pink", "balloon_blue"]
	for k in balloons.size():
		var path := "res://art/models/%s.glb" % balloons[k]
		if not ResourceLoader.exists(path):
			continue
		var n: Node3D = Models.instance(path)
		n.scale = Vector3.ONE * 1.6
		add_child(n)
		_life.append({"node": n, "kind": "balloon", "t": k * 0.5, "speed": 0.01, "lane": 5.6 + k * 0.8,
			"dir": 1.0, "h": 3.0 + k * 0.6})


func _update_life(delta: float) -> void:
	for l: Dictionary in _life:
		var n: Node3D = l.node
		if not is_instance_valid(n):
			continue
		l.t = fposmod(l.t + delta * l.speed * l.dir, 1.0)
		var a: float = l.t * TAU
		n.position = Vector3(cos(a) * l.lane, l.h + sin(_time * 0.8 + l.lane) * 0.15, sin(a) * l.lane * 1.25)


## Repaints a player's puck (equipped cosmetic skin).
func tint_token(pi: int, color: Color) -> void:
	if pi < 0 or pi >= _tokens.size():
		return
	var old: Node3D = _tokens[pi]
	var av: String = avatars[pi] if pi < avatars.size() else "a%02d" % (pi + 1)
	var t := puck(color, av)
	t.position = old.position
	t.scale = old.scale
	add_child(t)
	old.queue_free()
	_tokens[pi] = t
