extends Node

enum JobRole {
	AUTO,
	CASHIER,
	MEAT_GRILLER,
	BURGER_PREPPER,
	FRIES_FRYER,
	CATERER
}

const APPLE_PAY_SOUND := preload("res://assets/audio/applepay.mp3")
const VFX := preload("res://src/world/restaurant_vfx_factory.gd")
const CARRIED_FOOD_HAND_OFFSET := Vector3(0.0, 0.08, 0.06)
const CARRIED_FOOD_WALK_OFFSET := Vector3(0.0, 0.1, 0.1)

class WorkerStats:
	var movement_speed_pct := 0
	var order_speed_pct := 0
	var grill_speed_pct := 0
	var fry_speed_pct := 0
	var prep_speed_pct := 0
	var delivery_speed_pct := 0
	var delivery_capacity := 1

	static func roll() -> WorkerStats:
		var rolled := WorkerStats.new()
		rolled.movement_speed_pct = randi_range(-10, 20)
		rolled.order_speed_pct = randi_range(-20, 30)
		rolled.grill_speed_pct = randi_range(-20, 30)
		rolled.fry_speed_pct = randi_range(-20, 30)
		rolled.prep_speed_pct = randi_range(-20, 30)
		rolled.delivery_speed_pct = randi_range(-20, 30)
		rolled.delivery_capacity = randi_range(1, 3)
		return rolled

	func to_display_parts() -> PackedStringArray:
		return PackedStringArray([
			"Move %s" % _format_pct(movement_speed_pct),
			"Order %s" % _format_pct(order_speed_pct),
			"Grill %s" % _format_pct(grill_speed_pct),
			"Fry %s" % _format_pct(fry_speed_pct),
			"Prep %s" % _format_pct(prep_speed_pct),
			"Delivery %s" % _format_pct(delivery_speed_pct),
			"Carry %d" % delivery_capacity
		])

	static func _format_pct(value: int) -> String:
		if value > 0:
			return "+%d%%" % value
		return "%d%%" % value

var job_role: int = JobRole.AUTO
var stats: WorkerStats = null
var current_action_label: String = "Idle"
var current_task_type_label: String = "-"
var target_customer_label: String = "-"
var target_customer_path: String = "-"
var reason_text: String = "Waiting for task"
var destination_text: String = "-"
var _worker: CharacterBody3D
var _base_move_speed := 3.4
var _current_task: Object = null
var _is_executing := false
var _last_idle_station: Node = null
var _pending_job_role := -1
var _pending_job_role_reason := ""
var _shift_started_at := 0.0
var _task_started_at := 0.0
var _last_delivery_batch_count := 1
var _performance_counts := {
	"orders": 0,
	"meat_batches": 0,
	"fries_batches": 0,
	"burgers": 0,
	"deliveries": 0,
	"failed": 0,
}
var _performance_seconds := {
	"orders": 0.0,
	"meat_batches": 0.0,
	"fries_batches": 0.0,
	"burgers": 0.0,
	"deliveries": 0.0,
}
var _observed_max_carry := 1

func _ready() -> void:
	_worker = get_parent() as CharacterBody3D
	_shift_started_at = Time.get_ticks_msec() / 1000.0
	if _worker != null:
		_base_move_speed = float(_worker.get("move_speed"))
	if stats == null:
		generate_worker_stats()
	else:
		_apply_movement_stat()
	call_deferred("_start_task_loop")

func generate_worker_stats() -> void:
	stats = WorkerStats.roll()
	_apply_movement_stat()

func get_stats_summary() -> String:
	if stats == null:
		return "-"
	return ", ".join(stats.to_display_parts())

