extends Node3D

const VFX := preload("res://src/world/restaurant_vfx_factory.gd")

@export var snap_point_path: NodePath = ^"WorkerPrepSnapPoint"
@export var entrance_point_path: NodePath = ^"WorkerPrepEntrancePoint"
@export var exit_point_path: NodePath = ^"WorkerPrepExitPoint"
@export var assembly_point_path: NodePath = ^"BurgerAssemblyPoint"
@export var storage_point_path: NodePath = ^"BurgerStoragePoint"
@export var prep_shelf_path: NodePath = ^".."
@export var grill_station_path: NodePath = ^"../../../Grills/Grill_002/Grill002Station"
@export var cooked_meat_stock := 0
@export var layer_spacing := 0.24
@export var burger_scale := Vector3(0.0035, 0.0035, 0.0035)
@export var finished_burger_scale_multiplier := 0.65
@export var layer_scale := 0.1
@export var ingredient_contact_height := 0.12
@export var ingredient_front_offset := 0.16
@export var burger_place_height := 0.18
@export var prep_hand_target_rotation_degrees := Vector3(-90.0, 0.0, 90.0)
@export var burger_storage_spacing := Vector2(0.22, 0.22)
@export var default_recipe := PackedStringArray(["meat", "cheese", "pickles", "onion", "lettuce"])
@export var station_vfx_enabled := true
@export_range(0.25, 2.0, 0.05) var particle_quality_scale := 1.0

const FOOD_SCENES := {
	"bottom_bun": preload("res://scenes/props/food/bottom_bun.tscn"),
	"meat": preload("res://scenes/props/food/meat.tscn"),
	"cheese": preload("res://scenes/props/food/cheese.tscn"),
	"pickles": preload("res://scenes/props/food/pickles.tscn"),
	"onion": preload("res://scenes/props/food/onion.tscn"),
	"lettuce": preload("res://scenes/props/food/lettuce.tscn"),
	"tomato": preload("res://scenes/props/food/tomato.tscn"),
	"top_bun": preload("res://scenes/props/food/top_bun.tscn"),
}
const FINISHED_BURGER_SCENE := preload("res://scenes/props/food/burger.tscn")

var _current_burger: Node3D
var _stored_burgers: Array[Node3D] = []
var _full_label: Label3D
var _using_explicit_reach_target := false
var _is_busy := false
var _reserved_worker: Node = null
static var _shared_cooked_meat_stock := 0

func _ready() -> void:
	if cooked_meat_stock > 0:
		_shared_cooked_meat_stock = maxi(_shared_cooked_meat_stock, cooked_meat_stock)
	_prepare_storage_visuals()

func is_available() -> bool:
	return not _is_busy

func reserve_for(worker: Node) -> bool:
	if _is_busy and _reserved_worker != worker:
		return false
	_is_busy = true
	_reserved_worker = worker
	return true

func release_reservation(worker: Node = null) -> void:
	if worker != null and _reserved_worker != null and _reserved_worker != worker:
		return
	_is_busy = false
	_reserved_worker = null

func get_stand_point() -> Node3D:
	return get_snap_point()

func get_snap_point() -> Node3D:
	var snap_point := get_node_or_null(snap_point_path) as Node3D
	if snap_point != null:
		return snap_point
	return get_node_or_null(^"WorkerPrepStandPoint") as Node3D

func get_entrance_point() -> Node3D:
	var entrance_point := get_node_or_null(entrance_point_path) as Node3D
	if entrance_point != null:
		return entrance_point
	return get_snap_point()

func get_exit_point() -> Node3D:
	var exit_point := get_node_or_null(exit_point_path) as Node3D
	if exit_point != null:
		return exit_point
	return get_entrance_point()

func get_assembly_point() -> Node3D:
	return get_node_or_null(assembly_point_path) as Node3D

func get_storage_point() -> Node3D:
	return get_node_or_null(storage_point_path) as Node3D

