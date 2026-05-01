extends Node

enum JobRole {
	ANY,
	CASHIER,
	COOK,
	PREP,
	DELIVER
}

var job_role: int = JobRole.ANY
var current_action_label: String = "Idle"
var current_task_type_label: String = "-"
var target_customer_label: String = "-"
var target_customer_path: String = "-"
var reason_text: String = "Waiting for task"
var destination_text: String = "-"
var _worker: CharacterBody3D
var _current_task: Object = null
var _is_executing := false

func _ready() -> void:
	_worker = get_parent() as CharacterBody3D
	call_deferred("_start_task_loop")

func _start_task_loop() -> void:
	var task_manager = get_node("/root/TaskManager")
	while is_inside_tree():
		if not _is_executing:
			var task = task_manager.get_next_task(_worker)
			if task != null:
				_is_executing = true
				_current_task = task
				_set_task_status(task, "Starting", "Task assigned")
				await _execute_task(task)
				task_manager.complete_task(task)
				_current_task = null
				_is_executing = false
				_set_idle_status()
			else:
				_set_idle_status()
				await get_tree().create_timer(0.5).timeout
		else:
			await get_tree().process_frame

func _execute_task(task: Object) -> void:
	var tm = get_node("/root/TaskManager")
	if task.type == tm.TaskType.PROCESS_ORDER:
		await _execute_process_order(task)
	elif task.type == tm.TaskType.COOK_MEAT:
		await _execute_cook_meat(task)
	elif task.type == tm.TaskType.FRY_FRIES:
		await _execute_fry_fries(task)
	elif task.type == tm.TaskType.ASSEMBLE_BURGER:
		await _execute_assemble_burger(task)
	elif task.type == tm.TaskType.DELIVER_FOOD:
		await _execute_deliver_food(task)

func _execute_process_order(task: Object) -> void:
	_set_task_status(task, "Taking order", "Walking to register")
	var customer = task.args.get("customer") as Node
	var register_marker = task.args.get("register_marker") as Node3D
	if not is_instance_valid(customer) or not is_instance_valid(register_marker): return
	
	var register = register_marker.get_parent()
	var stand_point = register_marker
	if register != null:
		var found = register.get_node_or_null(NodePath(String(register.name) + "_Opposite"))
		if found != null: stand_point = found
	
	_move_worker_to(stand_point.global_position, register_marker.global_position)
	await _wait_for_arrival()
	
	if is_instance_valid(customer) and customer.has_method("take_order"):
		_set_task_status(task, "Taking order", "Customer is ordering")
		await get_tree().create_timer(1.0).timeout
		customer.take_order(_worker)

func _execute_cook_meat(task: Object) -> void:
	_set_task_status(task, "Cooking", "Claiming grill")
	var grill = task.args.get("station") as Node
	if grill == null or not is_instance_valid(grill): return
	
	if grill.has_method("reserve_for") and not bool(grill.call("reserve_for", _worker)): return
	
	var entrance = grill.call("get_entrance_point") if grill.has_method("get_entrance_point") else grill
	var snap = grill.call("get_snap_point") if grill.has_method("get_snap_point") else grill
	var exit_pt = grill.call("get_exit_point") if grill.has_method("get_exit_point") else grill
	
	var look_target = grill.call("get_look_target") if grill.has_method("get_look_target") else entrance.global_position
	
	_set_task_status(task, "Cooking", "Walking to grill")
	_move_worker_to(entrance.global_position, look_target)
	await _wait_for_arrival()
	
	if _worker.has_method("snap_to_station"):
		_worker.snap_to_station(snap, exit_pt)
		
	var reach = _get_reach_controller(_worker)
	if grill.has_method("cook_meat"):
		_set_task_status(task, "Cooking", "Cooking meat")
		var raw_pos = grill.global_position
		if grill.has_method("get_meat_pickup_point"):
			var pt = grill.call("get_meat_pickup_point")
			if pt: raw_pos = pt.global_position
		var cooked_count = await grill.call("cook_meat", _worker, raw_pos, reach)
		if cooked_count > 0:
			var prep = get_tree().current_scene.find_child("BurgerPrepStation", true, false)
			if prep and prep.has_method("stock_cooked_meat"):
				prep.call("stock_cooked_meat", cooked_count)

