extends PanelContainer

@onready var max_customers_spinbox: SpinBox = $VBoxContainer/MaxCustomersContainer/SpinBox
@onready var root_container: VBoxContainer = $VBoxContainer
@onready var workers_container: VBoxContainer = $VBoxContainer/WorkersContainer

var _worker_options: Dictionary = {}
var _price_spinboxes: Dictionary = {}
var _syncing_prices := false

func _ready() -> void:
	visible = false # hide by default
	_build_price_controls()
	
	# Try find customer manager
	var tree = get_tree()
	if tree and tree.current_scene:
		var cm = tree.current_scene.find_child("CustomerManager", true, false)
		if cm:
			max_customers_spinbox.value = cm.max_customers
			max_customers_spinbox.value_changed.connect(_on_max_customers_changed)
			
	# Watch for new workers
	get_tree().node_added.connect(_on_node_added)
	
	# Initial workers
	_refresh_workers()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"): # Or another key if configured
		visible = !visible

func _on_max_customers_changed(value: float) -> void:
	var tree = get_tree()
	if tree and tree.current_scene:
		var cm = tree.current_scene.find_child("CustomerManager", true, false)
		if cm:
			cm.max_customers = int(value)

func _build_price_controls() -> void:
	var rm := get_node_or_null("/root/RestaurantManager")
	if rm == null or not rm.has_method("get_menu_items"):
		return

	var header := Label.new()
	header.text = "Menu Prices"
	root_container.add_child(header)

	for item in rm.call("get_menu_items"):
		if not (item is Dictionary):
			continue
		var item_id := String(item.get("id", ""))
		if item_id.is_empty():
			continue

		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = String(item.get("label", item_id)).capitalize() + ":"
		row.add_child(label)

		var spinbox := SpinBox.new()
		spinbox.min_value = 0.0
		spinbox.max_value = 100.0
		spinbox.step = 0.25
		spinbox.value = float(item.get("price", 0.0))
		spinbox.value_changed.connect(_on_price_changed.bind(item_id))
		row.add_child(spinbox)

		_price_spinboxes[item_id] = spinbox
		root_container.add_child(row)

	if rm.has_signal("menu_prices_changed"):
		var callback := Callable(self, "_refresh_price_controls")
		if not rm.is_connected("menu_prices_changed", callback):
			rm.connect("menu_prices_changed", callback)

func _on_price_changed(value: float, food_type: String) -> void:
	if _syncing_prices:
		return
	var rm := get_node_or_null("/root/RestaurantManager")
	if rm != null and rm.has_method("set_food_price"):
		rm.call("set_food_price", food_type, value)

func _refresh_price_controls() -> void:
	var rm := get_node_or_null("/root/RestaurantManager")
	if rm == null or not rm.has_method("get_food_price"):
		return
	_syncing_prices = true
	for food_type in _price_spinboxes.keys():
		var spinbox := _price_spinboxes[food_type] as SpinBox
		if spinbox != null and is_instance_valid(spinbox):
			spinbox.value = float(rm.call("get_food_price", String(food_type)))
	_syncing_prices = false

func _on_node_added(node: Node) -> void:
	if node.is_in_group("worker_npc"):
		call_deferred("_refresh_workers")

func _refresh_workers() -> void:
	for child in workers_container.get_children():
		child.queue_free()
	
	_worker_options.clear()
	
	var workers = get_tree().get_nodes_in_group("worker_npc")
	for worker in workers:
		var ai = worker.get_node_or_null("WorkerAI")
		if ai == null: continue
		
		var hbox = HBoxContainer.new()
		var label = Label.new()
		label.text = worker.name
		hbox.add_child(label)
		
		var ob = OptionButton.new()
		var selected_index := 0
		var role_options: Array = ai.call("get_job_role_options") if ai.has_method("get_job_role_options") else _get_fallback_role_options()
		for index in range(role_options.size()):
			var role: Dictionary = role_options[index]
			var role_id := int(role.get("id", index))
			ob.add_item(String(role.get("label", str(role_id))), role_id)
			if role_id == int(ai.job_role):
				selected_index = index
		ob.selected = selected_index
		
		ob.item_selected.connect(func(idx):
			var role_id := ob.get_item_id(idx)
			if ai.has_method("set_job_role"):
				ai.call("set_job_role", role_id)
			else:
				ai.job_role = role_id
		)
		
		hbox.add_child(ob)
		workers_container.add_child(hbox)

func _get_fallback_role_options() -> Array[Dictionary]:
	return [
		{"id": 0, "label": "Auto"},
		{"id": 1, "label": "Cashier"},
		{"id": 2, "label": "Meat Griller"},
		{"id": 3, "label": "Burger Prepper"},
		{"id": 4, "label": "Fries Fryer"},
		{"id": 5, "label": "Caterer"}
	]