func _start_task_loop() -> void:
	var task_manager = get_node("/root/TaskManager")
	while is_inside_tree():
		if not _is_executing:
			var task = task_manager.get_next_task(_worker)
			if task != null:
				_is_executing = true
				_current_task = task
				_task_started_at = Time.get_ticks_msec() / 1000.0
				_last_delivery_batch_count = 1
				_set_task_status(task, "Starting", "Task assigned")
				await _execute_task(task)
				_record_task_performance(task, Time.get_ticks_msec() / 1000.0 - _task_started_at)
				task_manager.complete_task(task)
				_current_task = null
				_is_executing = false
				_apply_pending_job_role_if_any()
				_set_idle_status()
				_move_to_assigned_idle_station()
			else:
				_set_idle_status()
				_move_to_assigned_idle_station()
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
	var customer_value: Variant = task.args.get("customer")
	var register_marker_value: Variant = task.args.get("register_marker")
	if customer_value == null or not is_instance_valid(customer_value):
		get_node("/root/TaskManager").fail_task(task)
		return
	if register_marker_value == null or not is_instance_valid(register_marker_value) or not (register_marker_value is Node3D):
		get_node("/root/TaskManager").fail_task(task)
		return
	var customer := customer_value as Node
	var register_marker := register_marker_value as Node3D
		
	var register = register_marker.get_parent()
	var stand_point = register_marker
	var register_look_target: Vector3 = register_marker.global_position
	if register != null:
		if register is Node3D:
			register_look_target = (register as Node3D).global_position
		var found = register.get_node_or_null(NodePath(String(register.name) + "_Approach"))
		if found != null: stand_point = found
	
	_move_worker_to(stand_point.global_position, register_look_target)
	await _wait_for_arrival()
	
	if is_instance_valid(customer) and customer.has_method("take_order"):
		_set_task_status(task, "Taking order", "Customer is ordering")
		await get_tree().create_timer(_scaled_duration(1.0, _get_effective_speed_pct("order"))).timeout
		customer.take_order(_worker)
		_play_register_order_sound(register_marker)

func _execute_cook_meat(task: Object) -> void:
	_set_task_status(task, "Cooking", "Claiming grill")
	var grill = task.args.get("station") as Node
	if grill == null or not is_instance_valid(grill): return
	var tm = get_node("/root/TaskManager")
	var reserved_grill := false
	if grill.has_method("reserve_for"):
		reserved_grill = bool(grill.call("reserve_for", _worker))
		if not reserved_grill:
			tm.cancel_task(task)
			return
	
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
		var duration_multiplier := _duration_multiplier(_get_effective_speed_pct("grill"))
		_set_reach_timing_scale(reach, duration_multiplier)
		var cooked_count = await grill.call("cook_meat", _worker, raw_pos, reach, duration_multiplier)
		_reset_reach_timing_scale(reach)
		if cooked_count > 0:
			var prep = task.args.get("prep_station") as Node
			if prep == null or not is_instance_valid(prep):
				prep = get_tree().current_scene.find_child("BurgerPrepStation", true, false)
			if prep and prep.has_method("stock_cooked_meat"):
				prep.call("stock_cooked_meat", cooked_count)
	if reserved_grill and grill.has_method("release_reservation"):
		grill.call("release_reservation", _worker)

func _play_register_order_sound(register_marker: Node3D) -> void:
	if register_marker == null or not is_instance_valid(register_marker):
		return

	var register_body := _resolve_cash_register_body(register_marker)
	var audio_parent := register_body
	if audio_parent == null:
		audio_parent = register_marker

	var player := AudioStreamPlayer3D.new()
	player.name = "ApplePaySound"
	player.stream = APPLE_PAY_SOUND
	player.max_distance = 8.0
	player.finished.connect(Callable(player, "queue_free"))
	audio_parent.add_child(player)
	player.global_position = register_body.global_position if register_body != null else audio_parent.global_position
	player.play()
	VFX.spawn_burst(audio_parent, player.global_position + Vector3.UP * 0.48, Color(0.42, 1.0, 0.58, 0.82), 46, 0.62, 0.16, 0.45, 1.45, 0.28, 0.95, true, 0.022)

