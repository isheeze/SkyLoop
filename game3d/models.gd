extends RefCounted
## Small 3D helpers: loading Blender models with baked vertex colours, cached materials, a box.

static var _mats := {}
static var _fixed := {}  # material instance id -> true


## Instantiates a Blender model and makes its materials use the baked vertex colours (the
## export step paints plain colours into vertices so each model draws with one material).
static func instance(path: String) -> Node3D:
	var n: Node3D = (load(path) as PackedScene).instantiate()
	_use_vertex_colors(n)
	return n


static func _use_vertex_colors(n: Node) -> void:
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i) as BaseMaterial3D
				if m != null and not _fixed.has(m.get_instance_id()):
					_fixed[m.get_instance_id()] = true
					# Only the shared "Painted" material carries baked colours (stored linear).
					if m.resource_name.begins_with("Painted"):
						m.vertex_color_use_as_albedo = true
						m.vertex_color_is_srgb = false
	for c in n.get_children():
		_use_vertex_colors(c)


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


static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


## Lays a material over every mesh under n (dice skins).
static func overlay(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_overlay = m
	for c in n.get_children():
		overlay(c, m)
