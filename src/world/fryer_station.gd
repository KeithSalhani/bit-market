extends Node

const VFX := preload("res://src/world/restaurant_vfx_factory.gd")

@export var cook_seconds := 6.0
@export var basket_lower_offset := 0.18
@export var fries_scene: PackedScene = preload("res://scenes/props/food/fries.tscn")
@export var bagged_fries_scene: PackedScene = preload("res://scenes/props/food/fires_bagged.tscn")
@export var fryer_sound_path: NodePath
@export var oil_particles_enabled := true
@export var oil_color := Color(1.0, 0.78, 0.08, 0.42)
@export var raw_fries_scale := Vector3(0.35, 0.35, 0.35)
@export var bagged_fries_scale := Vector3(0.45, 0.45, 0.45)
@export var bagged_fries_output_count := 1
@export var station_vfx_enabled := true
@export_range(0.25, 2.0, 0.05) var particle_quality_scale := 1.0
@export var heat_shimmer_enabled := true

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
var _steam_particles: Array[GPUParticles3D] = []
var _spark_particles: Array[GPUParticles3D] = []
var _heat_shimmer: MeshInstance3D
var _cook_light: OmniLight3D

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

func fry_fries(worker: Node, reach_controller: Node = null, duration_multiplier: float = 1.0) -> Array[Node3D]:
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

	for index in range(_baskets.size()):
		await reach_controller.call("reach_to", _handle_positions[index].global_position)
		await _move_basket(index, _basket_start_positions[index] + Vector3.DOWN * basket_lower_offset)
		_spawn_oil_burst(_fries_positions[index].global_position)

	_set_particles_emitting(oil_particles_enabled)
	_set_station_vfx_active(true)
	_set_fryer_sound_playing(true)
	await get_tree().create_timer(cook_seconds * maxf(duration_multiplier, 0.05)).timeout
	_set_fryer_sound_playing(false)
	_set_particles_emitting(false)
	_set_station_vfx_active(false)

	for index in range(_baskets.size()):
		await reach_controller.call("reach_to", _handle_positions[index].global_position)
		await _move_basket(index, _basket_start_positions[index])
		_spawn_oil_burst(_fries_positions[index].global_position, Color(1.0, 0.72, 0.18, 0.72))

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
	_create_station_vfx()
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
	particles.amount = 42
	particles.lifetime = 0.85
	particles.one_shot = false
	particles.emitting = false
	particles.draw_pass_1 = _make_bubble_mesh()
	particles.process_material = _make_bubble_material()
	_oil.add_child(particles)
	_oil_particles.append(particles)

	var sizzle := GPUParticles3D.new()
	sizzle.name = "OilSizzle"
	sizzle.amount = 30
	sizzle.lifetime = 0.45
	sizzle.one_shot = false
	sizzle.emitting = false
	sizzle.draw_pass_1 = _make_sizzle_mesh()
	sizzle.process_material = _make_sizzle_material()
	_oil.add_child(sizzle)
	_oil_particles.append(sizzle)

func _set_particles_emitting(value: bool) -> void:
	VFX.set_particles_emitting(_oil_particles, value)

func _create_station_vfx() -> void:
	if not station_vfx_enabled or _oil == null:
		return

	var steam := VFX.create_continuous_particles(
		_oil,
		"FryerSteamWisps",
		Vector3.ZERO,
		Color(0.86, 0.86, 0.78, 0.34),
		int(42.0 * particle_quality_scale),
		1.25,
		Vector3(0.34, 0.025, 0.2),
		0.12,
		0.36,
		0.35,
		1.1,
		Vector3(0.0, 0.42, 0.0),
		false,
		0.026
	)
	if steam != null:
		_steam_particles.append(steam)

	var sparks := VFX.create_continuous_particles(
		_oil,
		"FryerHotFlecks",
		Vector3.ZERO,
		Color(1.0, 0.72, 0.18, 0.68),
		int(14.0 * particle_quality_scale),
		0.35,
		Vector3(0.32, 0.02, 0.18),
		0.08,
		0.26,
		0.2,
		0.5,
		Vector3(0.0, 0.12, 0.0),
		true,
		0.01
	)
	if sparks != null:
		_spark_particles.append(sparks)

	if heat_shimmer_enabled:
		_heat_shimmer = VFX.create_heat_shimmer(_oil, "FryerHeatShimmer", Vector3(0.0, 0.16, 0.0), Vector2(0.75, 0.48))
	_cook_light = VFX.create_flicker_light(_oil, "FryerCookLight", Vector3(0.0, 0.16, 0.0), Color(1.0, 0.62, 0.16, 1.0), 0.0, 1.35)

