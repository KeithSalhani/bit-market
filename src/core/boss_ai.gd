extends Node
class_name BossAI

signal status_changed()

const BossKnowledgeScript: Script = preload("res://src/core/boss_knowledge.gd")
const GeminiLLMClientScript: Script = preload("res://src/core/gemini_llm_client.gd")
const ROUTE_ZONES := ["registers", "grill", "fryer", "prep", "food_table", "dining_room", "workers"]
const DEBUG_LOG_PATH := "user://boss_manager_debug.jsonl"
const MANAGER_DECISION_SECONDS := 20.0
const STOCK_CAPS := {"burger": 3, "fries": 3, "meat": 24}
const MEAT_OVERSTOCK_THRESHOLD := 24
const MEAT_OVERSTOCK_HARD_LIMIT := 30
const ROLE_LABELS := {
	0: "Auto",
	1: "Cashier",
	2: "Meat Griller",
	3: "Burger Prepper",
	4: "Fries Fryer",
	5: "Caterer",
}
const ROLE_IDS := {
	"auto": 0,
	"cashier": 1,
	"meat_griller": 2,
	"meat griller": 2,
	"griller": 2,
	"burger_prepper": 3,
	"burger prepper": 3,
	"prepper": 3,
	"fries_fryer": 4,
	"fries fryer": 4,
	"fryer": 4,
	"caterer": 5,
}
const MIN_PRICES := {"burger": 3.0, "fries": 1.0, "soda": 0.5}
const MAX_PRICES := {"burger": 8.0, "fries": 4.0, "soda": 3.0}

@export var observation_radius := 4.5
@export var pause_at_zone_seconds := 1.2
@export var decision_cooldown_seconds := MANAGER_DECISION_SECONDS
@export var director_interval_seconds := 5.0
@export var price_cooldown_seconds := 45.0
@export var route_completion_decisions := false
@export var debug_log_enabled := false
@export var debug_log_reset_on_start := true

var knowledge: RefCounted = BossKnowledgeScript.new()
var current_destination := "starting"
var last_llm_action := "-"
var last_rejected_reason := ""
var last_failure := ""
var last_raw_llm_json := ""
var last_raw_llm_prompt := ""
var boss_speech := ""

var _boss: CharacterBody3D
var _llm_client: Node
var _zone_index := 0
var _route_observations_since_decision := 0
var _last_decision_time := -999.0
var _last_price_change_time := -999.0
var _last_director_time := -999.0
var _action_history: Array[String] = []
var _event_log: Array[Dictionary] = []
var _event_sequence := 0
var _pending_role_changes: Dictionary = {}
var _last_metrics_snapshot: Dictionary = {}
var _last_parsed_plan: Dictionary = {}
var _last_validation_results: Array[Dictionary] = []
var _questioned_worker_traits: Dictionary = {}
var _opening_plan_requested := false

func _ready() -> void:
	_boss = get_parent() as CharacterBody3D
	_llm_client = Node.new()
	_llm_client.set_script(GeminiLLMClientScript)
	_llm_client.name = "GeminiLLMClient"
	_llm_client.action_received.connect(_on_llm_action_received)
	_llm_client.request_failed.connect(_on_llm_request_failed)
	add_child(_llm_client)
	var rm := get_node_or_null("/root/RestaurantManager")
	if rm != null and rm.has_signal("open_state_changed"):
		rm.open_state_changed.connect(_on_restaurant_open_state_changed)
	_initialize_debug_log()
	call_deferred("_patrol_loop")

func get_status() -> Dictionary:
	return {
		"destination": current_destination,
		"latest_observations": knowledge.get_latest_observations(4),
		"known_zones": knowledge.get_known_zone_ids(),
		"stale_zones": knowledge.get_stale_zone_ids(PackedStringArray(ROUTE_ZONES), _now()),
		"last_action": last_llm_action,
		"rejected_reason": last_rejected_reason,
		"failure": last_failure,
		"raw_json": last_raw_llm_json,
		"raw_prompt": last_raw_llm_prompt,
		"speech": boss_speech,
		"llm_enabled": _llm_client != null and _llm_client.enabled,
		"llm_available": _llm_client != null and _llm_client.is_available(),
		"next_director_seconds": maxf(0.0, director_interval_seconds - (_now() - _last_director_time)),
		"next_llm_seconds": maxf(0.0, decision_cooldown_seconds - (_now() - _last_decision_time)),
		"event_log": _event_log.duplicate(),
		"debug_log_path": ProjectSettings.globalize_path(DEBUG_LOG_PATH) if debug_log_enabled else "",
		"pending_role_changes": _pending_role_changes.duplicate(true),
		"worker_metrics": _last_metrics_snapshot.get("workers", []),
		"restaurant_metrics": _last_metrics_snapshot.get("restaurant", {}),
		"last_plan": _last_parsed_plan.duplicate(true),
		"validation_results": _last_validation_results.duplicate(true),
	}

func _patrol_loop() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	while is_inside_tree() and is_instance_valid(_boss):
		var zone_id: String = ROUTE_ZONES[_zone_index]
		current_destination = zone_id
		status_changed.emit()
		var destination := _resolve_zone_destination(zone_id)
		if destination != null:
			_move_boss_to(destination)
			await _boss.arrived_at_target
		await get_tree().create_timer(pause_at_zone_seconds).timeout
		_observe_zone(zone_id)
		_run_local_execution_tick()
		_request_llm_decision_if_ready()
		_zone_index = (_zone_index + 1) % ROUTE_ZONES.size()
		if _zone_index == 0 and route_completion_decisions:
			_request_llm_decision_if_ready()

func _move_boss_to(target: Node3D) -> void:
	var nav_map: RID = _boss.get_world_3d().navigation_map
	var closest: Vector3 = target.global_position
	if NavigationServer3D.map_get_iteration_id(nav_map) != 0:
		closest = NavigationServer3D.map_get_closest_point(nav_map, target.global_position)
	if _boss.has_method("set_navigation_target_with_look_target"):
		_boss.call("set_navigation_target_with_look_target", closest, target.global_position)
	elif _boss.has_method("set_navigation_target"):
		_boss.call("set_navigation_target", closest)

func _observe_zone(zone_id: String) -> void:
	var facts: Array[String] = []
	match zone_id:
		"registers":
			facts = _observe_registers()
		"grill":
			facts = _observe_stations_with_method("cook_meat", "grill")
		"fryer":
			facts = _observe_stations_with_method("fry_fries", "fryer")
		"prep":
			facts = _observe_prep()
		"food_table":
			facts = _observe_food_table()
		"dining_room":
			facts = _observe_dining_room()
		"workers":
			facts = _observe_workers()
		_:
			facts = ["No known observation routine."]
	if facts.is_empty():
		facts.append("No clear facts observed nearby.")
	knowledge.add_observation(zone_id, facts, 0.75, _now())
	_route_observations_since_decision += 1
	_record_event("observe", zone_id, "; ".join(facts), {})
	status_changed.emit()

func _observe_registers() -> Array[String]:
	var facts: Array[String] = []
	var markers: Array[Node3D] = _collect_register_markers("Approach")
	facts.append("%d register worker positions visible." % markers.size())
	var cashier_count: int = _count_workers_in_role(1)
	facts.append("%d observed workers currently assigned as cashiers." % cashier_count)
	var cm: Node = _current_scene_node("CustomerManager")
	if cm != null:
		facts.append("%d customers in restaurant according to the front-of-house count." % int(cm.get("current_customers")))
	var register_waiting: int = _count_customers_in_states([1, 2])
	if register_waiting > 0:
		facts.append("%d customers appear to be waiting at or near registers." % register_waiting)
	return facts

func _observe_stations_with_method(method_name: String, label: String) -> Array[String]:
	var stations: Array[Node] = []
	_collect_nodes_with_method(get_tree().current_scene, method_name, stations)
	var available: int = 0
	var busy: int = 0
	for station in stations:
		if station.has_method("is_available") and not bool(station.call("is_available")):
			busy += 1
		else:
			available += 1
	return ["%d %s stations visible, %d available and %d busy." % [stations.size(), label, available, busy]]

func _observe_prep() -> Array[String]:
	var prep: Node = _best_prep_station_for_backlog()
	if prep == null:
		return ["Prep station not found from this route point."]
	var facts: Array[String] = []
	if prep.has_method("has_cooked_meat"):
		facts.append("Cooked meat stock appears %s." % ("available" if bool(prep.call("has_cooked_meat")) else "low or empty"))
	if prep.has_method("get_finished_burger_count"):
		facts.append("%d finished burgers seen at prep." % int(prep.call("get_finished_burger_count")))
	if prep.has_method("is_available"):
		facts.append("Prep station is %s." % ("available" if bool(prep.call("is_available")) else "busy"))
	return facts

func _observe_food_table() -> Array[String]:
	var table: Node = _current_scene_node("FoodTable")
	if table == null:
		return ["Food table not found from this route point."]
	var facts: Array[String] = []
	if table.has_method("get_available_food_capacity"):
		facts.append("%d food table slots appear open." % int(table.call("get_available_food_capacity")))
	if table.has_method("has_food_item"):
		facts.append("Ready burgers: %s." % ("yes" if bool(table.call("has_food_item", "burger")) else "no"))
		facts.append("Ready fries: %s." % ("yes" if bool(table.call("has_food_item", "fries")) else "no"))
		facts.append("Ready counts look like burgers %d, fries %d." % [_count_ready_food(table, "burger"), _count_ready_food(table, "fries")])
	return facts