func get_look_target() -> Vector3:
	var assembly_point := get_assembly_point()
	if assembly_point != null:
		return assembly_point.global_position

	var prep_shelf := get_node_or_null(prep_shelf_path) as Node3D
	if prep_shelf != null:
		return prep_shelf.global_position

	return global_position

func assemble_default_burger(worker: Node) -> bool:
	return await assemble_burger(worker, default_recipe)

func assemble_burger(worker: Node, recipe: PackedStringArray) -> bool:
	if _is_busy and _reserved_worker != worker:
		return false
	var auto_reserved := false
	if not _is_busy:
		if not reserve_for(worker):
			return false
		auto_reserved = true

	if is_burger_storage_full():
		show_storage_full()
		_release_auto_reservation(worker, auto_reserved)
		return false

	var assembly_point := get_assembly_point()
	if assembly_point == null:
		push_warning("Burger prep station cannot assemble: BurgerAssemblyPoint is missing.")
		_release_auto_reservation(worker, auto_reserved)
		return false

	var reach_controller := _get_reach_controller(worker)
	if reach_controller == null or not reach_controller.has_method("can_reach") or not bool(reach_controller.call("can_reach")):
		push_warning("Burger prep station cannot assemble: selected worker has no configured right-hand IK reach controller.")
		_release_auto_reservation(worker, auto_reserved)
		return false

	_clear_current_burger()
	_current_burger = Node3D.new()
	_current_burger.name = "AssembledBurger"
	add_child(_current_burger)
	_current_burger.global_position = assembly_point.global_position
	_current_burger.global_rotation = Vector3.ZERO
	_current_burger.scale = burger_scale

	var layer_index := 0
	_spawn_layer("bottom_bun", layer_index)
	layer_index += 1

	for ingredient in recipe:
		var ingredient_name := String(ingredient)
		var target := _find_ingredient_target(ingredient_name)
		if target == null:
			push_warning("Burger prep station skipped '%s': ingredient reach target is missing." % ingredient_name)
			continue

		if ingredient_name == "meat" and not await ensure_cooked_meat(worker, reach_controller):
			_release_auto_reservation(worker, auto_reserved)
			return false

		var pickup_position := target.global_position if _using_explicit_reach_target else _get_ingredient_contact_position(target)
		var place_position := _get_burger_place_position(layer_index)
		if reach_controller.has_method("pick_and_place"):
			await reach_controller.call("pick_and_place", pickup_position, place_position, place_position, prep_hand_target_rotation_degrees)
		else:
			await reach_controller.call("reach_to", pickup_position)
			await reach_controller.call("reach_to", place_position)
		if ingredient_name == "meat":
			consume_cooked_meat()
		_spawn_layer(ingredient_name, layer_index)
		layer_index += 1

	_spawn_layer("top_bun", layer_index)
	_replace_with_finished_burger(assembly_point)
	await _store_finished_burger(worker, reach_controller)
	_release_auto_reservation(worker, auto_reserved)
	return true

func is_burger_storage_full() -> bool:
	return _get_stored_burger_count() >= _get_storage_capacity() and _current_burger != null

func show_storage_full() -> void:
	_prepare_storage_visuals()
	if _full_label == null:
		return
	_full_label.visible = true
	var tween := create_tween()
	tween.tween_property(_full_label, "modulate:a", 1.0, 0.05)
	tween.tween_interval(1.0)
	tween.tween_property(_full_label, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void:
		if _full_label != null:
			_full_label.visible = false
	)

func has_finished_burger() -> bool:
	return _peek_next_finished_burger() != null

func get_finished_burger_count() -> int:
	var count := 0
	if _current_burger != null and is_instance_valid(_current_burger):
		count += 1

	for index in range(_stored_burgers.size()):
		var burger := _stored_burgers[index]
		if burger != null and is_instance_valid(burger):
			count += 1
		else:
			_stored_burgers[index] = null
	return count

func debug_add_cooked_meat(amount := 4) -> void:
	stock_cooked_meat(amount)

