extends Node3D

@export_node_path("Node3D") var seating_map_path: NodePath = ^"../SeatingMap"
@export var worker_scene: PackedScene = preload("res://scenes/characters/worker.tscn")
@export var ray_length := 1000.0
@export var navigation_plane_y := 0.4
@export var spawn_spacing := 0.55
@export_node_path("Node3D") var worker_spawn_point_path: NodePath = ^"../WorkerSpawnPoint"
@export var prep_station_path: NodePath = ^"../Kitchen/Preperation_Shelf/prep_shelf/BurgerPrepStation"
@export var food_table_path: NodePath = ^"../Kitchen/FoodTable"
@export var fryer_1_path: NodePath = ^"../Kitchen/Fryer_1"
@export var fryer_2_path: NodePath = ^"../Kitchen/Fryer_2"
@export var carried_burger_hand_offset := Vector3(0.0, -0.12, 0.04)
@export var carried_burger_walk_offset := Vector3(0.0, -0.24, 0.08)
@export var carried_fries_hand_offset := Vector3(0.0, -0.08, 0.04)
@export var carried_fries_walk_offset := Vector3(0.0, -0.18, 0.07)

var workers_root: Node3D
var seating_map: Node3D
var selected_worker: CharacterBody3D = null
var worker_count := 0

var status_label: Label
var role_option_button: OptionButton
var send_button: Button
var prep_button: Button
var transport_burger_button: Button
var fry_fries_button: Button
var debug_add_meat_button: Button
var debug_create_burger_button: Button
var spawn_customer_button: Button

func _ready() -> void:
	workers_root = Node3D.new()
	workers_root.name = "Workers"
	add_child(workers_root)
	seating_map = _resolve_seating_map()
	_build_menu()
	call_deferred("_refresh_status")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var clicked_worker := _pick_worker(event.position)
			if clicked_worker != null:
				_select_worker(clicked_worker)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and selected_worker != null:
			var target_position: Variant = _get_world_position(event.position)
			if target_position != null:
				_move_worker_to(selected_worker, target_position)
				get_viewport().set_input_as_handled()

