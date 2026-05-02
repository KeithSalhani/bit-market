extends Node

@export var worker_scene: PackedScene = preload("res://scenes/characters/worker.tscn")
@export var initial_workers: int = 1
@export var spawn_spacing: float = 0.55
@export_node_path("Node3D") var worker_spawn_point_path: NodePath = ^"../WorkerSpawnPoint"

var workers: Array[CharacterBody3D] = []

func _ready() -> void:
	call_deferred("_spawn_initial_workers")

func _spawn_initial_workers() -> void:
	for i in range(initial_workers):
		hire_worker()

func hire_worker() -> void:
	var rm = get_node("/root/RestaurantManager")
	var cost = 100.0 # simple cost
	if workers.size() > 0: # First worker is free
		if not rm.spend_money(cost):
			return
			
	var worker = worker_scene.instantiate() as CharacterBody3D
	worker.name = "Worker_%d" % (workers.size() + 1)
	get_parent().add_child(worker)
	
	var pos = _get_worker_spawn_position(workers.size())
	
	worker.global_position = pos
	workers.append(worker)

func _get_worker_spawn_position(spawn_index: int) -> Vector3:
	var spawn_point := _resolve_worker_spawn_point()
	if spawn_point != null:
		return spawn_point.global_position + Vector3.RIGHT * float(spawn_index) * spawn_spacing

	var seating_map = get_parent().find_child("SeatingMap", true, false)
	if seating_map != null:
		var registers: Array[Node3D] = []
		_collect_markers(seating_map, "Approach", registers)
		if not registers.is_empty():
			var marker = registers[0]
			return marker.global_position + Vector3.RIGHT * float(spawn_index) * spawn_spacing

	return Vector3(0, 0.4, 0)

func _resolve_worker_spawn_point() -> Node3D:
	var configured := get_node_or_null(worker_spawn_point_path) as Node3D
	if configured != null:
		return configured

	var current_scene := get_tree().current_scene
	if current_scene != null:
		return current_scene.find_child("WorkerSpawnPoint", true, false) as Node3D
	return null

func _collect_markers(node: Node, marker_suffix: String, markers: Array[Node3D]) -> void:
	if node is Node3D:
		var node_name = String(node.name)
		if node_name.ends_with("_" + marker_suffix):
			markers.append(node as Node3D)
	for child in node.get_children():
		_collect_markers(child, marker_suffix, markers)
