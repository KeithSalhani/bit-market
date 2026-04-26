extends Node3D

@export var snap_point_path: NodePath = ^"WorkerPrepSnapPoint"
@export var entrance_point_path: NodePath = ^"WorkerPrepEntrancePoint"
@export var exit_point_path: NodePath = ^"WorkerPrepExitPoint"
@export var assembly_point_path: NodePath = ^"BurgerAssemblyPoint"
@export var prep_shelf_path: NodePath = ^".."
@export var layer_spacing := 0.24
@export var burger_scale := Vector3(0.0035, 0.0035, 0.0035)
@export var layer_scale := 0.1
@export var ingredient_contact_height := 0.12
@export var ingredient_front_offset := 0.16
@export var burger_place_height := 0.18
@export var default_recipe := PackedStringArray(["meat", "cheese", "pickles", "onion", "lettuce"])

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

var _current_burger: Node3D
var _using_explicit_reach_target := false

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
	var assembly_point := get_assembly_point()
	if assembly_point == null:
		push_warning("Burger prep station cannot assemble: BurgerAssemblyPoint is missing.")
		return false

	var reach_controller := _get_reach_controller(worker)
	if reach_controller == null or not reach_controller.has_method("can_reach") or not bool(reach_controller.call("can_reach")):
		push_warning("Burger prep station cannot assemble: selected worker has no configured right-hand IK reach controller.")
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

		var pickup_position := target.global_position if _using_explicit_reach_target else _get_ingredient_contact_position(target)
		var place_position := _get_burger_place_position(layer_index)
		if reach_controller.has_method("pick_and_place"):
			await reach_controller.call("pick_and_place", pickup_position, place_position)
		else:
			await reach_controller.call("reach_to", pickup_position)
			await reach_controller.call("reach_to", place_position)
		_spawn_layer(ingredient_name, layer_index)
		layer_index += 1

	_spawn_layer("top_bun", layer_index)
	return true

func _spawn_layer(layer_name: String, layer_index: int) -> void:
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

func _get_layer_transform(layer_index: int, _layer_name: String) -> Transform3D:
	var layer_basis := Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * layer_scale)
	return Transform3D(layer_basis, Vector3(0.0, float(layer_index) * layer_spacing, 0.0))

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