func _resolve_cash_register_body(register_marker: Node3D) -> Node3D:
	var register_root := register_marker.get_parent() as Node3D
	if register_root == null:
		return register_marker

	if register_root.has_meta("source_register"):
		var source_path := NodePath(String(register_root.get_meta("source_register")))
		var source_register := get_node_or_null(source_path) as Node3D
		if source_register != null:
			return source_register

	return register_root

func _execute_fry_fries(task: Object) -> void:
	_set_task_status(task, "Frying", "Claiming fryer")
	var fryer = task.args.get("station") as Node
	var food_table = task.args.get("food_table") as Node
	var food_type := String(task.args.get("food_type", "fries"))
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
		var duration_multiplier := _duration_multiplier(_get_effective_speed_pct("fry"))
		_set_reach_timing_scale(reach, duration_multiplier)
		var outputs = await fryer.call("fry_fries", _worker, reach, duration_multiplier)
		_reset_reach_timing_scale(reach)
		if outputs is Array:
			for o in outputs:
				if o is Node3D: fried_outputs.append(o)
				
	if fried_outputs.is_empty(): return
	
	var table_stand = _get_food_table_worker_stand_point(food_table)
	var table_storage = _get_food_table_burger_storage_point(food_table)
	
	var carry_attachments: Array[Node3D] = []
	var hand_bones = ["RightHand", "LeftHand"]
	for i in range(mini(2, fried_outputs.size())):
		carry_attachments.append(_attach_carried_food_to_hand(_worker, fried_outputs[i], hand_bones[i], "CarriedFries", CARRIED_FOOD_HAND_OFFSET))
	_set_carried_food_offsets(carry_attachments, CARRIED_FOOD_WALK_OFFSET)
	
	_set_task_status(task, "Stocking food", "Moving fries to food table")
	_move_worker_to(table_stand.global_position, table_storage.global_position)
	await _wait_for_arrival()
	
	if _worker.has_method("snap_to_station"):
		_worker.snap_to_station(table_stand)
		
	var tm = get_node("/root/TaskManager")
	var customer = task.args.get("customer")
	var delivery_task_added := false
	for i in range(mini(2, fried_outputs.size())):
		var fries = fried_outputs[i]
		if not is_instance_valid(fries): continue
		fries.set_meta("food_type", food_type)
		
		var place_pos = _get_food_table_next_burger_position(food_table, table_storage)
		if reach != null and reach.has_method("reach_to"):
			await reach.call("reach_to", place_pos)
			
		if food_table.has_method("store_food_item"):
			food_table.call("store_food_item", fries, food_type)
		else:
			fries.reparent(food_table, true)
			fries.global_position = place_pos
			
		if is_instance_valid(customer) and not delivery_task_added:
			tm.add_task(tm.TaskType.DELIVER_FOOD, {"food_table": food_table, "customer": customer, "seat": customer.my_seat, "food_type": food_type})
			delivery_task_added = true
			
		if is_instance_valid(carry_attachments[i]):
			carry_attachments[i].queue_free()

