extends Node

@export var customer_scenes: Array[PackedScene] = [
	preload("res://scenes/characters/character_npc.tscn")
]
@export var spawn_interval_min: float = 5.0
@export var spawn_interval_max: float = 10.0
@export var max_customers: int = 5
@export var spawn_point_path: NodePath = ^"../BurgerPiz2/Door_01"

var _timer: Timer
var current_customers: int = 0

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
	if current_customers >= max_customers:
		_start_timer()
		return

	if customer_scenes.is_empty(): return
	var scene = customer_scenes[randi() % customer_scenes.size()]
	var customer = scene.instantiate() as CharacterBody3D
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
	
	_start_timer()

func customer_left() -> void:
	current_customers -= 1

func _get_spawn_position(spawn_point: Node3D) -> Vector3:
	var spawn_position := spawn_point.global_position
	var navigation_map: RID = spawn_point.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(navigation_map) != 0:
		return NavigationServer3D.map_get_closest_point(navigation_map, spawn_position)

	spawn_position.y = 0.6
	return spawn_position
