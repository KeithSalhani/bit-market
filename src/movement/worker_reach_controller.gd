extends Node3D

signal reach_completed(target_position: Vector3)

@export var skeleton_path: NodePath
@export var root_bone := "RightUpperArm"
@export var tip_bone := "RightHand"
@export var rest_local_position := Vector3(0.35, 1.05, 0.18)
@export var use_current_hand_as_rest := true
@export var hand_target_rotation_degrees := Vector3(-90.0, 0.0, 0.0)
@export var reach_duration := 0.45
@export var place_duration := 0.3
@export var hold_duration := 0.2

var _skeleton: Skeleton3D
var _ik: SkeletonIK3D
var _target: Node3D
var _ready_for_reach := false
var _tip_bone_index := -1
var _timing_scale := 1.0

func _ready() -> void:
	_ready_for_reach = _configure_ik()

func can_reach() -> bool:
	return _ready_for_reach

func set_timing_scale(value: float) -> void:
	_timing_scale = maxf(value, 0.05)

func reset_timing_scale() -> void:
	_timing_scale = 1.0

func reach_to(target_position: Vector3) -> bool:
	if not _ready_for_reach:
		push_warning("Worker reach controller cannot run: right-hand IK is not configured.")
		return false

	_ik.start()
	var rest_position := _get_rest_global_position()
	_apply_target_pose(rest_position)
	await _tween_target(target_position, _scaled_duration(reach_duration))
	await get_tree().create_timer(_scaled_duration(hold_duration)).timeout
	reach_completed.emit(target_position)
	await _tween_target(rest_position, _scaled_duration(reach_duration))
	_ik.stop()
	return true

func pick_and_place(
	pickup_position: Vector3,
	place_position: Vector3,
	requested_return_position: Variant = null,
	requested_hand_rotation_degrees: Variant = null
) -> bool:
	if not _ready_for_reach:
		push_warning("Worker reach controller cannot run: right-hand IK is not configured.")
		return false

	_ik.start()
	var rest_position := _get_rest_global_position()
	var return_position := rest_position
	if requested_return_position is Vector3:
		return_position = requested_return_position
	var target_rotation_degrees := hand_target_rotation_degrees
	if requested_hand_rotation_degrees is Vector3:
		target_rotation_degrees = requested_hand_rotation_degrees
	_apply_target_pose(rest_position, target_rotation_degrees)
	await _tween_target(pickup_position, _scaled_duration(reach_duration), target_rotation_degrees)
	await get_tree().create_timer(_scaled_duration(hold_duration)).timeout
	await _tween_target(place_position, _scaled_duration(place_duration), target_rotation_degrees)
	await get_tree().create_timer(_scaled_duration(hold_duration)).timeout
	reach_completed.emit(place_position)
	await _tween_target(return_position, _scaled_duration(reach_duration), target_rotation_degrees)
	_ik.stop()
	return true

func _configure_ik() -> bool:
	_skeleton = _resolve_skeleton()
	if _skeleton == null:
		push_warning("Worker reach controller cannot find a Skeleton3D.")
		return false

	var root_index := _skeleton.find_bone(root_bone)
	var tip_index := _skeleton.find_bone(tip_bone)
	if root_index == -1 or tip_index == -1:
		push_warning("Worker reach controller cannot find right-hand IK bones '%s' -> '%s'." % [root_bone, tip_bone])
		return false
	_tip_bone_index = tip_index

	_target = Node3D.new()
	_target.name = "RightHandIKTarget"
	add_child(_target)
	_target.position = rest_local_position

	_ik = SkeletonIK3D.new()
	_ik.name = "RightHandSkeletonIK"
	_ik.root_bone = root_bone
	_ik.tip_bone = tip_bone
	_skeleton.add_child(_ik)
	_ik.target_node = _ik.get_path_to(_target)
	_ik.interpolation = 1.0
	if _has_property(_ik, "override_tip_basis"):
		_ik.set("override_tip_basis", true)
	_ik.stop()
	return true

func _resolve_skeleton() -> Skeleton3D:
	var configured := get_node_or_null(skeleton_path) as Skeleton3D
	if configured != null:
		return configured
	return _find_skeleton(get_parent())

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

func _get_rest_global_position() -> Vector3:
	if use_current_hand_as_rest and _skeleton != null and _tip_bone_index != -1:
		var hand_pose := _skeleton.get_bone_global_pose(_tip_bone_index)
		return _skeleton.global_transform * hand_pose.origin
	return global_transform * rest_local_position

func _tween_target(target_position: Vector3, duration: float, target_rotation_degrees: Vector3 = hand_target_rotation_degrees) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_target, "global_transform", _get_target_transform(target_position, target_rotation_degrees), duration)
	await tween.finished

func _scaled_duration(duration: float) -> float:
	return maxf(0.01, duration * _timing_scale)

func _apply_target_pose(target_position: Vector3, target_rotation_degrees: Vector3 = hand_target_rotation_degrees) -> void:
	_target.global_transform = _get_target_transform(target_position, target_rotation_degrees)

func _get_target_transform(target_position: Vector3, target_rotation_degrees: Vector3 = hand_target_rotation_degrees) -> Transform3D:
	var target_basis := Basis.from_euler(Vector3(
		deg_to_rad(target_rotation_degrees.x),
		deg_to_rad(target_rotation_degrees.y),
		deg_to_rad(target_rotation_degrees.z)
	))
	return Transform3D(target_basis, target_position)

func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true
	return false
