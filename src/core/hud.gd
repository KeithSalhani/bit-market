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
var boss_text: RichTextLabel
var _worker_refresh_timer: Timer
var _boss_refresh_timer: Timer
var _worker_rows: Dictionary = {}

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
	boss_panel.offset_top = 330.0
	boss_panel.offset_right = 720.0
	boss_panel.offset_bottom = 620.0
	add_child(boss_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	boss_panel.add_child(outer)

	var title := Label.new()
	title.text = "Boss Manager"
	outer.add_child(title)

	boss_text = RichTextLabel.new()
	boss_text.custom_minimum_size = Vector2(680.0, 240.0)
	boss_text.fit_content = false
	boss_text.scroll_active = true
	boss_text.bbcode_enabled = false
	outer.add_child(boss_text)

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
	if boss_text == null:
		return
	var boss_ai := _resolve_boss_ai()
	if boss_ai == null or not boss_ai.has_method("get_status"):
		boss_text.text = "Boss AI not found."
		return
	var status: Dictionary = boss_ai.call("get_status")
	var lines := PackedStringArray()
	lines.append("Destination: %s" % String(status.get("destination", "-")))
	lines.append("LLM: %s" % ("enabled" if bool(status.get("llm_enabled", false)) else "disabled"))
	lines.append("Known zones: %s" % _join_packed(status.get("known_zones", PackedStringArray())))
	lines.append("Stale/unknown zones: %s" % _join_packed(status.get("stale_zones", PackedStringArray())))
	lines.append("Last action: %s" % String(status.get("last_action", "-")))
	var rejected := String(status.get("rejected_reason", ""))
	if not rejected.is_empty():
		lines.append("Rejected: %s" % rejected)
	var failure := String(status.get("failure", ""))
	if not failure.is_empty():
		lines.append("Failure: %s" % failure)
	var speech := String(status.get("speech", ""))
	if not speech.is_empty():
		lines.append("Speech: %s" % speech)
	lines.append("")
	lines.append("Latest observations:")
	var latest: Array = status.get("latest_observations", [])
	if latest.is_empty():
		lines.append("- none")
	else:
		for observation in latest:
			if not (observation is Dictionary):
				continue
			var entry := observation as Dictionary
			lines.append("- %s: %s" % [String(entry.get("zone", "-")), "; ".join(entry.get("facts", []))])
	var raw_json := String(status.get("raw_json", ""))
	if not raw_json.is_empty():
		lines.append("")
		lines.append("Raw LLM JSON:")
		lines.append(raw_json)
	boss_text.text = "\n".join(lines)

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
	else:
		ai.job_role = role_id

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
	return [
		{"id": 0, "label": "Auto"},
		{"id": 1, "label": "Cashier"},
		{"id": 2, "label": "Meat Griller"},
		{"id": 3, "label": "Burger Prepper"},
		{"id": 4, "label": "Fries Fryer"},
		{"id": 5, "label": "Caterer"}
	]
