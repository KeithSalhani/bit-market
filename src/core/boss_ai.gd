extends Node
class_name BossAI

signal status_changed()

const BossKnowledgeScript: Script = preload("res://src/core/boss_knowledge.gd")
const GeminiLLMClientScript: Script = preload("res://src/core/gemini_llm_client.gd")
const ROUTE_ZONES := ["registers", "grill", "fryer", "prep", "food_table", "dining_room", "workers"]
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
@export var decision_cooldown_seconds := 4.0
@export var price_cooldown_seconds := 45.0
@export var route_completion_decisions := true
@export var service_director_enabled := true
@export var max_auto_workers := 5

var knowledge: RefCounted = BossKnowledgeScript.new()
var current_destination := "starting"
var last_llm_action := "-"
var last_rejected_reason := ""
var last_failure := ""
var last_raw_llm_json := ""
var boss_speech := ""

var _boss: CharacterBody3D
var _llm_client: Node
var _zone_index := 0
var _route_observations_since_decision := 0
var _last_decision_time := -999.0
var _last_price_change_time := -999.0
var _last_director_time := -999.0
var _action_history: Array[String] = []

func _ready() -> void:
	_boss = get_parent() as CharacterBody3D
	_llm_client = Node.new()
	_llm_client.set_script(GeminiLLMClientScript)
	_llm_client.name = "GeminiLLMClient"
	_llm_client.action_received.connect(_on_llm_action_received)
	_llm_client.request_failed.connect(_on_llm_request_failed)
	add_child(_llm_client)
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
		"raw_json": last_raw_llm_json if _llm_client != null and _llm_client.raw_debug_enabled else "",
		"speech": boss_speech,
		"llm_enabled": _llm_client != null and _llm_client.enabled,
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
		_run_service_director()
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
	if action.to_lower() == "idle":
		facts.append("may be underutilized if this repeats")
	else:
		facts.append("appears active in assigned work")
	return facts

func _request_llm_decision_if_ready() -> void:
	if _llm_client == null or not _llm_client.is_available():
		if _llm_client != null and not _llm_client.enabled:
			last_failure = "LLM disabled or missing config; boss will keep observing."
			status_changed.emit()
		return
	if _now() - _last_decision_time < decision_cooldown_seconds:
		return
	_last_decision_time = _now()
	_route_observations_since_decision = 0
	_llm_client.request_action(_build_prompt())

func _run_service_director() -> void:
	if not service_director_enabled:
		return
	if _now() - _last_director_time < 2.0:
		return
	_last_director_time = _now()
	var rm: Node = get_node("/root/RestaurantManager")
	if rm == null or not bool(rm.get("is_open")):
		return

	var actions: PackedStringArray = []
	var workers: Array[Node] = get_tree().get_nodes_in_group("worker_npc")
	var customer_count: int = _get_customer_count()
	var register_waiting: int = _count_customers_in_states([1, 2])
	var seated_waiting: int = _count_customers_in_states([4])
	var ordered_burgers: int = _count_open_orders("burger")
	var ordered_fries: int = _count_open_orders("fries")
	var food_table: Node = _current_scene_node("FoodTable")
	var prep: Node = _best_prep_station_for_backlog()
	var tm: Node = get_node_or_null("/root/TaskManager")
	if tm != null:
		_clear_pending_cook_meat_tasks_if_meat_available(tm)
	var grill_needed: bool = tm != null and _has_task_type(tm, tm.TaskType.COOK_MEAT) and _get_shared_prep_meat_stock() <= 0

	if workers.size() < max_auto_workers and rm.money >= 100.0:
		var hire_pressure: bool = customer_count >= maxi(3, workers.size() * 2)
		hire_pressure = hire_pressure or (register_waiting >= 2 and _count_workers_in_role(1) == 0)
		hire_pressure = hire_pressure or (seated_waiting >= 3 and workers.size() < 3)
		if hire_pressure and _hire_worker_director():
			actions.append("hired worker for service pressure")
			workers = get_tree().get_nodes_in_group("worker_npc")

	_assign_workers_for_service(workers, register_waiting, ordered_burgers, ordered_fries, seated_waiting, grill_needed, actions)
	_ensure_food_backlog(prep, food_table, ordered_burgers, ordered_fries, actions)
	_ensure_ready_food_deliveries(food_table, actions)

	if not actions.is_empty():
		last_llm_action = "director: %s" % "; ".join(actions)
		_action_history.append(last_llm_action)
		while _action_history.size() > 12:
			_action_history.pop_front()
		_say(actions[0].capitalize())
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
	var burger_work: int = _count_tasks_for_food(tm, "burger") + ready_burgers
	var fries_work: int = _count_tasks_for_food(tm, "fries") + ready_fries
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