func _build_menu() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "WorkerMenuCanvas"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.name = "WorkerMenuPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = 244.0
	panel.offset_bottom = 390.0
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "Workers"
	layout.add_child(title)

	var spawn_button := Button.new()
	spawn_button.text = "Spawn worker"
	spawn_button.pressed.connect(_spawn_worker)
	layout.add_child(spawn_button)

	spawn_customer_button = Button.new()
	spawn_customer_button.text = "Spawn customer"
	spawn_customer_button.pressed.connect(_spawn_customer)
	layout.add_child(spawn_customer_button)

	var role_row := HBoxContainer.new()
	role_row.add_theme_constant_override("separation", 6)
	layout.add_child(role_row)

	var role_label := Label.new()
	role_label.text = "Role"
	role_label.custom_minimum_size = Vector2(44.0, 0.0)
	role_row.add_child(role_label)

	role_option_button = OptionButton.new()
	role_option_button.disabled = true
	role_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role_option_button.item_selected.connect(_on_role_option_selected)
	role_row.add_child(role_option_button)
	_populate_role_options(null)

	send_button = Button.new()
	send_button.text = "Send to register"
	send_button.disabled = true
	send_button.pressed.connect(_send_selected_worker_to_register)
	layout.add_child(send_button)

	prep_button = Button.new()
	prep_button.text = "Prep burger"
	prep_button.disabled = true
	prep_button.pressed.connect(_prep_selected_worker_burger)
	layout.add_child(prep_button)

	transport_burger_button = Button.new()
	transport_burger_button.text = "Move burger to table"
	transport_burger_button.disabled = true
	transport_burger_button.pressed.connect(_transport_finished_burger_to_food_table)
	layout.add_child(transport_burger_button)

	fry_fries_button = Button.new()
	fry_fries_button.text = "Fry fries"
	fry_fries_button.disabled = true
	fry_fries_button.pressed.connect(_fry_selected_worker_fries)
	layout.add_child(fry_fries_button)

	debug_add_meat_button = Button.new()
	debug_add_meat_button.text = "Debug: add meat"
	debug_add_meat_button.pressed.connect(_debug_add_meat_to_prep)
	layout.add_child(debug_add_meat_button)

	debug_create_burger_button = Button.new()
	debug_create_burger_button.text = "Debug: create burger"
	debug_create_burger_button.pressed.connect(_debug_create_finished_burger)
	layout.add_child(debug_create_burger_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "No worker selected"
	layout.add_child(status_label)

func _spawn_worker() -> void:
	if worker_scene == null:
		push_warning("Worker menu has no worker scene assigned.")
		return

	var worker := worker_scene.instantiate() as CharacterBody3D
	if worker == null:
		push_warning("Worker scene did not instantiate as CharacterBody3D.")
		return

	worker_count += 1
	worker.name = "WorkerNPC_%02d" % worker_count
	workers_root.add_child(worker)
	worker.global_position = _get_worker_spawn_position(worker_count - 1)
	_select_worker(worker)

func _spawn_customer() -> void:
	var customer_manager := _resolve_customer_manager()
	if customer_manager == null:
		push_warning("Worker menu could not find CustomerManager.")
		_set_status_message("CustomerManager not found.")
		return
	if not customer_manager.has_method("spawn_customer_now"):
		push_warning("CustomerManager does not expose spawn_customer_now().")
		_set_status_message("Customer spawn method missing.")
		return

	var customer := customer_manager.call("spawn_customer_now") as CharacterBody3D
	if customer == null:
		_set_status_message("Customer limit reached.")
		return

	_set_status_message("Spawned %s." % customer.name)

func _send_selected_worker_to_register() -> void:
	if selected_worker == null:
		_set_status_message("Select a worker first.")
		return

	var register_target := _find_register_target(selected_worker.global_position)
	if register_target == null:
		push_warning("No cash register red point found.")
		_set_status_message("No cash register target found.")
		return

	var register_position := _get_register_position(register_target)
	_move_worker_to(selected_worker, register_target.global_position, register_position)

func _prep_selected_worker_burger() -> void:
	if selected_worker == null:
		_set_status_message("Select a worker first.")
		return

	var prep_station := _resolve_prep_station()
	if prep_station == null:
		push_warning("Burger prep station missing at Kitchen/Preperation_Shelf/prep_shelf/BurgerPrepStation.")
		_set_status_message("Burger prep station missing.")
		return
	if prep_station.has_method("is_burger_storage_full") and bool(prep_station.call("is_burger_storage_full")):
		if prep_station.has_method("show_storage_full"):
			prep_station.call("show_storage_full")
		_set_status_message("Burger storage full.")
		return

	var snap_point: Node3D = null
	if prep_station.has_method("get_snap_point"):
		snap_point = prep_station.call("get_snap_point") as Node3D
	if snap_point == null:
		push_warning("Burger prep station is missing WorkerPrepSnapPoint.")
		_set_status_message("Prep snap point missing.")
		return

	var entrance_point: Node3D = null
	if prep_station.has_method("get_entrance_point"):
		entrance_point = prep_station.call("get_entrance_point") as Node3D
	if entrance_point == null:
		push_warning("Burger prep station is missing WorkerPrepEntrancePoint.")
		_set_status_message("Prep entrance point missing.")
		return

	var exit_point: Node3D = null
	if prep_station.has_method("get_exit_point"):
		exit_point = prep_station.call("get_exit_point") as Node3D

	var assembly_point: Node3D = null
	if prep_station.has_method("get_assembly_point"):
		assembly_point = prep_station.call("get_assembly_point") as Node3D
	if assembly_point == null:
		push_warning("Burger prep station is missing BurgerAssemblyPoint.")
		_set_status_message("Burger assembly point missing.")
		return

	var look_target := assembly_point.global_position
	if prep_station.has_method("get_look_target"):
		var called_look_target: Variant = prep_station.call("get_look_target")
		if called_look_target is Vector3:
			look_target = called_look_target
	_move_worker_to(selected_worker, entrance_point.global_position, look_target, false)
	_set_status_message("Sending %s to prep burger." % selected_worker.name)
	await selected_worker.arrived_at_target

	if selected_worker == null:
		return
	if selected_worker.has_method("snap_to_station"):
		selected_worker.snap_to_station(snap_point, exit_point)
	_set_status_message("%s is assembling a burger." % selected_worker.name)
	var assembled: bool = bool(await prep_station.call("assemble_default_burger", selected_worker))
	if assembled:
		_set_status_message("%s prepped a burger." % selected_worker.name)
	else:
		_set_status_message("Burger prep could not start.")

func _transport_finished_burger_to_food_table() -> void:
	if selected_worker == null:
		_set_status_message("Select a worker first.")
		return

	var prep_station := _resolve_prep_station()
	if prep_station == null:
		_set_status_message("Burger prep station missing.")
		return
	if not prep_station.has_method("has_finished_burger") or not bool(prep_station.call("has_finished_burger")):
		_set_status_message("No finished burger to move.")
		return

	var food_table := _resolve_food_table()
	if food_table == null:
		push_warning("FoodTable was not found in the current scene.")
		_set_status_message("Food table missing.")
		return
	var table_capacity := _get_food_table_available_capacity(food_table)
	if table_capacity <= 0:
		_set_status_message("Food table full.")
		return
	var prep_burger_count := _get_prep_finished_burger_count(prep_station)
	var transport_count: int = mini(2, mini(prep_burger_count, table_capacity))
	if transport_count <= 0:
		_set_status_message("No finished burger to move.")
		return

	var table_stand_point := _get_food_table_worker_stand_point(food_table)
	var table_storage_point := _get_food_table_burger_storage_point(food_table)
	if table_stand_point == null or table_storage_point == null:
		push_warning("FoodTable is missing workerstandpoint or burgerstoragepoint.")
		_set_status_message("Food table points missing.")
		return

	var prep_entrance: Node3D = null
	if prep_station.has_method("get_entrance_point"):
		prep_entrance = prep_station.call("get_entrance_point") as Node3D
	var prep_snap: Node3D = null
	if prep_station.has_method("get_snap_point"):
		prep_snap = prep_station.call("get_snap_point") as Node3D
	var prep_exit: Node3D = null
	if prep_station.has_method("get_exit_point"):
		prep_exit = prep_station.call("get_exit_point") as Node3D
	if prep_entrance == null or prep_snap == null:
		_set_status_message("Prep station points missing.")
		return

	_set_status_message("Sending %s to pick up burger." % selected_worker.name)
	_move_worker_to(selected_worker, prep_entrance.global_position, prep_station.call("get_look_target") if prep_station.has_method("get_look_target") else null, false)
	await selected_worker.arrived_at_target
	if selected_worker == null:
		return
	if selected_worker.has_method("snap_to_station"):
		selected_worker.snap_to_station(prep_snap, prep_exit)

	var carried_burgers: Array[Node3D] = []
	var carry_attachments: Array[Node3D] = []
	var hand_bones := ["RightHand", "LeftHand"]
	for index in range(transport_count):
		var burger := await prep_station.call("pick_finished_burger_for_transport", selected_worker) as Node3D
		if burger == null:
			break
		carried_burgers.append(burger)
		carry_attachments.append(_attach_carried_burger_to_hand(selected_worker, burger, hand_bones[index]))
	if carried_burgers.is_empty():
		_set_status_message("No finished burger to move.")
		return

	_set_status_message("Taking %d burger%s to food table." % [carried_burgers.size(), "" if carried_burgers.size() == 1 else "s"])
	_set_carried_burger_offsets(carry_attachments, carried_burger_walk_offset)
	var table_place_position := _get_food_table_next_burger_position(food_table, table_storage_point)
	_move_worker_to(selected_worker, table_stand_point.global_position, table_place_position)
	await selected_worker.arrived_at_target
	if selected_worker == null:
		return
	if selected_worker.has_method("snap_to_station"):
		selected_worker.snap_to_station(table_stand_point)

	var reach_controller := _get_reach_controller(selected_worker)
	for index in range(carried_burgers.size()):
		var burger := carried_burgers[index]
		if burger == null or not is_instance_valid(burger):
			continue

		table_place_position = _get_food_table_next_burger_position(food_table, table_storage_point)
		if reach_controller != null and reach_controller.has_method("reach_to"):
			await reach_controller.call("reach_to", table_place_position)

		if food_table.has_method("store_burger"):
			if not bool(food_table.call("store_burger", burger)):
				_set_status_message("Food table full.")
				_cleanup_carry_attachments(carry_attachments)
				return
		else:
			burger.reparent(food_table, true)
			burger.global_position = table_place_position
			burger.global_rotation = Vector3.ZERO
			burger.visible = true

		var attachment := carry_attachments[index]
		if attachment != null and is_instance_valid(attachment):
			attachment.queue_free()
	_cleanup_carry_attachments(carry_attachments)
	_set_status_message("%s moved %d burger%s to the food table." % [selected_worker.name, carried_burgers.size(), "" if carried_burgers.size() == 1 else "s"])

func _fry_selected_worker_fries() -> void:
	if selected_worker == null:
		_set_status_message("Select a worker first.")
		return
	var worker := selected_worker

	var food_table := _resolve_food_table()
	if food_table == null:
		push_warning("FoodTable was not found in the current scene.")
		_set_status_message("Food table missing.")
		return
	var table_capacity := _get_food_table_available_capacity(food_table)
	if table_capacity < 2:
		_set_status_message("Food table full.")
		return

	var fryer := _get_first_available_fryer()
	if fryer == null:
		_set_status_message("No fryer available.")
		return

	var entrance_point := _get_station_entrance_point(fryer)
	var stand_point := _get_station_stand_point(fryer)
	if entrance_point == null or stand_point == null:
		push_warning("%s is missing WorkerEnterancePoint or WorkerStandPoint." % fryer.name)
		_set_status_message("Fryer points missing.")
		return

	var table_stand_point := _get_food_table_worker_stand_point(food_table)
	var table_storage_point := _get_food_table_burger_storage_point(food_table)
	if table_stand_point == null or table_storage_point == null:
		push_warning("FoodTable is missing workerstandpoint or burgerstoragepoint.")
		_set_status_message("Food table points missing.")
		return

	if fryer.has_method("reserve_for") and not bool(fryer.call("reserve_for", worker)):
		_set_status_message("No fryer available.")
		return

	var look_target := entrance_point.global_position
	if fryer is Node3D:
		look_target = (fryer as Node3D).global_position
	if fryer.has_method("get_look_target"):
		var called_look_target: Variant = fryer.call("get_look_target")
		if called_look_target is Vector3:
			look_target = called_look_target

	_set_status_message("Sending %s to fry fries." % worker.name)
	_move_worker_to(worker, entrance_point.global_position, look_target, false)
	await worker.arrived_at_target
	if worker == null or not is_instance_valid(worker):
		if fryer.has_method("release_reservation"):
			fryer.call("release_reservation")
		return
	if worker.has_method("snap_to_station"):
		worker.snap_to_station(stand_point)

	var reach_controller := _get_reach_controller(worker)
	var fried_outputs: Array[Node3D] = []
	if fryer.has_method("fry_fries"):
		var called_outputs: Variant = await fryer.call("fry_fries", worker, reach_controller)
		if called_outputs is Array:
			for output in called_outputs:
				if output is Node3D:
					fried_outputs.append(output as Node3D)
	if fried_outputs.is_empty():
		_set_status_message("Fries could not be cooked.")
		return

	var carry_attachments: Array[Node3D] = []
	var hand_bones := ["RightHand", "LeftHand"]
	var carry_count := mini(2, fried_outputs.size())
	for index in range(carry_count):
		carry_attachments.append(_attach_carried_food_to_hand(
			worker,
			fried_outputs[index],
			hand_bones[index],
			"CarriedFries",
			carried_fries_hand_offset
		))

	_set_status_message("Taking fries to food table.")
	_set_carried_food_offsets(carry_attachments, carried_fries_walk_offset)
	var table_place_position := _get_food_table_next_burger_position(food_table, table_storage_point)
	_move_worker_to(worker, table_stand_point.global_position, table_place_position)
	await worker.arrived_at_target
	if worker == null or not is_instance_valid(worker):
		return
	if worker.has_method("snap_to_station"):
		worker.snap_to_station(table_stand_point)

	for index in range(carry_count):
		var fries := fried_outputs[index]
		if fries == null or not is_instance_valid(fries):
			continue

		table_place_position = _get_food_table_next_burger_position(food_table, table_storage_point)
		if reach_controller != null and reach_controller.has_method("reach_to"):
			await reach_controller.call("reach_to", table_place_position)

		if food_table.has_method("store_food_item"):
			if not bool(food_table.call("store_food_item", fries)):
				_set_status_message("Food table full.")
				_cleanup_carry_attachments(carry_attachments)
				return
		elif food_table.has_method("store_burger"):
			if not bool(food_table.call("store_burger", fries)):
				_set_status_message("Food table full.")
				_cleanup_carry_attachments(carry_attachments)
				return
		else:
			fries.reparent(food_table, true)
			fries.global_position = table_place_position
			fries.global_rotation = Vector3.ZERO
			fries.visible = true

		var attachment := carry_attachments[index]
		if attachment != null and is_instance_valid(attachment):
			attachment.queue_free()
	_cleanup_carry_attachments(carry_attachments)
	_set_status_message("%s moved %d fries to the food table." % [worker.name, carry_count])

func _debug_add_meat_to_prep() -> void:
	var prep_station := _resolve_prep_station()
	if prep_station == null:
		_set_status_message("Burger prep station missing.")
		return
	if prep_station.has_method("debug_add_cooked_meat"):
		prep_station.call("debug_add_cooked_meat", 4)
	elif prep_station.has_method("stock_cooked_meat"):
		prep_station.call("stock_cooked_meat", 4)
	_set_status_message("Added 4 cooked meat to prep.")

func _debug_create_finished_burger() -> void:
	var prep_station := _resolve_prep_station()
	if prep_station == null:
		_set_status_message("Burger prep station missing.")
		return
	if not prep_station.has_method("debug_create_finished_burger"):
		_set_status_message("Debug burger create unavailable.")
		return

	var created: bool = bool(await prep_station.call("debug_create_finished_burger"))
	if created:
		_set_status_message("Created finished burger.")
	else:
		_set_status_message("Burger storage full.")

func _select_worker(worker: CharacterBody3D) -> void:
	if selected_worker != null and selected_worker.has_method("set_selected"):
		selected_worker.set_selected(false)

	selected_worker = worker
	if selected_worker != null and selected_worker.has_method("set_selected"):
		selected_worker.set_selected(true)

	_refresh_status()

func _on_role_option_selected(index: int) -> void:
	if selected_worker == null or role_option_button == null:
		return
	var ai := selected_worker.get_node_or_null("WorkerAI")
	if ai == null:
		return
	var role_id := role_option_button.get_item_id(index)
	if ai.has_method("set_job_role"):
		ai.call("set_job_role", role_id)
	else:
		ai.job_role = role_id
	_set_status_message("%s role: %s." % [selected_worker.name, _get_worker_role_label(selected_worker)])

func _move_worker_to(worker: CharacterBody3D, target_position: Vector3, look_target: Variant = null, release_station_snap := true) -> void:
	var navigation_map := get_world_3d().navigation_map
	var closest_point := NavigationServer3D.map_get_closest_point(navigation_map, target_position)
	if not release_station_snap and worker.has_method("set_navigation_target_without_leaving_station"):
		worker.set_navigation_target_without_leaving_station(closest_point, look_target)
	elif look_target != null and worker.has_method("set_navigation_target_with_look_target"):
		worker.set_navigation_target_with_look_target(closest_point, look_target as Vector3)
	elif worker.has_method("set_navigation_target"):
		worker.set_navigation_target(closest_point)
	_refresh_status()

func _get_register_position(register_marker: Node3D) -> Vector3:
	var register_root := register_marker.get_parent() as Node3D
	if register_root != null:
		return register_root.global_position
	return register_marker.global_position

func _get_worker_spawn_position(spawn_index: int) -> Vector3:
	var worker_spawn_point := _resolve_worker_spawn_point()
	if worker_spawn_point != null:
		return worker_spawn_point.global_position + Vector3.RIGHT * float(spawn_index) * spawn_spacing

	var spawn_markers := _get_register_markers("Approach")
	if not spawn_markers.is_empty():
		var marker := spawn_markers[spawn_index % spawn_markers.size()]
		var row := floori(float(spawn_index) / float(spawn_markers.size()))
		return marker.global_position + Vector3.RIGHT * float(row) * spawn_spacing

	var register_markers := _get_register_markers("Opposite")
	if not register_markers.is_empty():
		return register_markers[0].global_position + Vector3.RIGHT * float(spawn_index + 1) * spawn_spacing

	return Vector3(float(spawn_index) * spawn_spacing, navigation_plane_y, 0.0)

func _resolve_worker_spawn_point() -> Node3D:
	var configured := get_node_or_null(worker_spawn_point_path) as Node3D
	if configured != null:
		return configured

	var current_scene := get_tree().current_scene
	if current_scene != null:
		return current_scene.find_child("WorkerSpawnPoint", true, false) as Node3D
	return null

func _resolve_customer_manager() -> Node:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	return current_scene.find_child("CustomerManager", true, false)

func _find_register_target(from_position: Vector3) -> Node3D:
	var register_markers := _get_register_markers("Approach")
	var nearest_marker: Node3D = null
	var nearest_distance := INF
	for marker in register_markers:
		var offset := marker.global_position - from_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_marker = marker
	return nearest_marker

func _get_register_markers(marker_suffix: String) -> Array[Node3D]:
	if seating_map == null:
		seating_map = _resolve_seating_map()

	var markers: Array[Node3D] = []
	if seating_map == null:
		return markers

	_collect_register_markers(seating_map, marker_suffix, markers)
	markers.sort_custom(_sort_nodes_by_name)
	return markers

func _resolve_seating_map() -> Node3D:
	var configured_map := get_node_or_null(seating_map_path) as Node3D
	if configured_map != null:
		return configured_map
	return get_tree().current_scene.find_child("SeatingMap", true, false) as Node3D

func _resolve_prep_station() -> Node:
	var configured_station := get_node_or_null(prep_station_path)
	if configured_station != null:
		return configured_station

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null

	var prep_shelf := current_scene.get_node_or_null("Kitchen/Preperation_Shelf/prep_shelf")
	if prep_shelf == null:
		push_warning("Kitchen/Preperation_Shelf/prep_shelf was not found.")
		return null
	return prep_shelf.get_node_or_null("BurgerPrepStation")

func _resolve_food_table() -> Node:
	var configured_table := get_node_or_null(food_table_path)
	if configured_table != null:
		return configured_table

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	return _find_named_descendant(current_scene, "foodtable")

func _find_named_descendant(node: Node, normalized_name: String) -> Node:
	if String(node.name).to_lower() == normalized_name:
		return node
	for child in node.get_children():
		var found := _find_named_descendant(child, normalized_name)
		if found != null:
			return found
	return null

func _get_food_table_worker_stand_point(food_table: Node) -> Node3D:
	if food_table.has_method("get_worker_stand_point"):
		return food_table.call("get_worker_stand_point") as Node3D
	return _find_named_descendant(food_table, "workerstandpoint") as Node3D

func _get_food_table_burger_storage_point(food_table: Node) -> Node3D:
	if food_table.has_method("get_burger_storage_point"):
		return food_table.call("get_burger_storage_point") as Node3D
	return _find_named_descendant(food_table, "burgerstoragepoint") as Node3D

func _get_food_table_available_capacity(food_table: Node) -> int:
	if food_table.has_method("get_available_food_capacity"):
		return int(food_table.call("get_available_food_capacity"))
	if food_table.has_method("get_available_burger_capacity"):
		return int(food_table.call("get_available_burger_capacity"))
	if food_table.has_method("has_burger_capacity"):
		return 1 if bool(food_table.call("has_burger_capacity")) else 0
	return 1

func _get_food_table_next_burger_position(food_table: Node, fallback_storage_point: Node3D) -> Vector3:
	if food_table.has_method("get_next_food_position"):
		var called_food_position: Variant = food_table.call("get_next_food_position")
		if called_food_position is Vector3:
			return called_food_position
	if food_table.has_method("get_next_burger_position"):
		var called_position: Variant = food_table.call("get_next_burger_position")
		if called_position is Vector3:
			return called_position
	return fallback_storage_point.global_position

func _get_prep_finished_burger_count(prep_station: Node) -> int:
	if prep_station.has_method("get_finished_burger_count"):
		return int(prep_station.call("get_finished_burger_count"))
	if prep_station.has_method("has_finished_burger") and bool(prep_station.call("has_finished_burger")):
		return 1
	return 0

func _attach_carried_burger_to_hand(worker: Node3D, burger: Node3D, hand_bone: String) -> Node3D:
	return _attach_carried_food_to_hand(worker, burger, hand_bone, "CarriedBurger", carried_burger_hand_offset)

func _attach_carried_food_to_hand(worker: Node3D, food_item: Node3D, hand_bone: String, attachment_prefix: String, hand_offset: Vector3) -> Node3D:
	if worker == null or food_item == null or not is_instance_valid(food_item):
		return null

	var carried_global_scale := food_item.global_transform.basis.get_scale()
	var attachment_parent := _find_worker_skeleton(worker)
	var attachment := Node3D.new()
	attachment.name = "%s_%s" % [attachment_prefix, hand_bone]
	if attachment_parent != null:
		var bone_attachment := BoneAttachment3D.new()
		bone_attachment.name = attachment.name
		bone_attachment.bone_name = hand_bone
		attachment_parent.add_child(bone_attachment)
		attachment = bone_attachment
	else:
		worker.add_child(attachment)
		attachment.position = Vector3(-0.32 if hand_bone == "LeftHand" else 0.32, 0.95, 0.2)

	food_item.reparent(attachment, false)
	food_item.visible = true
	food_item.position = hand_offset
	food_item.rotation_degrees = Vector3.ZERO
	_apply_global_scale(food_item, carried_global_scale)
	return attachment

func _cleanup_carry_attachments(carry_attachments: Array[Node3D]) -> void:
	for attachment in carry_attachments:
		if attachment != null and is_instance_valid(attachment) and attachment.get_child_count() == 0:
			attachment.queue_free()

func _set_carried_burger_offsets(carry_attachments: Array[Node3D], offset: Vector3) -> void:
	_set_carried_food_offsets(carry_attachments, offset)

func _set_carried_food_offsets(carry_attachments: Array[Node3D], offset: Vector3) -> void:
	for attachment in carry_attachments:
		if attachment == null or not is_instance_valid(attachment):
			continue
		for child in attachment.get_children():
			if child is Node3D:
				(child as Node3D).position = offset

func _find_worker_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_worker_skeleton(child)
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

func _get_reach_controller(worker: Node) -> Node:
	if worker == null:
		return null
	var configured := worker.get_node_or_null(^"WorkerReachController")
	if configured != null:
		return configured
	return worker.find_child("WorkerReachController", true, false)

func _get_first_available_fryer() -> Node:
	for fryer in [_resolve_fryer(fryer_1_path, "Fryer_1"), _resolve_fryer(fryer_2_path, "Fryer_2")]:
		if fryer == null:
			continue
		if fryer.has_method("is_available") and not bool(fryer.call("is_available")):
			continue
		return fryer
	return null

func _resolve_fryer(fryer_path: NodePath, fallback_name: String) -> Node:
	var configured_fryer := get_node_or_null(fryer_path)
	if configured_fryer != null:
		return configured_fryer

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	var kitchen := current_scene.get_node_or_null("Kitchen")
	if kitchen != null:
		return kitchen.get_node_or_null(fallback_name)
	return current_scene.find_child(fallback_name, true, false)

func _get_station_entrance_point(station: Node) -> Node3D:
	if station.has_method("get_entrance_point"):
		return station.call("get_entrance_point") as Node3D
	return _find_named_descendant(station, "workerenterancepoint") as Node3D

func _get_station_stand_point(station: Node) -> Node3D:
	if station.has_method("get_stand_point"):
		return station.call("get_stand_point") as Node3D
	if station.has_method("get_snap_point"):
		return station.call("get_snap_point") as Node3D
	return _find_named_descendant(station, "workerstandpoint") as Node3D

func _collect_register_markers(node: Node, marker_suffix: String, markers: Array[Node3D]) -> void:
	if node is Node3D:
		var node_name := String(node.name)
		if node_name.begins_with("CashRegister_") and node_name.ends_with("_" + marker_suffix):
			markers.append(node as Node3D)

	for child in node.get_children():
		_collect_register_markers(child, marker_suffix, markers)

func _sort_nodes_by_name(a: Node3D, b: Node3D) -> bool:
	return String(a.name).naturalnocasecmp_to(String(b.name)) < 0

func _pick_worker(screen_position: Vector2) -> CharacterBody3D:
	var hit := _raycast(screen_position)
	if hit.is_empty() or not hit.has("collider"):
		return null

	var node := hit["collider"] as Node
	while node != null:
		if node is CharacterBody3D and node.is_in_group("worker_npc"):
			return node as CharacterBody3D
		node = node.get_parent()

	return null

func _get_world_position(screen_position: Vector2) -> Variant:
	var hit := _raycast(screen_position)
	if hit.has("position"):
		return hit["position"]

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null

	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var navigation_plane := Plane(Vector3.UP, navigation_plane_y)
	return navigation_plane.intersects_ray(ray_origin, ray_direction)

func _raycast(screen_position: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}

	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * ray_length)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func _refresh_status() -> void:
	if send_button != null:
		send_button.disabled = selected_worker == null
	if prep_button != null:
		prep_button.disabled = selected_worker == null
	if transport_burger_button != null:
		transport_burger_button.disabled = selected_worker == null
	if fry_fries_button != null:
		fry_fries_button.disabled = selected_worker == null
	if role_option_button != null:
		role_option_button.disabled = selected_worker == null
		_populate_role_options(selected_worker)
	if status_label == null:
		return

	var count := workers_root.get_child_count() if workers_root != null else 0
	if selected_worker == null:
		status_label.text = "%d workers. Select a worker, then right-click to move." % count
	else:
		status_label.text = "Selected: %s (%s). Right-click to move." % [selected_worker.name, _get_worker_role_label(selected_worker)]

