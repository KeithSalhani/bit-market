extends CharacterBody3D

@export var move_speed := 4.5
@export var acceleration := 18.0
@export var deceleration := 22.0
@export var turn_speed := 10.0
@export var stopping_distance := 0.35
@export var waypoint_distance := 0.65
@export var print_debug_messages := true
@export var sit_position_height_offset := -0.9
@export var visual_node_path: NodePath = ^"Rogue"
@export var animation_player_path: NodePath = ^"Rogue/AnimationPlayer"
@export var idle_animation: StringName = &"Idle_A"
@export var move_animation: StringName = &"Running_A"
@export var fall_animation: StringName = &"Jump_Full_Long"
@export var seated_animation: StringName = &"custom/sit_down"
@export var unisex_seated_animation_keywords: PackedStringArray = ["carla", "man"]
@export var female_seated_animation_keywords: PackedStringArray = ["woman"]

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

const ANIMATION_LIBRARY := &"Player"

enum NpcState {
	IDLE,
	MOVING,
	MOVING_TO_SEAT,
	SEATED,
}

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _has_target := false
var _state := NpcState.IDLE
var _target_seat: Node3D = null
var _target_seat_transform := Transform3D.IDENTITY
var _target_approach: Node3D = null
var _target_approach_transform := Transform3D.IDENTITY
var visual_node: Node3D = null
var animation_player: AnimationPlayer = null

func _ready() -> void:
	_refresh_visual_references()
	navigation_agent.max_speed = move_speed
	navigation_agent.path_desired_distance = waypoint_distance
	navigation_agent.target_desired_distance = stopping_distance
	_play_animation(idle_animation, 0.0)

func _refresh_visual_references() -> void:
	visual_node = get_node_or_null(visual_node_path) as Node3D
	animation_player = get_node_or_null(animation_player_path) as AnimationPlayer

func set_navigation_target(target_position: Vector3) -> void:
	_release_target_seat()
	_state = NpcState.MOVING
	_set_navigation_target(target_position)

func sit_at_seat(seat: Node3D) -> void:
	if seat == null:
		push_warning("Cannot sit: seat is null")
		return

	_release_target_seat()
	_target_seat = seat
	_target_seat_transform = seat.global_transform
	_target_approach = _get_seat_approach_marker(seat)
	if _target_approach != null:
		_target_approach_transform = _target_approach.global_transform
	else:
		_target_approach_transform = seat.global_transform
	_target_seat.set_meta("occupied", true)
	_target_seat.set_meta("reserved_by", get_path())
	_state = NpcState.MOVING_TO_SEAT

	var navigation_map := get_world_3d().navigation_map
	var approach_position := NavigationServer3D.map_get_closest_point(navigation_map, _target_approach_transform.origin)
	_set_navigation_target(approach_position)
	if print_debug_messages:
		print("NPC sitting target: ", seat.get_path(), " approach: ", approach_position)

func sit_at_seat_path(seat_path: NodePath) -> void:
	var seat := get_node_or_null(seat_path) as Node3D
	if seat == null:
		push_warning("Cannot sit: seat path not found: %s" % String(seat_path))
		return
	sit_at_seat(seat)

func stand_up() -> void:
	if _state != NpcState.SEATED:
		return
	global_position = _target_approach_transform.origin
	rotation.y = _target_approach_transform.basis.get_euler().y
	if visual_node != null:
		visual_node.rotation.y = 0.0
	_release_target_seat()
	_state = NpcState.IDLE
	_has_target = false
	_play_animation(idle_animation)

func _set_navigation_target(target_position: Vector3) -> void:
	navigation_agent.target_position = target_position
	_has_target = true
	if print_debug_messages:
		print("NPC target received: ", target_position, " from ", global_position)