func _build_prompt() -> String:
	var rm: Node = get_node("/root/RestaurantManager")
	var legal_options: Array[Dictionary] = _build_legal_actions()
	var context: Dictionary = {
		"boss_memory": knowledge.get_prompt_memory(PackedStringArray(ROUTE_ZONES), _now()),
		"restaurant_state": {
			"money": rm.money,
			"time": rm.get_time_string(),
			"is_open": rm.is_open,
			"menu_prices": {
				"burger": rm.burger_price,
				"fries": rm.fries_price,
				"soda": rm.soda_price,
			},
		},
		"legal_actions": legal_options,
		"recent_boss_actions": _action_history.slice(maxi(0, _action_history.size() - 6), _action_history.size()),
	}
	return "\n".join([
		"You are the physical boss manager in a restaurant game.",
		"You only know what is in boss_memory. Unknown and stale areas must be treated as uncertain.",
		"Choose exactly one legal management action from legal_actions.",
		"Return strict JSON only. No markdown.",
		"Allowed schemas:",
		"{\"action\":\"inspect_zone\",\"zone\":\"registers|grill|fryer|prep|food_table|dining_room|workers\",\"reason\":\"short\"}",
		"{\"action\":\"set_worker_role\",\"worker\":\"Worker_1\",\"role\":\"cashier|meat_griller|burger_prepper|fries_fryer|caterer|auto\",\"reason\":\"short\"}",
		"{\"action\":\"hire_worker\",\"reason\":\"short\"}",
		"{\"action\":\"fire_worker\",\"worker\":\"Worker_1\",\"reason\":\"short\"}",
		"{\"action\":\"set_price\",\"item\":\"burger|fries|soda\",\"price\":5.5,\"reason\":\"short\"}",
		"{\"action\":\"say\",\"text\":\"short\"}",
		"{\"action\":\"do_nothing\",\"reason\":\"short\"}",
		JSON.stringify(context),
	])

func _build_legal_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = [{"action": "do_nothing"}, {"action": "say", "max_chars": 80}]
	for zone in ROUTE_ZONES:
		actions.append({"action": "inspect_zone", "zone": zone})
	for worker in get_tree().get_nodes_in_group("worker_npc"):
		if worker == null or not is_instance_valid(worker):
			continue
		for role_key in ["auto", "cashier", "meat_griller", "burger_prepper", "fries_fryer", "caterer"]:
			actions.append({"action": "set_worker_role", "worker": String(worker.name), "role": role_key})
		if get_tree().get_nodes_in_group("worker_npc").size() > 1:
			actions.append({"action": "fire_worker", "worker": String(worker.name)})
	var rm: Node = get_node("/root/RestaurantManager")
	if rm.money >= 100.0:
		actions.append({"action": "hire_worker", "cost": 100.0})
	if _now() - _last_price_change_time >= price_cooldown_seconds:
		for item in ["burger", "fries", "soda"]:
			actions.append({"action": "set_price", "item": item, "min": MIN_PRICES[item], "max": MAX_PRICES[item]})
	return actions

func _on_llm_action_received(action: Dictionary, raw_json: String) -> void:
	last_raw_llm_json = raw_json
	last_failure = ""
	var result: Dictionary = _validate_and_apply_action(action)
	if bool(result.get("ok", false)):
		last_rejected_reason = ""
		last_llm_action = JSON.stringify(action)
		_action_history.append("%s: %s" % [String(action.get("action", "unknown")), String(result.get("message", ""))])
		while _action_history.size() > 12:
			_action_history.pop_front()
	else:
		last_rejected_reason = String(result.get("reason", "Rejected invalid boss action."))
	status_changed.emit()

func _on_llm_request_failed(reason: String) -> void:
	last_failure = reason
	status_changed.emit()

func _validate_and_apply_action(action: Dictionary) -> Dictionary:
	var action_type := String(action.get("action", "")).to_lower()
	match action_type:
		"inspect_zone":
			var zone := String(action.get("zone", ""))
			if not ROUTE_ZONES.has(zone):
				return {"ok": false, "reason": "Unknown inspection zone."}
			_zone_index = ROUTE_ZONES.find(zone)
			_say("Checking %s." % zone.replace("_", " "))
			return {"ok": true, "message": "Queued inspection of %s." % zone}
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
	if ai.has_method("set_job_role"):
		ai.call("set_job_role", role_id)
	else:
		ai.set("job_role", role_id)
	_say("%s, take %s." % [worker.name, String(ROLE_LABELS[role_id]).to_lower()])
	return {"ok": true, "message": "Set %s to %s." % [worker.name, ROLE_LABELS[role_id]]}

func _apply_hire_worker() -> Dictionary:
	var rm := get_node("/root/RestaurantManager")
	if rm.money < 100.0:
		return {"ok": false, "reason": "Not enough money to hire."}
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
	var worker_entry: Dictionary = knowledge.worker_observations.get(worker_name, {})
	if worker_entry.is_empty():
		return false
	var facts: Array = worker_entry.get("facts", [])
	for fact in facts:
		var text := String(fact).to_lower()
		if text.contains("underutilized") or text.contains("idle"):
			return true
	return get_tree().get_nodes_in_group("worker_npc").size() >= 4

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
	var stored: Variant = food_table.get("_stored_food_items")
	if not (stored is Array):
		if food_table.has_method("has_food_item"):
			return 1 if bool(food_table.call("has_food_item", food_type)) else 0
		return 0
	var count := 0
	for item in stored as Array:
		if item == null or not is_instance_valid(item):
			continue
		if _food_item_matches_type(item as Node, food_type):
			count += 1
	return count

func _food_item_matches_type(food_item: Node, food_type: String) -> bool:
	if food_item == null:
		return false
	if food_item.has_meta("food_type"):
		return String(food_item.get_meta("food_type")) == food_type
	var normalized := String(food_item.name).to_lower()
	if food_type == "burger":
		return normalized.contains("burger")
	if food_type == "fries":
		return normalized.contains("fries")
	return false

func _count_tasks_for_food(tm: Node, food_type: String) -> int:
	var count := 0
	for task in _get_all_tasks(tm):
		if _task_food_type(task) == food_type:
			count += 1
	return count

func _has_task_type(tm: Node, task_type: int) -> bool:
	for task in _get_all_tasks(tm):
		if int(task.get("type")) == task_type:
			return true
	return false

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
