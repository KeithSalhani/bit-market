@tool
extends Node3D

@export_node_path("Node3D") var source_map_path: NodePath = ^"../BurgerPiz2"
@export var rebuild_in_editor := true
@export var rebuild_on_ready := true
@export var show_debug_labels := true:
	set(value):
		show_debug_labels = value
		_set_labels_visible(value)
@export var table_label_height := 1.9
@export var seat_label_height := 1.15
@export var seat_marker_height := 0.55
@export var armchair_seat_offset := 0.45
@export var approach_offset := 1.8
@export var register_approach_reference_position := Vector3(0.422, 0.0, 8.304)
@export var register_label_height := 0.8
@export var approach_marker_height := 0.08
@export var approach_dot_radius := 0.12
@export var label_pixel_size := 0.006
@export var print_summary := true

var tables: Array[Node3D] = []
var chairs: Array[Node3D] = []
var armchairs: Array[Node3D] = []
var cash_registers: Array[Node3D] = []

func _ready() -> void:
	if Engine.is_editor_hint() and not rebuild_in_editor:
		return
	if rebuild_on_ready:
		call_deferred("rebuild")

func rebuild() -> void:
	_clear_generated_children()

	var source_map := get_node_or_null(source_map_path) as Node3D
	if source_map == null:
		push_warning("SeatingMap could not find source map at path: %s" % String(source_map_path))
		return

	tables.clear()
	chairs.clear()
	armchairs.clear()
	cash_registers.clear()
	_collect_furniture(source_map)
	tables.sort_custom(_sort_nodes_by_name)
	chairs.sort_custom(_sort_nodes_by_name)
	armchairs.sort_custom(_sort_nodes_by_name)
	cash_registers.sort_custom(_sort_nodes_by_name)

	var table_groups: Array[Dictionary] = []
	for table_node in tables:
		table_groups.append({
			"table": table_node,
			"chairs": [],
			"armchairs": [],
		})

	for chair_node in chairs:
		var chair_group := _find_nearest_table_group(table_groups, chair_node.global_position)
		if not chair_group.is_empty():
			(chair_group["chairs"] as Array).append(chair_node)

	for armchair_node in armchairs:
		var armchair_group := _find_nearest_table_group(table_groups, armchair_node.global_position)
		if not armchair_group.is_empty():
			(armchair_group["armchairs"] as Array).append(armchair_node)

	for index in table_groups.size():
		_build_table_group(index + 1, table_groups[index])

	for index in cash_registers.size():
		_build_cash_register(index + 1, cash_registers[index])

	if print_summary:
		print("SeatingMap: ", tables.size(), " tables, ", chairs.size(), " chairs, ", armchairs.size(), " armchairs, ", cash_registers.size(), " cash registers")

func _collect_furniture(node: Node) -> void:
	if node is Node3D:
		var node_3d := node as Node3D
		var node_name := String(node.name)
		if _is_indexed_furniture_name(node_name, "Table"):
			tables.append(node_3d)
		elif _is_indexed_furniture_name(node_name, "Chair"):
			chairs.append(node_3d)
		elif _is_indexed_furniture_name(node_name, "Armchair"):
			armchairs.append(node_3d)
		elif _is_cash_register_name(node_name):
			cash_registers.append(node_3d)

	for child in node.get_children():
		_collect_furniture(child)

func _is_indexed_furniture_name(node_name: String, base_name: String) -> bool:
	if node_name == base_name:
		return true
	if not node_name.begins_with(base_name + "_"):
		return false

	var suffix := node_name.substr(base_name.length() + 1)
	return suffix.is_valid_int()

func _is_cash_register_name(node_name: String) -> bool:
	if node_name == "Cash_register":
		return true
	if not node_name.begins_with("Cash_register_"):
		return false

	var suffix := node_name.substr("Cash_register_".length())
	return suffix.is_valid_int()