func _observe_dining_room() -> Array[String]:
	var seating_map: Node = _current_scene_node("SeatingMap")
	var seats: int = 0
	var occupied: int = 0
	if seating_map != null:
		var stack: Array[Node] = [seating_map]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if String(node.name).contains("_Seat_"):
				seats += 1
				if node.has_meta("occupied") and bool(node.get_meta("occupied")):
					occupied += 1
			for child in node.get_children():
				stack.append(child)
	return ["Dining room shows %d occupied seats out of %d visible seats." % [occupied, seats]]

func _observe_workers() -> Array[String]:
	var facts: Array[String] = []
	var observed: int = 0
	for worker in get_tree().get_nodes_in_group("worker_npc"):
		if worker == null or not is_instance_valid(worker):
			continue
		if _boss.global_position.distance_to((worker as Node3D).global_position) > observation_radius:
			continue
		observed += 1
		var inferred: Array[String] = _infer_worker_facts(worker)
		knowledge.add_worker_observation(String(worker.name), inferred, 0.65, _now())
		facts.append("%s observed: %s" % [String(worker.name), "; ".join(inferred)])
	facts.append("%d workers close enough to observe." % observed)
	return facts

func _infer_worker_facts(worker: Node) -> Array[String]:
	var ai: Node = worker.get_node_or_null("WorkerAI")
	if ai == null or not ai.has_method("get_activity_status"):
		return ["no visible activity details"]
	var status: Dictionary = ai.call("get_activity_status")
	var action := String(status.get("action", "-"))
	var role := String(status.get("role", "-"))
	var reason := String(status.get("reason", "-"))
	var facts: Array[String] = ["role %s" % role, "currently %s" % action]
	if reason != "-":
		facts.append("reason: %s" % reason)
	if ai.has_method("get_interview_summary"):
		var interview: Dictionary = ai.call("get_interview_summary")
		_questioned_worker_traits[String(worker.name)] = {
			"delivery_capacity": int(interview.get("delivery_capacity", 1)),
			"asked_at_seconds": _now(),
			"source": "boss_questioned_worker",
		}
		facts.append("worker says they can carry %d delivery item(s) per trip" % int(interview.get("delivery_capacity", 1)))
	if action.to_lower() == "idle":
		facts.append("may be underutilized if this repeats")
	else:
		facts.append("appears active in assigned work")
	return facts

func _on_restaurant_open_state_changed(is_open: bool) -> void:
	if not is_open:
		_opening_plan_requested = false
		return
	call_deferred("_run_opening_manager_assessment")

func _run_opening_manager_assessment() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if _opening_plan_requested:
		return
	_opening_plan_requested = true
	_interview_all_workers_for_opening()
	_last_director_time = -999.0
	_run_local_execution_tick()
	_request_llm_decision_if_ready(true, "Sent opening manager plan request after crew interviews.")

func _interview_all_workers_for_opening() -> void:
	var summaries := PackedStringArray()
	for worker in get_tree().get_nodes_in_group("worker_npc"):
		if worker == null or not is_instance_valid(worker):
			continue
		var ai: Node = worker.get_node_or_null("WorkerAI")
		if ai == null or not ai.has_method("get_interview_summary"):
			continue
		var interview: Dictionary = ai.call("get_interview_summary")
		_questioned_worker_traits[String(worker.name)] = {
			"delivery_capacity": int(interview.get("delivery_capacity", 1)),
			"asked_at_seconds": _now(),
			"source": "opening_crew_interview",
		}
		summaries.append("%s carry %d" % [String(worker.name), int(interview.get("delivery_capacity", 1))])
	if not summaries.is_empty():
		_record_event("observe", "opening_interviews", "Opening crew interviews: %s." % "; ".join(summaries), {})

func _request_llm_decision_if_ready(force := false, explanation := "Sent manager plan request.") -> void:
	var rm: Node = get_node_or_null("/root/RestaurantManager")
	if rm == null or not bool(rm.get("is_open")):
		return
	if _llm_client == null or not _llm_client.is_available():
		if _llm_client != null and not _llm_client.enabled:
			last_failure = "LLM disabled or missing config; boss will keep observing."
			_record_event("llm", "disabled", last_failure, {})
			status_changed.emit()
		return
	if not force and _now() - _last_decision_time < decision_cooldown_seconds:
		return
	_last_decision_time = _now()
	_route_observations_since_decision = 0
	last_raw_llm_prompt = _build_prompt()
	_record_event("llm", "request", explanation, {
		"prompt": last_raw_llm_prompt,
		"metrics": _last_metrics_snapshot,
	})
	_llm_client.request_action(last_raw_llm_prompt)

func _run_local_execution_tick() -> void:
	if _now() - _last_director_time < director_interval_seconds:
		return
	_last_director_time = _now()
	var rm: Node = get_node("/root/RestaurantManager")
	if rm == null or not bool(rm.get("is_open")):
		_record_event("local", "skip", "Restaurant is closed.", {})
		return
	var actions: PackedStringArray = []
	var food_table: Node = _current_scene_node("FoodTable")
	var tm: Node = get_node_or_null("/root/TaskManager")
	_apply_pending_role_changes(actions)
	_ensure_assigned_grillers_have_work(tm, actions)
	_ensure_ready_food_deliveries(food_table, actions)
	_last_metrics_snapshot = _build_manager_metrics()
	if not actions.is_empty():
		_record_event("local", "actions", "; ".join(actions), {
			"metrics": _last_metrics_snapshot,
			"pending_role_changes": _pending_role_changes,
		})
		_say(actions[0].capitalize())
		status_changed.emit()
	else:
		_record_event("local", "no_action", "No local execution action needed.", {
			"metrics": _last_metrics_snapshot,
			"pending_role_changes": _pending_role_changes,
		})
		status_changed.emit()

func _assign_workers_for_service(workers: Array[Node], register_waiting: int, ordered_burgers: int, ordered_fries: int, seated_waiting: int, grill_needed: bool, actions: PackedStringArray) -> void:
	if workers.is_empty():
		return
	workers.sort_custom(func(a: Node, b: Node) -> bool:
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0
	)
	if workers.size() == 1:
		_set_worker_role_director(workers[0], 0, actions)
		return

	var index := 0
	if register_waiting > 0:
		_set_worker_role_director(workers[index], 1, actions)
		index += 1
	if workers.size() >= 3 and grill_needed and index < workers.size():
		_set_worker_role_director(workers[index], 2, actions)
		index += 1
	if workers.size() >= 4 and ordered_burgers > 0 and index < workers.size():
		_set_worker_role_director(workers[index], 3, actions)
		index += 1
	if workers.size() >= 4 and ordered_fries > 0 and index < workers.size():
		_set_worker_role_director(workers[index], 4, actions)
		index += 1
	if seated_waiting > 1 and index < workers.size():
		_set_worker_role_director(workers[index], 5, actions)
		index += 1
	while index < workers.size():
		_set_worker_role_director(workers[index], 0, actions)
		index += 1

func _set_worker_role_director(worker: Node, role_id: int, actions: PackedStringArray) -> void:
	var ai: Node = worker.get_node_or_null("WorkerAI") if worker != null else null
	if ai == null or int(ai.get("job_role")) == role_id:
		return
	if ai.has_method("set_job_role"):
		ai.call("set_job_role", role_id)
	else:
		ai.set("job_role", role_id)
	actions.append("assigned %s to %s" % [String(worker.name), String(ROLE_LABELS[role_id]).to_lower()])

func _ensure_food_backlog(prep: Node, food_table: Node, ordered_burgers: int, ordered_fries: int, actions: PackedStringArray) -> void:
	var tm: Node = get_node_or_null("/root/TaskManager")
	if tm == null or food_table == null:
		return
	var ready_burgers: int = _count_ready_food(food_table, "burger")
	var ready_fries: int = _count_ready_food(food_table, "fries")
	var burger_work: int = _count_production_tasks_for_food(tm, "burger") + ready_burgers
	var fries_work: int = _count_production_tasks_for_food(tm, "fries") + ready_fries
	var burger_target: int = maxi(ordered_burgers, 1 if _get_customer_count() > 0 else 0)
	var fries_target: int = maxi(ordered_fries, 1 if _get_customer_count() > 1 else 0)

	var burgers_to_queue: int = maxi(0, burger_target - burger_work)
	while burgers_to_queue > 0:
		prep = _best_prep_station_for_backlog()
		if prep == null:
			break
		if prep.has_method("has_cooked_meat") and not bool(prep.call("has_cooked_meat")) and not _has_task_type(tm, tm.TaskType.COOK_MEAT):
			if tm.has_method("request_cooked_meat_for_prep"):
				tm.call("request_cooked_meat_for_prep", prep)
				actions.append("queued grill meat for burger backlog")
		tm.add_task(tm.TaskType.ASSEMBLE_BURGER, {"station": prep, "food_table": food_table, "food_type": "burger"})
		actions.append("queued burger prep backlog at %s" % _prep_station_label(prep))
		burgers_to_queue -= 1

	if fries_target > fries_work:
		var fryer: Node = _best_fryer_for_backlog()
		if fryer != null and not _has_task_type_for_food(tm, tm.TaskType.FRY_FRIES, "fries"):
			tm.add_task(tm.TaskType.FRY_FRIES, {"station": fryer, "food_table": food_table, "food_type": "fries"})
			actions.append("queued fries backlog")