func _execute_assemble_burger(task: Object) -> void:
	_set_task_status(task, "Assembling", "Claiming prep station")
	var prep = task.args.get("station") as Node
	var food_table = task.args.get("food_table") as Node
	var food_type := String(task.args.get("food_type", "burger"))
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
	var prep_multiplier := _duration_multiplier(_get_effective_speed_pct("prep"))
	var prep_reach := _get_reach_controller(_worker)
	_set_reach_timing_scale(prep_reach, prep_multiplier)
	var assembled = await prep.call("assemble_default_burger", _worker)
	_reset_reach_timing_scale(prep_reach)
	if assembled:
		var table_stand = _get_food_table_worker_stand_point(food_table)
		var table_storage = _get_food_table_burger_storage_point(food_table)
		
		_move_worker_to(entrance.global_position, look)
		await _wait_for_arrival()
		
		if _worker.has_method("snap_to_station"):
			_worker.snap_to_station(snap, exit_pt)
			
		_set_reach_timing_scale(prep_reach, prep_multiplier)
		var burger = await prep.call("pick_finished_burger_for_transport", _worker)
		_reset_reach_timing_scale(prep_reach)
		if burger:
			burger.set_meta("food_type", food_type)
			var carry = _attach_carried_food_to_hand(_worker, burger, "RightHand", "CarriedBurger", CARRIED_FOOD_HAND_OFFSET)
			_set_carried_food_offsets([carry], CARRIED_FOOD_WALK_OFFSET)
			
			_set_task_status(task, "Stocking food", "Moving burger to food table")
			_move_worker_to(table_stand.global_position, table_storage.global_position)
			await _wait_for_arrival()
			
			if _worker.has_method("snap_to_station"):
				_worker.snap_to_station(table_stand)
				
			var place_pos = _get_food_table_next_burger_position(food_table, table_storage)
			var reach = _get_reach_controller(_worker)
			_set_reach_timing_scale(reach, prep_multiplier)
			if reach and reach.has_method("reach_to"):
				await reach.call("reach_to", place_pos)
			_reset_reach_timing_scale(reach)
				
			if food_table.has_method("store_food_item"):
				food_table.call("store_food_item", burger, food_type)
			else:
				if burger.get_parent() != null:
					burger.reparent(food_table, true)
				else:
					food_table.add_child(burger)
				burger.global_position = place_pos
				
			var tm = get_node("/root/TaskManager")
			var customer = task.args.get("customer")
			if is_instance_valid(customer):
				tm.add_task(tm.TaskType.DELIVER_FOOD, {"food_table": food_table, "customer": customer, "seat": customer.my_seat, "food_type": food_type})
				
			if is_instance_valid(carry):
				carry.queue_free()
	else:
		# Could not assemble (missing meat).
		var tm = get_node("/root/TaskManager")
		if tm.has_method("request_cooked_meat_for_prep"):
			tm.call("request_cooked_meat_for_prep", prep)
		if reserved_prep and prep.has_method("release_reservation"):
			prep.call("release_reservation", _worker)
		tm.cancel_task(task)
		return

	if reserved_prep and prep.has_method("release_reservation"):
		prep.call("release_reservation", _worker)

func _execute_deliver_food(task: Object) -> void:
	_set_task_status(task, "Delivering", "Validating delivery")
	var tm = get_node("/root/TaskManager")
	var food_table_value: Variant = task.args.get("food_table")
	var customer_value: Variant = task.args.get("customer")
	var seat_value: Variant = task.args.get("seat")
	var food_type := String(task.args.get("food_type", ""))
	if (
		food_table_value == null or not is_instance_valid(food_table_value)
		or customer_value == null or not is_instance_valid(customer_value)
		or seat_value == null or not is_instance_valid(seat_value) or not (seat_value is Node3D)
	):
		tm.fail_task(task)
		return
	var food_table := food_table_value as Node
	var customer := customer_value as Node
	var seat := seat_value as Node3D
	if not _delivery_is_valid(customer, task):
		tm.fail_task(task)
		return
	
	var table_stand = _get_food_table_worker_stand_point(food_table)
	var table_storage = _get_food_table_burger_storage_point(food_table)
	if table_stand == null or table_storage == null:
		tm.fail_task(task)
		return

	_set_task_status(task, "Delivering", "Walking to food table")
	_move_worker_to(table_stand.global_position, table_storage.global_position)
	await _wait_for_arrival()
	if not _delivery_is_valid(customer, task):
		tm.fail_task(task)
		return
	
	if _worker.has_method("snap_to_station"):
		_worker.snap_to_station(table_stand)

	var delivery_tasks: Array = [task]
	var capacity := _get_effective_delivery_capacity()
	if job_role == JobRole.CATERER and capacity > 1 and tm.has_method("claim_ready_delivery_tasks_for_worker"):
		var extra_tasks: Array = tm.call("claim_ready_delivery_tasks_for_worker", _worker, task, capacity - 1)
		delivery_tasks.append_array(extra_tasks)
	_last_delivery_batch_count = delivery_tasks.size()
	_observed_max_carry = maxi(_observed_max_carry, _last_delivery_batch_count)

	var reach = _get_reach_controller(_worker)
	var delivery_multiplier := _duration_multiplier(_get_effective_speed_pct("delivery"))
	_set_reach_timing_scale(reach, delivery_multiplier)
	var deliveries: Array[Dictionary] = []
	for index in range(delivery_tasks.size()):
		var delivery_task = delivery_tasks[index]
		var delivery_customer := delivery_task.args.get("customer") as Node
		var delivery_food_type := String(delivery_task.args.get("food_type", ""))
		if not _delivery_is_valid(delivery_customer, delivery_task):
			tm.fail_task(delivery_task)
			continue

		var food_item := _take_food_item_from_table(food_table, delivery_food_type)
		if food_item == null:
			tm.fail_task(delivery_task)
			continue
		if reach and reach.has_method("reach_to"):
			await reach.call("reach_to", food_item.global_position)
		var carry := _attach_carried_food_for_delivery(_worker, food_item, index)
		deliveries.append({
			"task": delivery_task,
			"customer": delivery_customer,
			"seat": delivery_task.args.get("seat") as Node3D,
			"food_type": delivery_food_type,
			"food_item": food_item,
			"carry": carry,
			"carry_slot": index
		})
	_reset_reach_timing_scale(reach)

	if deliveries.is_empty():
		return

	deliveries.sort_custom(_sort_deliveries_by_nearest_seat)
	_set_delivery_carry_offsets(deliveries)
	for delivery in deliveries:
		await _deliver_single_food_item(delivery, delivery_multiplier)