func clear_navigation_target() -> void:
	_has_target = false
	if _state != NpcState.SEATED:
		_state = NpcState.IDLE

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _state == NpcState.SEATED:
		velocity = Vector3.ZERO
		return

	var direction := Vector3.ZERO

	if _has_target and _is_navigation_target_reached():
		if _has_target and print_debug_messages:
			print("NPC navigation finished at: ", global_position)
		if _state == NpcState.MOVING_TO_SEAT:
			_finish_sitting()
			return
		_has_target = false
		if _state == NpcState.MOVING:
			_state = NpcState.IDLE
	elif _has_target:
		var next_path_position := navigation_agent.get_next_path_position()
		direction = next_path_position - global_position
		direction.y = 0.0
		if direction.length() > 0.01:
			direction = direction.normalized()
		else:
			direction = Vector3.ZERO

	if direction != Vector3.ZERO:
		var target_rotation := atan2(direction.x, direction.z)
		if visual_node != null:
			visual_node.rotation.y = rotate_toward(visual_node.rotation.y, target_rotation, turn_speed * delta)

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

func _is_navigation_target_reached() -> bool:
	if navigation_agent.is_navigation_finished():
		return true

	var target_offset := navigation_agent.target_position - global_position
	target_offset.y = 0.0
	return target_offset.length() <= stopping_distance

func _finish_sitting() -> void:
	_has_target = false
	velocity = Vector3.ZERO

	global_position = _target_seat_transform.origin + Vector3.UP * sit_position_height_offset
	rotation.y = _target_seat_transform.basis.get_euler().y
	if visual_node != null:
		visual_node.rotation.y = 0.0
	_state = NpcState.SEATED
	var resolved_seated_animation := _select_seated_animation()
	if not _play_animation(resolved_seated_animation):
		_play_animation(idle_animation)
	if print_debug_messages and _target_seat != null:
		print("NPC seated at: ", _target_seat.get_path())

func _release_target_seat() -> void:
	if _target_seat == null:
		return
	if _target_seat.get_meta("reserved_by", NodePath()) == get_path():
		_target_seat.set_meta("occupied", false)
		_target_seat.remove_meta("reserved_by")
	_target_seat = null
	_target_approach = null

func _get_seat_approach_marker(seat: Node3D) -> Node3D:
	if not seat.has_meta("approach_path"):
		return null

	var approach_path := seat.get_meta("approach_path") as NodePath
	return seat.get_node_or_null(approach_path) as Node3D

func _select_seated_animation() -> StringName:
	if _uses_female_seated_animations():
		var female_animation := _find_seated_animation(female_seated_animation_keywords, false)
		if not female_animation.is_empty():
			return female_animation

	var unisex_animation := _find_seated_animation(unisex_seated_animation_keywords, true)
	if not unisex_animation.is_empty():
		return unisex_animation

	return seated_animation

func _find_seated_animation(keywords: PackedStringArray, exclude_female_only: bool) -> StringName:
	if animation_player == null:
		return StringName()

	for animation_name in animation_player.get_animation_list():
		var normalized := String(animation_name).to_lower()
		if not normalized.contains("sit"):
			continue
		if exclude_female_only and normalized.contains("woman"):
			continue
		for keyword in keywords:
			if normalized.contains(keyword.to_lower()):
				return animation_name

	return StringName()

func _uses_female_seated_animations() -> bool:
	return false

func _update_animation(direction: Vector3) -> void:
	if not is_on_floor():
		_play_animation(fall_animation)
		return

	if direction != Vector3.ZERO:
		_play_animation(move_animation)
		if animation_player != null:
			animation_player.speed_scale = clamp(Vector2(velocity.x, velocity.z).length() / move_speed, 0.85, 1.3)
	else:
		_play_animation(idle_animation)
		if animation_player != null:
			animation_player.speed_scale = 1.0

func _play_animation(animation_name: StringName, blend: float = 0.15) -> bool:
	if animation_player == null:
		return false

	var resolved_name := _resolve_animation_name(animation_name)
	if resolved_name.is_empty():
		push_warning("Animation not found: %s" % String(animation_name))
		return false

	if animation_player.current_animation == resolved_name and animation_player.is_playing():
		return true
	animation_player.play(resolved_name, blend)
	return true

func _resolve_animation_name(animation_name: StringName) -> StringName:
	if animation_player == null:
		return StringName()

	if animation_player.has_animation(animation_name):
		return animation_name

	var library_name := StringName("%s/%s" % [String(ANIMATION_LIBRARY), String(animation_name)])
	if animation_player.has_animation(library_name):
		return library_name

	var requested := String(animation_name)
	for available_name in animation_player.get_animation_list():
		var available := String(available_name)
		if available == requested or available.begins_with(requested + "/"):
			return available_name

	return StringName()
