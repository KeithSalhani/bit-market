extends Node

@export var customer_scenes: Array[PackedScene] = [
	preload("res://scenes/characters/character_npc.tscn")
]
@export var spawn_interval_min: float = 5.0
@export var spawn_interval_max: float = 10.0
@export var max_customers: int = 5
@export var spawn_point_path: NodePath = ^"../BurgerPiz2/Door_01"
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

func _get_spawn_position(spawn_point: Node3D) -> Vector3:
	var spawn_position := spawn_point.global_position
	var navigation_map: RID = spawn_point.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(navigation_map) != 0:
		return NavigationServer3D.map_get_closest_point(navigation_map, spawn_position)

	spawn_position.y = 0.6
	return spawn_position
