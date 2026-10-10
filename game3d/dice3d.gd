extends Node3D
## Throws physical-looking dice onto the island: an arc, two bounces, a tumble that settles
## on the rolled faces. Purely visual; the engine has already decided the values.

const Models = preload("res://game3d/models.gd")
## Local axis of each face, in Godot space (see tools/blender/build_props.py).
const FACE_AXIS := {1: Vector3.UP, 6: Vector3.DOWN, 2: Vector3.BACK, 5: Vector3.FORWARD,
	3: Vector3.RIGHT, 4: Vector3.LEFT}

const SIZE := 2.2

## Tint for an equipped dice skin; white means the standard dice.
var skin := Color.WHITE

var _dice: Array = []


func throw(values: Array, at: Vector3) -> void:
	clear()
	var tweens := []
	for i in values.size():
		var d: Node3D = Models.instance("res://art/models/die.glb")
		add_child(d)
		if skin != Color.WHITE:
			var over := StandardMaterial3D.new()
			over.albedo_color = Color(skin.r, skin.g, skin.b, 0.55)
			over.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			over.roughness = 0.3
			Models.overlay(d, over)
		_dice.append(d)
		var side := (i - (values.size() - 1) / 2.0) * 0.55
		var land := at + Vector3(side, 0.22, randf_range(-0.08, 0.08))
		var start := land + Vector3(randf_range(-1.2, 1.2), 2.6, 2.4)
		var yaw := randf() * TAU
		var final := Basis(Vector3.UP, yaw) * Basis(Quaternion(FACE_AXIS[int(values[i])], Vector3.UP))
		var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var spins := randf_range(2.0, 3.0) * TAU
		d.position = start
		d.basis = (Basis(axis, spins) * final).scaled(Vector3.ONE * SIZE)
		var tw := d.create_tween()  # dies with the die if it is cleared mid-throw
		tw.tween_method(func(t: float) -> void:
			# Ballistic arc with two shrinking bounces, tumbling down onto the final face.
			var p := start.lerp(land, minf(t * 1.25, 1.0))
			var h := 0.0
			if t < 0.8:
				var u := t / 0.8
				h = (1.0 - u) * 2.6 * (1.0 - u) * 0.0 + sin(u * PI) * 0.4 * (1.0 - u) + (1.0 - u) * (1.0 - u) * 2.6
			else:
				h = absf(sin((t - 0.8) / 0.2 * PI)) * 0.08
			d.position = Vector3(p.x, land.y + h, p.z)
			d.basis = (Basis(axis, spins * pow(1.0 - minf(t * 1.1, 1.0), 2.0)) * final).scaled(Vector3.ONE * SIZE),
			0.0, 1.0, 0.9)
		tweens.append(tw)
	for tw: Tween in tweens:
		if tw.is_valid():
			await tw.finished


## Shrinks the dice away.
func clear() -> void:
	for d: Node3D in _dice:
		if is_instance_valid(d):
			var tw := create_tween()
			tw.tween_property(d, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_callback(d.queue_free)
	_dice.clear()
