extends Node

enum State {
	ENTERING,
	WAITING_FOR_REGISTER,
	ORDERING,
	WAITING_FOR_SEAT,
	SEATED_WAITING_FOR_FOOD,
	EATING,
	LEAVING,
	GONE
}

var state: int = State.ENTERING
var customer: CharacterBody3D
var my_seat: Node3D = null
var current_target: Node3D = null
var tm: Node
var _wait_timer: float = 0.0
var _has_ordered: bool = false
var _food_received: bool = false
var _delivery_reservation: Variant = null
var ordered_food_type := ""
var _order_label: Label3D = null
var _held_food_attachment: Node3D = null
var _held_food_item: Node3D = null
var _assigned_register_marker: Node3D = null
var _register_task_requested := false
var _eating_controller: Node = null

const FOOD_BURGER := "burger"
const FOOD_FRIES := "fries"
const ORDER_LABEL_HEIGHT := 2.1
const CUSTOMER_HAND_BONE := "RightHand"
const CUSTOMER_HAND_OFFSET := Vector3(0.0, -0.1, 0.04)

func _ready() -> void:
	customer = get_parent() as CharacterBody3D
	tm = get_node("/root/TaskManager")
	_eating_controller = _get_eating_controller()
	if customer != null and customer.has_signal("arrived_at_target"):
		var arrival_callback := Callable(self, "_on_customer_arrived_at_target")
		if not customer.arrived_at_target.is_connected(arrival_callback):
			customer.arrived_at_target.connect(arrival_callback)
	call_deferred("_start_ai")

func _start_ai() -> void:
	var cm := _get_customer_manager()
	if cm != null and cm.has_method("request_register_slot"):
		state = State.WAITING_FOR_REGISTER
		cm.call("request_register_slot", self)
	else:
		current_target = _find_register_customer_point()
		if current_target != null:
			go_to_register(current_target)
		else:
			_leave()

func go_to_register(register_marker: Node3D) -> void:
	if register_marker == null or not is_instance_valid(register_marker):
		_leave()
		return
	_assigned_register_marker = register_marker
	_register_task_requested = false
	current_target = register_marker
	state = State.WAITING_FOR_REGISTER
	_move_to(register_marker.global_position, _get_register_look_target(register_marker))

func wait_in_register_queue(queue_marker: Node3D, look_target: Vector3) -> void:
	if queue_marker == null or not is_instance_valid(queue_marker):
		return
	if _assigned_register_marker != null and is_instance_valid(_assigned_register_marker):
		return
	current_target = queue_marker
	state = State.WAITING_FOR_REGISTER
	_move_to(queue_marker.global_position, look_target)

func _physics_process(delta: float) -> void:
	if customer == null or not is_instance_valid(customer): return
	
	if state == State.WAITING_FOR_REGISTER:
		if _assigned_register_marker != null and is_instance_valid(_assigned_register_marker) and _is_at_target() and not _register_task_requested:
			state = State.ORDERING
			_wait_timer = 2.0 # Wait a bit before order is placed if no worker, but worker should come
			_register_task_requested = true
			tm.add_task(tm.TaskType.PROCESS_ORDER, {"customer": self, "register_marker": _assigned_register_marker})
			
	elif state == State.ORDERING:
		if _has_ordered:
			_wait_timer -= delta
			if _wait_timer <= 0:
				_release_register_slot()
				_find_seat()
				
	elif state == State.WAITING_FOR_SEAT:
		if not customer.has_method("sit_at_seat") and _is_at_target():
			_snap_customer_to_seat()
			
	elif state == State.SEATED_WAITING_FOR_FOOD:
		if _food_received:
			state = State.EATING
			_wait_timer = 5.0 # Eat for 5 seconds
			_start_eating_motion()
			
	elif state == State.EATING:
		_wait_timer -= delta
		if _wait_timer <= 0:
			var rm = get_node("/root/RestaurantManager")
			var order_total := 15.50
			if rm != null and rm.has_method("get_food_price"):
				order_total = float(rm.call("get_food_price", ordered_food_type))
			rm.add_money(order_total) # Pay
			_leave()
			
	elif state == State.LEAVING:
		if _is_at_target():
			state = State.GONE
			var cm = customer.get_parent()
			if cm and cm.has_method("customer_left"):
				cm.customer_left()
			clear_delivery_reservation()
			customer.queue_free()

func _is_at_target() -> bool:
	if current_target == null: return false
	var target_pos = current_target.global_position
	var my_pos = customer.global_position
	target_pos.y = 0
	my_pos.y = 0
	var dist = my_pos.distance_to(target_pos)
	return dist < 1.2 # Tolerance

