extends Node

@export var burger_storage_point_path: NodePath = ^"Shelf_C_001/BurgerStoragePoint"
@export var burger_capacity := 8
@export var burger_column_spacing := 0.18
@export var burger_row_spacing := 0.16

var _stored_food_items: Array[Node3D] = []

func _ready() -> void:
	_resize_storage()

func has_burger_capacity() -> bool:
	return has_food_capacity()

func get_available_burger_capacity() -> int:
	return get_available_food_capacity()

func get_next_burger_position() -> Vector3:
	return get_next_food_position()

func store_burger(burger: Node3D) -> bool:
	return store_food_item(burger)

func has_food_capacity() -> bool:
	_resize_storage()
	return _get_next_open_slot() != -1

func get_available_food_capacity() -> int:
	_resize_storage()
	var open_slots := 0
	for index in range(_stored_food_items.size()):
		var food_item := _stored_food_items[index]
		if food_item == null or not is_instance_valid(food_item):
			_stored_food_items[index] = null
			open_slots += 1
	return open_slots

func get_first_food_item() -> Node3D:
	return get_first_food_item_by_type("")

func get_first_food_item_by_type(food_type: String = "") -> Node3D:
	for index in range(_stored_food_items.size()):
		var food_item := _stored_food_items[index]
		if food_item != null and is_instance_valid(food_item) and _food_item_matches_type(food_item, food_type):
			_stored_food_items[index] = null
			return food_item
	return null

func has_food_item(food_type: String = "") -> bool:
	for index in range(_stored_food_items.size()):
		var food_item := _stored_food_items[index]
		if food_item != null and is_instance_valid(food_item) and _food_item_matches_type(food_item, food_type):
			return true
		if food_item != null and not is_instance_valid(food_item):
			_stored_food_items[index] = null
	return false

func get_next_food_position() -> Vector3:
	var slot_index := _get_next_open_slot()
	if slot_index == -1:
		var storage_point := get_burger_storage_point()
		if storage_point != null:
			return storage_point.global_position
		return Vector3.ZERO
	return _get_slot_position(slot_index)

func store_food_item(food_item: Node3D, food_type: String = "") -> bool:
	if food_item == null or not is_instance_valid(food_item):
		return false

	var slot_index := _get_next_open_slot()
	if slot_index == -1:
		return false

	if food_type.is_empty():
		food_type = _infer_food_type(food_item)
	if not food_type.is_empty():
		food_item.set_meta("food_type", food_type)

	var stored_global_scale := food_item.scale
	if food_item.is_inside_tree():
		stored_global_scale = food_item.global_transform.basis.get_scale()
		food_item.reparent(self, true)
	else:
		add_child(food_item)

	food_item.global_position = _get_slot_position(slot_index)
	food_item.global_rotation = Vector3.ZERO
	if food_item.is_inside_tree():
		_apply_global_scale(food_item, stored_global_scale)
	food_item.visible = true
	_stored_food_items[slot_index] = food_item
	return true

func _food_item_matches_type(food_item: Node3D, food_type: String) -> bool:
	if food_type.is_empty():
		return true
	return _infer_food_type(food_item) == food_type

func _infer_food_type(food_item: Node3D) -> String:
	if food_item.has_meta("food_type"):
		return String(food_item.get_meta("food_type"))

	var normalized_name := String(food_item.name).to_lower()
	if normalized_name.contains("fries"):
		return "fries"
	if normalized_name.contains("burger"):
		return "burger"
	return ""

func get_worker_stand_point() -> Node3D:
	return _find_named_descendant(self, "workerstandpoint") as Node3D

func get_burger_storage_point() -> Node3D:
	var configured := get_node_or_null(burger_storage_point_path) as Node3D
	if configured != null:
		return configured
	return _find_named_descendant(self, "burgerstoragepoint") as Node3D

func _resize_storage() -> void:
	var capacity: int = maxi(burger_capacity, 0)
	if _stored_food_items.size() != capacity:
		_stored_food_items.resize(capacity)

func _get_next_open_slot() -> int:
	_resize_storage()
	for index in range(_stored_food_items.size()):
		var food_item := _stored_food_items[index]
		if food_item == null or not is_instance_valid(food_item):
			_stored_food_items[index] = null
			return index
	return -1

func _get_slot_position(slot_index: int) -> Vector3:
	var storage_point := get_burger_storage_point()
	if storage_point == null:
		return Vector3.ZERO

	var column := floori(float(slot_index) / 2.0)
	var row_sign := -1.0 if slot_index % 2 == 0 else 1.0
	var row_offset := row_sign * burger_row_spacing * 0.5
	var offset := Vector3(float(column) * burger_column_spacing, 0.0, row_offset)
	return storage_point.global_transform * offset

func _find_named_descendant(node: Node, normalized_name: String) -> Node:
	if String(node.name).to_lower() == normalized_name:
		return node
	for child in node.get_children():
		var found := _find_named_descendant(child, normalized_name)
		if found != null:
			return found
	return null

func _apply_global_scale(node: Node3D, target_global_scale: Vector3) -> void:
	var current_global_scale := node.global_transform.basis.get_scale()
	node.scale = Vector3(
		_get_adjusted_local_scale(node.scale.x, current_global_scale.x, target_global_scale.x),
		_get_adjusted_local_scale(node.scale.y, current_global_scale.y, target_global_scale.y),
		_get_adjusted_local_scale(node.scale.z, current_global_scale.z, target_global_scale.z)
	)

func _get_adjusted_local_scale(local_scale: float, current_global_scale: float, target_global_scale: float) -> float:
	if absf(current_global_scale) <= 0.0001:
		return local_scale
	return local_scale * target_global_scale / current_global_scale