func _take_food_item_from_table(food_table: Node, food_type: String) -> Node3D:
	if food_table == null or not is_instance_valid(food_table):
		return null
	if food_table.has_method("get_first_food_item_by_type"):
		return food_table.call("get_first_food_item_by_type", food_type) as Node3D
	if food_table.has_method("get_first_food_item"):
		return food_table.call("get_first_food_item") as Node3D
	return null

func _attach_carried_food_for_delivery(worker: Node3D, food_item: Node3D, slot_index: int) -> Node3D:
	match slot_index:
		0:
			return _attach_carried_food_to_hand(worker, food_item, "RightHand", "CarriedFood", _get_delivery_hand_offset(slot_index))
		1:
			return _attach_carried_food_to_hand(worker, food_item, "LeftHand", "CarriedFood", _get_delivery_hand_offset(slot_index))
	return _attach_carried_food_to_hand(worker, food_item, "RightHand", "CarriedFood", _get_delivery_hand_offset(slot_index))

func _set_delivery_carry_offsets(deliveries: Array[Dictionary]) -> void:
	for delivery in deliveries:
		var carry := delivery.get("carry") as Node3D
		var slot_index := int(delivery.get("carry_slot", 0))
		if carry == null or not is_instance_valid(carry):
			continue
		for child in carry.get_children():
			if child is Node3D:
				(child as Node3D).position = _get_delivery_hand_offset(slot_index)

func _get_delivery_hand_offset(slot_index: int) -> Vector3:
	match slot_index:
		0:
			return Vector3(-0.04, 0.1, 0.1)
		1:
			return CARRIED_FOOD_WALK_OFFSET
		_:
			return Vector3(0.08, 0.16, 0.14)

func _sort_deliveries_by_nearest_seat(a: Dictionary, b: Dictionary) -> bool:
	var a_seat := a.get("seat") as Node3D
	var b_seat := b.get("seat") as Node3D
	if a_seat == null:
		return false
	if b_seat == null:
		return true
	return _worker.global_position.distance_squared_to(a_seat.global_position) < _worker.global_position.distance_squared_to(b_seat.global_position)