func debug_create_finished_burger() -> bool:
	if is_burger_storage_full():
		show_storage_full()
		return false

	var assembly_point := get_assembly_point()
	if assembly_point == null:
		push_warning("Burger prep station cannot debug-create burger: BurgerAssemblyPoint is missing.")
		return false

	if _current_burger != null and is_instance_valid(_current_burger):
		await _store_finished_burger(null, null)
	if _current_burger != null and is_instance_valid(_current_burger):
		show_storage_full()
		return false

	_replace_with_finished_burger(assembly_point)
	await _store_finished_burger(null, null)
	return true

func pick_finished_burger_for_transport(worker: Node) -> Node3D:
	if _is_busy and _reserved_worker != worker:
		return null

	var burger := _peek_next_finished_burger()
	if burger == null:
		return null

	var reach_controller := _get_reach_controller(worker)
	if reach_controller != null and reach_controller.has_method("reach_to"):
		await reach_controller.call("reach_to", burger.global_position)

	_remove_finished_burger_from_storage(burger)
	burger.visible = false
	return burger

func stock_cooked_meat(amount: int) -> void:
	_shared_cooked_meat_stock = maxi(_shared_cooked_meat_stock + amount, 0)
	cooked_meat_stock = _shared_cooked_meat_stock

func get_cooked_meat_stock() -> int:
	return _shared_cooked_meat_stock

func has_cooked_meat() -> bool:
	return _shared_cooked_meat_stock > 0

func get_grill_station() -> Node3D:
	return _get_grill_station()

func consume_cooked_meat(amount := 1) -> bool:
	if _shared_cooked_meat_stock < amount:
		return false
	_shared_cooked_meat_stock -= amount
	cooked_meat_stock = _shared_cooked_meat_stock
	return true

func ensure_cooked_meat(worker: Node, reach_controller: Node = null) -> bool:
	if _shared_cooked_meat_stock > 0:
		return true

	# We no longer want the prep station to forcefully cook the meat itself.
	# We want the task manager to handle COOK_MEAT tasks explicitly.
	return false

func _spawn_layer(layer_name: String, layer_index: int) -> void:
	if _current_burger == null or not is_instance_valid(_current_burger):
		push_warning("Burger prep station cannot add '%s': no active assembled burger." % layer_name)
		return

	if not FOOD_SCENES.has(layer_name):
		push_warning("Burger prep station has no prop scene for '%s'." % layer_name)
		return

	var layer := FOOD_SCENES[layer_name].instantiate() as Node3D
	if layer == null:
		push_warning("Burger prep station prop '%s' did not instantiate as Node3D." % layer_name)
		return

	layer.name = layer_name
	_current_burger.add_child(layer)
	layer.transform = _get_layer_transform(layer_index, layer_name)
	_spawn_ingredient_burst(layer_name, _get_burger_place_position(layer_index))

func _release_auto_reservation(worker: Node, auto_reserved: bool) -> void:
	if auto_reserved:
		release_reservation(worker)

func _get_layer_transform(layer_index: int, _layer_name: String) -> Transform3D:
	var layer_basis := Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * layer_scale)
	return Transform3D(layer_basis, Vector3(0.0, float(layer_index) * layer_spacing, 0.0))

func _replace_with_finished_burger(assembly_point: Node3D) -> void:
	_clear_current_burger()
	var finished_burger := FINISHED_BURGER_SCENE.instantiate() as Node3D
	if finished_burger == null:
		push_warning("Burger prep station finished burger scene did not instantiate as Node3D.")
		return

	finished_burger.name = "AssembledBurger"
	add_child(finished_burger)
	finished_burger.global_position = assembly_point.global_position
	finished_burger.global_rotation = Vector3.ZERO
	finished_burger.scale *= finished_burger_scale_multiplier
	_current_burger = finished_burger
	_spawn_finished_burger_vfx(assembly_point.global_position)

