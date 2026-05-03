extends Node

signal tasks_changed()

enum TaskType {
	PROCESS_ORDER,
	COOK_MEAT,
	FRY_FRIES,
	ASSEMBLE_BURGER,
	DELIVER_FOOD
}

class Task:
	var type: int
	var args: Dictionary
	var assigned_worker: Node = null
	var status: String = "pending" # pending, in_progress, completed
	
	func _init(t: int, a: Dictionary = {}) -> void:
		type = t
		args = a

var pending_tasks: Array[Task] = []
var active_tasks: Array[Task] = []

const ROLE_AUTO := 0
const ROLE_CASHIER := 1
const ROLE_MEAT_GRILLER := 2
const ROLE_BURGER_PREPPER := 3
const ROLE_FRIES_FRYER := 4
const ROLE_CATERER := 5

func add_task(type: int, args: Dictionary = {}) -> Task:
	var task = Task.new(type, args)
	if not _prepare_task_for_queue(task):
		return null
	pending_tasks.append(task)
	tasks_changed.emit()
	# print("TaskManager: Added task type ", type)
	return task

func get_next_task(worker: Node) -> Task:
	if pending_tasks.is_empty():
		return null
	
	var ai = worker.get_node("WorkerAI") if worker.has_node("WorkerAI") else null
	var role = ai.job_role if ai else ROLE_AUTO
	
	var i := 0
	while i < pending_tasks.size():
		var task = pending_tasks[i]
		if _can_worker_do_task(role, task.type):
			if not _task_matches_worker_station(worker, role, task):
				i += 1
				continue
			_assign_task_station_for_worker(worker, role, task)
			if _station_has_active_task(task):
				i += 1
				continue
			if _task_station_is_unavailable(task):
				i += 1
				continue

			if task.type == TaskType.ASSEMBLE_BURGER and _burger_prep_is_waiting_for_meat(task):
				_ensure_cook_meat_task_for_burger(task)
				i += 1
				continue

			# Additional checks based on task type
			if task.type == TaskType.DELIVER_FOOD:
				var customer = task.args.get("customer")
				if not _customer_can_accept_delivery(customer, task):
					_clear_delivery_reservation(customer, task)
					pending_tasks.remove_at(i)
					tasks_changed.emit()
					continue
				if not _delivery_task_has_ready_food(task):
					i += 1
					continue
			
			pending_tasks.remove_at(i)
			task.assigned_worker = worker
			task.status = "in_progress"
			active_tasks.append(task)
			tasks_changed.emit()
			# print("TaskManager: Assigned task type ", task.type, " to ", worker.name)
			return task
		i += 1
	return null

func claim_ready_delivery_tasks_for_worker(worker: Node, excluded_task: Task, max_count: int) -> Array[Task]:
	var claimed: Array[Task] = []
	if worker == null or max_count <= 0:
		return claimed
	var ai = worker.get_node("WorkerAI") if worker.has_node("WorkerAI") else null
	var role = ai.job_role if ai else ROLE_AUTO
	if not _can_worker_do_task(role, TaskType.DELIVER_FOOD):
		return claimed
	var food_table: Variant = null
	if excluded_task != null:
		food_table = excluded_task.args.get("food_table")
	var claimed_food_counts := {}
	if excluded_task != null:
		var excluded_food_type := String(excluded_task.args.get("food_type", ""))
		claimed_food_counts[excluded_food_type] = 1

	var i := 0
	while i < pending_tasks.size() and claimed.size() < max_count:
		var task := pending_tasks[i]
		if task == excluded_task or task.type != TaskType.DELIVER_FOOD:
			i += 1
			continue
		if food_table != null and task.args.get("food_table") != food_table:
			i += 1
			continue
		var customer = task.args.get("customer")
		if not _customer_can_accept_delivery(customer, task):
			_clear_delivery_reservation(customer, task)
			pending_tasks.remove_at(i)
			continue
		var food_type := String(task.args.get("food_type", ""))
		var already_claimed_count := int(claimed_food_counts.get(food_type, 0))
		if _delivery_ready_food_count(task) <= already_claimed_count:
			i += 1
			continue
		pending_tasks.remove_at(i)
		task.assigned_worker = worker
		task.status = "in_progress"
		active_tasks.append(task)
		claimed.append(task)
		claimed_food_counts[food_type] = already_claimed_count + 1
	tasks_changed.emit()
	return claimed