func _execute_fry_fries(task: Object) -> void:
	_set_task_status(task, "Frying", "Claiming fryer")
	var fryer = task.args.get("station") as Node
	var food_table = task.args.get("food_table") as Node
	if fryer == null or not is_instance_valid(fryer) or food_table == null or not is_instance_valid(food_table): return
	
	if fryer.has_method("reserve_for") and not bool(fryer.call("reserve_for", _worker)): return
	
	var entrance = fryer.call("get_entrance_point") if fryer.has_method("get_entrance_point") else fryer
	var snap = fryer.call("get_stand_point") if fryer.has_method("get_stand_point") else fryer
	var look = fryer.call("get_look_target") if fryer.has_method("get_look_target") else entrance.global_position
	
	_set_task_status(task, "Frying", "Walking to fryer")
	_move_worker_to(entrance.global_position, look)
	await _wait_for_arrival()
	
	if _worker.has_method("snap_to_station"):
		_worker.snap_to_station(snap)
		
	var reach = _get_reach_controller(_worker)
	var fried_outputs: Array[Node3D] = []
	if fryer.has_method("fry_fries"):
		_set_task_status(task, "Frying", "Frying fries")
		var outputs = await fryer.call("fry_fries", _worker, reach)
		if outputs is Array:
			for o in outputs:
				if o is Node3D: fried_outputs.append(o)
				
	if fried_outputs.is_empty(): return
	
	var table_stand = _get_food_table_worker_stand_point(food_table)
	var table_storage = _get_food_table_burger_storage_point(food_table)
	
	var carry_attachments: Array[Node3D] = []
	var hand_bones = ["RightHand", "LeftHand"]
	for i in range(mini(2, fried_outputs.size())):
		carry_attachments.append(_attach_carried_food_to_hand(_worker, fried_outputs[i], hand_bones[i], "CarriedFries", Vector3(0, -0.08, 0.04)))
	_set_carried_food_offsets(carry_attachments, Vector3(0, -0.18, 0.07))
	
	_set_task_status(task, "Stocking food", "Moving fries to food table")
	_move_worker_to(table_stand.global_position, table_storage.global_position)
	await _wait_for_arrival()
	
	if _worker.has_method("snap_to_station"):
		_worker.snap_to_station(table_stand)
		
	var tm = get_node("/root/TaskManager")
	var customer = task.args.get("customer")
	for i in range(mini(2, fried_outputs.size())):
		var fries = fried_outputs[i]
		if not is_instance_valid(fries): continue
		
		var place_pos = _get_food_table_next_burger_position(food_table, table_storage)
		if reach != null and reach.has_method("reach_to"):
			await reach.call("reach_to", place_pos)
			
		if food_table.has_method("store_food_item"):
			food_table.call("store_food_item", fries)
		else:
			fries.reparent(food_table, true)
			fries.global_position = place_pos
			
		if is_instance_valid(customer):
			tm.add_task(tm.TaskType.DELIVER_FOOD, {"food_table": food_table, "customer": customer, "seat": customer.my_seat})
			
		if is_instance_valid(carry_attachments[i]):
			carry_attachments[i].queue_free()