func _store_finished_burger(worker: Node, reach_controller: Node) -> bool:
	if _current_burger == null or not is_instance_valid(_current_burger):
		return false
	var finished_burger := _current_burger

	var slot_index := _get_next_storage_slot_index()
	if slot_index == -1:
		return false

	var assembly_point := get_assembly_point()
	var storage_position := _get_storage_slot_position(slot_index)
	if assembly_point != null and reach_controller != null:
		if reach_controller.has_method("pick_and_place"):
			await reach_controller.call("pick_and_place", assembly_point.global_position, storage_position)
		else:
			await reach_controller.call("reach_to", assembly_point.global_position)
			await reach_controller.call("reach_to", storage_position)

	if not is_instance_valid(finished_burger):
		return false

	finished_burger.global_position = storage_position
	finished_burger.global_rotation = Vector3.ZERO
	_stored_burgers[slot_index] = finished_burger
	_spawn_finished_burger_vfx(storage_position)
	if _current_burger == finished_burger:
		_current_burger = null
	return true

func _prepare_storage_visuals() -> void:
	if _stored_burgers.size() != _get_storage_capacity():
		_stored_burgers.resize(_get_storage_capacity())

	var storage_point := get_storage_point()
	if storage_point == null or _full_label != null:
		return

	_full_label = Label3D.new()
	_full_label.name = "BurgerStorageFullLabel"
	_full_label.text = "Full!"
	_full_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_full_label.font_size = 72
	_full_label.modulate = Color(1.0, 0.15, 0.08, 0.0)
	_full_label.outline_size = 8
	_full_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_full_label.position = Vector3(0.0, 0.35, 0.0)
	_full_label.visible = false
	storage_point.add_child(_full_label)

func _get_storage_capacity() -> int:
	return 4

func _get_stored_burger_count() -> int:
	var count := 0
	for index in range(_stored_burgers.size()):
		var burger := _stored_burgers[index]
		if burger != null and is_instance_valid(burger):
			count += 1
		else:
			_stored_burgers[index] = null
	return count

func _get_next_storage_slot_index() -> int:
	if _stored_burgers.size() != _get_storage_capacity():
		_stored_burgers.resize(_get_storage_capacity())

	for index in range(_stored_burgers.size()):
		var burger := _stored_burgers[index]
		if burger == null or not is_instance_valid(burger):
			_stored_burgers[index] = null
			return index
	return -1

func _peek_next_finished_burger() -> Node3D:
	if _current_burger != null and is_instance_valid(_current_burger):
		return _current_burger

	for index in range(_stored_burgers.size() - 1, -1, -1):
		var burger := _stored_burgers[index]
		if burger != null and is_instance_valid(burger):
			return burger
		_stored_burgers[index] = null
	return null

func _remove_finished_burger_from_storage(burger: Node3D) -> void:
	if _current_burger == burger:
		_current_burger = null
	for index in range(_stored_burgers.size()):
		if _stored_burgers[index] == burger:
			_stored_burgers[index] = null
			return

func _get_storage_slot_position(slot_index: int) -> Vector3:
	var storage_point := get_storage_point()
	if storage_point == null:
		return global_position

	var offsets := [
		Vector3(-burger_storage_spacing.x, 0.0, -burger_storage_spacing.y),
		Vector3(burger_storage_spacing.x, 0.0, -burger_storage_spacing.y),
		Vector3(-burger_storage_spacing.x, 0.0, burger_storage_spacing.y),
		Vector3(burger_storage_spacing.x, 0.0, burger_storage_spacing.y),
	]
	return storage_point.global_transform * offsets[clampi(slot_index, 0, offsets.size() - 1)]

