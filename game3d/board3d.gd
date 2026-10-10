extends Node3D
## The 3D diorama board. Mirrors game state visually and animates changes; it never changes
## the game itself.

const Board = preload("res://core/board.gd")
const Models = preload("res://game3d/models.gd")

const TILE := 1.0
const TILE_TOP := 0.05  # top of a lot
const ROAD_Y := 0.02
const BUILDING_SCALE := 1.3  # only for procedural fallback models
const FONT = preload("res://art/fonts/Outfit.ttf")
const PriceTag = preload("res://game3d/price_tag.gd")
const LOT_COLOR := Color("efe6d6")
const CORNER_MODELS := {
	Board.Kind.PAYDAY: "payday", Board.Kind.AUDIT: "audit", Board.Kind.JACKPOT: "jackpot",
	Board.Kind.TAX_RAID: "tax_raid", Board.Kind.METRO: "metro", Board.Kind.WINDFALL: "windfall",
	Board.Kind.PERMIT_OFFICE: "permit",
}

var g
var colors: Array = []

var _tiles: Array = []  # per tile: {root, lot, flag, building, tag}
var _tokens: Array = []
var _token_tile: Array = []
var _levels: Array = []
var _owners: Array = []
var _targets: Array = []  # [{tile, node}]
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	# The island bobs gently, as if floating.
	position.y = sin(_time * 0.6) * 0.03
	_update_life(delta)


func setup(game, player_colors: Array) -> void:
	g = game
	colors = player_colors
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
		var t := Models.token_v2(colors[pi])
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


## Tokens drive on the ring road in front of their tile.
func token_slot(i: int, k: int, n: int) -> Vector3:
	var c := tile_center(i)
	var inner := inner_dir(i)
	var spread := (k - (n - 1) / 2.0) * 0.2
	if inner == Vector3.ZERO:
		var diag := -Vector3(c.x, 0, c.z).normalized()
		var at := c + diag * 1.1
		return Vector3(at.x, ROAD_Y, at.z) + Vector3(diag.z, 0, -diag.x) * spread
	var perp := Vector3(inner.z, 0, -inner.x)
	var at := c + inner * 0.78 + perp * spread
	return Vector3(at.x, ROAD_Y, at.z)


# ---------------------------------------------------------------- construction

func _build_static() -> void:
	for name in ["island", "board"]:
		add_child(Models.instance("res://art/models/%s.glb" % name))


