extends Node

@export var cook_seconds := 6.0
@export var basket_lower_offset := 0.18
@export var fries_scene: PackedScene = preload("res://scenes/props/food/fries.tscn")
@export var bagged_fries_scene: PackedScene = preload("res://scenes/props/food/fires_bagged.tscn")
@export var oil_particles_enabled := true
@export var oil_color := Color(1.0, 0.78, 0.08, 0.42)
@export var raw_fries_scale := Vector3(0.35, 0.35, 0.35)
@export var bagged_fries_scale := Vector3(0.45, 0.45, 0.45)
@export var bagged_fries_output_count := 1

var _is_busy := false
var _reserved_worker: Node
var _oil: Node3D
var _stand_point: Node3D
var _entrance_point: Node3D
var _baskets: Array[Node3D] = []
var _handle_positions: Array[Node3D] = []
var _fries_positions: Array[Node3D] = []
var _basket_start_positions: Array[Vector3] = []
var _raw_fries_props: Array[Node3D] = []
var _oil_particles: Array[GPUParticles3D] = []

func _ready() -> void:
	_resolve_station_nodes()
	_prepare_visuals()

func is_available() -> bool:
	return not _is_busy

func reserve_for(worker: Node) -> bool:
	if _is_busy:
		return false
	_is_busy = true
	_reserved_worker = worker
	return true

func release_reservation(worker: Node = null) -> void:
	if worker != null and _reserved_worker != null and _reserved_worker != worker:
		return
	_is_busy = false
	_reserved_worker = null

func get_entrance_point() -> Node3D:
	return _entrance_point

func get_stand_point() -> Node3D:
	return _stand_point

func get_snap_point() -> Node3D:
	return _stand_point

func get_look_target() -> Vector3:
	if _handle_positions.size() > 0 and _handle_positions[0] != null:
		return _handle_positions[0].global_position
	if _oil != null:
		return _oil.global_position
	if get_parent() is Node3D:
		return (get_parent() as Node3D).global_position
	return Vector3.ZERO

func fry_fries(worker: Node, reach_controller: Node = null) -> Array[Node3D]:
	var outputs: Array[Node3D] = []
	if _is_busy and _reserved_worker != worker:
		return outputs
	if _baskets.is_empty() or _handle_positions.is_empty() or _fries_positions.is_empty():
		push_warning("%s cannot fry fries: fryer basket markers are incomplete." % name)
		release_reservation(worker)
		return outputs

	if reach_controller == null:
		reach_controller = _get_reach_controller(worker)
	if reach_controller == null or not reach_controller.has_method("reach_to"):
		push_warning("%s cannot fry fries: selected worker has no right-hand IK reach controller." % name)
		release_reservation(worker)
		return outputs

	_is_busy = true
	_reserved_worker = null
	_set_oil_visible(true)
	_spawn_raw_fries()
	_set_particles_emitting(oil_particles_enabled)

	for index in range(_baskets.size()):
		await reach_controller.call("reach_to", _handle_positions[index].global_position)
		await _move_basket(index, _basket_start_positions[index] + Vector3.DOWN * basket_lower_offset)

	await get_tree().create_timer(cook_seconds).timeout

	for index in range(_baskets.size()):
		await reach_controller.call("reach_to", _handle_positions[index].global_position)
		await _move_basket(index, _basket_start_positions[index])

	_set_particles_emitting(false)
	_clear_raw_fries()
	_set_oil_visible(false)
	outputs = _create_bagged_fries_outputs()
	_is_busy = false
	return outputs

func _resolve_station_nodes() -> void:
	_oil = _find_named_descendant(self, "oil") as Node3D
	_stand_point = _find_named_descendant(self, "workerstandpoint") as Node3D
	_entrance_point = _find_named_descendant(self, "workerenterancepoint") as Node3D
	if _entrance_point == null:
		_entrance_point = _stand_point

	_baskets.clear()
	_handle_positions.clear()
	_fries_positions.clear()
	_basket_start_positions.clear()
	for child in get_children():
		if not (child is Node3D):
			continue
		var child_node := child as Node3D
		var handle := child_node.get_node_or_null(^"HandlePosition") as Node3D
		var fries_position := child_node.get_node_or_null(^"FriesPosition") as Node3D
		if handle == null or fries_position == null:
			continue
		_baskets.append(child_node)
		_handle_positions.append(handle)
		_fries_positions.append(fries_position)
		_basket_start_positions.append(child_node.position)