func _set_station_vfx_active(value: bool) -> void:
	if not station_vfx_enabled:
		return
	VFX.set_particles_emitting(_steam_particles, value)
	VFX.set_particles_emitting(_spark_particles, value)
	VFX.set_node_visible(_heat_shimmer, value and heat_shimmer_enabled)
	if _cook_light != null:
		_cook_light.light_energy = 0.42 if value else 0.0

func _spawn_oil_burst(global_position: Vector3, color: Color = Color(1.0, 0.88, 0.26, 0.72)) -> void:
	if not station_vfx_enabled or _oil == null:
		return
	VFX.spawn_burst(_oil, global_position + Vector3.UP * 0.04, color, int(20.0 * particle_quality_scale), 0.36, 0.06, 0.28, 0.95, 0.16, 0.55, true, 0.012)
	if _cook_light != null:
		VFX.pulse_light(_cook_light, 0.9, 0.3)

func _set_fryer_sound_playing(value: bool) -> void:
	var fryer_sound := _get_fryer_sound()
	if fryer_sound == null:
		return
	if value:
		if fryer_sound.has_method("play") and not bool(fryer_sound.get("playing")):
			fryer_sound.call("play")
	elif fryer_sound.has_method("stop"):
		fryer_sound.call("stop")

func _get_fryer_sound() -> Node:
	if not fryer_sound_path.is_empty():
		var configured := get_node_or_null(fryer_sound_path)
		if configured != null:
			return configured

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return null
	for sound_name in _get_fryer_sound_names():
		var direct := scene_root.get_node_or_null(NodePath(sound_name))
		if direct != null:
			return direct
		var found := scene_root.find_child(sound_name, true, false)
		if found != null:
			return found
	return null

func _get_fryer_sound_names() -> Array[String]:
	var names: Array[String] = []
	var normalized_name := String(name).to_lower()
	if normalized_name.ends_with("_1") or normalized_name.ends_with("-1"):
		names.append("fryer-sound-1")
		names.append("FryerSound1")
		names.append("fryer_sound_1")
	elif normalized_name.ends_with("_2") or normalized_name.ends_with("-2"):
		names.append("fryer-sound-2")
		names.append("FryerSound2")
		names.append("fryer_sound_2")
	names.append("fryer-sound-1")
	names.append("fryer-sound-2")
	return names

func _make_bubble_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.018
	mesh.height = 0.036
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.86, 0.38, 0.62)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	return mesh

func _make_sizzle_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.012
	mesh.height = 0.024
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.94, 0.62, 0.72)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.68, 0.22, 1.0)
	material.emission_energy_multiplier = 0.45
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	return mesh

func _make_bubble_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(0.36, 0.015, 0.22)
	material.direction = Vector3.UP
	material.spread = 16.0
	material.gravity = Vector3(0.0, 0.04, 0.0)
	material.initial_velocity_min = 0.06
	material.initial_velocity_max = 0.22
	material.scale_min = 0.35
	material.scale_max = 0.85
	return material

func _make_sizzle_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(0.34, 0.012, 0.2)
	material.direction = Vector3.UP
	material.spread = 28.0
	material.gravity = Vector3(0.0, 0.12, 0.0)
	material.initial_velocity_min = 0.18
	material.initial_velocity_max = 0.42
	material.scale_min = 0.2
	material.scale_max = 0.6
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
