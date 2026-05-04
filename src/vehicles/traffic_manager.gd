extends Node

@export var road_path: NodePath = ^"../Road"
@export var vehicles_per_lane := 2
@export var min_speed := 10.0
@export var max_speed := 16.0
@export var lane_spawn_spacing := 0.22
@export_group("Audio")
@export var vehicle_audio_range := 170.0
@export var vehicle_audio_unit_size := 1.0
@export var engine_min_volume_db := -10.0
@export var engine_max_volume_db := -1.5
@export var drive_min_volume_db := -24.0
@export var drive_max_volume_db := -11.0
@export_group("")
@export var vehicle_scenes: Array[PackedScene] = []

var _lanes: Array[Dictionary] = []
var _traffic: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_cache_lanes()
	_spawn_initial_traffic()

func _process(delta: float) -> void:
	for car in _traffic:
		_update_car(car, delta)

func _cache_lanes() -> void:
	var road := get_node_or_null(road_path) as Node3D
	if road == null:
		push_warning("TrafficManager could not find road node at %s" % String(road_path))
		return

	_add_lane(road, ^"begin_right_road_right_lane", ^"end_right_road_right_lane")
	_add_lane(road, ^"begin_right_road_left_lane", ^"end_right_road_left_lane2")
	_add_lane(road, ^"begin_left_road_left_lane", ^"end_left_road_left_lane")
	_add_lane(road, ^"begin_left_road_right_lane", ^"end_left_road_right_lane")

func _add_lane(road: Node3D, start_path: NodePath, end_path: NodePath) -> void:
	var start := road.get_node_or_null(start_path) as Node3D
	var end := road.get_node_or_null(end_path) as Node3D
	if start == null or end == null:
		push_warning("TrafficManager lane missing marker: %s -> %s" % [String(start_path), String(end_path)])
		return

	_lanes.append({
		"start": start.global_position,
		"end": end.global_position,
		"length": start.global_position.distance_to(end.global_position),
	})

func _spawn_initial_traffic() -> void:
	if _lanes.is_empty() or vehicle_scenes.is_empty():
		return

	for lane_index in range(_lanes.size()):
		for slot in range(vehicles_per_lane):
			var progress := fposmod(float(slot) / maxf(float(vehicles_per_lane), 1.0) + lane_spawn_spacing * float(lane_index), 1.0)
			_spawn_car(lane_index, progress)

func _spawn_car(lane_index: int, progress: float) -> void:
	var scene := vehicle_scenes[_rng.randi_range(0, vehicle_scenes.size() - 1)]
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return

	instance.name = "TrafficVehicle"
	add_child(instance)
	instance.set("preview_spin_enabled", false)
	_apply_audio_settings(instance)
	_remove_preview_helpers(instance)

	var speed := _rng.randf_range(min_speed, max_speed)
	var car := {
		"node": instance,
		"lane": lane_index,
		"progress": progress,
		"speed": speed,
	}
	_position_car(car)
	if instance.has_method("set_drive_speed"):
		instance.call("set_drive_speed", speed)
	_traffic.append(car)

func _remove_preview_helpers(instance: Node3D) -> void:
	for node_name in ["PreviewCamera", "PreviewSun", "PreviewEnvironment"]:
		var helper := instance.get_node_or_null(NodePath(node_name))
		if helper != null:
			helper.queue_free()

func _update_car(car: Dictionary, delta: float) -> void:
	var lane: Dictionary = _lanes[int(car["lane"])]
	car["progress"] = fposmod(float(car["progress"]) + (float(car["speed"]) * delta / float(lane["length"])), 1.0)
	_position_car(car)
	var node := car["node"] as Node3D
	if node != null:
		_apply_audio_settings(node)
		if node.has_method("set_drive_speed"):
			node.call("set_drive_speed", float(car["speed"]))

func _apply_audio_settings(vehicle: Node3D) -> void:
	if vehicle.has_method("apply_audio_settings"):
		vehicle.call(
			"apply_audio_settings",
			vehicle_audio_range,
			vehicle_audio_unit_size,
			engine_min_volume_db,
			engine_max_volume_db,
			drive_min_volume_db,
			drive_max_volume_db
		)

func _position_car(car: Dictionary) -> void:
	var node := car["node"] as Node3D
	if node == null:
		return

	var lane: Dictionary = _lanes[int(car["lane"])]
	var start: Vector3 = lane["start"]
	var end: Vector3 = lane["end"]
	var progress := float(car["progress"])
	var position := start.lerp(end, progress)
	var direction := (end - start).normalized()
	node.global_position = position + Vector3.UP * 0.04
	if direction.length_squared() > 0.001:
		node.look_at(position + direction, Vector3.UP)
		node.rotate_y(PI)