func _ensure_ready_food_deliveries(food_table: Node, actions: PackedStringArray) -> void:
	if food_table == null:
		return
	var tm: Node = get_node_or_null("/root/TaskManager")
	if tm == null:
		return
	var ready_counts := {
		"burger": _count_ready_food(food_table, "burger"),
		"fries": _count_ready_food(food_table, "fries"),
	}
	if int(ready_counts["burger"]) <= 0 and int(ready_counts["fries"]) <= 0:
		return
	for customer_ai in _get_waiting_customer_ais():
		if customer_ai == null or not is_instance_valid(customer_ai):
			continue
		if _customer_has_delivery_task(tm, customer_ai):
			continue
		var food_type := ""
		if customer_ai.has_method("get_ordered_food_type"):
			food_type = String(customer_ai.call("get_ordered_food_type"))
		if food_type.is_empty() or int(ready_counts.get(food_type, 0)) <= 0:
			continue
		var seat: Node3D = customer_ai.get("my_seat") as Node3D
		if seat == null:
			continue
		var delivery = tm.add_task(tm.TaskType.DELIVER_FOOD, {
			"food_table": food_table,
			"customer": customer_ai,
			"seat": seat,
			"food_type": food_type,
		})
		if delivery != null:
			ready_counts[food_type] = int(ready_counts[food_type]) - 1
			actions.append("queued %s delivery" % food_type)

func _get_waiting_customer_ais() -> Array[Node]:
	var result: Array[Node] = []
	var cm: Node = _current_scene_node("CustomerManager")
	if cm == null:
		return result
	for child in cm.get_children():
		var ai: Node = child.get_node_or_null("CustomerAI") if child is Node else null
		if ai == null:
			continue
		if int(ai.get("state")) == 4:
			result.append(ai)
	return result

func _customer_has_delivery_task(tm: Node, customer_ai: Node) -> bool:
	for task in _get_all_tasks(tm):
		if int(task.get("type")) != tm.TaskType.DELIVER_FOOD:
			continue
		var args: Dictionary = task.get("args") if task is Object else {}
		if args.get("customer") == customer_ai:
			return true
	return false

func _hire_worker_director() -> bool:
	var emp: Node = _current_scene_node("EmployeeManager")
	if emp == null or not emp.has_method("hire_worker"):
		return false
	var before := get_tree().get_nodes_in_group("worker_npc").size()
	emp.call("hire_worker")
	return get_tree().get_nodes_in_group("worker_npc").size() > before

func _apply_pending_role_changes(actions: PackedStringArray) -> void:
	var to_remove := PackedStringArray()
	for worker_name in _pending_role_changes.keys():
		var worker := _find_worker_by_name(String(worker_name))
		if worker == null:
			to_remove.append(String(worker_name))
			continue
		var ai: Node = worker.get_node_or_null("WorkerAI")
		if ai == null:
			to_remove.append(String(worker_name))
			continue
		if ai.has_method("is_executing_task") and bool(ai.call("is_executing_task")):
			continue
		var change: Dictionary = _pending_role_changes[worker_name]
		var role_id := int(change.get("role_id", 0))
		if int(ai.get("job_role")) != role_id:
			if not _can_move_worker_to_role(worker, role_id):
				actions.append("blocked pending role %s -> %s during service pressure" % [String(worker_name), String(ROLE_LABELS[role_id]).to_lower()])
				to_remove.append(String(worker_name))
				continue
			_set_worker_role_now(worker, role_id)
			actions.append("applied pending role %s -> %s" % [String(worker_name), String(ROLE_LABELS[role_id]).to_lower()])
		to_remove.append(String(worker_name))
	for worker_name in to_remove:
		_pending_role_changes.erase(worker_name)

func _build_manager_metrics() -> Dictionary:
	var food_table: Node = _current_scene_node("FoodTable")
	var tm: Node = get_node_or_null("/root/TaskManager")
	var restaurant := {
		"customers": _get_customer_count(),
		"register_waiting": _count_customers_in_states([1, 2]),
		"seated_waiting": _count_customers_in_states([4]),
		"ordered_burgers": _count_open_orders("burger"),
		"ordered_fries": _count_open_orders("fries"),
		"ready_burgers": _count_ready_food(food_table, "burger"),
		"ready_fries": _count_ready_food(food_table, "fries"),
		"cooked_meat": _get_shared_prep_meat_stock(),
		"pending_active_burgers": _count_production_tasks_for_food(tm, "burger") if tm != null else 0,
		"pending_active_fries": _count_production_tasks_for_food(tm, "fries") if tm != null else 0,
		"pending_active_meat": _count_tasks_of_type(tm, tm.TaskType.COOK_MEAT) if tm != null else 0,
		"pending_active_burger_deliveries": _count_delivery_tasks_for_food(tm, "burger") if tm != null else 0,
		"pending_active_fries_deliveries": _count_delivery_tasks_for_food(tm, "fries") if tm != null else 0,
		"meat_overstocked": _get_shared_prep_meat_stock() >= MEAT_OVERSTOCK_THRESHOLD,
		"meat_overstock_hard_limit": MEAT_OVERSTOCK_HARD_LIMIT,
		"pending_role_changes": _pending_role_changes.duplicate(true),
	}
	var ready_food_total := int(restaurant["ready_burgers"]) + int(restaurant["ready_fries"])
	restaurant["ready_food_total"] = ready_food_total
	var rm: Node = get_node_or_null("/root/RestaurantManager")
	if rm != null and rm.has_method("get_service_metrics"):
		restaurant["service_rates"] = rm.call("get_service_metrics")
	restaurant["delivery_pressure"] = _delivery_pressure_label(restaurant)
	var workers: Array[Dictionary] = []
	for worker in get_tree().get_nodes_in_group("worker_npc"):
		if worker == null or not is_instance_valid(worker):
			continue
		var ai: Node = worker.get_node_or_null("WorkerAI")
		if ai == null:
			continue
		var status: Dictionary = ai.call("get_activity_status") if ai.has_method("get_activity_status") else {}
		var perf: Dictionary = status.get("performance", {}) if status.has("performance") else {}
		var worker_name := String(worker.name)
		var pending_role_label := String(status.get("pending_role", ""))
		if pending_role_label.is_empty() and _pending_role_changes.has(worker_name):
			_pending_role_changes.erase(worker_name)
		var worker_entry := {
			"worker": worker_name,
			"role": String(status.get("role", "-")),
			"action": String(status.get("action", "-")),
			"task": String(status.get("task", "-")),
			"reason": String(status.get("reason", "-")),
			"is_busy": bool(status.get("is_executing", false)),
			"pending_role": pending_role_label,
			"performance": perf,
		}
		if _questioned_worker_traits.has(worker_name):
			worker_entry["interview"] = (_questioned_worker_traits[worker_name] as Dictionary).duplicate(true)
		else:
			worker_entry["interview"] = {"delivery_capacity": "unknown", "source": "not_questioned_yet"}
		workers.append(worker_entry)
	_add_worker_comparisons(workers)
	restaurant["caterer_count"] = _count_metric_workers_in_role(workers, "Caterer")
	restaurant["low_carry_caterer_count"] = _count_low_carry_caterers(workers)
	restaurant.merge(_build_delivery_staffing_metrics(workers, restaurant), true)
	return {
		"restaurant": restaurant,
		"workers": workers,
		"generated_at_seconds": _now(),
	}

func _add_worker_comparisons(workers: Array[Dictionary]) -> void:
	var keys := ["orders_per_min", "burgers_per_min", "meat_batches_per_min", "fries_batches_per_min", "deliveries_per_min"]
	var averages := {}
	for key in keys:
		var total := 0.0
		for worker in workers:
			var perf: Dictionary = worker.get("performance", {})
			total += float(perf.get(key, 0.0))
		averages[key] = total / maxf(1.0, float(workers.size()))
	for worker in workers:
		var perf: Dictionary = worker.get("performance", {})
		worker["comparison"] = {
			"cashier": _grade_rate(float(perf.get("orders_per_min", 0.0)), float(averages["orders_per_min"]), 0.25),
			"burger_prepper": _grade_rate(float(perf.get("burgers_per_min", 0.0)), float(averages["burgers_per_min"]), 0.18),
			"meat_griller": _grade_rate(float(perf.get("meat_batches_per_min", 0.0)), float(averages["meat_batches_per_min"]), 0.12),
			"fries_fryer": _grade_rate(float(perf.get("fries_batches_per_min", 0.0)), float(averages["fries_batches_per_min"]), 0.12),
			"caterer": _grade_rate(float(perf.get("deliveries_per_min", 0.0)), float(averages["deliveries_per_min"]), 0.25),
			"caterer_pressure_fit": _grade_caterer_pressure_fit(worker),
			"observed_max_carry": int(perf.get("observed_max_carry", 1)),
		}

func _grade_caterer_pressure_fit(worker: Dictionary) -> String:
	var perf: Dictionary = worker.get("performance", {})
	var carry := int(perf.get("observed_max_carry", 1))
	var deliveries_per_min := float(perf.get("deliveries_per_min", 0.0))
	if carry <= 1 and deliveries_per_min < 2.5:
		return "poor_when_many_seated"
	if carry >= 2 or deliveries_per_min >= 2.5:
		return "good"
	return "average"