func _prepare_visuals() -> void:
	_apply_oil_material()
	_set_oil_visible(false)
	_create_oil_particles()
	_set_particles_emitting(false)

func _set_oil_visible(value: bool) -> void:
	if _oil != null:
		_oil.visible = value

func _apply_oil_material() -> void:
	if _oil == null:
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = oil_color
	material.emission_enabled = true
	material.emission = Color(oil_color.r, oil_color.g, oil_color.b, 1.0)
	material.emission_energy_multiplier = 0.35
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.roughness = 0.18
	_apply_material_to_meshes(_oil, material)

func _apply_material_to_meshes(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_material_to_meshes(child, material)

func _spawn_raw_fries() -> void:
	_clear_raw_fries()
	for fries_position in _fries_positions:
		if fries_position == null or fries_scene == null:
			continue
		var fries := fries_scene.instantiate() as Node3D
		if fries == null:
			continue
		fries.name = "RawFries"
		fries_position.add_child(fries)
		fries.transform = Transform3D(Basis.IDENTITY.scaled(raw_fries_scale), Vector3.ZERO)
		fries.visible = true
		_raw_fries_props.append(fries)

func _clear_raw_fries() -> void:
	for prop in _raw_fries_props:
		if prop != null and is_instance_valid(prop):
			prop.queue_free()
	_raw_fries_props.clear()

func _create_bagged_fries_outputs() -> Array[Node3D]:
	var outputs: Array[Node3D] = []
	var output_count := mini(bagged_fries_output_count, _fries_positions.size())
	for index in range(output_count):
		if bagged_fries_scene == null:
			continue
		var fries := bagged_fries_scene.instantiate() as Node3D
		if fries == null:
			continue
		fries.name = "BaggedFries_%d" % (index + 1)
		add_child(fries)
		fries.global_position = _fries_positions[index].global_position
		fries.global_rotation = Vector3.ZERO
		fries.scale *= bagged_fries_scale
		fries.visible = false
		outputs.append(fries)
	return outputs

func _move_basket(index: int, target_position: Vector3) -> void:
	if index < 0 or index >= _baskets.size():
		return
	var basket := _baskets[index]
	if basket == null or not is_instance_valid(basket):
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(basket, "position", target_position, 0.35)
	await tween.finished

func _create_oil_particles() -> void:
	_oil_particles.clear()
	if _oil == null:
		return
	var particles := GPUParticles3D.new()
	particles.name = "OilBubbles"
	particles.amount = 18
	particles.lifetime = 0.7
	particles.one_shot = false
	particles.emitting = false
	particles.draw_pass_1 = _make_bubble_mesh()
	particles.process_material = _make_bubble_material()
	_oil.add_child(particles)
	_oil_particles.append(particles)

func _set_particles_emitting(value: bool) -> void:
	for particles in _oil_particles:
		if particles != null and is_instance_valid(particles):
			particles.emitting = value

func _make_bubble_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.78, 0.28, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	return mesh

func _make_bubble_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(0.32, 0.02, 0.18)
	material.direction = Vector3.UP
	material.spread = 8.0
	material.gravity = Vector3(0.0, 0.05, 0.0)
	material.initial_velocity_min = 0.04
	material.initial_velocity_max = 0.16
	material.scale_min = 0.25
	material.scale_max = 0.7
	return material

func _find_named_descendant(node: Node, normalized_name: String) -> Node:
	if String(node.name).to_lower() == normalized_name:
		return node
	for child in node.get_children():
		var found := _find_named_descendant(child, normalized_name)
		if found != null:
			return found
	return null

func _get_reach_controller(worker: Node) -> Node:
	if worker == null:
		return null
	var configured := worker.get_node_or_null(^"WorkerReachController")
	if configured != null:
		return configured
	return worker.find_child("WorkerReachController", true, false)
