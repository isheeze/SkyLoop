extends Node3D
## The 3D diorama board. Mirrors game state visually and animates changes; it never changes
## the game itself.

const Board = preload("res://core/board.gd")
const Models = preload("res://game3d/models.gd")

const TILE := 1.0
const TILE_TOP := 0.12
const BUILDING_SCALE := 1.3
const FONT = preload("res://art/fonts/Outfit.ttf")
const CLOUDS = preload("res://game3d/clouds.gdshader")
const PriceTag = preload("res://game3d/price_tag.gd")

var g
var colors: Array = []

var _tiles: Array = []  # per tile: {root, outline: Array[MeshInstance3D], building, sign, label}
var _tokens: Array = []
var _token_tile: Array = []
var _levels: Array = []
var _owners: Array = []
var _puffs: Array = []
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	for k in _puffs.size():
		var p: Node3D = _puffs[k]
		p.position.y += sin(_time * 0.4 + k) * delta * 0.05
		p.rotate_y(delta * 0.01 * (1 if k % 2 == 0 else -1))


func setup(game, player_colors: Array) -> void:
	g = game
	colors = player_colors
	for c in get_children():
		c.queue_free()
	_tiles.clear()
	_tokens.clear()
	_token_tile.clear()
	_puffs.clear()
	_build_static()
	for i in Board.TILE_COUNT:
		_build_tile(i)
	for pi in g.players.size():
		var t := Models.token(colors[pi])
		add_child(t)
		_tokens.append(t)
		_token_tile.append(-1)
	_levels.resize(Board.TILE_COUNT)
	_owners.resize(Board.TILE_COUNT)
	_levels.fill(-1)
	_owners.fill(-2)
	sync_all()


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


## Unit vector from the tile toward the middle of the board (zero for corners).
static func inner_dir(i: int) -> Vector3:
	var c := cell_of(i)
	var corner := (c.x == 0 or c.x == 7) and (c.y == 0 or c.y == 7)
	if corner:
		return Vector3.ZERO
	if c.y == 7:
		return Vector3(0, 0, -1)
	if c.y == 0:
		return Vector3(0, 0, 1)
	if c.x == 0:
		return Vector3(1, 0, 0)
	return Vector3(-1, 0, 0)


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


func token_slot(i: int, k: int, n: int) -> Vector3:
	var c := tile_center(i)
	var inner := inner_dir(i)
	if inner == Vector3.ZERO:
		# Corners have a prop in the middle, so tokens line up along the front edge.
		return c + Vector3((k - (n - 1) / 2.0) * 0.21, 0, 0.32)
	var perp := Vector3(inner.z, 0, -inner.x)
	return c + inner * 0.3 + perp * ((k - (n - 1) / 2.0) * 0.21)


# ---------------------------------------------------------------- construction