func _execute_assemble_burger(task: Object) -> void:
	_set_task_status(task, "Assembling", "Claiming prep station")
	var prep = task.args.get("station") as Node
	var food_table = task.args.get("food_table") as Node
	if prep == null or not is_instance_valid(prep) or food_table == null or not is_instance_valid(food_table): return

	var reserved_prep := false
	if prep.has_method("reserve_for"):
		reserved_prep = bool(prep.call("reserve_for", _worker))
		if not reserved_prep:
			get_node("/root/TaskManager").cancel_task(task)
			return
	
	if prep.has_method("is_burger_storage_full") and bool(prep.call("is_burger_storage_full")):
		if reserved_prep and prep.has_method("release_reservation"):
			prep.call("release_reservation", _worker)
		get_node("/root/TaskManager").cancel_task(task)
		return
		
	var snap = prep.call("get_snap_point") if prep.has_method("get_snap_point") else prep
	var entrance = prep.call("get_entrance_point") if prep.has_method("get_entrance_point") else prep
	var exit_pt = prep.call("get_exit_point") if prep.has_method("get_exit_point") else prep
	var look = prep.call("get_look_target") if prep.has_method("get_look_target") else entrance.global_position
	
	_set_task_status(task, "Assembling", "Walking to prep station")
	_move_worker_to(entrance.global_position, look)
	await _wait_for_arrival()
	
	if _worker.has_method("snap_to_station"):
		_worker.snap_to_station(snap, exit_pt)
		
	_set_task_status(task, "Assembling", "Building burger")
	var assembled = await prep.call("assemble_default_burger", _worker)
	if assembled:
		var table_stand = _get_food_table_worker_stand_point(food_table)
		var table_storage = _get_food_table_burger_storage_point(food_table)
		
		_move_worker_to(entrance.global_position, look)
		await _wait_for_arrival()
		
		if _worker.has_method("snap_to_station"):
			_worker.snap_to_station(snap, exit_pt)
			
		var burger = await prep.call("pick_finished_burger_for_transport", _worker)
		if burger:
			var carry = _attach_carried_food_to_hand(_worker, burger, "RightHand", "CarriedBurger", Vector3(0, -0.12, 0.04))
			_set_carried_food_offsets([carry], Vector3(0, -0.24, 0.08))
			
			_set_task_status(task, "Stocking food", "Moving burger to food table")
			_move_worker_to(table_stand.global_position, table_storage.global_position)
			await _wait_for_arrival()
			
			if _worker.has_method("snap_to_station"):
				_worker.snap_to_station(table_stand)
				
			var place_pos = _get_food_table_next_burger_position(food_table, table_storage)
			var reach = _get_reach_controller(_worker)
			if reach and reach.has_method("reach_to"):
				await reach.call("reach_to", place_pos)
				
			if food_table.has_method("store_burger"):
				food_table.call("store_burger", burger)
			else:
				if burger.get_parent() != null:
					burger.reparent(food_table, true)
				else:
					food_table.add_child(burger)
				burger.global_position = place_pos
				
			var tm = get_node("/root/TaskManager")
			var customer = task.args.get("customer")
			if is_instance_valid(customer):
				tm.add_task(tm.TaskType.DELIVER_FOOD, {"food_table": food_table, "customer": customer, "seat": customer.my_seat})
				
			if is_instance_valid(carry):
				carry.queue_free()
	else:
		# Could not assemble (missing meat).
		var tm = get_node("/root/TaskManager")
		var grill = get_tree().current_scene.find_child("Grill_002", true, false)
		if grill:
			var gc = grill.get_node_or_null("Grill002Station")
			tm.add_task(tm.TaskType.COOK_MEAT, {"station": gc if gc else grill})
		if reserved_prep and prep.has_method("release_reservation"):
			prep.call("release_reservation", _worker)
		tm.cancel_task(task)
		return

	if reserved_prep and prep.has_method("release_reservation"):
		prep.call("release_reservation", _worker)

func _execute_deliver_food(task: Object) -> void:
	_set_task_status(task, "Delivering", "Validating delivery")
	var tm = get_node("/root/TaskManager")
	var food_table = task.args.get("food_table") as Node
	var customer = task.args.get("customer") as Node
	var seat = task.args.get("seat") as Node3D
	if food_table == null or customer == null or seat == null:
		tm.fail_task(task)
		return
	if not _delivery_is_valid(customer, task):
		tm.fail_task(task)
		return
	
	var table_stand = _get_food_table_worker_stand_point(food_table)
	var table_storage = _get_food_table_burger_storage_point(food_table)
	if table_stand == null or table_storage == null:
		tm.fail_task(task)
		return
	
	var food_item = null
	while food_item == null and is_inside_tree() and is_instance_valid(customer):
		if not _delivery_is_valid(customer, task):
			tm.fail_task(task)
			return
		_set_task_status(task, "Delivering", "Waiting for food on table")
		if food_table.has_method("get_first_food_item"):
			food_item = food_table.call("get_first_food_item")
		if food_item == null:
			await get_tree().create_timer(1.0).timeout
			
	if not is_instance_valid(customer) or food_item == null or not _delivery_is_valid(customer, task):
		_return_food_to_table(food_table, food_item)
		tm.fail_task(task)
		return
		
	_set_task_status(task, "Delivering", "Walking to food table")
	_move_worker_to(table_stand.global_position, table_storage.global_position)
	await _wait_for_arrival()
	if not _delivery_is_valid(customer, task):
		_return_food_to_table(food_table, food_item)
		tm.fail_task(task)
		return
	
	if _worker.has_method("snap_to_station"):
		_worker.snap_to_station(table_stand)
		
	var reach = _get_reach_controller(_worker)
	if reach and reach.has_method("reach_to"):
		await reach.call("reach_to", food_item.global_position)
		
	var carry = _attach_carried_food_to_hand(_worker, food_item, "RightHand", "CarriedFood", Vector3(0, -0.12, 0.04))
	_set_carried_food_offsets([carry], Vector3(0, -0.24, 0.08))
	if not _delivery_is_valid(customer, task):
		if is_instance_valid(carry): carry.queue_free()
		_return_food_to_table(food_table, food_item)
		tm.fail_task(task)
		return
	
	# Seat approach
	var seat_approach = seat
	if seat.has_meta("approach_path"):
		seat_approach = seat.get_node(seat.get_meta("approach_path"))
		
	_set_task_status(task, "Delivering", "Walking to customer")
	_move_worker_to(seat_approach.global_position, seat.global_position)
	await _wait_for_arrival()
	
	if not is_instance_valid(customer) or not _delivery_is_valid(customer, task):
		if is_instance_valid(carry): carry.queue_free()
		_return_food_to_table(food_table, food_item)
		tm.fail_task(task)
		return
		
	var place_pos = seat.global_position + Vector3(0, 0.8, 0.4)
	if reach and reach.has_method("reach_to"):
		await reach.call("reach_to", place_pos)
		if food_item.get_parent() != null:
			food_item.reparent(seat, true)
		else:
			seat.add_child(food_item)
		food_item.global_position = place_pos
	else:
		if food_item.get_parent() != null:
			food_item.reparent(seat, true)
		else:
			seat.add_child(food_item)
		food_item.global_position = place_pos
		
	if is_instance_valid(carry):
		carry.queue_free()
		
	if customer.has_method("receive_food"):
		var received = bool(customer.call("receive_food", task))
		if not received:
			_return_food_to_table(food_table, food_item)
			tm.fail_task(task)
			return
		_set_task_status(task, "Delivered", "Customer received food")

