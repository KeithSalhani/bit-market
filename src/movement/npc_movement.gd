extends CharacterBody3D

signal arrived_at_target(target_position: Vector3)

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
@export var randomize_seated_animation := true
@export_range(0.0, 1.0, 0.05) var seated_animation_height_compensation_scale := 0.5
@export var unisex_seated_animation_keywords: PackedStringArray = ["carla", "man"]
@export var female_seated_animation_keywords: PackedStringArray = ["woman"]
@export var seated_visual_height_offset := -1

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
var _active_seated_animation: StringName = StringName()
var _visual_rest_position := Vector3.ZERO
var _has_look_target := false
var _look_target := Vector3.ZERO

func _ready() -> void:
	_refresh_visual_references()
	navigation_agent.max_speed = move_speed
	navigation_agent.path_desired_distance = waypoint_distance
	navigation_agent.target_desired_distance = stopping_distance
	_play_animation(idle_animation, 0.0)

func _refresh_visual_references() -> void:
	visual_node = get_node_or_null(visual_node_path) as Node3D
	if visual_node != null:
		_visual_rest_position = visual_node.position
	animation_player = get_node_or_null(animation_player_path) as AnimationPlayer

func set_navigation_target(target_position: Vector3) -> void:
	_active_seated_animation = StringName()
	_reset_visual_seated_offset()
	_release_target_seat()
	_state = NpcState.MOVING
	_has_look_target = false
	_set_navigation_target(target_position)

func set_navigation_target_with_look_target(target_position: Vector3, look_target: Vector3) -> void:
	_active_seated_animation = StringName()
	_reset_visual_seated_offset()
	_release_target_seat()
	_state = NpcState.MOVING
	_look_target = look_target
	_has_look_target = true
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
	_reset_visual_seated_offset()
	_release_target_seat()
	_active_seated_animation = StringName()
	_has_look_target = false
	_state = NpcState.IDLE
	_has_target = false
	_play_animation(idle_animation)

func _set_navigation_target(target_position: Vector3) -> void:
	navigation_agent.target_position = target_position
	_has_target = true
	if print_debug_messages:
		print("NPC target received: ", target_position, " from ", global_position)
	
	if _is_navigation_target_reached():
		_on_target_reached_immediate()

func _on_target_reached_immediate() -> void:
	# Use call_deferred to ensure signals are consistent
	call_deferred("_handle_arrival")

func _handle_arrival() -> void:
	if not _has_target: return
	if print_debug_messages:
		print("NPC navigation finished at: ", global_position)
	var target_pos = navigation_agent.target_position
	if _state == NpcState.MOVING_TO_SEAT:
		_finish_sitting()
		arrived_at_target.emit(target_pos)
		return
	_has_target = false
	if _state == NpcState.MOVING:
		_state = NpcState.IDLE
	if _has_look_target:
		_face_target(_look_target, 1.0)
	arrived_at_target.emit(target_pos)

func clear_navigation_target() -> void:
	_has_target = false
	if _state != NpcState.SEATED:
		_state = NpcState.IDLE

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _state == NpcState.SEATED:
		velocity = Vector3.ZERO
		_keep_seated_animation_playing()
		return

	var direction := Vector3.ZERO

	if _has_target and _is_navigation_target_reached():
		_handle_arrival()
	elif _has_target:
		var next_path_position := navigation_agent.get_next_path_position()
		direction = next_path_position - global_position
		direction.y = 0.0
		if direction.length() > 0.01:
			direction = direction.normalized()
		else:
			direction = Vector3.ZERO

	if direction != Vector3.ZERO:
		_face_direction(direction, delta)
	elif _has_look_target:
		_face_target(_look_target, delta)

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
	var target_offset := navigation_agent.target_position - global_position
	target_offset.y = 0.0
	if target_offset.length() <= stopping_distance:
		return true
	return navigation_agent.is_navigation_finished()

func _face_target(target_position: Vector3, delta: float) -> void:
	var direction := target_position - global_position
	direction.y = 0.0
	if direction.length() <= 0.01:
		return
	_face_direction(direction.normalized(), delta)

func _face_direction(direction: Vector3, delta: float) -> void:
	if visual_node == null:
		return
	var target_rotation := atan2(direction.x, direction.z)
	visual_node.rotation.y = rotate_toward(visual_node.rotation.y, target_rotation, turn_speed * delta)

func _finish_sitting() -> void:
	_has_target = false
	velocity = Vector3.ZERO

	var resolved_sit_position_height_offset := _get_seat_float_meta("sit_position_height_offset", sit_position_height_offset)
	var resolved_seated_visual_height_offset := _get_seat_float_meta("seated_visual_height_offset", seated_visual_height_offset)
	var resolved_seated_animation := _select_seated_animation()
	resolved_seated_visual_height_offset += _get_seated_animation_height_compensation(resolved_seated_animation)

	global_position = _target_seat_transform.origin + Vector3.UP * resolved_sit_position_height_offset
	rotation.y = _target_seat_transform.basis.get_euler().y
	if visual_node != null:
		visual_node.rotation.y = 0.0
		visual_node.position = _visual_rest_position + Vector3.UP * resolved_seated_visual_height_offset
	_state = NpcState.SEATED
	if animation_player != null:
		animation_player.speed_scale = 1.0
	if not _play_seated_animation(resolved_seated_animation):
		_play_animation(idle_animation)
	else:
		_active_seated_animation = resolved_seated_animation
	if print_debug_messages and _target_seat != null:
		var character_label := ""
		if _has_property("character_id"):
			character_label = " character: %s" % String(get("character_id"))
		var seat_height_offset := 0.0
		if _target_seat.has_meta("height_offset"):
			seat_height_offset = float(_target_seat.get_meta("height_offset"))
		print(
			"NPC seated at: ",
			_target_seat.get_path(),
			" seat_origin: ",
			_target_seat_transform.origin,
			" actor_origin: ",
			global_position,
			" seat_height_offset: ",
			seat_height_offset,
			" sit_position_height_offset: ",
			resolved_sit_position_height_offset,
			" seated_visual_height_offset: ",
			resolved_seated_visual_height_offset,
			character_label,
			" animation: ",
			resolved_seated_animation
		)