func _can_worker_do_task(role: int, task_type: int) -> bool:
	if role == ROLE_AUTO: return true
	match role:
		ROLE_CASHIER:
			return task_type == TaskType.PROCESS_ORDER
		ROLE_MEAT_GRILLER:
			return task_type == TaskType.COOK_MEAT
		ROLE_BURGER_PREPPER:
			return task_type == TaskType.ASSEMBLE_BURGER
		ROLE_FRIES_FRYER:
			return task_type == TaskType.FRY_FRIES
		ROLE_CATERER:
			return task_type == TaskType.DELIVER_FOOD
	return true

func get_assigned_station_for_worker(worker: Node, role: int = -1) -> Node:
	if worker == null or not is_instance_valid(worker):
		return null
	var worker_role := role
	if worker_role < 0:
		var ai := worker.get_node_or_null("WorkerAI")
		worker_role = int(ai.job_role) if ai != null else ROLE_AUTO
	if worker_role == ROLE_AUTO or worker_role == ROLE_CATERER:
		return null

	var stations := _get_stations_for_role(worker_role)
	if stations.is_empty():
		return null

	var workers := _get_workers_for_role(worker_role)
	var worker_index := workers.find(worker)
	if worker_index < 0 or worker_index >= stations.size():
		return null
	return stations[worker_index]

func _task_matches_worker_station(worker: Node, role: int, task: Task) -> bool:
	var task_role := _get_role_for_task_type(task.type)
	if task_role == ROLE_AUTO or task_role == ROLE_CATERER:
		return true

	var task_station := _get_task_station(task)
	var assigned_station := get_assigned_station_for_worker(worker, role)

	if role == ROLE_AUTO:
		if task.type == TaskType.FRY_FRIES and _station_is_owned_by_role(task_station, task_role):
			return _get_first_unowned_available_station(ROLE_FRIES_FRYER) != null
		return not _station_is_owned_by_role(task_station, task_role)

	if assigned_station == null:
		return false
	if task.type == TaskType.FRY_FRIES:
		return true
	if task_station == null:
		return true
	return _stations_match(assigned_station, task_station)

func _assign_task_station_for_worker(worker: Node, role: int, task: Task) -> void:
	if task.type != TaskType.FRY_FRIES:
		return
	var assigned_station := get_assigned_station_for_worker(worker, role)
	if assigned_station != null:
		task.args["station"] = assigned_station
		return
	if role == ROLE_AUTO:
		var current_station := task.args.get("station") as Node
		if (
			current_station != null
			and is_instance_valid(current_station)
			and not _station_is_owned_by_role(current_station, ROLE_FRIES_FRYER)
			and (not current_station.has_method("is_available") or bool(current_station.call("is_available")))
		):
			return
		var open_station := _get_first_unowned_available_station(ROLE_FRIES_FRYER)
		if open_station != null:
			task.args["station"] = open_station

func _get_role_for_task_type(task_type: int) -> int:
	match task_type:
		TaskType.PROCESS_ORDER:
			return ROLE_CASHIER
		TaskType.COOK_MEAT:
			return ROLE_MEAT_GRILLER
		TaskType.ASSEMBLE_BURGER:
			return ROLE_BURGER_PREPPER
		TaskType.FRY_FRIES:
			return ROLE_FRIES_FRYER
		TaskType.DELIVER_FOOD:
			return ROLE_CATERER
	return ROLE_AUTO

func _get_task_station(task: Task) -> Node:
	if task.type == TaskType.PROCESS_ORDER:
		return task.args.get("register_marker") as Node
	return task.args.get("station") as Node

func _station_is_owned_by_role(station: Node, role: int) -> bool:
	if station == null or not is_instance_valid(station):
		return false
	for worker in _get_workers_for_role(role):
		var assigned_station := get_assigned_station_for_worker(worker, role)
		if assigned_station != null and _stations_match(assigned_station, station):
			return true
	return false

func _get_first_unowned_available_station(role: int) -> Node:
	for station in _get_stations_for_role(role):
		if _station_is_owned_by_role(station, role):
			continue
		if station.has_method("is_available") and not bool(station.call("is_available")):
			continue
		return station
	return null

func _stations_match(a: Node, b: Node) -> bool:
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return false
	if a == b:
		return true
	var a_register := _get_register_root(a)
	var b_register := _get_register_root(b)
	if a_register != null or b_register != null:
		return a_register != null and a_register == b_register
	return a == b

