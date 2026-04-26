extends CharacterBody3D

signal arrived_at_target(target_position: Vector3)

@export var move_speed := 3.4
@export var acceleration := 16.0
@export var deceleration := 20.0
@export var turn_speed := 9.0
@export var stopping_distance := 0.28
@export var waypoint_distance := 0.45
@export var visual_node_path: NodePath = ^"VisualRoot"
@export var animation_player_path: NodePath = ^"AnimationPlayer"
@export var idle_animation: StringName = &""
@export var move_animation: StringName = &""

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var visual_node: Node3D = get_node_or_null(visual_node_path) as Node3D
@onready var animation_player: AnimationPlayer = _get_animation_player()
@onready var selection_ring: MeshInstance3D = $SelectionRing

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _has_target := false
var _selected := false
var _last_animation: StringName = &""
var _has_look_target := false
var _look_target := Vector3.ZERO
var _current_target := Vector3.ZERO
var _is_snapped_to_station := false
var _station_exit_transform := Transform3D.IDENTITY

func _ready() -> void:
	add_to_group("worker_npc")
	navigation_agent.max_speed = move_speed
	navigation_agent.path_desired_distance = waypoint_distance
	navigation_agent.target_desired_distance = stopping_distance
	set_selected(false)
	_play_worker_animation(idle_animation)

func set_selected(value: bool) -> void:
	_selected = value
	if selection_ring != null:
		selection_ring.visible = _selected

func is_selected() -> bool:
	return _selected

func set_navigation_target(target_position: Vector3) -> void:
	_leave_station_snap()
	navigation_agent.target_position = target_position
	_current_target = target_position
	_has_target = true
	_has_look_target = false

func set_navigation_target_with_look_target(target_position: Vector3, look_target: Vector3) -> void:
	_leave_station_snap()
	navigation_agent.target_position = target_position
	_current_target = target_position
	_look_target = look_target
	_has_target = true
	_has_look_target = true

func set_navigation_target_without_leaving_station(target_position: Vector3, look_target: Variant = null) -> void:
	navigation_agent.target_position = target_position
	_current_target = target_position
	_has_target = true
	if look_target is Vector3:
		_look_target = look_target
		_has_look_target = true
	else:
		_has_look_target = false

func snap_to_station(snap_marker: Node3D, exit_marker: Node3D = null) -> void:
	if snap_marker == null:
		return
	_has_target = false
	velocity = Vector3.ZERO
	_apply_station_marker_transform(snap_marker.global_transform)
	if exit_marker != null:
		_station_exit_transform = exit_marker.global_transform
	else:
		_station_exit_transform = snap_marker.global_transform
	_is_snapped_to_station = true

func clear_navigation_target() -> void:
	_has_target = false
	_has_look_target = false

func _physics_process(delta: float) -> void:
	if _is_snapped_to_station:
		velocity = Vector3.ZERO
		_update_worker_animation(Vector3.ZERO)
		return

	var direction := Vector3.ZERO

	if _has_target and _is_navigation_target_reached():
		_has_target = false
		if _has_look_target:
			_face_target(_look_target, delta)
		arrived_at_target.emit(_current_target)
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
	var blend_rate := acceleration if direction != Vector3.ZERO else deceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, blend_rate * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, blend_rate * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()
	_update_worker_animation(direction)

func _is_navigation_target_reached() -> bool:
	if navigation_agent.is_navigation_finished():
		return true

	var target_offset := navigation_agent.target_position - global_position
	target_offset.y = 0.0
	return target_offset.length() <= stopping_distance

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

func _update_worker_animation(direction: Vector3) -> void:
	if direction == Vector3.ZERO:
		_play_worker_animation(idle_animation)
	else:
		_play_worker_animation(move_animation)

func _play_worker_animation(animation_name: StringName) -> void:
	if animation_player == null:
		return
	if animation_name.is_empty():
		_last_animation = &""
		animation_player.stop()
		return

	var resolved_animation := _resolve_worker_animation(animation_name)
	if resolved_animation.is_empty():
		_last_animation = &""
		animation_player.stop()
		return
	if _last_animation == resolved_animation and animation_player.is_playing():
		return

	_last_animation = resolved_animation
	animation_player.play(resolved_animation)

func _resolve_worker_animation(animation_name: StringName) -> StringName:
	if animation_player.has_animation(animation_name):
		return animation_name

	var requested := String(animation_name).to_lower()
	for available_name in animation_player.get_animation_list():
		var available := String(available_name)
		var normalized := available.to_lower()
		if normalized == requested or normalized.ends_with("/" + requested) or normalized.contains(requested):
			return available_name

	return StringName()

func _get_animation_player() -> AnimationPlayer:
	var configured_player := get_node_or_null(animation_player_path) as AnimationPlayer
	if configured_player != null:
		return configured_player

	var visual_player := _find_animation_player(visual_node)
	if visual_player != null:
		return visual_player

	return _find_animation_player(self)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer

	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found

	return null

func _leave_station_snap() -> void:
	if not _is_snapped_to_station:
		return
	_apply_station_marker_transform(_station_exit_transform)
	_is_snapped_to_station = false

func _apply_station_marker_transform(marker_transform: Transform3D) -> void:
	global_position = marker_transform.origin
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	if visual_node != null:
		visual_node.rotation.y = marker_transform.basis.get_euler().y