func _build_table_group(table_number: int, table_group: Dictionary) -> void:
	var source_table := table_group["table"] as Node3D
	var table_root := Node3D.new()
	table_root.name = "Table_%02d" % table_number
	add_child(table_root)
	table_root.global_position = source_table.global_position
	table_root.set_meta("source_table", source_table.get_path())

	_add_label(table_root, "Label_Table_%02d" % table_number, "Table %02d" % table_number, source_table.global_position + Vector3.UP * table_label_height)

	var source_chairs := table_group["chairs"] as Array
	source_chairs.sort_custom(_sort_nodes_clockwise.bind(source_table.global_position))
	var source_armchairs := table_group["armchairs"] as Array
	source_armchairs.sort_custom(_sort_nodes_clockwise.bind(source_table.global_position))
	var approach_markers := _build_approach_markers(table_root, table_number, source_table)

	var seat_number := 1
	for source_chair in source_chairs:
		var chair_node := source_chair as Node3D
		_add_seat(table_root, table_number, seat_number, chair_node, chair_node.global_position, chair_node.global_transform.basis, approach_markers)
		seat_number += 1

	for source_armchair in source_armchairs:
		var armchair_node := source_armchair as Node3D
		var armchair_basis := armchair_node.global_transform.basis
		var side_axis := armchair_basis.x.normalized()
		_add_seat(table_root, table_number, seat_number, armchair_node, armchair_node.global_position - side_axis * armchair_seat_offset, armchair_basis, approach_markers)
		seat_number += 1
		_add_seat(table_root, table_number, seat_number, armchair_node, armchair_node.global_position + side_axis * armchair_seat_offset, armchair_basis, approach_markers)
		seat_number += 1

	table_root.set_meta("seat_count", seat_number - 1)
	table_root.set_meta("chair_count", source_chairs.size())
	table_root.set_meta("armchair_count", source_armchairs.size())
	table_root.set_meta("approach_count", approach_markers.size())

func _build_cash_register(register_number: int, source_register: Node3D) -> void:
	var register_root := Node3D.new()
	register_root.name = "CashRegister_%02d" % register_number
	add_child(register_root)
	register_root.global_position = source_register.global_position
	register_root.set_meta("source_register", source_register.get_path())
	register_root.set_meta("register_id", register_number)

	_add_label(
		register_root,
		"Label_CashRegister_%02d" % register_number,
		"Register %02d" % register_number,
		source_register.global_position + Vector3.UP * register_label_height,
		Color(1.0, 0.9, 0.05, 1.0)
	)

	var approach_marker := Marker3D.new()
	approach_marker.name = "CashRegister_%02d_Approach" % register_number
	register_root.add_child(approach_marker)
	approach_marker.global_position = Vector3(
		source_register.global_position.x,
		register_approach_reference_position.y + approach_marker_height,
		register_approach_reference_position.z
	)
	approach_marker.set_meta("register_id", register_number)

	_add_editor_red_dot(approach_marker)

func _build_approach_markers(parent: Node3D, table_number: int, source_table: Node3D) -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	var table_position := source_table.global_position
	var side_axis := source_table.global_transform.basis.x.normalized()
	if side_axis == Vector3.ZERO:
		side_axis = Vector3.RIGHT

	var candidate_a := _project_to_navigation(table_position + side_axis * approach_offset)
	var candidate_b := _project_to_navigation(table_position - side_axis * approach_offset)

	if table_number >= 5 and table_number <= 10:
		markers.append(_add_approach_marker(parent, table_number, "A", candidate_a))
		markers.append(_add_approach_marker(parent, table_number, "B", candidate_b))
	elif table_number >= 1 and table_number <= 4:
		markers.append(_add_approach_marker(parent, table_number, "A", candidate_a))
	else:
		markers.append(_add_approach_marker(parent, table_number, "B", candidate_b))

	return markers

