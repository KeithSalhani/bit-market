extends PanelContainer

@onready var max_customers_spinbox: SpinBox = $VBoxContainer/MaxCustomersContainer/SpinBox
@onready var workers_container: VBoxContainer = $VBoxContainer/WorkersContainer

var _worker_options: Dictionary = {}

func _ready() -> void:
	visible = false # hide by default
	
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
