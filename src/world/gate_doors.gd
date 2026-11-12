class_name GateDoors
extends Node3D
## The two timber leaves of a city gate and the bar that holds them shut.

signal opened

var is_open: bool = false
var barred: bool = false
var width: float = 4.0
var height: float = 4.5
var _leaves: Array[AnimatableBody3D] = []
var _bar: Node3D
var _bar_body: StaticBody3D


## Builds doors for a gate record from [member TroyWorld.info].
func setup(rec: Dictionary, start_open: bool, start_barred: bool) -> void:
	width = rec["width"]
	height = (rec["height"] as float) - 0.08
	var n: Vector3 = rec["normal"]
	var z := n.normalized()
	var x := Vector3(z.z, 0.0, -z.x)
	transform = Transform3D(Basis(x, Vector3.UP, z), (rec["pos"] as Vector3) + z * (rec["door_offset"] as float))
	var mats := Mats.all_local()
	var leaf_w := width * 0.5 - 0.02
	for side: float in [-1.0, 1.0]:
		var gb := GeoBuilder.new()
		gb.chunk_size = 0.0
		# Leaf geometry runs from the hinge toward the middle of the gateway.
		var cx := -side * leaf_w * 0.5
		gb.box(&"wood_door", Transform3D(Basis.IDENTITY, Vector3(cx, height * 0.5, 0)), Vector3(leaf_w, height, 0.16), Color.WHITE, false, 0)
		# Bronze-shod: bands across, and studs.
		for y: float in [0.35, height * 0.5, height - 0.35]:
			gb.box(&"bronze_dull", Transform3D(Basis.IDENTITY, Vector3(cx, y, 0)), Vector3(leaf_w - 0.06, 0.14, 0.2), Color.WHITE, false, 0)
			for i in 5:
				var sx := cx + lerpf(-leaf_w * 0.42, leaf_w * 0.42, i / 4.0)
				gb.box(&"bronze", Transform3D(Basis.IDENTITY, Vector3(sx, y, 0.0)), Vector3(0.07, 0.07, 0.26), Color.WHITE, false, 0)
		# Pivot post.
		gb.cylinder(&"wood_dark", Vector3(0, 0, 0), 0.09, 0.09, height, 8)
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(side * width * 0.5, 0.0, 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = gb.build_mesh(mats)
		body.add_child(mi)
		var shape := BoxShape3D.new()
		shape.size = Vector3(leaf_w, height, 0.3)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(cx, height * 0.5, 0)
		body.add_child(cs)
		add_child(body)
		_leaves.append(body)
	# The bar rests in brackets on the town side.
	_bar = Node3D.new()
	_bar.position = Vector3(0.0, 1.35, -0.26)
	var bgb := GeoBuilder.new()
	bgb.chunk_size = 0.0
	bgb.box(&"wood_dark", Transform3D.IDENTITY, Vector3(width + 0.9, 0.24, 0.22), Color.WHITE, false, 0)
	for sx: float in [-1.0, 1.0]:
		bgb.box(&"bronze_dull", Transform3D(Basis.IDENTITY, Vector3(sx * (width * 0.5 - 0.5), 0, 0)), Vector3(0.12, 0.3, 0.28), Color.WHITE, false, 0)
	var bmi := MeshInstance3D.new()
	bmi.mesh = bgb.build_mesh(mats)
	_bar.add_child(bmi)
	add_child(_bar)
	barred = start_barred
	_bar.visible = barred
	is_open = start_open
	_apply(1.0 if is_open else 0.0)


func _apply(k: float) -> void:
	# Leaves swing into the town (local -Z).
	_leaves[0].rotation.y = -deg_to_rad(104.0) * k
	_leaves[1].rotation.y = deg_to_rad(104.0) * k


## World position of the middle of the bar (for interaction prompts).
func bar_position() -> Vector3:
	return _bar.global_position


## Lifts the bar out of its brackets.
func lift_bar() -> void:
	if not barred:
		return
	barred = false
	Sfx.play_at(&"bar", global_position)
	var tw := create_tween()
	tw.tween_property(_bar, "position:y", 2.1, 0.9).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_bar, "position", Vector3(width * 0.5 + 1.6, 0.14, -1.0), 0.8)
	tw.parallel().tween_property(_bar, "rotation:y", 1.2, 0.8)


## Swings the gate open over [param seconds].
func open(seconds: float = 3.5) -> void:
	if is_open or barred:
		return
	is_open = true
	Sfx.play_at(&"gate", global_position)
	var tw := create_tween()
	tw.tween_method(_apply, 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: opened.emit())


## Swings the gate shut.
func close(seconds: float = 3.0) -> void:
	if not is_open:
		return
	is_open = false
	Sfx.play_at(&"gate", global_position)
	var tw := create_tween()
	tw.tween_method(_apply, 1.0, 0.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
