extends Node

@export var customer_scenes: Array[PackedScene] = [
	preload("res://scenes/characters/character_npc.tscn")
]
@export var spawn_interval_min: float = 5.0
@export var spawn_interval_max: float = 10.0
@export var max_customers: int = 5
@export var spawn_point_path: NodePath = ^"../BurgerPiz2/Door_01"
@export var register_queue_spacing := 1.1
@export var register_queue_start_offset := 1.2
@export var randomize_character_id := true
@export var customer_character_ids := PackedStringArray([
	"Character_01", "Character_02", "Character_03", "Character_04", "Character_05", "Character_06", "Character_07", "Character_08",
	"Character_09", "Character_10", "Character_11", "Character_12", "Character_13", "Character_14", "Character_15", "Character_16",
	"Character_17_Female_Police", "Character_17_Police", "Character_18_Female_Police", "Character_18_Police",
	"Character_19_Female_Police", "Character_19_Police", "Character_20_Female_Police", "Character_20_Police",
	"Character_21_Female_Firefighter", "Character_21_Police", "Character_22_Female_Firefighter", "Character_22_Police",
	"Character_23_Female_Doctor", "Character_23_Firefighter", "Character_24_Female_Doctor", "Character_24_Firefighter",
	"Character_25_Doctor", "Character_25_Female_Police", "Character_26_Doctor", "Character_26_Female_Police",
	"Character_27_Female_HM", "Character_27_HM", "Character_28_Female_HM", "Character_28_HM",
	"Character_29", "Character_29_Female", "Character_30", "Character_30_Female", "Character_31", "Character_31_Female",
	"Character_32", "Character_32_Female", "Character_33_Female",
	"Character_Female_02", "Character_Female_03", "Character_Female_04", "Character_Female_05", "Character_Female_06",
	"Character_Female_07", "Character_Female_08", "Character_Female_09", "Character_Female_10", "Character_Female_11",
	"Character_Female_12", "Character_Female_13", "Character_Female_14", "Character_Female_15", "Character_Female_16"
])

var _timer: Timer
var current_customers: int = 0
var _register_slots: Array[Dictionary] = []
var _register_queue: Array[Node] = []
var _queue_markers: Dictionary = {}

func _ready() -> void:
	var rm = get_node("/root/RestaurantManager")
	rm.connect("open_state_changed", _on_open_state_changed)
	
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_spawn_customer)
	add_child(_timer)
	
	if rm.is_open:
		_start_timer()

func _on_open_state_changed(is_open: bool) -> void:
	if is_open:
		_start_timer()
	else:
		_timer.stop()

func _start_timer() -> void:
	_timer.start(randf_range(spawn_interval_min, spawn_interval_max))

func _spawn_customer() -> void:
	spawn_customer_now()
	_start_timer()

func spawn_customer_now() -> CharacterBody3D:
	if current_customers >= max_customers:
		return null

	if customer_scenes.is_empty():
		return null
	var scene = customer_scenes[randi() % customer_scenes.size()]
	var customer = scene.instantiate() as CharacterBody3D
	if customer == null:
		return null

	_randomize_customer_visual(customer)
	add_child(customer)
	
	current_customers += 1
	
	var spawn_point = get_node_or_null(spawn_point_path) as Node3D
	if spawn_point != null:
		customer.global_position = _get_spawn_position(spawn_point)
	else:
		customer.global_position = Vector3(0, 0.6, 10) # Fallback
	
	# Add CustomerAI component
	var ai = Node.new()
	ai.name = "CustomerAI"
	var script = load("res://src/core/customer_ai.gd")
	ai.set_script(script)
	customer.add_child(ai)
	
	return customer

func _randomize_customer_visual(customer: CharacterBody3D) -> void:
	if not randomize_character_id or customer == null or customer_character_ids.is_empty():
		return
	if not _has_property(customer, "character_id"):
		return
	customer.character_id = customer_character_ids[randi() % customer_character_ids.size()]

func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true
	return false

func customer_left() -> void:
	current_customers -= 1

func request_register_slot(customer_ai: Node) -> void:
	if customer_ai == null or not is_instance_valid(customer_ai):
		return
	_prune_register_state()
	_ensure_register_slots()
	if not _register_queue.has(customer_ai) and _get_customer_register_slot_index(customer_ai) == -1:
		_register_queue.append(customer_ai)
	if _register_slots.is_empty():
		call_deferred("_retry_register_assignment")
		return
	_assign_open_registers()
	_update_register_queue_positions()

func release_register_slot(customer_ai: Node) -> void:
	if customer_ai == null:
		return
	for i in _register_slots.size():
		if _register_slots[i].get("customer") == customer_ai:
			_register_slots[i]["customer"] = null
	if _register_queue.has(customer_ai):
		_register_queue.erase(customer_ai)
	_remove_queue_marker(customer_ai)
	_assign_open_registers()
	_update_register_queue_positions()

func _get_spawn_position(spawn_point: Node3D) -> Vector3:
	var spawn_position := spawn_point.global_position
	var navigation_map: RID = spawn_point.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(navigation_map) != 0:
		return NavigationServer3D.map_get_closest_point(navigation_map, spawn_position)

	spawn_position.y = 0.6
	return spawn_position

func _ensure_register_slots() -> void:
	_prune_register_state()
	if not _register_slots.is_empty():
		return
	var level := get_tree().current_scene
	if level == null:
		return
	var seating_map := level.find_child("SeatingMap", true, false)
	if seating_map == null:
		return
	var register_markers: Array[Node3D] = []
	_collect_register_markers(seating_map, "Opposite", register_markers)
	register_markers.sort_custom(_sort_nodes_by_name)
	for marker in register_markers:
		_register_slots.append({
			"marker": marker,
			"customer": null,
		})

