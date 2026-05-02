extends Node3D

@export var entrance_point_path: NodePath = ^"WorkerGrillEntrancePoint"
@export var snap_point_path: NodePath = ^"WorkerGrillSnapPoint"
@export var exit_point_path: NodePath = ^"WorkerGrillExitPoint"
@export var meat_place_point_path: NodePath = ^"GrillMeatPlacePoint"
@export var meat_pickup_point_path: NodePath = ^"GrillMeatPickupPoint"
@export var smoke_origin_path: NodePath = ^"GrillSmokeOrigin"
@export var batch_size := 4
@export var cook_seconds := 6.0
@export var grilled_meat_scale := Vector3(0.001, 0.001, 0.001)
@export var grilled_meat_spacing := Vector2(0.08, 0.08)

const MEAT_SCENE := preload("res://scenes/props/food/meat.tscn")

var _grill_meat_props: Array[Node3D] = []
var _smoke_particles: Array[GPUParticles3D] = []
var _is_busy := false
var _reserved_worker: Node = null

func _ready() -> void:
	_prepare_grill_visuals()

func is_available() -> bool:
	return not _is_busy

func reserve_for(worker: Node) -> bool:
	if _is_busy and _reserved_worker != worker:
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
	return get_node_or_null(entrance_point_path) as Node3D

func get_snap_point() -> Node3D:
	return get_node_or_null(snap_point_path) as Node3D

func get_exit_point() -> Node3D:
	var exit_point := get_node_or_null(exit_point_path) as Node3D
	if exit_point != null:
		return exit_point
	return get_entrance_point()

func get_meat_place_point() -> Node3D:
	return get_node_or_null(meat_place_point_path) as Node3D

func get_meat_pickup_point() -> Node3D:
	return get_node_or_null(meat_pickup_point_path) as Node3D

func get_look_target() -> Vector3:
	var place_point := get_meat_place_point()
	if place_point != null:
		return place_point.global_position
	return global_position

func cook_meat(worker: Node, raw_meat_pickup_position: Vector3, reach_controller: Node = null) -> int:
	if worker == null:
		return 0
	if _is_busy and _reserved_worker != worker:
		return 0
	_is_busy = true
	_reserved_worker = worker
	if reach_controller == null:
		reach_controller = _get_reach_controller(worker)
	if reach_controller == null:
		push_warning("Grill station cannot cook meat: selected worker has no right-hand IK reach controller.")
		release_reservation(worker)
		return 0

	var entrance_point := get_entrance_point()
	var snap_point := get_snap_point()
	var place_point := get_meat_place_point()
	var pickup_point := get_meat_pickup_point()
	if entrance_point == null or snap_point == null or place_point == null or pickup_point == null:
		push_warning("Grill station cannot cook meat: grill markers are incomplete.")
		release_reservation(worker)
		return 0

	if not await _navigate_worker_to(worker, entrance_point.global_position, get_look_target()):
		release_reservation(worker)
		return 0

	if worker.has_method("snap_to_station"):
		worker.call("snap_to_station", snap_point, get_exit_point())

	if reach_controller.has_method("pick_and_place"):
		await reach_controller.call("pick_and_place", raw_meat_pickup_position, place_point.global_position)
	else:
		await reach_controller.call("reach_to", raw_meat_pickup_position)
		await reach_controller.call("reach_to", place_point.global_position)

	_set_grill_meat_visible(true)
	_set_smoke_emitting(true)
	await get_tree().create_timer(cook_seconds).timeout
	_set_smoke_emitting(false)

	await reach_controller.call("reach_to", pickup_point.global_position)
	_set_grill_meat_visible(false)
	release_reservation(worker)
	return batch_size

func _navigate_worker_to(worker: Node, target_position: Vector3, look_target: Vector3) -> bool:
	var navigation_map := get_world_3d().navigation_map
	var closest_point := NavigationServer3D.map_get_closest_point(navigation_map, target_position)
	if worker.has_method("set_navigation_target_with_look_target"):
		worker.call("set_navigation_target_with_look_target", closest_point, look_target)
	elif worker.has_method("set_navigation_target"):
		worker.call("set_navigation_target", closest_point)
	else:
		push_warning("Grill station cannot move worker: worker has no navigation target API.")
		return false

	await worker.arrived_at_target
	return true

func _prepare_grill_visuals() -> void:
	var place_point := get_meat_place_point()
	if place_point != null:
		_create_grill_meat_props(place_point)

	var smoke_origin := get_node_or_null(smoke_origin_path) as Node3D
	if smoke_origin != null:
		_create_smoke_particles(smoke_origin)

func _set_grill_meat_visible(value: bool) -> void:
	for prop in _grill_meat_props:
		if prop != null and is_instance_valid(prop):
			prop.visible = value

func _create_grill_meat_props(parent: Node3D) -> void:
	_grill_meat_props.clear()
	var offsets := _get_batch_offsets()
	var names := ["TopLeft", "TopRight", "BottomLeft", "BottomRight"]
	var prop_count: int = mini(batch_size, offsets.size())
	for index in range(prop_count):
		var prop := MEAT_SCENE.instantiate() as Node3D
		if prop == null:
			continue
		prop.name = "GrillMeat_%s" % names[index]
		parent.add_child(prop)
		prop.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(grilled_meat_scale), offsets[index])
		prop.visible = false
		_grill_meat_props.append(prop)

func _create_smoke_particles(parent: Node3D) -> void:
	_smoke_particles.clear()
	var offsets := _get_batch_offsets()
	var names := ["TopLeft", "TopRight", "BottomLeft", "BottomRight"]
	var particle_count: int = mini(batch_size, offsets.size())
	for index in range(particle_count):
		var particles := GPUParticles3D.new()
		particles.name = "GrillSmoke_%s" % names[index]
		particles.amount = 12
		particles.lifetime = 1.4
		particles.one_shot = false
		particles.emitting = false
		particles.position = offsets[index]
		particles.draw_pass_1 = _make_smoke_mesh()
		particles.process_material = _make_smoke_material()
		parent.add_child(particles)
		_smoke_particles.append(particles)

func _set_smoke_emitting(value: bool) -> void:
	for particles in _smoke_particles:
		if particles != null and is_instance_valid(particles):
			particles.emitting = value

func _get_batch_offsets() -> Array[Vector3]:
	return [
		Vector3(-grilled_meat_spacing.x, 0.0, -grilled_meat_spacing.y),
		Vector3(grilled_meat_spacing.x, 0.0, -grilled_meat_spacing.y),
		Vector3(-grilled_meat_spacing.x, 0.0, grilled_meat_spacing.y),
		Vector3(grilled_meat_spacing.x, 0.0, grilled_meat_spacing.y),
	]

func _make_smoke_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.78, 0.72, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	return mesh

func _make_smoke_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.08
	material.direction = Vector3.UP
	material.spread = 18.0
	material.gravity = Vector3(0.0, 0.35, 0.0)
	material.initial_velocity_min = 0.16
	material.initial_velocity_max = 0.34
	material.scale_min = 0.45
	material.scale_max = 1.15
	return material

func _get_reach_controller(worker: Node) -> Node:
	var configured := worker.get_node_or_null(^"WorkerReachController")
	if configured != null:
		return configured
	return worker.find_child("WorkerReachController", true, false)