func _delivery_pressure_label(restaurant: Dictionary) -> String:
	var seated := int(restaurant.get("seated_waiting", 0))
	var ready := int(restaurant.get("ready_burgers", 0)) + int(restaurant.get("ready_fries", 0))
	if seated >= 12:
		return "critical"
	if seated >= 6:
		return "high"
	if seated > 0 and ready > 0:
		return "active"
	return "low"

func _count_metric_workers_in_role(workers: Array[Dictionary], role_label: String) -> int:
	var count := 0
	for worker in workers:
		if String(worker.get("role", "")) == role_label:
			count += 1
	return count

func _count_low_carry_caterers(workers: Array[Dictionary]) -> int:
	var count := 0
	for worker in workers:
		if String(worker.get("role", "")) != "Caterer":
			continue
		var perf: Dictionary = worker.get("performance", {})
		if int(perf.get("observed_max_carry", 1)) <= 1:
			count += 1
	return count

func _build_delivery_staffing_metrics(workers: Array[Dictionary], restaurant: Dictionary) -> Dictionary:
	var formal_caterers := 0
	var active_delivery_workers := 0
	var known_carry_capacity := 0
	var low_capacity_names := PackedStringArray()
	var high_capacity_names := PackedStringArray()
	for worker in workers:
		var role := String(worker.get("role", ""))
		var action := String(worker.get("action", "")).to_lower()
		if role == "Caterer":
			formal_caterers += 1
		if role == "Caterer" or action == "delivering":
			active_delivery_workers += 1
		var worker_name := String(worker.get("worker", ""))
		var perf: Dictionary = worker.get("performance", {})
		var best_known_carry := _known_delivery_capacity_for_worker_entry(worker)
		if role == "Caterer":
			known_carry_capacity += maxi(1, best_known_carry)
			if best_known_carry <= 1:
				low_capacity_names.append(worker_name)
			elif best_known_carry > 1:
				high_capacity_names.append(worker_name)
	var seated := int(restaurant.get("seated_waiting", 0))
	var ready_food := int(restaurant.get("ready_food_total", 0))
	var recommended_caterers := 0
	if seated > 0:
		recommended_caterers = clampi(ceili(float(seated) / 5.0), 1, 4)
	var delivery_understaffed := seated >= 6 and ready_food > 0 and formal_caterers < recommended_caterers
	var delivery_capacity_short := seated >= 8 and ready_food > 0 and known_carry_capacity < ceili(float(seated) / 4.0)
	return {
		"formal_caterer_count": formal_caterers,
		"active_delivery_workers_count": active_delivery_workers,
		"known_caterer_carry_capacity": known_carry_capacity,
		"recommended_caterers": recommended_caterers,
		"delivery_understaffed": delivery_understaffed,
		"delivery_capacity_short": delivery_capacity_short,
		"delivery_blocked_by_no_ready_food": seated >= 6 and ready_food <= 0,
		"low_capacity_caterers": Array(low_capacity_names),
		"high_capacity_caterers": Array(high_capacity_names),
	}

func _known_delivery_capacity_for_worker_entry(worker: Dictionary) -> int:
	var perf: Dictionary = worker.get("performance", {})
	var observed_carry := int(perf.get("observed_max_carry", 1))
	var interview: Dictionary = worker.get("interview", {})
	var capacity_value: Variant = interview.get("delivery_capacity", "unknown")
	if capacity_value is int or capacity_value is float:
		return maxi(observed_carry, int(capacity_value))
	var capacity_text := String(capacity_value)
	if capacity_text.is_valid_int():
		return maxi(observed_carry, int(capacity_text))
	return observed_carry

func _grade_rate(rate: float, average: float, minimum: float) -> String:
	if rate <= 0.0:
		return "unknown" if average <= 0.0 else "below"
	if rate < minimum:
		return "below"
	if average > 0.0 and rate >= average * 1.2:
		return "above"
	if average > 0.0 and rate < average * 0.8:
		return "below"
	return "average"

func _build_prompt() -> String:
	var rm: Node = get_node("/root/RestaurantManager")
	_last_metrics_snapshot = _build_manager_metrics()
	var restaurant_metrics: Dictionary = _last_metrics_snapshot.get("restaurant", {})
	var context: Dictionary = {
		"boss_memory": knowledge.get_prompt_memory(PackedStringArray(ROUTE_ZONES), _now()),
		"manager_metrics": _last_metrics_snapshot,
		"metric_glossary": _build_metric_glossary(),
		"restaurant_state": {
			"money": rm.money,
			"time": rm.get_time_string(),
			"is_open": rm.is_open,
			"menu_prices": {
				"burger": rm.burger_price,
				"fries": rm.fries_price,
				"soda": rm.soda_price,
			},
			"payment_timing": "Customers pay immediately when the cashier takes their order at the register.",
		},
		"legal_plan_schema": _build_legal_plan_schema(),
		"recent_boss_actions": _action_history.slice(maxi(0, _action_history.size() - 6), _action_history.size()),
		"opening_guidance": {
			"opening_plan_needed": bool(rm.is_open) and int(restaurant_metrics.get("customers", 0)) == 0,
			"goal": "At opening, assign workers to useful stations and set small stock targets so cooking starts before the rush.",
			"suggested_four_worker_start": "Usually start with cashier, meat_griller, burger_prepper, fries_fryer. Use best known delivery_capacity worker as future caterer when seated_waiting rises.",
		},
	}
	return "\n".join([
		"You are the physical boss manager in a restaurant game.",
		"You only know what is in boss_memory. Unknown and stale areas must be treated as uncertain.",
		"Every %.0f real seconds, choose one full manager_plan." % decision_cooldown_seconds,
		"Use observed worker performance only. Do not assume hidden stats.",
		"You may use interview.delivery_capacity only after the boss has questioned that worker in person.",
		"Use worker comparison grades to assign stronger workers to matching roles.",
		"Prefer stable assignments unless performance or pressure suggests a change.",
		"Role changes are applied only when workers are idle; busy workers receive pending role changes.",
		"Set stock_targets for desired ready+queued burger/fries/meat backlog. Local validation caps them.",
		"Important: pending_active_burgers/fries/meat means queued or currently in-progress production work, not delivery work and not ready food.",
		"Important: pending_active_*_deliveries means queued or in-progress delivery work for ready food.",
		"Important: queued food work only progresses if a worker has a compatible role.",
		"Important: customer payment is collected at order time, not after eating or when leaving.",
		"Important: Meat Griller only creates cooked_meat stock. Burger Prepper is required to turn cooked_meat into ready burgers.",
		"If a worker is assigned Meat Griller, they are expected to keep grilling meat for backlog even when no current order needs meat.",
		"If meat_overstocked is true or cooked_meat is 20-30+, stop assigning extra grilling and move Meat Griller toward Burger Prepper if burger demand/backlog exists.",
		"Hiring is limited. Hire only when legal_plan_schema.can_hire is true and hire_guidance says why staff is short.",
		"Do not keep hiring for the same bottleneck if idle/Auto workers can be reassigned first.",
		"If delivery_understaffed or delivery_capacity_short is true, assign questioned high-capacity workers to Caterer before hiring.",
		"If a Caterer has known/observed carry 1 and seated_waiting stays high, replace them with a questioned worker who carries more than 1. Fire the slow caterer only after coverage exists.",
		"Do not treat a caterer as good only because they are best among current workers. Use caterer_pressure_fit and observed_max_carry against seated_waiting pressure.",
		"Use orders_per_ingame_hour and avg_order_to_delivery_seconds to set stock_targets: high order rate or slow delivery means keep small burger/fries/meat backlogs ready.",
		"At opening, do not leave all workers Auto. Assign initial useful roles and set small stock_targets so grill/fryer/prep begin building backlog.",
		"Return strict JSON only. No markdown.",
		"Required schema:",
		"{\"action\":\"manager_plan\",\"reason\":\"short\",\"staffing_plan\":[{\"worker\":\"Worker_1\",\"role\":\"cashier|meat_griller|burger_prepper|fries_fryer|caterer|auto\",\"reason\":\"short\"}],\"stock_targets\":{\"burger\":0,\"fries\":0,\"meat\":0},\"hire_worker\":false,\"fire_worker\":\"\",\"say\":\"short\"}",
		JSON.stringify(context),
	])