func take_order(worker: Node) -> void:
	if _has_ordered: return
	_has_ordered = true
	ordered_food_type = _choose_order_type()
	_show_order_label()
	
	var level = customer.get_tree().current_scene
	var prep_station = level.find_child("BurgerPrepStation", true, false)
	var fryer_station = level.find_child("Fryer_1", true, false)
	var food_table = level.find_child("FoodTable", true, false)
	
	if food_table != null:
		if ordered_food_type == FOOD_BURGER and prep_station != null:
			tm.add_task(tm.TaskType.ASSEMBLE_BURGER, {"station": prep_station, "food_table": food_table, "customer": self, "food_type": ordered_food_type})
		elif ordered_food_type == FOOD_FRIES and fryer_station != null:
			tm.add_task(tm.TaskType.FRY_FRIES, {"station": fryer_station, "food_table": food_table, "customer": self, "food_type": ordered_food_type})

func can_accept_delivery_task(reservation: Variant = null) -> bool:
	if _food_received:
		return false
	if state == State.LEAVING or state == State.GONE:
		return false
	if customer == null or not is_instance_valid(customer):
		return false
	return _delivery_reservation == null or _delivery_reservation == reservation

func reserve_delivery(reservation: Variant) -> bool:
	if not can_accept_delivery_task(reservation):
		return false
	_delivery_reservation = reservation
	return true

func clear_delivery_reservation(reservation: Variant = null) -> void:
	if reservation == null or _delivery_reservation == reservation:
		_delivery_reservation = null

func has_received_food() -> bool:
	return _food_received

func get_delivery_reservation_label() -> String:
	if _delivery_reservation == null:
		return "none"
	if _delivery_reservation is Object and is_instance_valid(_delivery_reservation):
		return str((_delivery_reservation as Object).get_instance_id())
	return str(_delivery_reservation)

func receive_food(reservation: Variant = null, food_item: Node3D = null) -> bool:
	if not can_accept_delivery_task(reservation):
		return false
	if food_item != null and is_instance_valid(food_item):
		_attach_food_to_hand(food_item)
	_food_received = true
	clear_delivery_reservation(reservation)
	if state == State.EATING:
		_start_eating_motion()
	return true

func get_ordered_food_type() -> String:
	return ordered_food_type

func _choose_order_type() -> String:
	return FOOD_BURGER if randf() > 0.5 else FOOD_FRIES

func _show_order_label() -> void:
	if _order_label == null:
		_order_label = Label3D.new()
		_order_label.name = "OrderLabel"
		_order_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_order_label.no_depth_test = true
		_order_label.pixel_size = 0.01
		_order_label.modulate = Color(1.0, 0.95, 0.2, 1.0)
		customer.add_child(_order_label)
		_order_label.position = Vector3.UP * ORDER_LABEL_HEIGHT
	_order_label.text = "Burger" if ordered_food_type == FOOD_BURGER else "Fries"
	_order_label.visible = true

func _set_order_label_visible(value: bool) -> void:
	if _order_label != null and is_instance_valid(_order_label):
		_order_label.visible = value

func _attach_food_to_hand(food_item: Node3D) -> void:
	_clear_held_food()
	var carried_global_scale := food_item.global_transform.basis.get_scale()
	var attachment_parent := _find_skeleton(customer)
	var attachment := Node3D.new()
	attachment.name = "CustomerHeldFood"
	if attachment_parent != null:
		var bone_attachment := BoneAttachment3D.new()
		bone_attachment.name = attachment.name
		bone_attachment.bone_name = CUSTOMER_HAND_BONE
		attachment_parent.add_child(bone_attachment)
		attachment = bone_attachment
	else:
		customer.add_child(attachment)
		attachment.position = Vector3(0.32, 1.0, 0.2)

	if food_item.get_parent() != null:
		food_item.reparent(attachment, false)
	else:
		attachment.add_child(food_item)
	food_item.visible = true
	food_item.position = CUSTOMER_HAND_OFFSET
	food_item.rotation_degrees = Vector3.ZERO
	_apply_global_scale(food_item, carried_global_scale)
	_held_food_attachment = attachment
	_held_food_item = food_item

func _clear_held_food() -> void:
	_stop_eating_motion()
	if _held_food_attachment != null and is_instance_valid(_held_food_attachment):
		_held_food_attachment.queue_free()
	elif _held_food_item != null and is_instance_valid(_held_food_item):
		_held_food_item.queue_free()
	_held_food_attachment = null
	_held_food_item = null

func _start_eating_motion() -> void:
	_eating_controller = _get_eating_controller()
	if _eating_controller != null and _eating_controller.has_method("start_eating"):
		_eating_controller.call("start_eating")

func _stop_eating_motion() -> void:
	_eating_controller = _get_eating_controller()
	if _eating_controller != null and _eating_controller.has_method("stop_eating"):
		_eating_controller.call("stop_eating")

func _get_eating_controller() -> Node:
	if _eating_controller != null and is_instance_valid(_eating_controller):
		return _eating_controller
	if customer == null or not is_instance_valid(customer):
		return null
	return customer.get_node_or_null(^"CustomerEatingController")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
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