func _move_worker_to(target_pos: Vector3, look_target: Variant = null) -> void:
	if not is_instance_valid(_worker) or not _worker.is_inside_tree(): return
	destination_text = _format_vector(target_pos)
	var nav_map = _worker.get_world_3d().navigation_map
	var closest = NavigationServer3D.map_get_closest_point(nav_map, target_pos)
	if look_target != null and _worker.has_method("set_navigation_target_with_look_target"):
		_worker.call("set_navigation_target_with_look_target", closest, look_target as Vector3)
	elif _worker.has_method("set_navigation_target"):
		_worker.call("set_navigation_target", closest)

func _wait_for_arrival() -> void:
	if not is_instance_valid(_worker): return
	var dist = _worker.global_position.distance_to(_worker._current_target)
	if dist <= 0.35: # already there
		return
		
	await _worker.arrived_at_target

func _get_food_table_worker_stand_point(food_table: Node) -> Node3D:
	if food_table.has_method("get_worker_stand_point"): return food_table.call("get_worker_stand_point") as Node3D
	return _find_named_descendant(food_table, "workerstandpoint") as Node3D

func _get_food_table_burger_storage_point(food_table: Node) -> Node3D:
	if food_table.has_method("get_burger_storage_point"): return food_table.call("get_burger_storage_point") as Node3D
	return _find_named_descendant(food_table, "burgerstoragepoint") as Node3D

func _get_food_table_next_burger_position(food_table: Node, fallback_storage_point: Node3D) -> Vector3:
	if food_table.has_method("get_next_food_position"):
		var pos = food_table.call("get_next_food_position")
		if pos is Vector3: return pos
	return fallback_storage_point.global_position

func _find_named_descendant(node: Node, normalized_name: String) -> Node:
	if String(node.name).to_lower() == normalized_name: return node
	for child in node.get_children():
		var found = _find_named_descendant(child, normalized_name)
		if found != null: return found
	return null

func _get_reach_controller(worker: Node) -> Node:
	if worker == null: return null
	var configured = worker.get_node_or_null(^"WorkerReachController")
	if configured != null: return configured
	return worker.find_child("WorkerReachController", true, false)

func _attach_carried_food_to_hand(worker: Node3D, food_item: Node3D, hand_bone: String, attachment_prefix: String, hand_offset: Vector3) -> Node3D:
	if worker == null or food_item == null or not is_instance_valid(food_item): return null
	var carried_global_scale = food_item.global_transform.basis.get_scale()
	var attachment_parent = _find_worker_skeleton(worker)
	var attachment = Node3D.new()
	attachment.name = "%s_%s" % [attachment_prefix, hand_bone]
	if attachment_parent != null:
		var bone_attachment = BoneAttachment3D.new()
		bone_attachment.name = attachment.name
		bone_attachment.bone_name = hand_bone
		attachment_parent.add_child(bone_attachment)
		attachment = bone_attachment
	else:
		worker.add_child(attachment)
		attachment.position = Vector3(-0.32 if hand_bone == "LeftHand" else 0.32, 0.95, 0.2)
	if food_item.get_parent() != null:
		food_item.reparent(attachment, false)
	else:
		attachment.add_child(food_item)
	food_item.visible = true
	food_item.position = hand_offset
	food_item.rotation_degrees = Vector3.ZERO
	_apply_global_scale(food_item, carried_global_scale)
	return attachment

