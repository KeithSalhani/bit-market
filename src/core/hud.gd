extends CanvasLayer

@onready var money_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/MoneyLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/TimeLabel
@onready var day_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/DayLabel
@onready var open_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/OpenButton
@onready var hire_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/HireButton
@onready var hud_row: HBoxContainer = $MarginContainer/VBoxContainer/HBoxContainer

var spawn_customer_button: Button
var workers_button: Button
var boss_button: Button
var workers_panel: PanelContainer
var workers_list: VBoxContainer
var boss_panel: PanelContainer
var boss_summary_label: Label
var boss_view_option: OptionButton
var boss_browser: HBoxContainer
var boss_event_list: ItemList
var boss_detail_text: RichTextLabel
var _worker_refresh_timer: Timer
var _boss_refresh_timer: Timer
var _worker_rows: Dictionary = {}
var _boss_events_cache: Array = []
var _selected_boss_event_index := -1

func _ready() -> void:
	var rm = get_node("/root/RestaurantManager")
	rm.connect("money_changed", _on_money_changed)
	rm.connect("time_changed", _on_time_changed)
	rm.connect("day_changed", _on_day_changed)
	rm.connect("open_state_changed", _on_open_state_changed)
	
	open_button.connect("pressed", _on_open_button_pressed)
	
	hire_button.text = "Hire Worker ($100)"
	hire_button.connect("pressed", _on_hire_button_pressed)
	_create_spawn_customer_button()
	_create_worker_activity_ui()
	_create_boss_manager_ui()
	
	_on_money_changed(rm.money)
	_on_time_changed(rm.time_of_day)
	_on_day_changed(rm.current_day)
	_on_open_state_changed(rm.is_open)

func _on_money_changed(amount: float) -> void:
	money_label.text = "$%.2f" % amount

func _on_time_changed(_time: float) -> void:
	time_label.text = get_node("/root/RestaurantManager").get_time_string()

func _on_day_changed(day: int) -> void:
	day_label.text = "Day %d" % day

func _on_open_state_changed(is_open: bool) -> void:
	if is_open:
		open_button.text = "Close Restaurant"
	else:
		open_button.text = "Open Restaurant"

func _on_open_button_pressed() -> void:
	var rm = get_node("/root/RestaurantManager")
	if rm.is_open:
		rm.close_restaurant()
	else:
		rm.open_restaurant()

func _on_hire_button_pressed() -> void:
	# Try to find the EmployeeManager in the current scene
	var level = get_tree().current_scene
	if level != null:
		var emp_manager = level.find_child("EmployeeManager", true, false)
		if emp_manager != null and emp_manager.has_method("hire_worker"):
			emp_manager.call("hire_worker")

func _create_spawn_customer_button() -> void:
	spawn_customer_button = Button.new()
	spawn_customer_button.text = "Spawn Customer"
	spawn_customer_button.pressed.connect(_on_spawn_customer_button_pressed)
	hud_row.add_child(spawn_customer_button)

func _on_spawn_customer_button_pressed() -> void:
	var level := get_tree().current_scene
	if level == null:
		return

	var customer_manager := level.find_child("CustomerManager", true, false)
	if customer_manager == null or not customer_manager.has_method("spawn_customer_now"):
		push_warning("HUD could not find CustomerManager.spawn_customer_now().")
		return

	var customer := customer_manager.call("spawn_customer_now") as CharacterBody3D
	if customer == null:
		push_warning("Could not spawn customer. Customer limit may be reached.")