func _deliver_single_food_item(delivery: Dictionary, delivery_multiplier: float) -> void:
	var tm = get_node("/root/TaskManager")
	var delivery_task := delivery.get("task") as Object
	var delivery_customer := delivery.get("customer") as Node
	var delivery_seat := delivery.get("seat") as Node3D
	var food_item := delivery.get("food_item") as Node3D
	var food_type := String(delivery.get("food_type", ""))
	var carry := delivery.get("carry") as Node3D
	if delivery_task == null or delivery_customer == null or delivery_seat == null or food_item == null:
		if food_item != null:
			var failed_food_table: Node = null
			if delivery_task != null:
				failed_food_table = delivery_task.args.get("food_table") as Node
			_return_food_to_table(failed_food_table, food_item, food_type)
		if carry != null and is_instance_valid(carry):
			carry.queue_free()
		if delivery_task != null:
			tm.fail_task(delivery_task)
		return

	var seat_approach = delivery_seat
	if delivery_seat.has_meta("approach_path"):
		seat_approach = delivery_seat.get_node(delivery_seat.get_meta("approach_path"))

	_set_task_status(delivery_task, "Delivering", "Walking to customer")
	_move_worker_to(seat_approach.global_position, delivery_seat.global_position)
	await _wait_for_arrival()

	if not is_instance_valid(delivery_customer) or not _delivery_is_valid(delivery_customer, delivery_task):
		if carry != null and is_instance_valid(carry):
			carry.queue_free()
		_return_food_to_table(delivery_task.args.get("food_table") as Node, food_item, food_type)
		tm.fail_task(delivery_task)
		return

	if delivery_customer.has_method("receive_food"):
		var reach = _get_reach_controller(_worker)
		_set_reach_timing_scale(reach, delivery_multiplier)
		var received = bool(delivery_customer.call("receive_food", delivery_task, food_item))
		_reset_reach_timing_scale(reach)
		if carry != null and is_instance_valid(carry):
			carry.queue_free()
		if not received:
			_return_food_to_table(delivery_task.args.get("food_table") as Node, food_item, food_type)
			tm.fail_task(delivery_task)
			return
		_set_task_status(delivery_task, "Delivered", "Customer received food")
		tm.complete_task(delivery_task)
	else:
		if carry != null and is_instance_valid(carry):
			carry.queue_free()
		_return_food_to_table(delivery_task.args.get("food_table") as Node, food_item, food_type)
		tm.fail_task(delivery_task)

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
	if customer != null and is_instance_valid(customer) and customer is Node:
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
		"destination": destination_text,
		"stats": get_stats_summary(),
		"is_executing": _is_executing,
		"pending_role": _get_job_role_label(_pending_job_role) if _pending_job_role >= 0 else "",
		"performance": get_performance_summary(),
	}

func get_performance_summary() -> Dictionary:
	var elapsed_minutes: float = maxf(0.1, ((Time.get_ticks_msec() / 1000.0) - _shift_started_at) / 60.0)
	return {
		"elapsed_minutes": elapsed_minutes,
		"orders": int(_performance_counts["orders"]),
		"burgers": int(_performance_counts["burgers"]),
		"meat_batches": int(_performance_counts["meat_batches"]),
		"fries_batches": int(_performance_counts["fries_batches"]),
		"deliveries": int(_performance_counts["deliveries"]),
		"failed": int(_performance_counts["failed"]),
		"orders_per_min": float(_performance_counts["orders"]) / elapsed_minutes,
		"burgers_per_min": float(_performance_counts["burgers"]) / elapsed_minutes,
		"meat_batches_per_min": float(_performance_counts["meat_batches"]) / elapsed_minutes,
		"fries_batches_per_min": float(_performance_counts["fries_batches"]) / elapsed_minutes,
		"deliveries_per_min": float(_performance_counts["deliveries"]) / elapsed_minutes,
		"avg_order_seconds": _avg_seconds("orders"),
		"avg_burger_seconds": _avg_seconds("burgers"),
		"avg_meat_seconds": _avg_seconds("meat_batches"),
		"avg_fries_seconds": _avg_seconds("fries_batches"),
		"avg_delivery_seconds": _avg_seconds("deliveries"),
		"observed_max_carry": _observed_max_carry,
	}