func _get_register_root(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	var current := node
	while current != null:
		var node_name := String(current.name)
		if node_name.begins_with("CashRegister_") and not node_name.contains("_Approach") and not node_name.contains("_Opposite"):
			return current
		current = current.get_parent()
	return null

func _get_workers_for_role(role: int) -> Array[Node]:
	var workers: Array[Node] = []
	for worker in get_tree().get_nodes_in_group("worker_npc"):
		if worker == null or not is_instance_valid(worker):
			continue
		var ai := worker.get_node_or_null("WorkerAI")
		if ai != null and int(ai.job_role) == role:
			workers.append(worker)
	workers.sort_custom(_sort_nodes_by_name)
	return workers

func _get_stations_for_role(role: int) -> Array[Node]:
	var stations: Array[Node] = []
	var level := get_tree().current_scene
	if level == null:
		return stations
	match role:
		ROLE_CASHIER:
			var seating_map := level.find_child("SeatingMap", true, false)
			if seating_map != null:
				var register_markers: Array[Node3D] = []
				_collect_register_markers(seating_map, "Approach", register_markers)
				register_markers.sort_custom(_sort_nodes_by_name)
				for marker in register_markers:
					stations.append(marker)
		ROLE_MEAT_GRILLER:
			_collect_nodes_with_method(level, "cook_meat", stations)
			stations.sort_custom(_sort_nodes_by_path)
		ROLE_BURGER_PREPPER:
			_collect_nodes_with_method(level, "assemble_default_burger", stations)
			stations.sort_custom(_sort_nodes_by_path)
		ROLE_FRIES_FRYER:
			_collect_nodes_with_method(level, "fry_fries", stations)
			stations.sort_custom(_sort_nodes_by_name)
	return stations

func _collect_register_markers(node: Node, marker_suffix: String, markers: Array[Node3D]) -> void:
	if node is Node3D:
		var node_name := String(node.name)
		if node_name.begins_with("CashRegister_") and node_name.ends_with("_" + marker_suffix):
			markers.append(node as Node3D)
	for child in node.get_children():
		_collect_register_markers(child, marker_suffix, markers)

func _collect_nodes_with_method(node: Node, method_name: String, results: Array[Node]) -> void:
	if node.has_method(method_name):
		results.append(node)
	for child in node.get_children():
		_collect_nodes_with_method(child, method_name, results)

func _sort_nodes_by_name(a: Node, b: Node) -> bool:
	return String(a.name).naturalnocasecmp_to(String(b.name)) < 0

func _sort_nodes_by_path(a: Node, b: Node) -> bool:
	return String(a.get_path()).naturalnocasecmp_to(String(b.get_path())) < 0

func _task_station_is_unavailable(task: Task) -> bool:
	var station = task.args.get("station")
	if station == null or not is_instance_valid(station):
		return false
	if station.has_method("is_available"):
		return not bool(station.call("is_available"))
	return false

func _delivery_task_has_ready_food(task: Task) -> bool:
	return _delivery_ready_food_count(task) > 0

func _delivery_ready_food_count(task: Task) -> int:
	var food_table = task.args.get("food_table")
	if food_table == null or not is_instance_valid(food_table):
		return 0
	var food_type := String(task.args.get("food_type", ""))
	if food_table.has_method("has_food_item"):
		var stored_items = food_table.get("_stored_food_items")
		if stored_items is Array:
			var count := 0
			for item in stored_items:
				if item != null and is_instance_valid(item) and _food_item_matches_delivery_type(item, food_type):
					count += 1
			return count
		return 1 if bool(food_table.call("has_food_item", food_type)) else 0
	var fallback_stored_items = food_table.get("_stored_food_items")
	if fallback_stored_items is Array:
		var fallback_count := 0
		for item in fallback_stored_items:
			if item != null and is_instance_valid(item) and _food_item_matches_delivery_type(item, food_type):
				fallback_count += 1
		return fallback_count
	return 0

func _food_item_matches_delivery_type(food_item: Node, food_type: String) -> bool:
	if food_type.is_empty():
		return true
	if food_item.has_meta("food_type"):
		return String(food_item.get_meta("food_type")) == food_type
	var normalized_name := String(food_item.name).to_lower()
	if normalized_name.contains("fries"):
		return food_type == "fries"
	if normalized_name.contains("burger"):
		return food_type == "burger"
	return false

func _station_has_active_task(task: Task) -> bool:
	var station = task.args.get("station")
	if station == null or not is_instance_valid(station):
		return false
	for active_task in active_tasks:
		if active_task == task:
			continue
		if active_task.args.get("station") == station:
			return true
	return false

func _burger_prep_is_waiting_for_meat(task: Task) -> bool:
	var station = task.args.get("station")
	if station == null or not is_instance_valid(station):
		return false
	if not station.has_method("has_cooked_meat"):
		return false
	return not bool(station.call("has_cooked_meat"))

func _ensure_cook_meat_task_for_burger(task: Task) -> void:
	var prep_station = task.args.get("station")
	request_cooked_meat_for_prep(prep_station)

func request_cooked_meat_for_prep(prep_station: Node) -> void:
	if prep_station == null or not is_instance_valid(prep_station):
		return
	if _has_pending_or_active_cook_meat_task(prep_station):
		return

	var grill_station: Node = null
	if prep_station.has_method("get_grill_station"):
		grill_station = prep_station.call("get_grill_station") as Node
	if grill_station == null or not is_instance_valid(grill_station):
		return

	add_task(TaskType.COOK_MEAT, {"station": grill_station, "prep_station": prep_station})

func _has_pending_or_active_cook_meat_task(prep_station: Node) -> bool:
	for task in pending_tasks:
		if _is_cook_meat_task_for_prep(task, prep_station):
			return true
	for task in active_tasks:
		if _is_cook_meat_task_for_prep(task, prep_station):
			return true
	return false

func _is_cook_meat_task_for_prep(task: Task, prep_station: Node) -> bool:
	if task.type != TaskType.COOK_MEAT:
		return false
	if task.args.get("prep_station") == prep_station:
		return true
	var grill_station = task.args.get("station")
	if prep_station != null and prep_station.has_method("get_grill_station") and grill_station != null:
		return prep_station.call("get_grill_station") == grill_station
	return false

func complete_task(task: Task) -> void:
	if task in active_tasks:
		task.status = "completed"
		active_tasks.erase(task)
		tasks_changed.emit()

func cancel_task(task: Task) -> void:
	if task.type == TaskType.DELIVER_FOOD:
		_clear_delivery_reservation(task.args.get("customer"), task)
	if task in active_tasks:
		active_tasks.erase(task)
		task.assigned_worker = null
		task.status = "pending"
		pending_tasks.append(task)
		tasks_changed.emit()

func fail_task(task: Task) -> void:
	if task.type == TaskType.DELIVER_FOOD:
		_clear_delivery_reservation(task.args.get("customer"), task)
	if task in active_tasks:
		active_tasks.erase(task)
	if task in pending_tasks:
		pending_tasks.erase(task)
	task.assigned_worker = null
	task.status = "failed"
	tasks_changed.emit()

func get_task_type_label(type: int) -> String:
	match type:
		TaskType.PROCESS_ORDER:
			return "Process Order"
		TaskType.COOK_MEAT:
			return "Cook Meat"
		TaskType.FRY_FRIES:
			return "Fry Fries"
		TaskType.ASSEMBLE_BURGER:
			return "Assemble Burger"
		TaskType.DELIVER_FOOD:
			return "Deliver Food"
	return "Unknown"

func get_task_summary(task: Task) -> Dictionary:
	if task == null:
		return {}
	var customer = task.args.get("customer")
	return {
		"type": get_task_type_label(task.type),
		"status": task.status,
		"worker": task.assigned_worker.name if is_instance_valid(task.assigned_worker) else "unassigned",
		"customer": _node_label(customer),
		"customer_path": _node_path_label(customer),
		"station": _node_label(task.args.get("station")),
		"food_table": _node_label(task.args.get("food_table")),
		"food_type": String(task.args.get("food_type", "-"))
	}

func _prepare_task_for_queue(task: Task) -> bool:
	if task.type != TaskType.DELIVER_FOOD:
		return true
	var customer = task.args.get("customer")
	if not _customer_can_accept_delivery(customer, task):
		return false
	if customer.has_method("reserve_delivery"):
		return bool(customer.call("reserve_delivery", task))
	return false

func _customer_can_accept_delivery(customer: Variant, reservation: Variant) -> bool:
	if customer == null or not is_instance_valid(customer):
		return false
	if customer.has_method("has_received_food") and bool(customer.call("has_received_food")):
		return false
	if customer.has_method("can_accept_delivery_task"):
		return bool(customer.call("can_accept_delivery_task", reservation))
	return true

func _clear_delivery_reservation(customer: Variant, reservation: Variant) -> void:
	if customer != null and is_instance_valid(customer) and customer.has_method("clear_delivery_reservation"):
		customer.call("clear_delivery_reservation", reservation)

func _node_label(value: Variant) -> String:
	if value is Node and is_instance_valid(value):
		return String((value as Node).name)
	return "-"

func _node_path_label(value: Variant) -> String:
	if value is Node and is_instance_valid(value):
		return String((value as Node).get_path())
	return "-"
