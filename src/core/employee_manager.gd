extends Node

@export var worker_scene: PackedScene = preload("res://scenes/characters/worker.tscn")
@export var initial_workers: int = 1
@export var spawn_spacing: float = 0.55

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
	
	# Try to find a spawn position near a register
	var pos = Vector3(0, 0.4, 0)
	var seating_map = get_parent().find_child("SeatingMap", true, false)
	if seating_map != null:
		var registers: Array[Node3D] = []
		_collect_markers(seating_map, "Opposite", registers)
		if not registers.is_empty():
			var marker = registers[0]
			pos = marker.global_position + Vector3.RIGHT * float(workers.size()) * spawn_spacing
	
	worker.global_position = pos
	workers.append(worker)

func _collect_markers(node: Node, marker_suffix: String, markers: Array[Node3D]) -> void:
	if node is Node3D:
		var node_name = String(node.name)
		if node_name.ends_with("_" + marker_suffix):
			markers.append(node as Node3D)
	for child in node.get_children():
		_collect_markers(child, marker_suffix, markers)
