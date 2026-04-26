extends Node3D

@export_node_path("Node3D") var seating_map_path: NodePath = ^"../SeatingMap"
@export var worker_scene: PackedScene = preload("res://scenes/characters/worker.tscn")
@export var ray_length := 1000.0
@export var navigation_plane_y := 0.4
@export var spawn_spacing := 0.55
@export var prep_station_path: NodePath = ^"../Kitchen/Preperation_Shelf/prep_shelf/BurgerPrepStation"

var workers_root: Node3D
var seating_map: Node3D
var selected_worker: CharacterBody3D = null
var worker_count := 0

var status_label: Label
var send_button: Button
var prep_button: Button

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
	panel.offset_bottom = 204.0
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

func _select_worker(worker: CharacterBody3D) -> void:
	if selected_worker != null and selected_worker.has_method("set_selected"):
		selected_worker.set_selected(false)

	selected_worker = worker
	if selected_worker != null and selected_worker.has_method("set_selected"):
		selected_worker.set_selected(true)

	_refresh_status()

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
	var spawn_markers := _get_register_markers("Opposite")
	if not spawn_markers.is_empty():
		var marker := spawn_markers[spawn_index % spawn_markers.size()]
		var row := floori(float(spawn_index) / float(spawn_markers.size()))
		return marker.global_position + Vector3.RIGHT * float(row) * spawn_spacing

	var register_markers := _get_register_markers("Approach")
	if not register_markers.is_empty():
		return register_markers[0].global_position + Vector3.RIGHT * float(spawn_index + 1) * spawn_spacing

	return Vector3(float(spawn_index) * spawn_spacing, navigation_plane_y, 0.0)

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
	if status_label == null:
		return

	var count := workers_root.get_child_count() if workers_root != null else 0
	if selected_worker == null:
		status_label.text = "%d workers. Select a worker, then right-click to move." % count
	else:
		status_label.text = "Selected: %s. Right-click to move." % selected_worker.name

func _set_status_message(message: String) -> void:
	if status_label != null:
		status_label.text = message