func _cleanup_carry_attachments(carry_attachments: Array[Node3D]) -> void:
	for attachment in carry_attachments:
		if attachment != null and is_instance_valid(attachment) and attachment.get_child_count() == 0:
			attachment.queue_free()

func _set_carried_food_offsets(carry_attachments: Array[Node3D], offset: Vector3) -> void:
	for attachment in carry_attachments:
		if attachment == null or not is_instance_valid(attachment): continue
		for child in attachment.get_children():
			if child is Node3D: (child as Node3D).position = offset

func _find_worker_skeleton(node: Node) -> Skeleton3D:
	if node == null: return null
	if node is Skeleton3D: return node as Skeleton3D
	for child in node.get_children():
		var found = _find_worker_skeleton(child)
		if found != null: return found
	return null

func _apply_global_scale(node: Node3D, target_global_scale: Vector3) -> void:
	var current_global_scale = node.global_transform.basis.get_scale()
	node.scale = Vector3(
		_get_adjusted_local_scale(node.scale.x, current_global_scale.x, target_global_scale.x),
		_get_adjusted_local_scale(node.scale.y, current_global_scale.y, target_global_scale.y),
		_get_adjusted_local_scale(node.scale.z, current_global_scale.z, target_global_scale.z)
	)

func _get_adjusted_local_scale(local_scale: float, current_global_scale: float, target_global_scale: float) -> float:
	if absf(current_global_scale) <= 0.0001: return local_scale
	return local_scale * target_global_scale / current_global_scale

func _set_task_status(task: Object, action: String, reason: String) -> void:
	current_action_label = action
	reason_text = reason
	if task == null:
		current_task_type_label = "-"
		target_customer_label = "-"
		target_customer_path = "-"
		return
	var tm = get_node_or_null("/root/TaskManager")
	current_task_type_label = str(tm.call("get_task_type_label", task.type)) if tm != null and tm.has_method("get_task_type_label") else str(task.type)
	var customer = task.args.get("customer")
	if customer is Node and is_instance_valid(customer):
		target_customer_label = String((customer as Node).name)
		target_customer_path = String((customer as Node).get_path())
	else:
		target_customer_label = "-"
		target_customer_path = "-"

func _set_idle_status() -> void:
	current_action_label = "Idle"
	current_task_type_label = "-"
	target_customer_label = "-"
	target_customer_path = "-"
	reason_text = "Waiting for task"
	destination_text = "-"

func get_activity_status() -> Dictionary:
	return {
		"role": _get_job_role_label(job_role),
		"action": current_action_label,
		"task": current_task_type_label,
		"customer": target_customer_label,
		"customer_path": target_customer_path,
		"reason": reason_text,
		"destination": destination_text
	}

func _get_job_role_label(role: int) -> String:
	match role:
		JobRole.ANY:
			return "ANY"
		JobRole.CASHIER:
			return "CASHIER"
		JobRole.COOK:
			return "COOK"
		JobRole.PREP:
			return "PREP"
		JobRole.DELIVER:
			return "DELIVER"
	return "UNKNOWN"

func _format_vector(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]

func _delivery_is_valid(customer: Node, task: Object) -> bool:
	if customer == null or not is_instance_valid(customer):
		return false
	if customer.has_method("can_accept_delivery_task"):
		return bool(customer.call("can_accept_delivery_task", task))
	return true

func _return_food_to_table(food_table: Node, food_item: Node3D) -> void:
	if food_table == null or food_item == null or not is_instance_valid(food_item):
		return
	if food_table.has_method("store_food_item"):
		food_table.call("store_food_item", food_item)
		return
	var table_storage := _get_food_table_burger_storage_point(food_table)
	if food_item.get_parent() != null:
		food_item.reparent(food_table, true)
	else:
		food_table.add_child(food_item)
	if table_storage != null:
		food_item.global_position = table_storage.global_position
	food_item.visible = true
