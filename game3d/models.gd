extends RefCounted
## Procedural low-poly models for the diorama: buildings per level, district landmarks,
## corner props, tokens and scenery. Everything is built from primitive meshes so the look
## can be tuned in code before any hand-made art exists.

const Board = preload("res://core/board.gd")
const BUILDING_SHADER = preload("res://game3d/building.gdshader")

static var _mats := {}


# ---------------------------------------------------------------- materials

static func mat(color: Color, rough := 0.8, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var key := "s%s_%s_%s_%s" % [color.to_html(), rough, metal, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


static func glass(color: Color) -> StandardMaterial3D:
	var key := "g" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.roughness = 0.05
	m.metallic = 0.2
	_mats[key] = m
	return m


static func facade(body: Color, roof: Color, lit := 0.55) -> ShaderMaterial:
	var key := "f%s_%s_%s" % [body.to_html(), roof.to_html(), lit]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = BUILDING_SHADER
	m.set_shader_parameter("body", body)
	m.set_shader_parameter("roof", roof)
	m.set_shader_parameter("lit_ratio", lit)
	_mats[key] = m
	return m


# ---------------------------------------------------------------- primitives

static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3,
		material: Material, segments := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segments
	m.rings = 1
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, r: float, pos: Vector3, material: Material,
		scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi


static func prism(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := PrismMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 24
	m.ring_segments = 8
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- buildings

## Wall tint for a district: its colour washed toward warm white, so streets read as one
## neighbourhood without looking like toys.
static func district_body(d: int) -> Color:
	return Board.DISTRICTS[d].color.lerp(Color("efe6d8"), 0.62)


static func district_roof(d: int) -> Color:
	return Board.DISTRICTS[d].color.darkened(0.35)


## Builds the structure for a property at the given level (0 = empty lot). Uses the Blender
## kit model when one exists (art/models/d<district>_l<level>.glb, already at final size and
## tagged "prescaled"); otherwise falls back to the procedural placeholder.
static func building(d: int, level: int, seed: int) -> Node3D:
	var path := "res://art/models/d%d_l%d_v%d.glb" % [d, level, seed % 3]
	if level == 5:
		path = "res://art/models/d%d_l5.glb" % d
	if level > 0 and ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var inst: Node3D = scene.instantiate()
		inst.set_meta("prescaled", true)
		return inst
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + level
	var body := district_body(d)
	var roofc := district_roof(d)
	var f := facade(body, roofc.darkened(0.2))
	match level:
		0:
			box(root, Vector3(0.5, 0.02, 0.4), Vector3(0, 0.01, 0), mat(Color("3c4a3a")))
			for i in 3:
				var x := -0.15 + i * 0.15
				cyl(root, 0.0, 0.05, 0.14, Vector3(x, 0.09, 0.05), mat(Color("4f8a5b")), 6)
		1:
			box(root, Vector3(0.3, 0.2, 0.28), Vector3(0, 0.1, 0), f)
			var r := prism(root, Vector3(0.34, 0.14, 0.32), Vector3(0, 0.27, 0), mat(roofc))
			r.rotation_degrees.y = 90
			box(root, Vector3(0.05, 0.1, 0.05), Vector3(0.08, 0.3, 0.06), mat(roofc.darkened(0.3)))
		2:
			box(root, Vector3(0.38, 0.4, 0.32), Vector3(0, 0.2, 0), f)
			box(root, Vector3(0.4, 0.03, 0.34), Vector3(0, 0.415, 0), mat(roofc))
			box(root, Vector3(0.18, 0.18, 0.2), Vector3(-0.09, 0.09, 0.2), f)
		3:
			box(root, Vector3(0.42, 0.72, 0.38), Vector3(0, 0.36, 0), f)
			box(root, Vector3(0.44, 0.04, 0.4), Vector3(0, 0.74, 0), mat(roofc))
			box(root, Vector3(0.12, 0.08, 0.1), Vector3(0.08, 0.8, -0.06), mat(Color("9aa3b5")))
		4:
			box(root, Vector3(0.46, 0.6, 0.42), Vector3(0, 0.3, 0), f)
			box(root, Vector3(0.34, 0.62, 0.3), Vector3(0, 0.91, 0), f)
			box(root, Vector3(0.36, 0.04, 0.32), Vector3(0, 1.24, 0), mat(roofc))
			cyl(root, 0.006, 0.012, 0.3, Vector3(0.06, 1.4, 0), mat(Color("c8ccd6")), 6)
			sphere(root, 0.025, Vector3(0.06, 1.56, 0), mat(Color("ff4d5e"), 0.5, 0, 4.0))
		_:
			_landmark(root, d)
	return root


static func _landmark(root: Node3D, d: int) -> void:
	var c: Color = Board.DISTRICTS[d].color
	var white := mat(Color("f2eee8"))
	var gold := mat(Color("e8b94a"), 0.3, 0.8)
	match d:
		0:  # Lighthouse
			box(root, Vector3(0.5, 0.08, 0.5), Vector3(0, 0.04, 0), mat(Color("6b7280")))
			for i in 5:
				var col := white if i % 2 == 0 else mat(Color("e0505a"))
				var r0 := 0.17 - i * 0.012
				cyl(root, r0 - 0.012, r0, 0.22, Vector3(0, 0.19 + i * 0.22, 0), col)
			cyl(root, 0.1, 0.1, 0.14, Vector3(0, 1.26, 0), glass(Color(1, 0.9, 0.6, 0.5)))
			sphere(root, 0.07, Vector3(0, 1.26, 0), mat(Color("ffe08a"), 0.4, 0, 6.0))
			cyl(root, 0.0, 0.12, 0.12, Vector3(0, 1.39, 0), mat(Color("e0505a")))
			var light := OmniLight3D.new()
			light.light_color = Color("ffd27a")
			light.light_energy = 1.6
			light.omni_range = 2.2
			light.position = Vector3(0, 1.26, 0)
			root.add_child(light)
		1:  # Grand Bazaar
			box(root, Vector3(0.6, 0.34, 0.5), Vector3(0, 0.17, 0), facade(district_body(d), c))
			sphere(root, 0.2, Vector3(0, 0.36, 0), gold, Vector3(1, 1.1, 1))
			for x in [-0.27, 0.27]:
				for z in [-0.22, 0.22]:
					cyl(root, 0.025, 0.03, 0.62, Vector3(x, 0.31, z), white, 8)
					cyl(root, 0.0, 0.035, 0.08, Vector3(x, 0.66, z), gold, 8)
		2:  # Conservatory
			box(root, Vector3(0.62, 0.06, 0.56), Vector3(0, 0.03, 0), white)
			for i in 4:
				sphere(root, 0.07 + i * 0.01, Vector3(-0.15 + i * 0.1, 0.14, (i % 2) * 0.1 - 0.05),
					mat(Color("3f9a55")))
			sphere(root, 0.3, Vector3(0, 0.06, 0), glass(Color(0.75, 1.0, 0.85, 0.35)), Vector3(1, 1.15, 0.92))
			cyl(root, 0.01, 0.01, 0.12, Vector3(0, 0.44, 0), white, 6)
		3:  # Transit Hub
			box(root, Vector3(0.66, 0.26, 0.4), Vector3(0, 0.13, 0), facade(district_body(d), c))
			var arch := cyl(root, 0.24, 0.24, 0.62, Vector3(0, 0.26, 0), glass(Color(0.7, 0.85, 1.0, 0.55)), 20)
			arch.rotation_degrees.z = 90
			arch.scale = Vector3(1, 1, 0.8)
			box(root, Vector3(0.1, 0.5, 0.1), Vector3(0.28, 0.25, -0.16), white)
			sphere(root, 0.045, Vector3(0.28, 0.46, -0.1), mat(Color("ffe8b0"), 0.4, 0, 3.0))
		4:  # Arena
			cyl(root, 0.36, 0.32, 0.22, Vector3(0, 0.11, 0), white, 24)
			cyl(root, 0.29, 0.29, 0.02, Vector3(0, 0.215, 0), mat(Color("3c8f4a")), 24)
			torus(root, 0.32, 0.38, Vector3(0, 0.24, 0), mat(c, 0.4, 0, 3.0))
			for i in 4:
				var a := i * PI / 2 + PI / 4
				cyl(root, 0.01, 0.012, 0.42, Vector3(cos(a) * 0.36, 0.33, sin(a) * 0.36), white, 6)
				sphere(root, 0.03, Vector3(cos(a) * 0.36, 0.55, sin(a) * 0.36), mat(Color("fff4d0"), 0.4, 0, 5.0))
		5:  # Bank
			box(root, Vector3(0.6, 0.08, 0.48), Vector3(0, 0.04, 0), white)
			for i in 5:
				cyl(root, 0.03, 0.03, 0.36, Vector3(-0.22 + i * 0.11, 0.26, 0.17), white, 10)
			box(root, Vector3(0.56, 0.4, 0.3), Vector3(0, 0.28, -0.06), facade(Color("eae2d0"), c, 0.8))
			var ped := prism(root, Vector3(0.64, 0.16, 0.48), Vector3(0, 0.56, 0), gold)
			ped.rotation_degrees.y = 0
		6:  # The Spire
			var f := facade(Color("b9c8f0"), c.darkened(0.2), 0.7)
			box(root, Vector3(0.5, 0.3, 0.46), Vector3(0, 0.15, 0), f)
			cyl(root, 0.1, 0.2, 1.4, Vector3(0, 1.0, 0), f, 6)
			cyl(root, 0.0, 0.1, 0.5, Vector3(0, 1.95, 0), glass(Color(0.75, 0.85, 1.0, 0.6)), 6)
			sphere(root, 0.04, Vector3(0, 2.22, 0), mat(Color("9fd0ff"), 0.4, 0, 8.0))


## A small "for sale" sign for unowned lots.
static func for_sale(d: int) -> Node3D:
	var root := Node3D.new()
	cyl(root, 0.012, 0.012, 0.22, Vector3(0, 0.11, 0), mat(Color("d8d2c6")), 6)
	box(root, Vector3(0.2, 0.12, 0.02), Vector3(0, 0.22, 0), mat(Board.DISTRICTS[d].color, 0.6, 0, 0.4))
	return root


# ---------------------------------------------------------------- corners & specials

static func corner_prop(kind: int) -> Node3D:
	var root := Node3D.new()
	var white := mat(Color("f2eee8"))
	var gold := mat(Color("f0c34e"), 0.25, 0.9, 0.3)
	match kind:
		Board.Kind.PAYDAY:
			for i in 4:
				cyl(root, 0.17, 0.17, 0.05, Vector3(-0.1 + (i % 2) * 0.03, 0.03 + i * 0.055, 0), gold, 20)
			for i in 2:
				cyl(root, 0.14, 0.14, 0.05, Vector3(0.22, 0.03 + i * 0.055, 0.15), gold, 20)
		Board.Kind.AUDIT:
			box(root, Vector3(0.5, 0.4, 0.4), Vector3(0, 0.2, 0), facade(Color("c9ccd4"), Color("4a5060"), 0.3))
			for x in [-0.15, 0.15]:
				cyl(root, 0.012, 0.012, 0.6, Vector3(x, 0.3, 0.26), mat(Color("707888")), 6)
			box(root, Vector3(0.36, 0.03, 0.02), Vector3(0, 0.52, 0.26), mat(Color("707888")))
			sphere(root, 0.05, Vector3(0, 0.46, 0), mat(Color("ff3b4e"), 0.4, 0, 6.0))
		Board.Kind.JACKPOT:
			cyl(root, 0.4, 0.42, 0.1, Vector3(0, 0.05, 0), white, 28)
			cyl(root, 0.35, 0.35, 0.02, Vector3(0, 0.1, 0), mat(Color("49b5e6"), 0.1, 0, 1.2), 28)
			cyl(root, 0.05, 0.06, 0.34, Vector3(0, 0.25, 0), white, 10)
			sphere(root, 0.12, Vector3(0, 0.5, 0), mat(Color("ffd35c"), 0.3, 0.6, 3.0))
		Board.Kind.TAX_RAID:
			for x in [-0.28, 0.28]:
				box(root, Vector3(0.08, 0.3, 0.08), Vector3(x, 0.15, 0), white)
			for i in 6:
				var col := mat(Color("e8424f")) if i % 2 == 0 else white
				box(root, Vector3(0.09, 0.06, 0.05), Vector3(-0.225 + i * 0.09, 0.26, 0), col)
			sphere(root, 0.035, Vector3(-0.28, 0.33, 0), mat(Color("ff7a1a"), 0.4, 0, 5.0))
		Board.Kind.METRO:
			var teal := mat(Color("37c2c9"), 0.5, 0.2)
			for x in [-0.28, 0.28]:
				box(root, Vector3(0.07, 0.36, 0.1), Vector3(x, 0.18, 0), teal)
			box(root, Vector3(0.66, 0.1, 0.14), Vector3(0, 0.4, 0), teal)
			box(root, Vector3(0.3, 0.06, 0.12), Vector3(0, 0.48, 0), mat(Color("e9fbff"), 0.5, 0, 2.5))
			for z in [-0.1, 0.1]:
				box(root, Vector3(0.9, 0.015, 0.02), Vector3(0, 0.01, z), mat(Color("8b93a3"), 0.4, 0.8))
		Board.Kind.WINDFALL:
			cyl(root, 0.03, 0.045, 0.3, Vector3(0, 0.15, 0), mat(Color("6b4f3a")), 8)
			sphere(root, 0.2, Vector3(0, 0.42, 0), mat(Color("f5c84b"), 0.4, 0.2, 1.4))
			for i in 5:
				var a := i * TAU / 5.0
				cyl(root, 0.05, 0.05, 0.012, Vector3(cos(a) * 0.3, 0.01, sin(a) * 0.3), gold, 12)
		Board.Kind.PERMIT_OFFICE:
			box(root, Vector3(0.42, 0.24, 0.32), Vector3(0, 0.12, 0), facade(Color("e8e2d6"), Color("3c6fd8"), 0.6))
			var r := prism(root, Vector3(0.46, 0.14, 0.36), Vector3(0, 0.31, 0), mat(Color("3c6fd8")))
			r.rotation_degrees.y = 90
			box(root, Vector3(0.14, 0.02, 0.1), Vector3(0.24, 0.01, 0.24), mat(Color("ff5a6a"), 0.5, 0, 0.6))
	return root


# ---------------------------------------------------------------- tokens & scenery

static func token(color: Color) -> Node3D:
	var root := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.35
	m.roughness = 0.22
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.35
	# Built at 1.6x so tokens read clearly from the playing camera.
	var body := Node3D.new()
	body.scale = Vector3.ONE * 1.6
	root.add_child(body)
	cyl(body, 0.075, 0.085, 0.035, Vector3(0, 0.018, 0), m, 20)
	cyl(body, 0.03, 0.065, 0.15, Vector3(0, 0.11, 0), m, 20)
	sphere(body, 0.055, Vector3(0, 0.215, 0), m)
	var ring := torus(body, 0.08, 0.1, Vector3(0, 0.01, 0), mat(color, 0.4, 0.0, 2.5))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func tree(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var h := rng.randf_range(0.12, 0.2)
	cyl(root, 0.012, 0.018, h, Vector3(0, h / 2, 0), mat(Color("5a4232")), 6)
	var greens := [Color("2f7d4f"), Color("3e8f53"), Color("2a6b52"), Color("4f9a4a")]
	var g: Color = greens[rng.randi_range(0, greens.size() - 1)]
	if rng.randf() < 0.5:
		sphere(root, rng.randf_range(0.08, 0.12), Vector3(0, h + 0.06, 0), mat(g))
	else:
		cyl(root, 0.0, rng.randf_range(0.07, 0.1), rng.randf_range(0.2, 0.28), Vector3(0, h + 0.1, 0), mat(g), 8)
	return root


static func lamp() -> Node3D:
	var root := Node3D.new()
	cyl(root, 0.008, 0.01, 0.22, Vector3(0, 0.11, 0), mat(Color("3a3f4c")), 6)
	sphere(root, 0.025, Vector3(0, 0.23, 0), mat(Color("ffd9a0"), 0.4, 0, 6.0))
	return root


## A small pennant flag on a pole; recolour it with `paint_flag`.
static func flag() -> Node3D:
	var root := Node3D.new()
	cyl(root, 0.008, 0.01, 0.42, Vector3(0, 0.21, 0), mat(Color("f2eee8"), 0.4, 0.6), 6)
	sphere(root, 0.018, Vector3(0, 0.43, 0), mat(Color("f0c34e"), 0.3, 0.8))
	var banner := box(root, Vector3(0.012, 0.13, 0.2), Vector3(0, 0.34, 0.1), mat(Color.WHITE))
	banner.name = "Banner"
	return root


static func paint_flag(f: Node3D, color: Color) -> void:
	(f.get_node("Banner") as MeshInstance3D).material_override = mat(color, 0.6)


## A cluster of soft spheres forming a stylised cloud.
static func cloud(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("fff3ee")
	m.roughness = 1.0
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.8
	m.emission_enabled = true
	m.emission = Color("ffd9c7")
	m.emission_energy_multiplier = 0.25
	for i in rng.randi_range(4, 7):
		var r := rng.randf_range(0.5, 1.0)
		var at := Vector3(rng.randf_range(-1.3, 1.3), rng.randf_range(-0.1, 0.35), rng.randf_range(-0.6, 0.6))
		var s := sphere(root, r, at, m, Vector3(1.0, 0.75, 1.0))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## The Blender pawn, tinted with the player's colour, with a glowing ring under it.
static func token_v2(color: Color) -> Node3D:
	var root := Node3D.new()
	var scene: PackedScene = load("res://art/models/token.glb")
	var pawn: Node3D = scene.instantiate()
	pawn.scale = Vector3.ONE * 0.95
	root.add_child(pawn)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.25
	m.metallic = 0.2
	m.rim_enabled = true
	m.rim = 0.5
	_tint(pawn, m)
	var ring := torus(root, 0.13, 0.16, Vector3(0, 0.005, 0), mat(color.lightened(0.2), 0.4, 0.0, 1.5))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func _tint(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
	for c in n.get_children():
		_tint(c, m)