func get_interview_summary() -> Dictionary:
	return {
		"delivery_capacity": stats.delivery_capacity if stats != null else 1,
	}

func is_executing_task() -> bool:
	return _is_executing

func _record_task_performance(task: Object, duration_seconds: float) -> void:
	if task == null:
		return
	if String(task.get("status")) == "failed":
		_performance_counts["failed"] = int(_performance_counts["failed"]) + 1
		return
	var tm = get_node_or_null("/root/TaskManager")
	if tm == null:
		return
	match int(task.get("type")):
		tm.TaskType.PROCESS_ORDER:
			_add_performance_sample("orders", 1, duration_seconds)
		tm.TaskType.COOK_MEAT:
			_add_performance_sample("meat_batches", 1, duration_seconds)
		tm.TaskType.FRY_FRIES:
			_add_performance_sample("fries_batches", 1, duration_seconds)
		tm.TaskType.ASSEMBLE_BURGER:
			_add_performance_sample("burgers", 1, duration_seconds)
		tm.TaskType.DELIVER_FOOD:
			_add_performance_sample("deliveries", maxi(1, _last_delivery_batch_count), duration_seconds)

func _add_performance_sample(key: String, amount: int, duration_seconds: float) -> void:
	_performance_counts[key] = int(_performance_counts.get(key, 0)) + amount
	_performance_seconds[key] = float(_performance_seconds.get(key, 0.0)) + maxf(0.0, duration_seconds)

func _avg_seconds(key: String) -> float:
	var count := int(_performance_counts.get(key, 0))
	if count <= 0:
		return 0.0
	return float(_performance_seconds.get(key, 0.0)) / float(count)

func get_job_role_options() -> Array[Dictionary]:
	return [
		{"id": JobRole.AUTO, "label": "Auto"},
		{"id": JobRole.CASHIER, "label": "Cashier"},
		{"id": JobRole.MEAT_GRILLER, "label": "Meat Griller"},
		{"id": JobRole.BURGER_PREPPER, "label": "Burger Prepper"},
		{"id": JobRole.FRIES_FRYER, "label": "Fries Fryer"},
		{"id": JobRole.CATERER, "label": "Caterer"}
	]

func get_job_role_label() -> String:
	return _get_job_role_label(job_role)

func set_job_role(role: int) -> void:
	job_role = role
	if _pending_job_role == role:
		_pending_job_role = -1
		_pending_job_role_reason = ""
	_last_idle_station = null
	if is_inside_tree() and not _is_executing:
		_move_to_assigned_idle_station()

func request_job_role(role: int, reason: String = "") -> bool:
	if not _is_executing:
		set_job_role(role)
		return true
	_pending_job_role = role
	_pending_job_role_reason = reason
	return false

func _apply_pending_job_role_if_any() -> void:
	if _pending_job_role < 0:
		return
	var role := _pending_job_role
	_pending_job_role = -1
	_pending_job_role_reason = ""
	set_job_role(role)

func _get_job_role_label(role: int) -> String:
	match role:
		JobRole.AUTO:
			return "Auto"
		JobRole.CASHIER:
			return "Cashier"
		JobRole.MEAT_GRILLER:
			return "Meat Griller"
		JobRole.BURGER_PREPPER:
			return "Burger Prepper"
		JobRole.FRIES_FRYER:
			return "Fries Fryer"
		JobRole.CATERER:
			return "Caterer"
	return "Unknown"

func _move_to_assigned_idle_station() -> void:
	if _worker == null or not is_instance_valid(_worker) or _is_executing:
		return
	var tm := get_node_or_null("/root/TaskManager")
	if tm == null or not tm.has_method("get_assigned_station_for_worker"):
		return
	var station := tm.call("get_assigned_station_for_worker", _worker, job_role) as Node
	if station == null or not is_instance_valid(station):
		_last_idle_station = null
		if job_role != JobRole.AUTO and job_role != JobRole.CATERER:
			reason_text = "No workstation available"
		return

	var idle_point := _get_station_idle_point(station)
	if idle_point == null:
		return
	if _last_idle_station == station and _worker.global_position.distance_to(idle_point.global_position) <= 0.45:
		reason_text = "At %s station" % _get_job_role_label(job_role)
		return

	_last_idle_station = station
	reason_text = "Going to %s station" % _get_job_role_label(job_role)
	_move_worker_to(idle_point.global_position, _get_station_idle_look_target(station, idle_point))