func _build_metric_glossary() -> Dictionary:
	return {
		"customers": "Total customers currently in the restaurant.",
		"register_waiting": "Customers waiting to place an order. Cashier role handles Process Order tasks.",
		"seated_waiting": "Customers seated and waiting for food. Caterer role delivers ready food from the food table.",
		"delivery_pressure": "Low/active/high/critical estimate from seated_waiting. Critical means delivery is a major bottleneck even if production is also busy.",
		"caterer_count": "Workers currently assigned Caterer.",
		"formal_caterer_count": "Same as caterer_count, included for clarity.",
		"active_delivery_workers_count": "Workers assigned Caterer or currently doing a delivery task.",
		"recommended_caterers": "Suggested number of formal caterers from seated_waiting. Capacity 1 workers may require more coverage.",
		"known_caterer_carry_capacity": "Sum of known or observed carry capacity for formal caterers.",
		"delivery_understaffed": "True when seated_waiting and ready food imply too few formal caterers.",
		"delivery_capacity_short": "True when caterers exist but known carry capacity is too low for seated_waiting.",
		"delivery_blocked_by_no_ready_food": "True when seated customers are waiting but no ready food exists; production/backlog is the bottleneck.",
		"low_carry_caterer_count": "Caterers observed carrying only 1 item at a time.",
		"interview.delivery_capacity": "What the worker told the boss when questioned in person. Unknown means the boss has not asked yet.",
		"service_rates.orders_per_ingame_hour": "How many customer orders are being placed per in-game hour so far today.",
		"service_rates.avg_order_to_delivery_seconds": "Average real seconds between a customer placing an order and receiving food.",
		"ordered_burgers": "Customers who still need burgers before leaving.",
		"ordered_fries": "Customers who still need fries before leaving.",
		"ready_burgers": "Completed burgers on the food table that can be delivered now.",
		"ready_fries": "Completed fries on the food table that can be delivered now.",
		"cooked_meat": "Cooked meat stock available to burger prep stations.",
		"pending_active_burgers": "Burger assembly production tasks queued or in progress. Does not include delivery tasks.",
		"pending_active_fries": "Fries production tasks queued or in progress. Does not include delivery tasks.",
		"pending_active_meat": "Cook meat tasks queued or in progress. Needs Meat Griller or Auto worker.",
		"meat_overstocked": "True when cooked meat stock is high enough that more grilling is wasteful. Prefer burger prep instead of more grilling.",
		"meat_overstock_hard_limit": "Around this cooked_meat count, Meat Griller should normally switch to Burger Prepper or another bottleneck.",
		"pending_active_burger_deliveries": "Burger delivery tasks queued or in progress. Needs Caterer or Auto worker and ready burger on food table.",
		"pending_active_fries_deliveries": "Fries delivery tasks queued or in progress. Needs Caterer or Auto worker and ready fries on food table.",
		"stock_targets": "Desired ready+pending+active amount. A target is already satisfied when ready plus pending_active is at or above target.",
		"role_task_map": {
			"cashier": "Process customer orders at registers.",
			"meat_griller": "Cook meat stock only. This does not create ready burgers.",
			"burger_prepper": "Assemble ready burgers from cooked meat.",
			"fries_fryer": "Cook fries.",
			"caterer": "Deliver ready burgers/fries to seated customers.",
			"auto": "Can do any task but is less specialized and may use unowned stations.",
		},
		"bottleneck_examples": [
			"If ready food is zero but pending_active food is high, assign workers to production roles instead of increasing stock_targets.",
			"If delivery_understaffed is true, assign idle/Auto workers to Caterer before hiring.",
			"If delivery_capacity_short is true, prefer a questioned worker with delivery_capacity above 1 as Caterer.",
			"If ready food is zero and delivery_blocked_by_no_ready_food is true, assign production roles and stock targets before adding caterers.",
			"If the only caterer has carry 1 and a questioned worker can carry more, replace the caterer instead of adding permanent headcount.",
			"If register_waiting is high, assign a cashier.",
			"If ordered_burgers are high, cooked_meat is zero, and pending_active_meat exists, assign a meat_griller.",
			"If cooked_meat is 20-30+ and ordered_burgers or pending_active_burgers exist, reassign a Meat Griller to Burger Prepper.",
			"If ordered_burgers are high, cooked_meat is available, and pending_active_burgers exists, assign a burger_prepper.",
			"If ordered_fries are high and pending_active_fries exists, assign a fries_fryer.",
		],
	}

func _current_hire_guidance() -> Dictionary:
	var rm: Node = get_node_or_null("/root/RestaurantManager")
	var workers := get_tree().get_nodes_in_group("worker_npc")
	var worker_count := workers.size()
	if rm == null or float(rm.get("money")) < 100.0:
		return {"can_hire": false, "reason": "not_enough_money", "recommended_staff_total": worker_count}
	var metrics := _last_metrics_snapshot
	if metrics.is_empty():
		metrics = _build_manager_metrics()
	var restaurant: Dictionary = metrics.get("restaurant", {})
	var recommended_caterers := int(restaurant.get("recommended_caterers", 0))
	var register_waiting := int(restaurant.get("register_waiting", 0))
	var ordered_burgers := int(restaurant.get("ordered_burgers", 0))
	var ordered_fries := int(restaurant.get("ordered_fries", 0))
	var ready_food := int(restaurant.get("ready_food_total", 0))
	var pending_food := int(restaurant.get("pending_active_burgers", 0)) + int(restaurant.get("pending_active_fries", 0)) + int(restaurant.get("pending_active_meat", 0))
	var needed_roles := 0
	if register_waiting > 0:
		needed_roles += 1
	if ordered_burgers > 0 or int(restaurant.get("cooked_meat", 0)) > 0:
		needed_roles += 1
	if ordered_burgers > 2 and int(restaurant.get("cooked_meat", 0)) <= 0:
		needed_roles += 1
	if ordered_fries > 0:
		needed_roles += 1
	needed_roles += recommended_caterers
	var recommended_total := clampi(maxi(1, needed_roles), 1, 5)
	var delivery_short := bool(restaurant.get("delivery_understaffed", false)) or bool(restaurant.get("delivery_capacity_short", false))
	var service_short := register_waiting >= 4 or delivery_short or (pending_food >= 4 and ready_food <= 1)
	var can_hire := worker_count < recommended_total and service_short
	if worker_count >= 4:
		can_hire = can_hire and (register_waiting >= 5 or String(restaurant.get("delivery_pressure", "")) == "critical" or bool(restaurant.get("delivery_capacity_short", false)))
	var reason := "staffing_within_recommended_total"
	if can_hire:
		reason = "worker_count_%d_below_recommended_%d_for_current_pressure" % [worker_count, recommended_total]
	return {
		"can_hire": can_hire,
		"reason": reason,
		"current_staff_total": worker_count,
		"recommended_staff_total": recommended_total,
		"hire_only_if_reassigning_idle_or_auto_cannot_cover": true,
	}

func _build_legal_plan_schema() -> Dictionary:
	var workers := PackedStringArray()
	for worker in get_tree().get_nodes_in_group("worker_npc"):
		if worker != null and is_instance_valid(worker):
			workers.append(String(worker.name))
	var hire_guidance := _current_hire_guidance()
	return {
		"action": "manager_plan",
		"workers": workers,
		"roles": ["auto", "cashier", "meat_griller", "burger_prepper", "fries_fryer", "caterer"],
		"stock_target_caps": STOCK_CAPS,
		"can_hire": bool(hire_guidance.get("can_hire", false)),
		"hire_guidance": hire_guidance,
		"can_fire": workers.size() > 1,
	}

func _build_legal_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = [{"action": "do_nothing"}, {"action": "say", "max_chars": 80}]
	for zone in ROUTE_ZONES:
		actions.append({"action": "inspect_zone", "zone": zone})
	for item in ["burger", "fries", "meat"]:
		for count in [1, 2, 3]:
			actions.append({"action": "queue_food", "item": item, "count": count})
	for worker in get_tree().get_nodes_in_group("worker_npc"):
		if worker == null or not is_instance_valid(worker):
			continue
		for role_key in ["auto", "cashier", "meat_griller", "burger_prepper", "fries_fryer", "caterer"]:
			actions.append({"action": "set_worker_role", "worker": String(worker.name), "role": role_key})
		if get_tree().get_nodes_in_group("worker_npc").size() > 1:
			actions.append({"action": "fire_worker", "worker": String(worker.name)})
	var rm: Node = get_node("/root/RestaurantManager")
	if bool(_current_hire_guidance().get("can_hire", false)):
		actions.append({"action": "hire_worker", "cost": 100.0})
	if _now() - _last_price_change_time >= price_cooldown_seconds:
		for item in ["burger", "fries", "soda"]:
			actions.append({"action": "set_price", "item": item, "min": MIN_PRICES[item], "max": MAX_PRICES[item]})
	return actions

func _on_llm_action_received(action: Dictionary, raw_json: String) -> void:
	last_raw_llm_json = raw_json
	last_failure = ""
	_last_parsed_plan = action.duplicate(true)
	_record_event("llm", "response", String(action.get("reason", "No reason supplied.")), {
		"action": action,
		"raw_json": raw_json,
		"metrics": _last_metrics_snapshot,
	})
	var result: Dictionary = _validate_and_apply_action(action)
	if bool(result.get("ok", false)):
		last_rejected_reason = ""
		last_llm_action = JSON.stringify(action)
		_action_history.append("%s: %s" % [String(action.get("action", "unknown")), String(result.get("message", ""))])
		while _action_history.size() > 12:
			_action_history.pop_front()
		_record_event("llm", "applied", String(result.get("message", "")), {
			"action": action,
			"validation_results": _last_validation_results,
			"pending_role_changes": _pending_role_changes,
		})
	else:
		last_rejected_reason = String(result.get("reason", "Rejected invalid boss action."))
		_record_event("llm", "rejected", last_rejected_reason, {
			"action": action,
			"validation_results": _last_validation_results,
		})
	status_changed.emit()

func _on_llm_request_failed(reason: String) -> void:
	last_failure = reason
	_record_event("llm", "failure", reason, {})
	status_changed.emit()