func _get_seat_float_meta(meta_name: StringName, fallback: float) -> float:
	if _target_seat == null or not _target_seat.has_meta(meta_name):
		return fallback
	return float(_target_seat.get_meta(meta_name))

func _has_property(property_name: String) -> bool:
	for property in get_property_list():
		if String(property.get("name", "")) == property_name:
			return true
	return false

func _release_target_seat() -> void:
	if _target_seat == null:
		return
	if _target_seat.get_meta("reserved_by", NodePath()) == get_path():
		_target_seat.set_meta("occupied", false)
		_target_seat.remove_meta("reserved_by")
	_target_seat = null
	_target_approach = null

func _reset_visual_seated_offset() -> void:
	if visual_node != null:
		visual_node.position = _visual_rest_position

func _get_seat_approach_marker(seat: Node3D) -> Node3D:
	if not seat.has_meta("approach_path"):
		return null

	var approach_path := seat.get_meta("approach_path") as NodePath
	return seat.get_node_or_null(approach_path) as Node3D

func _select_seated_animation() -> StringName:
	if randomize_seated_animation:
		var random_animation := _find_random_seated_animation()
		if not random_animation.is_empty():
			return random_animation

	if _can_play_animation(seated_animation):
		return seated_animation

	if _uses_female_seated_animations():
		var female_animation := _find_seated_animation(female_seated_animation_keywords, false)
		if not female_animation.is_empty():
			return female_animation

	var unisex_animation := _find_seated_animation(unisex_seated_animation_keywords, true)
	if not unisex_animation.is_empty():
		return unisex_animation

	return seated_animation

func _find_random_seated_animation() -> StringName:
	if animation_player == null:
		return StringName()

	var options: Array[StringName] = []
	for animation_name in animation_player.get_animation_list():
		var normalized := String(animation_name).to_lower()
		if normalized.contains("sit"):
			options.append(animation_name)

	if options.is_empty():
		return StringName()
	return options[randi() % options.size()]

func _get_seated_animation_height_compensation(animation_name: StringName) -> float:
	if animation_player == null:
		return 0.0
	var resolved_name := _resolve_animation_name(animation_name)
	if resolved_name.is_empty():
		return 0.0
	var animation := animation_player.get_animation(resolved_name)
	if animation == null:
		return 0.0

	var animated_hips_y := INF
	for i in range(animation.get_track_count()):
		if animation.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(animation.track_get_path(i))
		if not path.contains("Hips"):
			continue
		if animation.track_get_key_count(i) <= 0:
			continue
		var value: Variant = animation.track_get_key_value(i, 0)
		if value is Vector3:
			animated_hips_y = (value as Vector3).y
			break
	if animated_hips_y == INF:
		return 0.0

	var skeleton := _find_skeleton(visual_node)
	if skeleton == null:
		return 0.0
	var hips_index := skeleton.find_bone("Hips")
	if hips_index < 0:
		return 0.0
	var rest_hips_y := skeleton.get_bone_rest(hips_index).origin.y
	var visual_global_scale_y := visual_node.global_transform.basis.get_scale().y if visual_node != null else 1.0
	if absf(visual_global_scale_y) <= 0.0001:
		visual_global_scale_y = 1.0
	var skeleton_to_visual_scale_y := skeleton.global_transform.basis.get_scale().y / visual_global_scale_y
	return (rest_hips_y - animated_hips_y) * skeleton_to_visual_scale_y * seated_animation_height_compensation_scale

func _can_play_animation(animation_name: StringName) -> bool:
	return not _resolve_animation_name(animation_name).is_empty()

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

func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

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

func _play_seated_animation(animation_name: StringName) -> bool:
	if animation_player == null:
		return false

	var resolved_name := _resolve_animation_name(animation_name)
	if resolved_name.is_empty():
		push_warning("Animation not found: %s" % String(animation_name))
		return false

	var animation := animation_player.get_animation(resolved_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR

	if animation_player.current_animation == resolved_name and animation_player.is_playing():
		return true
	animation_player.play(resolved_name, 0.0)
	animation_player.seek(0.0, true)
	return true

func _keep_seated_animation_playing() -> void:
	if _active_seated_animation.is_empty():
		return
	if animation_player == null:
		return
	var resolved_name := _resolve_animation_name(_active_seated_animation)
	if resolved_name.is_empty():
		return
	if animation_player.current_animation == resolved_name and animation_player.is_playing():
		return
	if not _play_seated_animation(_active_seated_animation):
		_active_seated_animation = StringName()

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