func _get_station_idle_point(station: Node) -> Node3D:
	if station == null or not is_instance_valid(station):
		return null
	if station.has_method("get_stand_point"):
		var stand := station.call("get_stand_point") as Node3D
		if stand != null:
			return stand
	if station.has_method("get_snap_point"):
		var snap := station.call("get_snap_point") as Node3D
		if snap != null:
			return snap
	if station.has_method("get_entrance_point"):
		var entrance := station.call("get_entrance_point") as Node3D
		if entrance != null:
			return entrance
	return station as Node3D

func _get_station_idle_look_target(station: Node, idle_point: Node3D) -> Variant:
	if station != null and station.has_method("get_look_target"):
		return station.call("get_look_target")
	if station is Node3D:
		return (station as Node3D).global_position
	if idle_point != null:
		var parent_3d := idle_point.get_parent() as Node3D
		if parent_3d != null:
			return parent_3d.global_position
	return null

func _format_vector(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]

func _apply_movement_stat() -> void:
	if _worker == null or stats == null:
		return
	if _worker.has_method("set_move_speed"):
		_worker.call("set_move_speed", _base_move_speed * maxf(0.25, 1.0 + (float(stats.movement_speed_pct) / 100.0)))

func _get_effective_speed_pct(stat_name: String) -> int:
	if stats == null:
		return -10 if job_role == JobRole.AUTO and stat_name != "movement" else 0
	var pct := 0
	match stat_name:
		"movement":
			pct = stats.movement_speed_pct
		"order":
			pct = stats.order_speed_pct
		"grill":
			pct = stats.grill_speed_pct
		"fry":
			pct = stats.fry_speed_pct
		"prep":
			pct = stats.prep_speed_pct
		"delivery":
			pct = stats.delivery_speed_pct
	if job_role == JobRole.AUTO and stat_name != "movement":
		pct -= 10
	return pct

func _duration_multiplier(speed_pct: int) -> float:
	return 1.0 / maxf(0.25, 1.0 + (float(speed_pct) / 100.0))

func _scaled_duration(duration: float, speed_pct: int) -> float:
	return duration * _duration_multiplier(speed_pct)

func _set_reach_timing_scale(reach: Node, duration_multiplier: float) -> void:
	if reach != null and reach.has_method("set_timing_scale"):
		reach.call("set_timing_scale", duration_multiplier)

func _reset_reach_timing_scale(reach: Node) -> void:
	if reach != null and reach.has_method("reset_timing_scale"):
		reach.call("reset_timing_scale")

func _get_effective_delivery_capacity() -> int:
	var capacity := stats.delivery_capacity if stats != null else 1
	if job_role != JobRole.CATERER:
		capacity = mini(capacity, 2)
	return clampi(capacity, 1, 3)

func _delivery_is_valid(customer: Node, task: Object) -> bool:
	if customer == null or not is_instance_valid(customer):
		return false
	if customer.has_method("can_accept_delivery_task"):
		return bool(customer.call("can_accept_delivery_task", task))
	return true

func _return_food_to_table(food_table: Node, food_item: Node3D, food_type: String = "") -> void:
	if food_table == null or food_item == null or not is_instance_valid(food_item):
		return
	if food_table.has_method("store_food_item"):
		food_table.call("store_food_item", food_item, food_type)
		return
	var table_storage := _get_food_table_burger_storage_point(food_table)
	if food_item.get_parent() != null:
		food_item.reparent(food_table, true)
	else:
		food_table.add_child(food_item)
	if table_storage != null:
		food_item.global_position = table_storage.global_position
	food_item.visible = true