func _create_worker_activity_ui() -> void:
	workers_button = Button.new()
	workers_button.text = "Workers"
	workers_button.toggle_mode = true
	workers_button.pressed.connect(_on_workers_button_pressed)
	hud_row.add_child(workers_button)

	workers_panel = PanelContainer.new()
	workers_panel.visible = false
	workers_panel.anchor_left = 0.0
	workers_panel.anchor_top = 0.0
	workers_panel.anchor_right = 0.0
	workers_panel.anchor_bottom = 0.0
	workers_panel.offset_left = 12.0
	workers_panel.offset_top = 44.0
	workers_panel.offset_right = 1040.0
	workers_panel.offset_bottom = 320.0
	add_child(workers_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	workers_panel.add_child(outer)

	var title := Label.new()
	title.text = "Worker Activity"
	outer.add_child(title)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	outer.add_child(header)
	_add_worker_cell(header, "Worker", 90.0)
	_add_worker_cell(header, "Role", 150.0)
	_add_worker_cell(header, "Status", 100.0)
	_add_worker_cell(header, "Task", 110.0)
	_add_worker_cell(header, "Customer", 100.0)
	_add_worker_cell(header, "Reason", 190.0)
	_add_worker_cell(header, "Stats", 210.0)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1000.0, 220.0)
	outer.add_child(scroll)

	workers_list = VBoxContainer.new()
	workers_list.add_theme_constant_override("separation", 4)
	scroll.add_child(workers_list)

	_worker_refresh_timer = Timer.new()
	_worker_refresh_timer.wait_time = 0.25
	_worker_refresh_timer.autostart = true
	_worker_refresh_timer.timeout.connect(_refresh_worker_activity_panel)
	add_child(_worker_refresh_timer)
	_refresh_worker_activity_panel()

