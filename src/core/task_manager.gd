extends Node

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

func add_task(type: int, args: Dictionary = {}) -> Task:
	var task = Task.new(type, args)
	if not _prepare_task_for_queue(task):
		return null
	pending_tasks.append(task)
	# print("TaskManager: Added task type ", type)
	return task

func get_next_task(worker: Node) -> Task:
	if pending_tasks.is_empty():
		return null
	
	var ai = worker.get_node("WorkerAI") if worker.has_node("WorkerAI") else null
	var role = ai.job_role if ai else 0 # 0 is ANY
	
	var i := 0
	while i < pending_tasks.size():
		var task = pending_tasks[i]
		if _can_worker_do_task(role, task.type):
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
					continue
				# Only assign deliver food if there is actually food on the table
				var food_table = task.args.get("food_table")
				var food_type := String(task.args.get("food_type", ""))
				if food_table and food_table.has_method("get_first_food_item"):
					# We peek, we don't take it yet
					var has_food = true
					if food_table.has_method("has_food_item"):
						has_food = bool(food_table.call("has_food_item", food_type))
					else:
						has_food = false
						for item in food_table._stored_food_items:
							if item != null and is_instance_valid(item):
								has_food = true
								break
					if not has_food:
						i += 1
						continue # Skip this task for now, no food ready
			
			pending_tasks.remove_at(i)
			task.assigned_worker = worker
			task.status = "in_progress"
			active_tasks.append(task)
			# print("TaskManager: Assigned task type ", task.type, " to ", worker.name)
			return task
		i += 1
	return null

func _can_worker_do_task(role: int, task_type: int) -> bool:
	if role == 0: return true
	match role:
		1: # CASHIER
			return task_type == TaskType.PROCESS_ORDER
		2: # COOK (Fryer, Grill)
			return task_type == TaskType.COOK_MEAT or task_type == TaskType.FRY_FRIES
		3: # PREP (Burger)
			return task_type == TaskType.ASSEMBLE_BURGER
		4: # DELIVER
			return task_type == TaskType.DELIVER_FOOD
	return true

func _task_station_is_unavailable(task: Task) -> bool:
	var station = task.args.get("station")
	if station == null or not is_instance_valid(station):
		return false
	if station.has_method("is_available"):
		return not bool(station.call("is_available"))
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

func cancel_task(task: Task) -> void:
	if task.type == TaskType.DELIVER_FOOD:
		_clear_delivery_reservation(task.args.get("customer"), task)
	if task in active_tasks:
		active_tasks.erase(task)
		task.assigned_worker = null
		task.status = "pending"
		pending_tasks.append(task)

func fail_task(task: Task) -> void:
	if task.type == TaskType.DELIVER_FOOD:
		_clear_delivery_reservation(task.args.get("customer"), task)
	if task in active_tasks:
		active_tasks.erase(task)
	if task in pending_tasks:
		pending_tasks.erase(task)
	task.assigned_worker = null
	task.status = "failed"

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
