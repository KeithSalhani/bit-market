extends Node3D

const VFX := preload("res://src/world/restaurant_vfx_factory.gd")
const MEAT_SCENE := preload("res://scenes/props/food/meat.tscn")

@export var entrance_point_path: NodePath = ^"WorkerGrillEntrancePoint"
@export var snap_point_path: NodePath = ^"WorkerGrillSnapPoint"
@export var exit_point_path: NodePath = ^"WorkerGrillExitPoint"
@export var meat_place_point_path: NodePath = ^"GrillMeatPlacePoint"
@export var meat_pickup_point_path: NodePath = ^"GrillMeatPickupPoint"
@export var smoke_origin_path: NodePath = ^"GrillSmokeOrigin"
@export var grill_sound_path: NodePath
@export var batch_size := 4
@export var cook_seconds := 6.0
@export var grilled_meat_scale := Vector3(0.001, 0.001, 0.001)
@export var grilled_meat_spacing := Vector2(0.08, 0.08)
@export var station_vfx_enabled := true
@export_range(0.25, 2.0, 0.05) var particle_quality_scale := 1.0
@export var heat_shimmer_enabled := true

var _grill_meat_props: Array[Node3D] = []
var _smoke_particles: Array[GPUParticles3D] = []
var _ember_particles: Array[GPUParticles3D] = []
var _heat_shimmer: MeshInstance3D
var _cook_light: OmniLight3D
var _meat_top_fill_light: OmniLight3D
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

func cook_meat(worker: Node, raw_meat_pickup_position: Vector3, reach_controller: Node = null, duration_multiplier: float = 1.0) -> int:
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

	_spawn_place_burst(place_point.global_position)
	_set_grill_meat_visible(true)
	_set_smoke_emitting(true)
	_set_station_vfx_active(true)
	_set_grill_sound_playing(true)
	await get_tree().create_timer(cook_seconds * maxf(duration_multiplier, 0.05)).timeout
	_set_grill_sound_playing(false)
	_set_smoke_emitting(false)
	_set_station_vfx_active(false)

	await reach_controller.call("reach_to", pickup_point.global_position)
	_set_grill_meat_visible(false)
	_spawn_place_burst(pickup_point.global_position, Color(1.0, 0.82, 0.38, 0.72))
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
		_create_station_vfx(smoke_origin)

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
		var particles := VFX.create_continuous_particles(
			parent,
			"GrillSmoke_%s" % names[index],
			offsets[index],
			Color(0.78, 0.78, 0.72, 0.42),
			int(14.0 * particle_quality_scale),
			1.45,
			Vector3(0.05, 0.035, 0.05),
			0.14,
			0.34,
			0.5,
			1.2,
			Vector3(0.0, 0.35, 0.0),
			false,
			0.035
		)
		if particles != null:
			_smoke_particles.append(particles)

func _set_smoke_emitting(value: bool) -> void:
	VFX.set_particles_emitting(_smoke_particles, value)

func _create_station_vfx(parent: Node3D) -> void:
	if not station_vfx_enabled:
		return

	var embers := VFX.create_continuous_particles(
		parent,
		"GrillEmbers",
		Vector3.ZERO,
		Color(1.0, 0.28, 0.08, 0.74),
		int(16.0 * particle_quality_scale),
		0.55,
		Vector3(0.26, 0.025, 0.18),
		0.1,
		0.3,
		0.2,
		0.62,
		Vector3(0.0, 0.18, 0.0),
		true,
		0.012
	)
	if embers != null:
		_ember_particles.append(embers)

	if heat_shimmer_enabled:
		_heat_shimmer = VFX.create_heat_shimmer(parent, "GrillHeatShimmer", Vector3(0.0, 0.22, 0.0), Vector2(0.8, 0.62))
	_cook_light = VFX.create_flicker_light(parent, "GrillCookLight", Vector3(0.0, 0.24, 0.0), Color(1.0, 0.42, 0.12, 1.0), 0.0, 1.6)
	_meat_top_fill_light = VFX.create_flicker_light(parent, "GrillMeatTopFill", Vector3(0.0, 0.48, 0.0), Color(1.0, 0.72, 0.42, 1.0), 0.0, 0.85)

func _set_station_vfx_active(value: bool) -> void:
	if not station_vfx_enabled:
		return
	VFX.set_particles_emitting(_ember_particles, value)
	VFX.set_node_visible(_heat_shimmer, value and heat_shimmer_enabled)
	if _cook_light != null:
		_cook_light.light_energy = 0.55 if value else 0.0
	if _meat_top_fill_light != null:
		_meat_top_fill_light.light_energy = 0.38 if value else 0.0

func _spawn_place_burst(global_position: Vector3, color: Color = Color(1.0, 0.42, 0.14, 0.8)) -> void:
	if not station_vfx_enabled:
		return
	VFX.spawn_burst(self, global_position + Vector3.UP * 0.05, color, int(18.0 * particle_quality_scale), 0.4, 0.04, 0.35, 0.85, 0.18, 0.56, true, 0.014)
	if _cook_light != null:
		VFX.pulse_light(_cook_light, 1.1, 0.35)

func _set_grill_sound_playing(value: bool) -> void:
	var grill_sound := _get_grill_sound()
	if grill_sound == null:
		return
	if value:
		if grill_sound.has_method("play") and not bool(grill_sound.get("playing")):
			grill_sound.call("play")
	elif grill_sound.has_method("stop"):
		grill_sound.call("stop")

func _get_grill_sound() -> Node:
	if not grill_sound_path.is_empty():
		var configured := get_node_or_null(grill_sound_path)
		if configured != null:
			return configured

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return null
	var direct := scene_root.get_node_or_null(^"grill-sound")
	if direct != null:
		return direct
	var names := ["grill-sound", "GrillSound", "grill_sound"]
	for sound_name in names:
		var found := scene_root.find_child(sound_name, true, false)
		if found != null:
			return found
	return null

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
