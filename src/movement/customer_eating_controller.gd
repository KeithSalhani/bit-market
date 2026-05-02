extends Node3D

@export var root_bone := "RightUpperArm"
@export var tip_bone := "RightHand"
@export var head_bone := "Head"
@export var right_shoulder_bone := "RightShoulder"
@export_range(0.0, 1.0, 0.05) var shoulder_to_head_amount := 0.62
@export_range(0.0, 1.0, 0.05) var hand_to_bite_amount := 0.72
@export var bite_height_offset := -0.02
@export var bite_forward_offset := 0.08
@export var rest_forward_clearance := 0.12
@export var bite_forward_clearance := 0.18
@export var hand_target_rotation_degrees := Vector3(-35.0, 35.0, 90.0)
@export var raise_duration := 0.5
@export var mouth_hold_duration := 0.25
@export var lower_duration := 0.42
@export var rest_hold_duration := 0.35

var _skeleton: Skeleton3D
var _ik: SkeletonIK3D
var _target: Node3D
var _active := false
var _loop_id := 0
var _root_bone_index := -1
var _tip_bone_index := -1
var _head_bone_index := -1
var _right_shoulder_bone_index := -1

func start_eating() -> void:
	if _active:
		return
	if not _configure_ik():
		return

	_active = true
	_loop_id += 1
	_ik.start()
	_run_eating_loop(_loop_id)

func stop_eating() -> void:
	_active = false
	_loop_id += 1
	if _ik != null:
		_ik.stop()

func _run_eating_loop(loop_id: int) -> void:
	while _active and loop_id == _loop_id and is_inside_tree():
		var rest_position := _get_rest_global_position()
		var bite_position := _get_bite_global_position(rest_position)
		_apply_target_pose(rest_position)
		await _tween_target(bite_position, raise_duration)
		if not _loop_is_current(loop_id):
			break
		await get_tree().create_timer(mouth_hold_duration).timeout
		if not _loop_is_current(loop_id):
			break
		await _tween_target(rest_position, lower_duration)
		if not _loop_is_current(loop_id):
			break
		await get_tree().create_timer(rest_hold_duration).timeout

	if _loop_is_current(loop_id):
		stop_eating()

func _loop_is_current(loop_id: int) -> bool:
	return _active and loop_id == _loop_id and is_inside_tree()

func _configure_ik() -> bool:
	_skeleton = _resolve_skeleton()
	if _skeleton == null:
		push_warning("Customer eating controller cannot find a Skeleton3D.")
		return false

	if _ik != null and is_instance_valid(_ik) and _target != null and is_instance_valid(_target):
		return true

	_root_bone_index = _skeleton.find_bone(root_bone)
	_tip_bone_index = _skeleton.find_bone(tip_bone)
	_head_bone_index = _skeleton.find_bone(head_bone)
	_right_shoulder_bone_index = _skeleton.find_bone(right_shoulder_bone)
	if _root_bone_index == -1 or _tip_bone_index == -1 or _head_bone_index == -1 or _right_shoulder_bone_index == -1:
		push_warning("Customer eating controller cannot find bones '%s', '%s', '%s', '%s'." % [root_bone, tip_bone, head_bone, right_shoulder_bone])
		return false

	_target = Node3D.new()
	_target.name = "RightHandEatingIKTarget"
	add_child(_target)
	_target.global_transform = _get_target_transform(_get_rest_global_position())

	_ik = SkeletonIK3D.new()
	_ik.name = "RightHandEatingSkeletonIK"
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
	var parent := get_parent()
	return _find_skeleton(parent)

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
	var rest_position := _get_tip_global_position()
	return _apply_chest_clearance(rest_position, rest_forward_clearance)

func _get_bite_global_position(rest_position: Vector3) -> Vector3:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return rest_position
	if _head_bone_index == -1 or _right_shoulder_bone_index == -1:
		return rest_position
	var head_transform := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone_index)
	var shoulder_transform := _skeleton.global_transform * _skeleton.get_bone_global_pose(_right_shoulder_bone_index)
	var character_basis := _get_character_basis()
	var bite_anchor := shoulder_transform.origin.lerp(head_transform.origin, shoulder_to_head_amount)
	bite_anchor += character_basis.y.normalized() * bite_height_offset
	bite_anchor += character_basis.z.normalized() * bite_forward_offset
	if bite_anchor.y > head_transform.origin.y + bite_height_offset:
		bite_anchor.y = head_transform.origin.y + bite_height_offset
	var bite_position := rest_position.lerp(bite_anchor, hand_to_bite_amount)
	return _apply_chest_clearance(bite_position, bite_forward_clearance)

func _get_tip_global_position() -> Vector3:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return global_position
	if _tip_bone_index == -1:
		return global_position
	var tip_transform := _skeleton.global_transform * _skeleton.get_bone_global_pose(_tip_bone_index)
	return tip_transform.origin

func _get_character_basis() -> Basis:
	var parent_3d := get_parent() as Node3D
	if parent_3d == null:
		return global_transform.basis
	return parent_3d.global_transform.basis

func _apply_chest_clearance(position: Vector3, clearance: float) -> Vector3:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return position
	if _root_bone_index == -1:
		return position
	var root_transform := _skeleton.global_transform * _skeleton.get_bone_global_pose(_root_bone_index)
	var character_basis := _get_character_basis()
	var forward := character_basis.z.normalized()
	var from_chest := position - root_transform.origin
	var forward_distance := from_chest.dot(forward)
	if forward_distance < clearance:
		position += forward * (clearance - forward_distance)
	return position

func _tween_target(target_position: Vector3, duration: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var start_transform := _target.global_transform
	var end_transform := _get_target_transform(target_position)
	var elapsed := 0.0
	var safe_duration := maxf(duration, 0.001)
	while _active and elapsed < safe_duration and is_inside_tree():
		var t := elapsed / safe_duration
		var eased_t := 0.5 - cos(t * PI) * 0.5
		_target.global_transform = start_transform.interpolate_with(end_transform, eased_t)
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if _active and is_inside_tree():
		_target.global_transform = end_transform

func _apply_target_pose(target_position: Vector3) -> void:
	if _target != null and is_instance_valid(_target):
		_target.global_transform = _get_target_transform(target_position)

func _get_target_transform(target_position: Vector3) -> Transform3D:
	var target_basis := Basis.from_euler(Vector3(
		deg_to_rad(hand_target_rotation_degrees.x),
		deg_to_rad(hand_target_rotation_degrees.y),
		deg_to_rad(hand_target_rotation_degrees.z)
	))
	return Transform3D(target_basis, target_position)

func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true
	return false