func _validate_and_apply_action(action: Dictionary) -> Dictionary:
	var action_type := String(action.get("action", "")).to_lower()
	match action_type:
		"manager_plan":
			return _apply_manager_plan(action)
		"inspect_zone":
			var zone := String(action.get("zone", ""))
			if not ROUTE_ZONES.has(zone):
				return {"ok": false, "reason": "Unknown inspection zone."}
			_zone_index = ROUTE_ZONES.find(zone)
			_say("Checking %s." % zone.replace("_", " "))
			return {"ok": true, "message": "Queued inspection of %s." % zone}
		"queue_food":
			return _apply_queue_food(action)
		"set_worker_role":
			return _apply_set_worker_role(action)
		"hire_worker":
			return _apply_hire_worker()
		"fire_worker":
			return _apply_fire_worker(action)
		"set_price":
			return _apply_set_price(action)
		"say":
			_say(String(action.get("text", "")).left(80))
			return {"ok": true, "message": boss_speech}
		"do_nothing":
			_say(String(action.get("reason", "Keep watching.")).left(80))
			return {"ok": true, "message": "No management action taken."}
	return {"ok": false, "reason": "Unknown action type."}

func _apply_manager_plan(plan: Dictionary) -> Dictionary:
	_last_validation_results.clear()
	var applied := PackedStringArray()
	var staffing: Variant = plan.get("staffing_plan", [])
	if staffing is Array:
		for item in staffing as Array:
			if not (item is Dictionary):
				_add_validation_result(false, "staffing_plan", "Ignored malformed staffing item.", item)
				continue
			var result := _apply_set_worker_role(item as Dictionary)
			_add_validation_result(bool(result.get("ok", false)), "set_worker_role", String(result.get("message", result.get("reason", ""))), item)
			var message := String(result.get("message", ""))
			if bool(result.get("ok", false)) and not message.contains("already"):
				applied.append(message)
	var stock_targets: Variant = plan.get("stock_targets", {})
	if stock_targets is Dictionary:
		for item in ["burger", "fries", "meat"]:
			if not (stock_targets as Dictionary).has(item):
				continue
			var target := clampi(int((stock_targets as Dictionary).get(item, 0)), 0, int(STOCK_CAPS[item]))
			var result := _apply_stock_target(item, target)
			_add_validation_result(bool(result.get("ok", false)), "stock_target_%s" % item, String(result.get("message", result.get("reason", ""))), {"item": item, "target": target})
			if bool(result.get("ok", false)) and int(result.get("queued", 0)) > 0:
				applied.append(String(result.get("message", "")))
	if bool(plan.get("hire_worker", false)):
		var result := _apply_hire_worker()
		_add_validation_result(bool(result.get("ok", false)), "hire_worker", String(result.get("message", result.get("reason", ""))), {})
		if bool(result.get("ok", false)):
			applied.append(String(result.get("message", "")))
	var fire_worker := String(plan.get("fire_worker", "")).strip_edges()
	if not fire_worker.is_empty():
		var result := _apply_fire_worker({"worker": fire_worker})
		_add_validation_result(bool(result.get("ok", false)), "fire_worker", String(result.get("message", result.get("reason", ""))), {"worker": fire_worker})
		if bool(result.get("ok", false)):
			applied.append(String(result.get("message", "")))
	var say_text := String(plan.get("say", "")).strip_edges()
	if not say_text.is_empty():
		_say(say_text.left(80))
	if applied.is_empty():
		return {"ok": true, "message": "Manager plan accepted; no changes needed."}
	return {"ok": true, "message": "; ".join(applied)}

func _add_validation_result(ok: bool, action: String, message: String, raw: Variant) -> void:
	_last_validation_results.append({
		"ok": ok,
		"action": action,
		"message": message,
		"raw": raw,
	})

func _apply_set_worker_role(action: Dictionary) -> Dictionary:
	var worker: Node = _find_worker_by_name(String(action.get("worker", "")))
	if worker == null:
		return {"ok": false, "reason": "Worker name is not valid."}
	var role_key := String(action.get("role", "")).to_lower()
	if not ROLE_IDS.has(role_key):
		return {"ok": false, "reason": "Worker role is not valid."}
	var ai: Node = worker.get_node_or_null("WorkerAI")
	if ai == null:
		return {"ok": false, "reason": "Worker has no WorkerAI."}
	var role_id := int(ROLE_IDS[role_key])
	if int(ai.get("job_role")) == role_id:
		_pending_role_changes.erase(String(worker.name))
		return {"ok": true, "message": "%s already %s." % [worker.name, ROLE_LABELS[role_id]]}
	if role_id == 2 and _get_shared_prep_meat_stock() >= MEAT_OVERSTOCK_THRESHOLD:
		return {"ok": false, "reason": "Meat stock is over target; use burger prep or another bottleneck instead of assigning more grilling."}
	if not _can_move_worker_to_role(worker, role_id):
		return {"ok": false, "reason": "%s is protected in current role during service pressure." % String(worker.name)}
	if ai.has_method("is_executing_task") and bool(ai.call("is_executing_task")):
		var reason := String(action.get("reason", ""))
		if ai.has_method("request_job_role"):
			ai.call("request_job_role", role_id, reason)
		_pending_role_changes[String(worker.name)] = _pending_role_change_entry(role_id, role_key, reason)
		_say("%s, next take %s." % [worker.name, String(ROLE_LABELS[role_id]).to_lower()])
		return {"ok": true, "message": "Queued %s to %s when idle." % [worker.name, ROLE_LABELS[role_id]]}
	_set_worker_role_now(worker, role_id)
	_pending_role_changes.erase(String(worker.name))
	_say("%s, take %s." % [worker.name, String(ROLE_LABELS[role_id]).to_lower()])
	return {"ok": true, "message": "Set %s to %s." % [worker.name, ROLE_LABELS[role_id]]}

func _can_move_worker_to_role(worker: Node, new_role_id: int) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false
	var ai: Node = worker.get_node_or_null("WorkerAI")
	if ai == null:
		return false
	if int(ai.get("job_role")) != 5 or new_role_id == 5:
		return true
	var metrics := _last_metrics_snapshot
	if metrics.is_empty():
		metrics = _build_manager_metrics()
	var restaurant: Dictionary = metrics.get("restaurant", {})
	if int(restaurant.get("seated_waiting", 0)) < 8:
		return true
	if bool(restaurant.get("delivery_blocked_by_no_ready_food", false)):
		return true
	for entry_value in metrics.get("workers", []):
		if not (entry_value is Dictionary):
			continue
		var entry := entry_value as Dictionary
		if String(entry.get("worker", "")) != String(worker.name):
			continue
		return _known_delivery_capacity_for_worker_entry(entry) <= 1
	return true

func _set_worker_role_now(worker: Node, role_id: int) -> void:
	var ai: Node = worker.get_node_or_null("WorkerAI") if worker != null else null
	if ai == null:
		return
	if ai.has_method("set_job_role"):
		ai.call("set_job_role", role_id)
	else:
		ai.set("job_role", role_id)

func _pending_role_change_entry(role_id: int, role_key: String, reason: String) -> Dictionary:
	return {
		"role_id": role_id,
		"role_key": role_key,
		"role_label": String(ROLE_LABELS[role_id]),
		"reason": reason,
		"requested_at": _now(),
	}

func _apply_stock_target(item: String, target: int) -> Dictionary:
	if not STOCK_CAPS.has(item):
		return {"ok": false, "reason": "Stock target item is not valid."}
	var tm: Node = get_node_or_null("/root/TaskManager")
	if tm == null:
		return {"ok": false, "reason": "TaskManager unavailable."}
	var food_table: Node = _current_scene_node("FoodTable")
	var current := 0
	match item:
		"burger":
			current = _count_ready_food(food_table, "burger") + _count_production_tasks_for_food(tm, "burger")
		"fries":
			current = _count_ready_food(food_table, "fries") + _count_production_tasks_for_food(tm, "fries")
		"meat":
			current = _get_shared_prep_meat_stock() + _count_tasks_of_type(tm, tm.TaskType.COOK_MEAT)
	var needed := maxi(0, target - current)
	if needed <= 0:
		return {"ok": true, "message": "%s target already satisfied (%d/%d)." % [item, current, target], "queued": 0}
	var queued := _queue_food_backlog(item, needed)
	if queued <= 0:
		return {"ok": false, "reason": "%s target blocked; current %d target %d." % [item, current, target], "queued": 0}
	return {"ok": true, "message": "Queued %d %s toward target %d." % [queued, item, target], "queued": queued}

func _apply_queue_food(action: Dictionary) -> Dictionary:
	var item := String(action.get("item", "")).to_lower()
	if not ["burger", "fries", "meat"].has(item):
		return {"ok": false, "reason": "Food item is not valid."}
	var count := clampi(int(action.get("count", 1)), 1, 3)
	var queued := _queue_food_backlog(item, count)
	if queued <= 0:
		return {"ok": false, "reason": "Could not queue food; stock cap, station, or duplicate task blocked it."}
	var label := "cooked meat" if item == "meat" else item
	_say("Queue %d %s." % [queued, label])
	return {"ok": true, "message": "Queued %d %s backlog." % [queued, label]}