func _add_approach_marker(parent: Node3D, table_number: int, suffix: String, marker_position: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = "Table_%02d_Approach_%s" % [table_number, suffix]
	parent.add_child(marker)
	marker.global_position = marker_position + Vector3.UP * approach_marker_height
	marker.set_meta("table_id", table_number)
	marker.set_meta("approach_id", suffix)

	_add_editor_red_dot(marker)

	return marker

func _add_editor_red_dot(parent: Node3D) -> void:
	var dot := MeshInstance3D.new()
	dot.name = "RedDot"
	var sphere := SphereMesh.new()
	sphere.radius = approach_dot_radius
	sphere.height = approach_dot_radius * 2.0
	dot.mesh = sphere
	dot.visible = Engine.is_editor_hint()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.05, 0.03, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.05, 0.03, 1.0)
	dot.material_override = material
	parent.add_child(dot)

func _add_seat(parent: Node3D, table_number: int, seat_number: int, source_seat: Node3D, seat_position: Vector3, seat_basis: Basis, approach_markers: Array[Marker3D]) -> void:
	var seat_marker := Marker3D.new()
	seat_marker.name = "Table_%02d_Seat_%02d" % [table_number, seat_number]
	parent.add_child(seat_marker)
	seat_marker.global_transform = Transform3D(seat_basis, seat_position)
	seat_marker.set_meta("source_seat", source_seat.get_path())
	seat_marker.set_meta("table_id", table_number)
	seat_marker.set_meta("seat_id", seat_number)
	seat_marker.set_meta("occupied", false)
	var approach_marker := _find_nearest_approach_marker(approach_markers, seat_position)
	if approach_marker != null:
		seat_marker.set_meta("approach_path", seat_marker.get_path_to(approach_marker))

	_add_label(seat_marker, "Label", "T%02d-S%02d" % [table_number, seat_number], seat_position + Vector3.UP * seat_label_height)

func _find_nearest_approach_marker(approach_markers: Array[Marker3D], seat_position: Vector3) -> Marker3D:
	var nearest_marker: Marker3D = null
	var nearest_distance := INF
	for marker in approach_markers:
		var distance := _horizontal_distance(marker.global_position, seat_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_marker = marker
	return nearest_marker

func _project_to_navigation(world_position: Vector3) -> Vector3:
	if Engine.is_editor_hint():
		return world_position

	var navigation_map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return world_position

	return NavigationServer3D.map_get_closest_point(navigation_map, world_position)

func _add_label(parent: Node3D, label_name: String, text: String, label_position: Vector3, label_color := Color(0.1, 0.9, 1.0, 1.0)) -> void:
	var label := Label3D.new()
	label.name = label_name
	label.text = text
	label.pixel_size = label_pixel_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = label_color
	label.visible = show_debug_labels
	parent.add_child(label)
	label.global_position = label_position

func _find_nearest_table_group(table_groups: Array[Dictionary], furniture_position: Vector3) -> Dictionary:
	var nearest_group: Dictionary = {}
	var nearest_distance := INF
	for table_group in table_groups:
		var table_node := table_group["table"] as Node3D
		var distance := _horizontal_distance(table_node.global_position, furniture_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_group = table_group
	return nearest_group

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var offset := a - b
	offset.y = 0.0
	return offset.length()

func _sort_nodes_by_name(a: Node3D, b: Node3D) -> bool:
	return String(a.name).naturalnocasecmp_to(String(b.name)) < 0

func _sort_nodes_clockwise(a: Node3D, b: Node3D, center: Vector3) -> bool:
	var offset_a := a.global_position - center
	var offset_b := b.global_position - center
	return atan2(offset_a.z, offset_a.x) < atan2(offset_b.z, offset_b.x)

func _clear_generated_children() -> void:
	for child in get_children():
		child.queue_free()

func _set_labels_visible(labels_visible: bool) -> void:
	for child in get_children():
		_set_labels_visible_recursive(child, labels_visible)

func _set_labels_visible_recursive(node: Node, labels_visible: bool) -> void:
	if node is Label3D:
		(node as Label3D).visible = labels_visible
	for child in node.get_children():
		_set_labels_visible_recursive(child, labels_visible)