func _set_status_message(message: String) -> void:
	if status_label != null:
		status_label.text = message

func _populate_role_options(worker: CharacterBody3D) -> void:
	if role_option_button == null:
		return
	role_option_button.clear()
	var ai := worker.get_node_or_null("WorkerAI") if worker != null else null
	var role_options: Array = ai.call("get_job_role_options") if ai != null and ai.has_method("get_job_role_options") else _get_fallback_role_options()
	var selected_index := 0
	var selected_role := int(ai.job_role) if ai != null else 0
	for index in range(role_options.size()):
		var role: Dictionary = role_options[index]
		var role_id := int(role.get("id", index))
		role_option_button.add_item(String(role.get("label", str(role_id))), role_id)
		if role_id == selected_role:
			selected_index = index
	role_option_button.selected = selected_index

func _get_worker_role_label(worker: CharacterBody3D) -> String:
	if worker == null:
		return "Auto"
	var ai := worker.get_node_or_null("WorkerAI")
	if ai == null:
		return "Auto"
	if ai.has_method("get_job_role_label"):
		return String(ai.call("get_job_role_label"))
	for role in _get_fallback_role_options():
		if int(role.get("id", -1)) == int(ai.job_role):
			return String(role.get("label", "Auto"))
	return "Auto"

func _get_fallback_role_options() -> Array[Dictionary]:
	return [
		{"id": 0, "label": "Auto"},
		{"id": 1, "label": "Cashier"},
		{"id": 2, "label": "Meat Griller"},
		{"id": 3, "label": "Burger Prepper"},
		{"id": 4, "label": "Fries Fryer"},
		{"id": 5, "label": "Caterer"}
	]