func _find_ingredient_target(ingredient_name: String) -> Node3D:
	var direct := find_child("WorkerReachTarget_" + ingredient_name.capitalize(), true, false) as Node3D
	if direct != null:
		_using_explicit_reach_target = true
		return direct

	_using_explicit_reach_target = false
	var prep_shelf := get_node_or_null(prep_shelf_path) as Node3D
	if prep_shelf == null:
		return null

	var shelf_item := prep_shelf.find_child(ingredient_name, true, false) as Node3D
	if shelf_item != null:
		return shelf_item

	if ingredient_name == "meat":
		return get_node_or_null(^"WorkerReachTarget_Meat") as Node3D

	return null

func _get_ingredient_contact_position(target: Node3D) -> Vector3:
	var contact_position := target.global_position + Vector3.UP * ingredient_contact_height
	var stand_point := get_stand_point()
	if stand_point == null:
		return contact_position

	var toward_worker := stand_point.global_position - target.global_position
	toward_worker.y = 0.0
	if toward_worker.length() <= 0.01:
		return contact_position
	return contact_position + toward_worker.normalized() * ingredient_front_offset

func _get_burger_place_position(layer_index: int) -> Vector3:
	var assembly_point := get_assembly_point()
	if assembly_point == null:
		return global_position
	return assembly_point.global_position + Vector3.UP * (burger_place_height + float(layer_index) * layer_spacing * burger_scale.y)

func _get_raw_meat_pickup_position() -> Vector3:
	var target := _find_ingredient_target("meat")
	if target == null:
		return global_position
	return target.global_position if _using_explicit_reach_target else _get_ingredient_contact_position(target)

func _get_grill_station() -> Node3D:
	return get_node_or_null(grill_station_path) as Node3D

func _navigate_worker_to(worker: Node, target_position: Vector3, look_target: Vector3) -> bool:
	if worker == null:
		return false

	var navigation_map := get_world_3d().navigation_map
	var closest_point := NavigationServer3D.map_get_closest_point(navigation_map, target_position)
	if worker.has_method("set_navigation_target_with_look_target"):
		worker.call("set_navigation_target_with_look_target", closest_point, look_target)
	elif worker.has_method("set_navigation_target"):
		worker.call("set_navigation_target", closest_point)
	else:
		push_warning("Burger prep station cannot move worker: worker has no navigation target API.")
		return false

	await worker.arrived_at_target
	return true

func _get_reach_controller(worker: Node) -> Node:
	if worker == null:
		return null
	var configured := worker.get_node_or_null(^"WorkerReachController")
	if configured != null:
		return configured
	return worker.find_child("WorkerReachController", true, false)

func _clear_current_burger() -> void:
	if _current_burger != null and is_instance_valid(_current_burger):
		_current_burger.queue_free()
		_current_burger = null

func _spawn_ingredient_burst(layer_name: String, global_position: Vector3) -> void:
	if not station_vfx_enabled or not is_inside_tree():
		return
	var color := _ingredient_vfx_color(layer_name)
	VFX.spawn_burst(self, global_position + Vector3.UP * 0.03, color, int(12.0 * particle_quality_scale), 0.32, 0.035, 0.18, 0.55, 0.12, 0.42, true, 0.01)

func _spawn_finished_burger_vfx(global_position: Vector3) -> void:
	if not station_vfx_enabled or not is_inside_tree():
		return
	VFX.spawn_burst(self, global_position + Vector3.UP * 0.12, Color(1.0, 0.82, 0.34, 0.72), int(22.0 * particle_quality_scale), 0.55, 0.08, 0.24, 0.72, 0.18, 0.62, true, 0.014)

func _ingredient_vfx_color(layer_name: String) -> Color:
	match layer_name:
		"meat":
			return Color(1.0, 0.34, 0.12, 0.72)
		"cheese":
			return Color(1.0, 0.86, 0.2, 0.7)
		"lettuce":
			return Color(0.45, 1.0, 0.28, 0.62)
		"pickles":
			return Color(0.55, 0.95, 0.24, 0.62)
		"onion":
			return Color(0.88, 0.78, 1.0, 0.58)
		"tomato":
			return Color(1.0, 0.18, 0.14, 0.64)
	return Color(1.0, 0.72, 0.34, 0.58)