func _retry_register_assignment() -> void:
	_prune_register_state()
	_ensure_register_slots()
	_assign_open_registers()
	_update_register_queue_positions()

func _assign_open_registers() -> void:
	_prune_register_state()
	var i := 0
	while i < _register_slots.size():
		if _register_queue.is_empty():
			return
		var slot := _register_slots[i]
		if slot.get("customer") != null:
			i += 1
			continue
		var marker := slot.get("marker") as Node3D
		if marker == null or not is_instance_valid(marker):
			i += 1
			continue
		var customer_ai := _register_queue.pop_front() as Node
		if customer_ai == null or not is_instance_valid(customer_ai):
			continue
		_register_slots[i]["customer"] = customer_ai
		_remove_queue_marker(customer_ai)
		if customer_ai.has_method("go_to_register"):
			customer_ai.call("go_to_register", marker)
		i += 1

func _update_register_queue_positions() -> void:
	_prune_register_state()
	var queue_direction := _get_register_queue_direction()
	var queue_start := _get_register_queue_start(queue_direction)
	for index in _register_queue.size():
		var customer_ai := _register_queue[index]
		if customer_ai == null or not is_instance_valid(customer_ai):
			continue
		var marker := _get_queue_marker(customer_ai)
		marker.global_position = queue_start + queue_direction * register_queue_spacing * float(index)
		if customer_ai.has_method("wait_in_register_queue"):
			customer_ai.call("wait_in_register_queue", marker, _get_register_queue_look_target())

func _get_register_queue_start(queue_direction: Vector3) -> Vector3:
	var average_point := _get_average_register_customer_position()
	if average_point == Vector3.INF:
		return _get_fallback_queue_position()
	return average_point + queue_direction * register_queue_start_offset

func _get_register_queue_direction() -> Vector3:
	var average_customer_point := _get_average_register_customer_position()
	var average_register_point := _get_average_register_root_position()
	if average_customer_point != Vector3.INF and average_register_point != Vector3.INF:
		var direction := average_customer_point - average_register_point
		direction.y = 0.0
		if direction.length() > 0.01:
			return direction.normalized()
	var spawn_point := get_node_or_null(spawn_point_path) as Node3D
	if spawn_point != null and average_customer_point != Vector3.INF:
		var direction := spawn_point.global_position - average_customer_point
		direction.y = 0.0
		if direction.length() > 0.01:
			return direction.normalized()
	return Vector3.FORWARD

func _get_register_queue_look_target() -> Vector3:
	var target := _get_average_register_root_position()
	if target != Vector3.INF:
		return target
	target = _get_average_register_customer_position()
	if target != Vector3.INF:
		return target
	return _get_fallback_queue_position()

func _get_fallback_queue_position() -> Vector3:
	var spawn_point := get_node_or_null(spawn_point_path) as Node3D
	if spawn_point != null:
		return spawn_point.global_position
	return Vector3.ZERO

func _get_average_register_customer_position() -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for slot in _register_slots:
		var marker := slot.get("marker") as Node3D
		if marker != null and is_instance_valid(marker):
			total += marker.global_position
			count += 1
	if count == 0:
		return Vector3.INF
	return total / float(count)

func _get_average_register_root_position() -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for slot in _register_slots:
		var marker := slot.get("marker") as Node3D
		if marker == null or not is_instance_valid(marker):
			continue
		var register_root := marker.get_parent() as Node3D
		if register_root == null:
			continue
		total += register_root.global_position
		count += 1
	if count == 0:
		return Vector3.INF
	return total / float(count)

func _get_customer_register_slot_index(customer_ai: Node) -> int:
	for i in _register_slots.size():
		if _register_slots[i].get("customer") == customer_ai:
			return i
	return -1

func _get_queue_marker(customer_ai: Node) -> Marker3D:
	if _queue_markers.has(customer_ai):
		var existing := _queue_markers[customer_ai] as Marker3D
		if existing != null and is_instance_valid(existing):
			return existing
	var marker := Marker3D.new()
	marker.name = "RegisterQueueTarget_%s" % str(customer_ai.get_instance_id())
	add_child(marker)
	_queue_markers[customer_ai] = marker
	return marker

func _remove_queue_marker(customer_ai: Node) -> void:
	if not _queue_markers.has(customer_ai):
		return
	var marker := _queue_markers[customer_ai] as Marker3D
	_queue_markers.erase(customer_ai)
	if marker != null and is_instance_valid(marker):
		marker.queue_free()

func _prune_register_state() -> void:
	var i := _register_queue.size() - 1
	while i >= 0:
		var customer_ai := _register_queue[i]
		if customer_ai == null or not is_instance_valid(customer_ai):
			_register_queue.remove_at(i)
		i -= 1
	for slot in _register_slots:
		var marker := slot.get("marker") as Node3D
		if marker == null or not is_instance_valid(marker):
			slot["customer"] = null
			continue
		var customer_ai := slot.get("customer") as Node
		if customer_ai != null and not is_instance_valid(customer_ai):
			slot["customer"] = null
	for customer_ai in _queue_markers.keys():
		if customer_ai == null or not is_instance_valid(customer_ai):
			_remove_queue_marker(customer_ai)

func _collect_register_markers(node: Node, marker_suffix: String, markers: Array[Node3D]) -> void:
	if node is Node3D:
		var node_name := String(node.name)
		if node_name.begins_with("CashRegister_") and node_name.ends_with("_" + marker_suffix):
			markers.append(node as Node3D)
	for child in node.get_children():
		_collect_register_markers(child, marker_suffix, markers)

func _sort_nodes_by_name(a: Node3D, b: Node3D) -> bool:
	return String(a.name).naturalnocasecmp_to(String(b.name)) < 0