func _build_tile(i: int) -> void:
	var t: Dictionary = Board.TILES[i]
	var root := Node3D.new()
	root.position = tile_center(i) - Vector3(0, TILE_TOP, 0)
	add_child(root)
	var inner := inner_dir(i)
	var corner := inner == Vector3.ZERO
	var entry := {"root": root, "lot": null, "flag": null, "building": null, "tag": null}
	var lot: Node3D = Models.instance("res://art/models/lot.glb")
	root.add_child(lot)
	entry.lot = _first_mesh(lot)
	entry.lot.material_override = Models.mat(LOT_COLOR if not corner else Color("f4ead6"), 0.9)
	var facing := atan2(inner.x, inner.z)
	if t.kind == Board.Kind.PROPERTY:
		var perp := Vector3(inner.z, 0, -inner.x)
		var flag := Models.flag()
		flag.position = -inner * 0.36 + perp * 0.36 + Vector3(0, TILE_TOP, 0)
		flag.rotation.y = facing
		flag.visible = false
		root.add_child(flag)
		entry.flag = flag
	else:
		var path := "res://art/models/corner_%s.glb" % CORNER_MODELS[t.kind]
		var prop: Node3D = Models.instance(path) if ResourceLoader.exists(path) \
			else Models.corner_prop(t.kind)
		prop.position = Vector3(0, TILE_TOP, 0) - inner * 0.05
		prop.rotation.y = facing if not corner else atan2(-tile_center(i).x, -tile_center(i).z)
		root.add_child(prop)
	if t.kind == Board.Kind.PROPERTY or t.kind == Board.Kind.JACKPOT:
		var tag := PriceTag.new()
		# Always on the camera-facing edge of the lot, so buildings never hide it.
		tag.position = Vector3(0, TILE_TOP + 0.14, 0.4)
		root.add_child(tag)
		entry.tag = tag
	_tiles.append(entry)


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


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
		var lot: MeshInstance3D = e.lot
		var flag: Node3D = e.flag
		flag.visible = o != -1
		if o == -1:
			lot.material_override = Models.mat(LOT_COLOR, 0.9)
		else:
			var c: Color = colors[o]
			lot.material_override = Models.mat(c.lerp(Color.WHITE, 0.15), 0.8)
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
		var variant: int = Board.district_tiles(d).find(i)
		var b: Node3D = Models.for_sale(d) if want == -1 else Models.building(d, want, variant)
		b.position = -inner * 0.06 + Vector3(0, TILE_TOP, 0)
		b.rotation.y = atan2(inner.x, inner.z)
		var full := Vector3.ONE * (1.0 if b.has_meta("prescaled") else BUILDING_SCALE)
		b.scale = full
		e.root.add_child(b)
		e.building = b
		if animate:
			b.scale = Vector3(full.x, 0.01, full.z)
			var tw := create_tween()
			tw.tween_interval(0.12)
			tw.tween_property(b, "scale", full, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
		m.albedo_color = Color(c.r, c.g, c.b, 0.45)
		var glow := Models.box(root, Vector3(0.97, 0.02, 0.97), Vector3(0, 0.03, 0), m)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tw := glow.create_tween().set_loops()
		tw.tween_property(m, "albedo_color:a", 0.15, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(m, "albedo_color:a", 0.5, 0.6).set_trans(Tween.TRANS_SINE)
		var tag := PriceTag.new()
		tag.position = Vector3(0, 0.75, 0.1)
		tag.scale = Vector3.ONE * 1.35
		root.add_child(tag)
		tag.show_text("%d · %s" % [o.steps, o.text], c if o.tone != "neutral" else Color.WHITE)
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
		if e.tag != null:
			e.tag.visible = on


# ---------------------------------------------------------------- juice

var _coin_mesh: CylinderMesh
var _coin_mat: StandardMaterial3D
var _life: Array = []  # [{node, kind, t, speed, lane|radius, h}]


## Gold coins arc from one point to another; each landing ticks a little higher in pitch.
func coin_flight(from: Vector3, to: Vector3, count: int) -> void:
	if _coin_mesh == null:
		_coin_mesh = CylinderMesh.new()
		_coin_mesh.top_radius = 0.055
		_coin_mesh.bottom_radius = 0.055
		_coin_mesh.height = 0.016
		_coin_mesh.radial_segments = 16
		_coin_mat = Models.mat(Color("f2c14e"), 0.3, 0.7, 0.4)
	for k in count:
		var c := MeshInstance3D.new()
		c.mesh = _coin_mesh
		c.material_override = _coin_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		var a := from + Vector3(randf_range(-0.12, 0.12), 0.3, randf_range(-0.12, 0.12))
		var b := to + Vector3(0, 0.35, 0)
		c.position = a
		c.scale = Vector3.ZERO
		var pitch := 1.0 + k * 0.05
		var tw := c.create_tween()
		tw.tween_interval(k * 0.05)
		tw.tween_property(c, "scale", Vector3.ONE, 0.08)
		tw.tween_method(func(t: float) -> void:
			c.position = a.lerp(b, t) + Vector3(0, sin(t * PI) * 0.9, 0)
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
	p.initial_velocity_min = 2.2
	p.initial_velocity_max = 3.4
	p.gravity = Vector3(0, -3.5, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.035)
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
	p.position = at + Vector3(0, 0.3, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


func _spawn_life() -> void:
	_life.clear()
	var cars := ["car_red", "car_blue", "car_yellow"]
	for k in cars.size():
		var path := "res://art/models/%s.glb" % cars[k]
		if not ResourceLoader.exists(path):
			continue
		var n: Node3D = Models.instance(path)
		add_child(n)
		_life.append({"node": n, "kind": "car", "t": k / 3.0, "speed": 0.018 + k * 0.004,
			"lane": 2.55 if k % 2 == 0 else 2.88, "dir": 1.0 if k % 2 == 0 else -1.0})
	var balloons := ["balloon_pink", "balloon_blue"]
	for k in balloons.size():
		var path := "res://art/models/%s.glb" % balloons[k]
		if not ResourceLoader.exists(path):
			continue
		var n: Node3D = Models.instance(path)
		n.scale = Vector3.ONE * 1.4
		add_child(n)
		_life.append({"node": n, "kind": "balloon", "t": k * 0.5, "speed": 0.012, "lane": 6.6 + k * 0.9,
			"dir": 1.0, "h": 1.2 + k * 0.9})


static func _ring_point(t: float, r: float) -> Vector3:
	var a := t * TAU
	var c := cos(a)
	var s := sin(a)
	var k := pow(pow(absf(c), 8.0) + pow(absf(s), 8.0), -1.0 / 8.0) * r
	return Vector3(c * k, 0, s * k)


func _update_life(delta: float) -> void:
	for l: Dictionary in _life:
		var n: Node3D = l.node
		if not is_instance_valid(n):
			continue
		l.t = fposmod(l.t + delta * l.speed * l.dir, 1.0)
		if l.kind == "car":
			var p := _ring_point(l.t, l.lane)
			var ahead := _ring_point(l.t + 0.002 * l.dir, l.lane)
			n.position = Vector3(p.x, ROAD_Y, p.z)
			if ahead.distance_to(p) > 0.0001:
				n.look_at(Vector3(ahead.x, ROAD_Y, ahead.z), Vector3.UP)
				n.rotate_object_local(Vector3.UP, PI / 2)
		else:
			var a: float = l.t * TAU
			n.position = Vector3(cos(a) * l.lane, l.h + sin(_time * 0.8 + l.lane) * 0.15, sin(a) * l.lane)


## Repaints a player's pawn (equipped cosmetic skin).
func tint_token(pi: int, color: Color) -> void:
	if pi < 0 or pi >= _tokens.size():
		return
	var old: Node3D = _tokens[pi]
	var t := Models.token_v2(color)
	t.position = old.position
	add_child(t)
	old.queue_free()
	_tokens[pi] = t