func _create_boss_manager_ui() -> void:
	boss_button = Button.new()
	boss_button.text = "Boss"
	boss_button.toggle_mode = true
	boss_button.pressed.connect(_on_boss_button_pressed)
	hud_row.add_child(boss_button)

	boss_panel = PanelContainer.new()
	boss_panel.visible = false
	boss_panel.anchor_left = 0.0
	boss_panel.anchor_top = 0.0
	boss_panel.anchor_right = 0.0
	boss_panel.anchor_bottom = 0.0
	boss_panel.offset_left = 12.0
	boss_panel.offset_top = 260.0
	boss_panel.offset_right = 1040.0
	boss_panel.offset_bottom = 690.0
	add_child(boss_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	boss_panel.add_child(outer)

	var title := Label.new()
	title.text = "Boss Manager"
	outer.add_child(title)

	boss_summary_label = Label.new()
	boss_summary_label.custom_minimum_size = Vector2(1000.0, 44.0)
	boss_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(boss_summary_label)

	boss_view_option = OptionButton.new()
	for view_name in ["Overview", "LLM", "Workers", "Metrics", "Validation", "Raw"]:
		boss_view_option.add_item(view_name)
	boss_view_option.item_selected.connect(_on_boss_view_selected)
	outer.add_child(boss_view_option)

	boss_browser = HBoxContainer.new()
	boss_browser.add_theme_constant_override("separation", 8)
	outer.add_child(boss_browser)

	boss_event_list = ItemList.new()
	boss_event_list.custom_minimum_size = Vector2(360.0, 318.0)
	boss_event_list.select_mode = ItemList.SELECT_SINGLE
	boss_event_list.item_selected.connect(_on_boss_event_selected)
	boss_browser.add_child(boss_event_list)

	boss_detail_text = RichTextLabel.new()
	boss_detail_text.custom_minimum_size = Vector2(632.0, 318.0)
	boss_detail_text.fit_content = false
	boss_detail_text.scroll_active = true
	boss_detail_text.bbcode_enabled = false
	boss_browser.add_child(boss_detail_text)

	_boss_refresh_timer = Timer.new()
	_boss_refresh_timer.wait_time = 0.5
	_boss_refresh_timer.autostart = true
	_boss_refresh_timer.timeout.connect(_refresh_boss_panel)
	add_child(_boss_refresh_timer)
	_refresh_boss_panel()

func _on_boss_button_pressed() -> void:
	boss_panel.visible = boss_button.button_pressed
	if boss_panel.visible:
		_refresh_boss_panel()

func _refresh_boss_panel() -> void:
	if boss_summary_label == null or boss_event_list == null or boss_detail_text == null:
		return
	var boss_ai := _resolve_boss_ai()
	if boss_ai == null or not boss_ai.has_method("get_status"):
		boss_summary_label.text = "Boss AI not found."
		boss_event_list.clear()
		boss_detail_text.text = ""
		return
	var status: Dictionary = boss_ai.call("get_status")
	boss_summary_label.text = "Destination: %s | LLM: %s / %s | Next plan: %.1fs | Zones stale/unknown: %s" % [
		String(status.get("destination", "-")),
		"enabled" if bool(status.get("llm_enabled", false)) else "disabled",
		"ready" if bool(status.get("llm_available", false)) else "busy/unavailable",
		float(status.get("next_llm_seconds", 0.0)),
		_join_packed(status.get("stale_zones", PackedStringArray())),
	]
	var debug_path := String(status.get("debug_log_path", ""))
	if not debug_path.is_empty():
		boss_summary_label.text += "\nDebug log: %s" % debug_path

	var events: Array = status.get("event_log", [])
	_rebuild_boss_event_list(events)
	_refresh_boss_selected_view(status)

func _on_boss_view_selected(_index: int) -> void:
	_refresh_boss_panel()

func _on_boss_event_selected(index: int) -> void:
	_selected_boss_event_index = _event_index_from_list_index(index)
	_refresh_boss_panel()

func _rebuild_boss_event_list(events: Array) -> void:
	_boss_events_cache = events.duplicate()
	boss_event_list.clear()
	if _boss_events_cache.is_empty():
		_selected_boss_event_index = -1
		return
	if _selected_boss_event_index < 0 or _selected_boss_event_index >= _boss_events_cache.size():
		_selected_boss_event_index = _boss_events_cache.size() - 1
	for list_index in range(_boss_events_cache.size()):
		var event_index := _boss_events_cache.size() - 1 - list_index
		var event: Variant = _boss_events_cache[event_index]
		if not (event is Dictionary):
			continue
		var entry := event as Dictionary
		boss_event_list.add_item("%s  %s.%s" % [
			String(entry.get("game_time", "-")),
			String(entry.get("source", "-")),
			String(entry.get("action", "-")),
		])
	var selected_list_index := _list_index_from_event_index(_selected_boss_event_index)
	if selected_list_index >= 0 and selected_list_index < boss_event_list.item_count:
		boss_event_list.select(selected_list_index)

func _refresh_boss_event_detail(status: Dictionary) -> void:
	if _selected_boss_event_index < 0 or _selected_boss_event_index >= _boss_events_cache.size():
		boss_detail_text.text = "Select an action to inspect."
		return
	var event: Variant = _boss_events_cache[_selected_boss_event_index]
	if not (event is Dictionary):
		boss_detail_text.text = "Selected event is invalid."
		return
	var entry := event as Dictionary
	var lines := PackedStringArray()
	lines.append("Action: %s.%s" % [String(entry.get("source", "-")), String(entry.get("action", "-"))])
	lines.append("Game time: %s" % String(entry.get("game_time", "-")))
	lines.append("Real time: %.2fs" % float(entry.get("real_seconds", 0.0)))
	lines.append("")
	lines.append("Reason / description:")
	lines.append(String(entry.get("explanation", "No explanation recorded.")))
	var raw: Variant = entry.get("raw", {})
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		lines.append("")
		lines.append("Details:")
		lines.append(_format_boss_raw_details(raw as Dictionary))
	var latest: Array = status.get("latest_observations", [])
	if not latest.is_empty():
		lines.append("")
		lines.append("Latest observations:")
		for observation in latest:
			if observation is Dictionary:
				var obs := observation as Dictionary
				lines.append("- %s: %s" % [String(obs.get("zone", "-")), "; ".join(obs.get("facts", []))])
	boss_detail_text.text = "\n".join(lines)

func _refresh_boss_selected_view(status: Dictionary) -> void:
	var view_name := "Overview"
	if boss_view_option != null and boss_view_option.selected >= 0:
		view_name = boss_view_option.get_item_text(boss_view_option.selected)
	boss_event_list.visible = view_name == "Raw"
	if view_name == "Raw":
		boss_detail_text.custom_minimum_size = Vector2(632.0, 318.0)
		_refresh_boss_event_detail(status)
		return
	boss_detail_text.custom_minimum_size = Vector2(1000.0, 318.0)
	match view_name:
		"LLM":
			boss_detail_text.text = _build_boss_llm_view(status)
		"Workers":
			boss_detail_text.text = _build_boss_workers_view(status)
		"Metrics":
			boss_detail_text.text = _build_boss_metrics_view(status)
		"Validation":
			boss_detail_text.text = _build_boss_validation_view(status)
		_:
			boss_detail_text.text = _build_boss_overview_view(status)

func _build_boss_overview_view(status: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Current Plan")
	lines.append(JSON.stringify(status.get("last_plan", {}), "\t"))
	lines.append("")
	lines.append("Pending Role Changes")
	lines.append(JSON.stringify(status.get("pending_role_changes", {}), "\t"))
	lines.append("")
	lines.append("Restaurant Metrics")
	lines.append(JSON.stringify(status.get("restaurant_metrics", {}), "\t"))
	return "\n".join(lines)

func _build_boss_llm_view(status: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Last Parsed Plan")
	lines.append(JSON.stringify(status.get("last_plan", {}), "\t"))
	lines.append("")
	lines.append("Last Raw Response")
	lines.append(String(status.get("raw_json", "")))
	lines.append("")
	lines.append("Last Raw Prompt")
	lines.append(String(status.get("raw_prompt", "")))
	return "\n".join(lines)

func _build_boss_workers_view(status: Dictionary) -> String:
	var lines := PackedStringArray()
	var workers: Array = status.get("worker_metrics", [])
	if workers.is_empty():
		return "No worker metrics yet."
	for worker in workers:
		if not (worker is Dictionary):
			continue
		var entry := worker as Dictionary
		lines.append("%s | role %s | %s | pending %s" % [
			String(entry.get("worker", "-")),
			String(entry.get("role", "-")),
			String(entry.get("action", "-")),
			String(entry.get("pending_role", "")),
		])
		lines.append("  comparison: %s" % JSON.stringify(entry.get("comparison", {})))
		lines.append("  interview: %s" % JSON.stringify(entry.get("interview", {})))
		lines.append("  performance: %s" % JSON.stringify(entry.get("performance", {})))
	return "\n".join(lines)

func _build_boss_metrics_view(status: Dictionary) -> String:
	return JSON.stringify({
		"restaurant": status.get("restaurant_metrics", {}),
		"workers": status.get("worker_metrics", []),
	}, "\t")

func _build_boss_validation_view(status: Dictionary) -> String:
	var lines := PackedStringArray()
	var results: Array = status.get("validation_results", [])
	if results.is_empty():
		lines.append("No validation results yet.")
	else:
		for result in results:
			if result is Dictionary:
				var entry := result as Dictionary
				lines.append("%s %s: %s" % [
					"OK" if bool(entry.get("ok", false)) else "REJECTED",
					String(entry.get("action", "-")),
					String(entry.get("message", "")),
				])
				lines.append("  %s" % JSON.stringify(entry.get("raw", {})))
	lines.append("")
	lines.append("Recent Events")
	var events: Array = status.get("event_log", [])
	var start_index := maxi(0, events.size() - 10)
	for index in range(start_index, events.size()):
		var event: Variant = events[index]
		if event is Dictionary:
			var entry := event as Dictionary
			lines.append("%s %s.%s - %s" % [
				String(entry.get("game_time", "-")),
				String(entry.get("source", "-")),
				String(entry.get("action", "-")),
				String(entry.get("explanation", "")),
			])
	return "\n".join(lines)

func _format_boss_raw_details(raw: Dictionary) -> String:
	var lines := PackedStringArray()
	for key in raw.keys():
		var value: Variant = raw[key]
		if key == "prompt":
			lines.append("prompt:\n%s" % str(value))
		elif key == "raw_json":
			lines.append("raw_json:\n%s" % str(value))
		elif value is Dictionary or value is Array:
			lines.append("%s: %s" % [String(key), JSON.stringify(value, "\t")])
		else:
			lines.append("%s: %s" % [String(key), str(value)])
	return "\n".join(lines)

func _event_index_from_list_index(list_index: int) -> int:
	if list_index < 0:
		return -1
	return _boss_events_cache.size() - 1 - list_index

func _list_index_from_event_index(event_index: int) -> int:
	if event_index < 0:
		return -1
	return _boss_events_cache.size() - 1 - event_index

func _resolve_boss_ai() -> Node:
	var level := get_tree().current_scene
	if level == null:
		return null
	var boss := level.find_child("BossNpc", true, false)
	if boss == null:
		return null
	return boss.get_node_or_null("BossAI")

func _join_packed(value: Variant) -> String:
	if value is PackedStringArray:
		var packed := value as PackedStringArray
		return ", ".join(packed) if not packed.is_empty() else "-"
	if value is Array:
		var parts := PackedStringArray()
		for item in value:
			parts.append(String(item))
		return ", ".join(parts) if not parts.is_empty() else "-"
	return "-"

func _on_workers_button_pressed() -> void:
	workers_panel.visible = workers_button.button_pressed
	if workers_panel.visible:
		_refresh_worker_activity_panel()

func _refresh_worker_activity_panel() -> void:
	if workers_list == null:
		return

	var workers := get_tree().get_nodes_in_group("worker_npc")
	if _worker_rows_need_rebuild(workers):
		_rebuild_worker_activity_rows(workers)

	if workers.is_empty():
		return

	for worker in workers:
		if worker == null or not is_instance_valid(worker):
			continue
		if not _worker_rows.has(worker):
			continue
		var ai := worker.get_node_or_null("WorkerAI")
		var status := {}
		if ai != null and ai.has_method("get_activity_status"):
			status = ai.call("get_activity_status")
		var row_data: Dictionary = _worker_rows[worker]
		(row_data.get("worker") as Label).text = String(worker.name)
		_set_worker_role_option_selection(row_data.get("role") as OptionButton, worker)
		(row_data.get("action") as Label).text = str(status.get("action", "-"))
		(row_data.get("task") as Label).text = str(status.get("task", "-"))
		(row_data.get("customer") as Label).text = str(status.get("customer", "-"))
		(row_data.get("reason") as Label).text = str(status.get("reason", "-"))
		(row_data.get("stats") as Label).text = str(status.get("stats", "-"))

func _worker_rows_need_rebuild(workers: Array[Node]) -> bool:
	if workers.size() != _worker_rows.size():
		return true
	for worker in workers:
		if not _worker_rows.has(worker):
			return true
	return false

func _rebuild_worker_activity_rows(workers: Array[Node]) -> void:
	for child in workers_list.get_children():
		child.queue_free()
	_worker_rows.clear()

	if workers.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No workers"
		workers_list.add_child(empty_label)
		return

	for worker in workers:
		if worker == null or not is_instance_valid(worker):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		workers_list.add_child(row)

		var row_data := {
			"worker": _add_worker_cell(row, String(worker.name), 90.0),
			"role": _add_worker_role_option(row, worker, 150.0),
			"action": _add_worker_cell(row, "-", 100.0),
			"task": _add_worker_cell(row, "-", 110.0),
			"customer": _add_worker_cell(row, "-", 100.0),
			"reason": _add_worker_cell(row, "-", 190.0),
			"stats": _add_worker_cell(row, "-", 210.0)
		}
		_worker_rows[worker] = row_data

func _add_worker_cell(parent: Control, text: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0.0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label

func _add_worker_role_option(parent: Control, worker: Node, width: float) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(width, 0.0)
	option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ai := worker.get_node_or_null("WorkerAI") if worker != null else null
	option.disabled = ai == null
	var role_options := _get_worker_role_options(ai)
	for index in range(role_options.size()):
		var role: Dictionary = role_options[index]
		var role_id := int(role.get("id", index))
		option.add_item(String(role.get("label", str(role_id))), role_id)
	_set_worker_role_option_selection(option, worker)
	option.item_selected.connect(_on_worker_role_selected.bind(worker, option))
	parent.add_child(option)
	return option

func _on_worker_role_selected(index: int, worker: Node, option: OptionButton) -> void:
	if worker == null or not is_instance_valid(worker) or option == null:
		return
	var ai := worker.get_node_or_null("WorkerAI")
	if ai == null:
		return
	var role_id := option.get_item_id(index)
	if ai.has_method("set_job_role"):
		ai.call("set_job_role", role_id)

func _set_worker_role_option_selection(option: OptionButton, worker: Node) -> void:
	if option == null or worker == null or not is_instance_valid(worker):
		return
	var ai := worker.get_node_or_null("WorkerAI")
	if ai == null:
		option.disabled = true
		return
	option.disabled = false
	var selected_role := int(ai.job_role)
	for index in range(option.item_count):
		if option.get_item_id(index) == selected_role:
			if option.selected != index:
				option.selected = index
			return

func _get_worker_role_options(ai: Node) -> Array[Dictionary]:
	if ai != null and ai.has_method("get_job_role_options"):
		return ai.call("get_job_role_options")
	return []