func _apply_hire_worker() -> Dictionary:
	var rm := get_node("/root/RestaurantManager")
	if rm.money < 100.0:
		return {"ok": false, "reason": "Not enough money to hire."}
	var hire_guidance := _current_hire_guidance()
	if not bool(hire_guidance.get("can_hire", false)):
		return {"ok": false, "reason": "Hiring blocked: %s." % String(hire_guidance.get("reason", "staffing limit reached"))}
	var emp := _current_scene_node("EmployeeManager")
	if emp == null or not emp.has_method("hire_worker"):
		return {"ok": false, "reason": "EmployeeManager cannot hire."}
	emp.call("hire_worker")
	_say("Bring in another worker.")
	return {"ok": true, "message": "Hired a worker."}

func _apply_fire_worker(action: Dictionary) -> Dictionary:
	var workers: Array[Node] = get_tree().get_nodes_in_group("worker_npc")
	if workers.size() <= 1:
		return {"ok": false, "reason": "Cannot fire the last worker."}
	var worker_name := String(action.get("worker", ""))
	var worker: Node = _find_worker_by_name(worker_name)
	if worker == null:
		return {"ok": false, "reason": "Worker name is not valid."}
	if not _observed_worker_can_be_fired(worker_name):
		return {"ok": false, "reason": "No conservative observed reason to fire this worker."}
	var emp := _current_scene_node("EmployeeManager")
	if emp == null or not emp.has_method("fire_worker"):
		return {"ok": false, "reason": "EmployeeManager cannot fire."}
	if not bool(emp.call("fire_worker", worker_name)):
		return {"ok": false, "reason": "EmployeeManager rejected firing."}
	_say("%s, clock out." % worker_name)
	return {"ok": true, "message": "Fired %s." % worker_name}

func _apply_set_price(action: Dictionary) -> Dictionary:
	if _now() - _last_price_change_time < price_cooldown_seconds:
		return {"ok": false, "reason": "Price change cooldown is active."}
	var item := String(action.get("item", "")).to_lower()
	if not MIN_PRICES.has(item):
		return {"ok": false, "reason": "Price item is not valid."}
	var price := float(action.get("price", -1.0))
	if price < float(MIN_PRICES[item]) or price > float(MAX_PRICES[item]):
		return {"ok": false, "reason": "Price is outside allowed bounds."}
	var rm: Node = get_node("/root/RestaurantManager")
	var old_price: float = rm.get_food_price(item)
	if absf(price - old_price) > 1.0:
		return {"ok": false, "reason": "Price change is too large."}
	rm.set_food_price(item, price)
	_last_price_change_time = _now()
	_say("%s is now $%.2f." % [item.capitalize(), price])
	return {"ok": true, "message": "Set %s price to %.2f." % [item, price]}

func _observed_worker_can_be_fired(worker_name: String) -> bool:
	for worker in _last_metrics_snapshot.get("workers", []):
		if not (worker is Dictionary):
			continue
		var entry := worker as Dictionary
		if String(entry.get("worker", "")) != worker_name:
			continue
		var perf: Dictionary = entry.get("performance", {})
		if int(perf.get("failed", 0)) >= 2:
			return true
		var role := String(entry.get("role", ""))
		var known_capacity := _known_delivery_capacity_for_worker_entry(entry)
		if role == "Caterer" and known_capacity <= 1 and _has_better_known_caterer_coverage(worker_name):
			return true
		var comparison: Dictionary = entry.get("comparison", {})
		for role_key in ["cashier", "burger_prepper", "meat_griller", "fries_fryer", "caterer"]:
			if String(comparison.get(role_key, "")) == "below":
				return true
	var worker_entry: Dictionary = knowledge.worker_observations.get(worker_name, {})
	if worker_entry.is_empty():
		return false
	var facts: Array = worker_entry.get("facts", [])
	for fact in facts:
		var text := String(fact).to_lower()
		if text.contains("underutilized") or text.contains("idle"):
			return true
	return get_tree().get_nodes_in_group("worker_npc").size() >= 4

func _has_better_known_caterer_coverage(excluded_worker_name: String) -> bool:
	var high_capacity_caterers := 0
	var total_caterers := 0
	for worker in _last_metrics_snapshot.get("workers", []):
		if not (worker is Dictionary):
			continue
		var entry := worker as Dictionary
		if String(entry.get("worker", "")) == excluded_worker_name:
			continue
		if String(entry.get("role", "")) != "Caterer":
			continue
		total_caterers += 1
		var known_capacity := _known_delivery_capacity_for_worker_entry(entry)
		if known_capacity > 1:
			high_capacity_caterers += 1
	return high_capacity_caterers > 0 and total_caterers >= 1

func _get_customer_count() -> int:
	var cm: Node = _current_scene_node("CustomerManager")
	if cm != null:
		return int(cm.get("current_customers"))
	return 0

func _count_customers_in_states(states: Array[int]) -> int:
	var count := 0
	var cm: Node = _current_scene_node("CustomerManager")
	if cm == null:
		return 0
	for child in cm.get_children():
		var ai: Node = child.get_node_or_null("CustomerAI") if child is Node else null
		if ai != null and states.has(int(ai.get("state"))):
			count += 1
	return count

func _count_open_orders(food_type: String) -> int:
	var count := 0
	var cm: Node = _current_scene_node("CustomerManager")
	if cm == null:
		return 0
	for child in cm.get_children():
		var ai: Node = child.get_node_or_null("CustomerAI") if child is Node else null
		if ai == null:
			continue
		if int(ai.get("state")) == 6 or int(ai.get("state")) == 7:
			continue
		if ai.has_method("has_received_food") and bool(ai.call("has_received_food")):
			continue
		if ai.has_method("get_ordered_food_type") and String(ai.call("get_ordered_food_type")) == food_type:
			count += 1
	return count

func _count_ready_food(food_table: Node, food_type: String) -> int:
	if food_table == null:
		return 0
	if food_table.has_method("get_food_item_count"):
		return int(food_table.call("get_food_item_count", food_type))
	if food_table.has_method("has_food_item"):
		return 1 if bool(food_table.call("has_food_item", food_type)) else 0
	return 0

func _count_tasks_for_food(tm: Node, food_type: String) -> int:
	var count := 0
	for task in _get_all_tasks(tm):
		if _task_food_type(task) == food_type:
			count += 1
	return count

func _count_production_tasks_for_food(tm: Node, food_type: String) -> int:
	var count := 0
	if tm == null:
		return 0
	for task in _get_all_tasks(tm):
		if task == null or not is_instance_valid(task):
			continue
		var task_type := int(task.get("type"))
		if food_type == "burger" and task_type != tm.TaskType.ASSEMBLE_BURGER:
			continue
		if food_type == "fries" and task_type != tm.TaskType.FRY_FRIES:
			continue
		if _task_food_type(task) == food_type:
			count += 1
	return count

func _count_delivery_tasks_for_food(tm: Node, food_type: String) -> int:
	var count := 0
	if tm == null:
		return 0
	for task in _get_all_tasks(tm):
		if task == null or not is_instance_valid(task):
			continue
		if int(task.get("type")) == tm.TaskType.DELIVER_FOOD and _task_food_type(task) == food_type:
			count += 1
	return count

func _ensure_assigned_grillers_have_work(tm: Node, actions: PackedStringArray) -> void:
	if tm == null:
		return
	if _count_workers_in_role(2) <= 0:
		return
	if _get_shared_prep_meat_stock() >= MEAT_OVERSTOCK_THRESHOLD:
		return
	if _count_tasks_of_type(tm, tm.TaskType.COOK_MEAT) > 0:
		return
	var prep := _best_prep_station_for_backlog()
	if prep == null or not tm.has_method("request_cooked_meat_for_prep"):
		return
	var before := _count_tasks_of_type(tm, tm.TaskType.COOK_MEAT)
	tm.call("request_cooked_meat_for_prep", prep)
	if _count_tasks_of_type(tm, tm.TaskType.COOK_MEAT) > before:
		actions.append("queued meat for assigned griller")

func _queue_food_backlog(item: String, count: int) -> int:
	var tm: Node = get_node_or_null("/root/TaskManager")
	if tm == null:
		return 0
	var food_table: Node = _current_scene_node("FoodTable")
	var queued := 0
	match item:
		"burger":
			if food_table == null:
				return 0
			while queued < count and _count_ready_food(food_table, "burger") + _count_production_tasks_for_food(tm, "burger") < 3:
				var prep := _best_prep_station_for_backlog()
				if prep == null:
					break
				if prep.has_method("has_cooked_meat") and not bool(prep.call("has_cooked_meat")):
					tm.call("request_cooked_meat_for_prep", prep)
				if tm.add_task(tm.TaskType.ASSEMBLE_BURGER, {"station": prep, "food_table": food_table, "food_type": "burger"}) == null:
					break
				queued += 1
		"fries":
			if food_table == null:
				return 0
			while queued < count and _count_ready_food(food_table, "fries") + _count_production_tasks_for_food(tm, "fries") < 3:
				var fryer := _best_fryer_for_backlog()
				if fryer == null:
					break
				if tm.add_task(tm.TaskType.FRY_FRIES, {"station": fryer, "food_table": food_table, "food_type": "fries"}) == null:
					break
				queued += 1
		"meat":
			while queued < count:
				var prep := _best_prep_station_for_backlog()
				if prep == null or not tm.has_method("request_cooked_meat_for_prep"):
					break
				var before := _count_tasks_of_type(tm, tm.TaskType.COOK_MEAT)
				tm.call("request_cooked_meat_for_prep", prep)
				if _count_tasks_of_type(tm, tm.TaskType.COOK_MEAT) <= before:
					break
				queued += 1
	return queued