func _find_seat() -> void:
	var level = customer.get_tree().current_scene
	var seating_map = level.find_child("SeatingMap", true, false)
	if seating_map == null: 
		_leave()
		return
		
	var seats: Array[Node3D] = []
	_collect_seat_markers(seating_map, seats)
	
	for seat in seats:
		# Simple: just pick random for now, ignore if occupied (would need tracking)
		my_seat = seat
		break
		
	if my_seat != null:
		_send_customer_to_seat(my_seat)
	else:
		_leave()

func _leave() -> void:
	state = State.LEAVING
	_release_register_slot()
	clear_delivery_reservation()
	_clear_held_food()
	_set_order_label_visible(false)
	if customer.has_method("stand_up"):
		customer.call("stand_up")

	var leave_point := _get_customer_spawn_point()
	if leave_point != null:
		current_target = leave_point
		_move_to(leave_point.global_position)
	else:
		# Fallback
		var cm = customer.get_parent()
		if cm and cm.has_method("customer_left"):
			cm.customer_left()
		clear_delivery_reservation()
		customer.queue_free()

func _get_customer_spawn_point() -> Node3D:
	var cm = customer.get_parent()
	if cm != null:
		var configured_path: NodePath = cm.get("spawn_point_path")
		if not configured_path.is_empty():
			var configured := cm.get_node_or_null(configured_path) as Node3D
			if configured != null:
				return configured

	var level = customer.get_tree().current_scene
	if level != null:
		return level.find_child("Door_01", true, false) as Node3D
	return null

func _move_to(target_pos: Vector3, look_target: Variant = null) -> void:
	var nav_map = customer.get_world_3d().navigation_map
	var closest_point = NavigationServer3D.map_get_closest_point(nav_map, target_pos)
	if look_target is Vector3 and customer.has_method("set_navigation_target_with_look_target"):
		customer.call("set_navigation_target_with_look_target", closest_point, look_target)
	elif customer.has_method("set_navigation_target"):
		customer.call("set_navigation_target", closest_point)

func _release_register_slot() -> void:
	if _assigned_register_marker == null and not _register_task_requested:
		var cm_queued := _get_customer_manager()
		if cm_queued != null and cm_queued.has_method("release_register_slot"):
			cm_queued.call("release_register_slot", self)
		return
	var cm := _get_customer_manager()
	if cm != null and cm.has_method("release_register_slot"):
		cm.call("release_register_slot", self)
	_assigned_register_marker = null
	_register_task_requested = false

func _get_customer_manager() -> Node:
	if customer == null:
		return null
	return customer.get_parent()

func _send_customer_to_seat(seat: Node3D) -> void:
	state = State.WAITING_FOR_SEAT
	current_target = _get_seat_approach_marker(seat)
	if current_target == null:
		current_target = seat

	if customer.has_method("sit_at_seat"):
		customer.call("sit_at_seat", seat)
	else:
		_move_to(current_target.global_position)

func _on_customer_arrived_at_target(_target_position: Vector3) -> void:
	if state == State.WAITING_FOR_SEAT:
		_mark_customer_seated()

func _snap_customer_to_seat() -> void:
	if my_seat == null:
		_leave()
		return
	customer.global_position = my_seat.global_position
	customer.rotation.y = my_seat.global_transform.basis.get_euler().y
	_mark_customer_seated()

func _mark_customer_seated() -> void:
	state = State.SEATED_WAITING_FOR_FOOD

func _find_register_customer_point() -> Node3D:
	var level = customer.get_tree().current_scene
	var seating_map = level.find_child("SeatingMap", true, false)
	if seating_map == null: return null
	var customer_points: Array[Node3D] = []
	_collect_register_markers(seating_map, "Opposite", customer_points)
	if customer_points.is_empty(): return null
	return customer_points[randi() % customer_points.size()]

func _get_register_look_target(register_marker: Node3D) -> Vector3:
	var register_root := register_marker.get_parent() as Node3D
	if register_root != null:
		return register_root.global_position
	return register_marker.global_position

func _collect_register_markers(node: Node, marker_suffix: String, markers: Array[Node3D]) -> void:
	if node is Node3D:
		var node_name = String(node.name)
		if node_name.begins_with("CashRegister_") and node_name.ends_with("_" + marker_suffix):
			markers.append(node as Node3D)
	for child in node.get_children():
		_collect_register_markers(child, marker_suffix, markers)

func _collect_seat_markers(node: Node, markers: Array[Node3D]) -> void:
	if node is Node3D:
		var node_name = String(node.name)
		if node_name.contains("_Seat_") and not bool((node as Node3D).get_meta("occupied", false)):
			markers.append(node as Node3D)
	for child in node.get_children():
		_collect_seat_markers(child, markers)

func _get_seat_approach_marker(seat: Node3D) -> Node3D:
	if seat == null or not seat.has_meta("approach_path"):
		return null

	var approach_path := seat.get_meta("approach_path") as NodePath
	return seat.get_node_or_null(approach_path) as Node3D
