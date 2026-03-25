extends CharacterBody3D

@export var move_speed := 4.5
@export var acceleration := 18.0
@export var deceleration := 22.0
@export var turn_speed := 10.0
@export var stopping_distance := 0.35
@export var waypoint_distance := 0.65
@export var print_debug_messages := true

@onready var rogue_visual: Node3D = $Rogue
@onready var animation_player: AnimationPlayer = $Rogue/AnimationPlayer
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

const ANIMATION_LIBRARY := &"Player"

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _has_target := false
var _path: PackedVector3Array = PackedVector3Array()
var _path_index := 0

func _ready() -> void:
	navigation_agent.max_speed = move_speed
	navigation_agent.path_desired_distance = waypoint_distance
	navigation_agent.target_desired_distance = stopping_distance
	_play_animation("Idle_A", 0.0)

func set_navigation_target(target_position: Vector3) -> void:
	navigation_agent.target_position = target_position
	_has_target = true
	_path = NavigationServer3D.map_get_path(
		get_world_3d().navigation_map,
		NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, global_position),
		target_position,
		true
	)
	_path_index = 0
	if print_debug_messages:
		print("NPC target received: ", target_position, " from ", global_position, " path points: ", _path.size())

func clear_navigation_target() -> void:
	_has_target = false
	_path = PackedVector3Array()
	_path_index = 0

func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO

	if _has_target and _path_index < _path.size():
		while _path_index < _path.size() and _horizontal_distance_to(_path[_path_index]) <= waypoint_distance:
			_path_index += 1

		if _path_index < _path.size():
			direction = _path[_path_index] - global_position
			direction.y = 0.0
			if direction.length() > 0.01:
				direction = direction.normalized()
			else:
				direction = Vector3.ZERO
		elif _horizontal_distance_to(navigation_agent.target_position) > stopping_distance:
			direction = navigation_agent.target_position - global_position
			direction.y = 0.0
			direction = direction.normalized()
	else:
		if _has_target and print_debug_messages:
			print("NPC navigation finished at: ", global_position)
		_has_target = false

	if direction != Vector3.ZERO:
		var target_rotation := atan2(direction.x, direction.z)
		rogue_visual.rotation.y = rotate_toward(rogue_visual.rotation.y, target_rotation, turn_speed * delta)

	var target_velocity := direction * move_speed
	var blend_rate := deceleration
	if direction != Vector3.ZERO:
		blend_rate = acceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, blend_rate * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, blend_rate * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()
	_update_animation(direction)

func _horizontal_distance_to(target_position: Vector3) -> float:
	var offset := target_position - global_position
	offset.y = 0.0
	return offset.length()

func _update_animation(direction: Vector3) -> void:
	if not is_on_floor():
		_play_animation("Jump_Full_Long")
		return

	if direction != Vector3.ZERO:
		_play_animation("Running_A")
		animation_player.speed_scale = clamp(Vector2(velocity.x, velocity.z).length() / move_speed, 0.85, 1.3)
	else:
		_play_animation("Idle_A")
		animation_player.speed_scale = 1.0

func _play_animation(animation_name: StringName, blend: float = 0.15) -> void:
	var resolved_name := _resolve_animation_name(animation_name)
	if resolved_name.is_empty():
		push_warning("Animation not found: %s" % String(animation_name))
		return

	if animation_player.current_animation == resolved_name and animation_player.is_playing():
		return
	animation_player.play(resolved_name, blend)

func _resolve_animation_name(animation_name: StringName) -> StringName:
	if animation_player.has_animation(animation_name):
		return animation_name

	var library_name := StringName("%s/%s" % [String(ANIMATION_LIBRARY), String(animation_name)])
	if animation_player.has_animation(library_name):
		return library_name

	return StringName()