func _has_task_type(tm: Node, task_type: int) -> bool:
	for task in _get_all_tasks(tm):
		if int(task.get("type")) == task_type:
			return true
	return false

func _count_tasks_of_type(tm: Node, task_type: int) -> int:
	var count := 0
	for task in _get_all_tasks(tm):
		if int(task.get("type")) == task_type:
			count += 1
	return count

func _has_task_type_for_food(tm: Node, task_type: int, food_type: String) -> bool:
	for task in _get_all_tasks(tm):
		if int(task.get("type")) == task_type and _task_food_type(task) == food_type:
			return true
	return false

func _clear_pending_cook_meat_tasks_if_meat_available(tm: Node) -> void:
	if _get_shared_prep_meat_stock() <= 0:
		return
	var pending: Variant = tm.get("pending_tasks")
	if not (pending is Array):
		return
	var changed := false
	var i := (pending as Array).size() - 1
	while i >= 0:
		var task = (pending as Array)[i]
		if task != null and is_instance_valid(task) and int(task.get("type")) == tm.TaskType.COOK_MEAT:
			(pending as Array).remove_at(i)
			changed = true
		i -= 1
	if changed and tm.has_signal("tasks_changed"):
		tm.tasks_changed.emit()

func _get_shared_prep_meat_stock() -> int:
	var stations: Array[Node] = []
	_collect_nodes_with_method(get_tree().current_scene, "get_cooked_meat_stock", stations)
	var best := 0
	for station in stations:
		best = maxi(best, int(station.call("get_cooked_meat_stock")))
	return best

func _get_all_tasks(tm: Node) -> Array:
	var tasks: Array = []
	var pending: Variant = tm.get("pending_tasks")
	if pending is Array:
		tasks.append_array(pending as Array)
	var active: Variant = tm.get("active_tasks")
	if active is Array:
		tasks.append_array(active as Array)
	return tasks

func _task_food_type(task: Variant) -> String:
	if task == null:
		return ""
	var args: Dictionary = task.get("args") if task is Object else {}
	return String(args.get("food_type", ""))

func _best_fryer_for_backlog() -> Node:
	var fryers: Array[Node] = []
	_collect_nodes_with_method(get_tree().current_scene, "fry_fries", fryers)
	fryers.sort_custom(func(a: Node, b: Node) -> bool:
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0
	)
	for fryer in fryers:
		if fryer.has_method("is_available") and not bool(fryer.call("is_available")):
			continue
		return fryer
	return fryers[0] if not fryers.is_empty() else null

func _best_prep_station_for_backlog() -> Node:
	var stations: Array[Node] = []
	_collect_nodes_with_method(get_tree().current_scene, "assemble_default_burger", stations)
	if stations.is_empty():
		return null
	stations.sort_custom(func(a: Node, b: Node) -> bool:
		return String(a.get_path()).naturalnocasecmp_to(String(b.get_path())) < 0
	)
	var best: Node = null
	var best_score := INF
	for station in stations:
		var score := float(_count_open_tasks_for_station(station))
		if station.has_method("is_available") and not bool(station.call("is_available")):
			score += 100.0
		if station.has_method("is_burger_storage_full") and bool(station.call("is_burger_storage_full")):
			score += 1000.0
		if score < best_score:
			best_score = score
			best = station
	return best

func _count_open_tasks_for_station(station: Node) -> int:
	var tm: Node = get_node_or_null("/root/TaskManager")
	if tm == null or station == null:
		return 0
	var count := 0
	for task in _get_all_tasks(tm):
		if task != null and is_instance_valid(task) and task.get("args").get("station") == station:
			count += 1
	return count

func _prep_station_label(prep: Node) -> String:
	if prep == null:
		return "-"
	var shelf := prep.get_parent()
	if shelf != null and shelf.get_parent() != null:
		return String(shelf.get_parent().name)
	return String(prep.name)

func _say(text: String) -> void:
	boss_speech = text.strip_edges().left(80)
	var label: Label3D = _boss.get_node_or_null("BossSpeech") as Label3D
	if label != null:
		label.text = boss_speech
		label.visible = not boss_speech.is_empty()

func _initialize_debug_log() -> void:
	if not debug_log_enabled:
		return
	if debug_log_reset_on_start:
		var reset_file := FileAccess.open(DEBUG_LOG_PATH, FileAccess.WRITE)
		if reset_file != null:
			reset_file.close()
	_record_event("system", "session_start", "Boss manager debug session started.", {
		"director_interval_seconds": director_interval_seconds,
		"decision_cooldown_seconds": decision_cooldown_seconds,
		"route_zones": ROUTE_ZONES,
		"log_path": ProjectSettings.globalize_path(DEBUG_LOG_PATH),
	})

func _record_event(source: String, action: String, explanation: String, raw: Dictionary = {}) -> void:
	var rm: Node = get_node_or_null("/root/RestaurantManager")
	var game_time := "-"
	if rm != null and rm.has_method("get_time_string"):
		game_time = String(rm.call("get_time_string"))
	_event_sequence += 1
	var event := {
		"sequence": _event_sequence,
		"real_seconds": Time.get_ticks_msec() / 1000.0,
		"game_time": game_time,
		"source": source,
		"action": action,
		"explanation": explanation,
		"raw": raw,
	}
	_event_log.append(event)
	while _event_log.size() > 40:
		_event_log.pop_front()
	_write_debug_log_event(event)

func _write_debug_log_event(event: Dictionary) -> void:
	if not debug_log_enabled:
		return
	var file: FileAccess = null
	if FileAccess.file_exists(DEBUG_LOG_PATH):
		file = FileAccess.open(DEBUG_LOG_PATH, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(DEBUG_LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify(event))
	file.close()

func _find_worker_by_name(worker_name: String) -> Node:
	for worker in get_tree().get_nodes_in_group("worker_npc"):
		if worker != null and is_instance_valid(worker) and String(worker.name) == worker_name:
			return worker
	return null

func _count_workers_in_role(role_id: int) -> int:
	var count: int = 0
	for worker in get_tree().get_nodes_in_group("worker_npc"):
		var ai: Node = worker.get_node_or_null("WorkerAI") if worker != null else null
		if ai != null and int(ai.get("job_role")) == role_id:
			count += 1
	return count

func _resolve_zone_destination(zone_id: String) -> Node3D:
	match zone_id:
		"registers":
			var markers: Array[Node3D] = _collect_register_markers("Approach")
			return markers[0] if not markers.is_empty() else _boss
		"grill":
			return _first_station_point("cook_meat")
		"fryer":
			return _first_station_point("fry_fries")
		"prep":
			return _station_point(_current_scene_node("BurgerPrepStation"))
		"food_table":
			return _station_point(_current_scene_node("FoodTable"))
		"dining_room":
			return _current_scene_node("SeatingMap") as Node3D
		"workers":
			var worker: Node = _nearest_worker()
			return worker as Node3D if worker != null else _boss
	return _boss

func _first_station_point(method_name: String) -> Node3D:
	var stations: Array[Node] = []
	_collect_nodes_with_method(get_tree().current_scene, method_name, stations)
	if stations.is_empty():
		return _boss
	return _station_point(stations[0])

func _station_point(station: Node) -> Node3D:
	if station == null:
		return _boss
	for method_name in ["get_entrance_point", "get_stand_point", "get_snap_point", "get_worker_stand_point"]:
		if station.has_method(method_name):
			var point: Node3D = station.call(method_name) as Node3D
			if point != null:
				return point
	return station as Node3D if station is Node3D else _boss

func _nearest_worker() -> Node:
	var best: Node = null
	var best_dist: float = INF
	for worker in get_tree().get_nodes_in_group("worker_npc"):
		if worker == null or not is_instance_valid(worker) or not (worker is Node3D):
			continue
		var dist: float = _boss.global_position.distance_squared_to((worker as Node3D).global_position)
		if dist < best_dist:
			best = worker
			best_dist = dist
	return best

func _collect_register_markers(marker_suffix: String) -> Array[Node3D]:
	var markers: Array[Node3D] = []
	var seating_map: Node = _current_scene_node("SeatingMap")
	if seating_map != null:
		_collect_register_markers_recursive(seating_map, marker_suffix, markers)
	markers.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0
	)
	return markers

func _collect_register_markers_recursive(node: Node, marker_suffix: String, markers: Array[Node3D]) -> void:
	if node is Node3D:
		var node_name := String(node.name)
		if node_name.begins_with("CashRegister_") and node_name.ends_with("_" + marker_suffix):
			markers.append(node as Node3D)
	for child in node.get_children():
		_collect_register_markers_recursive(child, marker_suffix, markers)

func _collect_nodes_with_method(node: Node, method_name: String, results: Array[Node]) -> void:
	if node == null:
		return
	if node.has_method(method_name):
		results.append(node)
	for child in node.get_children():
		_collect_nodes_with_method(child, method_name, results)

func _current_scene_node(name_query: String) -> Node:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child(name_query, true, false)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
