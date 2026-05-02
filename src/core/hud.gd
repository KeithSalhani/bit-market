extends CanvasLayer

@onready var money_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/MoneyLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/TimeLabel
@onready var day_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/DayLabel
@onready var open_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/OpenButton
@onready var hire_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/HireButton
@onready var hud_row: HBoxContainer = $MarginContainer/VBoxContainer/HBoxContainer

var spawn_customer_button: Button
var workers_button: Button
var workers_panel: PanelContainer
var workers_list: VBoxContainer
var _worker_refresh_timer: Timer

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
	workers_panel.offset_right = 620.0
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
	_add_worker_cell(header, "Role", 70.0)
	_add_worker_cell(header, "Status", 100.0)
	_add_worker_cell(header, "Task", 110.0)
	_add_worker_cell(header, "Customer", 100.0)
	_add_worker_cell(header, "Reason", 190.0)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580.0, 220.0)
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

func _on_workers_button_pressed() -> void:
	workers_panel.visible = workers_button.button_pressed
	if workers_panel.visible:
		_refresh_worker_activity_panel()

func _refresh_worker_activity_panel() -> void:
	if workers_list == null:
		return
	for child in workers_list.get_children():
		child.queue_free()

	var workers := get_tree().get_nodes_in_group("worker_npc")
	if workers.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No workers"
		workers_list.add_child(empty_label)
		return

	for worker in workers:
		if worker == null or not is_instance_valid(worker):
			continue
		var ai := worker.get_node_or_null("WorkerAI")
		var status := {}
		if ai != null and ai.has_method("get_activity_status"):
			status = ai.call("get_activity_status")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		workers_list.add_child(row)
		_add_worker_cell(row, String(worker.name), 90.0)
		_add_worker_cell(row, str(status.get("role", "-")), 70.0)
		_add_worker_cell(row, str(status.get("action", "-")), 100.0)
		_add_worker_cell(row, str(status.get("task", "-")), 110.0)
		_add_worker_cell(row, str(status.get("customer", "-")), 100.0)
		_add_worker_cell(row, str(status.get("reason", "-")), 190.0)

func _add_worker_cell(parent: Control, text: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0.0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label