func _build_static() -> void:
	# Sea of clouds far below, and a few puffy clouds drifting near the island.
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	sea.mesh = plane
	var sm := ShaderMaterial.new()
	sm.shader = CLOUDS
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.008
	fn.fractal_octaves = 5
	tex.noise = fn
	sm.set_shader_parameter("noise_tex", tex)
	sea.material_override = sm
	sea.position = Vector3(0, -6.0, 0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 9:
		var a := i * TAU / 9.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(7.5, 10.5)
		var puff := Models.cloud(rng)
		puff.position = Vector3(cos(a) * r, rng.randf_range(-3.2, -1.4), sin(a) * r)
		add_child(puff)
		_puffs.append(puff)
	# The floating island: stone slab over an inverted rocky base.
	Models.box(self, Vector3(8.5, 0.5, 8.5), Vector3(0, -0.25, 0), Models.mat(Color("e9dcc8"), 0.85))
	Models.box(self, Vector3(8.56, 0.06, 8.56), Vector3(0, -0.03, 0), Models.mat(Color("7cc36f"), 0.9))
	var rock := Models.cyl(self, 6.0, 1.2, 3.2, Vector3(0, -2.1, 0), Models.mat(Color("8d6f5c"), 0.95), 4)
	rock.rotation_degrees.y = 45
	var rock2 := Models.cyl(self, 1.2, 0.0, 1.4, Vector3(0, -4.4, 0), Models.mat(Color("6f5546"), 0.95), 4)
	rock2.rotation_degrees.y = 45
	# Central park and the ring road.
	Models.box(self, Vector3(6.1, 0.03, 6.1), Vector3(0, 0.015, 0), Models.mat(Color("5d6475"), 0.9))
	Models.box(self, Vector3(5.7, 0.06, 5.7), Vector3(0, 0.03, 0), Models.mat(Color("67b05a"), 0.95))
	var water := Models.mat(Color("57b8de"), 0.15, 0.0, 0.0)
	for p: Array in [[Vector3(0.6, 0.065, 0.4), 0.7], [Vector3(-0.15, 0.065, -0.05), 0.5], [Vector3(-0.75, 0.065, 0.6), 0.35]]:
		Models.cyl(self, p[1] + 0.05, p[1] + 0.05, 0.012, p[0] - Vector3(0, 0.002, 0), Models.mat(Color("f1e6d2")), 28)
		Models.cyl(self, p[1], p[1], 0.014, p[0], water, 28)
	rng.seed = 42
	var placed := 0
	while placed < 46:
		var pos := Vector3(rng.randf_range(-2.65, 2.65), 0.06, rng.randf_range(-2.65, 2.65))
		if Vector2(pos.x - 0.6, pos.z - 0.4).length() < 0.8 or Vector2(pos.x + 0.15, pos.z + 0.05).length() < 0.6 \
				or Vector2(pos.x + 0.75, pos.z - 0.6).length() < 0.45:
			continue
		var t := Models.tree(rng)
		t.position = pos
		add_child(t)
		placed += 1
	for i in 16:
		var a := i * TAU / 16.0
		var l := Models.lamp()
		l.position = Vector3(cos(a) * 2.1 + 0.2, 0.06, sin(a) * 1.9 + 0.1)
		add_child(l)


func _build_tile(i: int) -> void:
	var t: Dictionary = Board.TILES[i]
	var root := Node3D.new()
	root.position = tile_center(i)
	add_child(root)
	var inner := inner_dir(i)
	var corner := inner == Vector3.ZERO
	var slab := Color("ece2d2") if not corner else Color("ddcdb5")
	Models.box(root, Vector3(0.95, TILE_TOP, 0.95), Vector3(0, -TILE_TOP / 2, 0), Models.mat(slab, 0.85))
	var entry := {"root": root, "plate": null, "flag": null, "building": null, "tag": null}
	var facing := atan2(inner.x, inner.z)
	if t.kind == Board.Kind.PROPERTY:
		var strip := Models.box(root, Vector3(0.95, 0.03, 0.16), Vector3(0, 0.005, 0),
			Models.mat(Board.DISTRICTS[t.district].color, 0.6))
		strip.position = inner * 0.395 + Vector3(0, 0.006, 0)
		strip.rotation.y = facing
		# Owner plate and flag, hidden until someone owns the tile.
		var plate := Models.box(root, Vector3(0.95, 0.012, 0.79), -inner * 0.08 + Vector3(0, 0.002, 0),
			Models.mat(Color.WHITE))
		plate.rotation.y = facing
		plate.visible = false
		entry.plate = plate
		var perp := Vector3(inner.z, 0, -inner.x)
		var flag := Models.flag()
		flag.position = -inner * 0.36 + perp * 0.36
		flag.rotation.y = facing
		flag.visible = false
		root.add_child(flag)
		entry.flag = flag
	else:
		var prop := Models.corner_prop(t.kind)
		prop.rotation.y = facing if not corner else 0.0
		prop.position = -inner * 0.1
		root.add_child(prop)
	if t.kind == Board.Kind.PROPERTY or t.kind == Board.Kind.JACKPOT:
		var tag := PriceTag.new()
		tag.position = Vector3(0, 0.34, 0.36)
		root.add_child(tag)
		entry.tag = tag
	_tiles.append(entry)


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
		if Board.TILES[i].kind == Board.Kind.JACKPOT:
			tag.show_text("$%d" % g.pot, Color("ffc857"))
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
		var plate: MeshInstance3D = e.plate
		var flag: Node3D = e.flag
		plate.visible = o != -1
		flag.visible = o != -1
		if o != -1:
			var c: Color = colors[o]
			plate.material_override = Models.mat(c, 0.7)
			Models.paint_flag(flag, c)
			if animate:
				plate.scale = Vector3(0.1, 1, 0.1)
				create_tween().tween_property(plate, "scale", Vector3.ONE, 0.35) \
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
		var b: Node3D = Models.for_sale(d) if want == -1 else Models.building(d, want, i)
		b.position = -inner * 0.13
		b.rotation.y = atan2(inner.x, inner.z)
		b.scale = Vector3.ONE * BUILDING_SCALE
		e.root.add_child(b)
		e.building = b
		if animate:
			b.scale = Vector3(BUILDING_SCALE, 0.01, BUILDING_SCALE)
			var tw := create_tween()
			tw.tween_interval(0.12)
			tw.tween_property(b, "scale", Vector3.ONE * BUILDING_SCALE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if want > 0:
				_puff(e.root.position + Vector3(0, 0.1, 0), Board.DISTRICTS[d].color)


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
		if animate:
			create_tween().tween_property(tok, "position", target, 0.2).set_trans(Tween.TRANS_SINE)
		else:
			tok.position = target


# ---------------------------------------------------------------- animation

func token_position(pi: int) -> Vector3:
	return _tokens[pi].position


## Hops a token tile by tile (or in one arc for a jump). Await it.
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
		var height := 1.2 if jump else 0.28
		var tw := create_tween()
		tw.tween_method(func(t: float) -> void:
			tok.position = a.lerp(b, t) + Vector3(0, sin(t * PI) * height, 0)
			tok.scale = Vector3(1.0 + 0.15 * sin(t * PI), 1.0 - 0.1 * sin(t * PI), 1.0 + 0.15 * sin(t * PI)),
			0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)
		await tw.finished
		Fx.play("hop")
		tok.scale = Vector3(1.15, 0.8, 1.15)
		create_tween().tween_property(tok, "scale", Vector3.ONE, 0.12)
	_token_tile[pi] = to
	_layout_tokens(to, true)


func float_text(at: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = FONT
	l.font_size = 64
	l.outline_size = 16
	l.outline_modulate = Color(0.03, 0.04, 0.08, 0.95)
	l.modulate = color
	l.pixel_size = 0.003
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.position = at + Vector3(0, 0.45, 0)
	add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y + 0.7, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)


func _puff(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.3
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var m := SphereMesh.new()
	m.radius = 0.025
	m.height = 0.05
	m.radial_segments = 6
	m.rings = 3
	m.material = Models.mat(color.lightened(0.3), 0.5, 0.0, 2.5)
	p.mesh = m
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
