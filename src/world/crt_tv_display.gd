extends Node3D

@export_enum("Custom", "Menu", "Orders") var display_mode: String = "Custom":
	set(value):
		display_mode = value
		if is_node_ready():
			_update_dynamic_display_text()

@export_multiline var display_text: String = "BIT MARKET\nCRT DISPLAY READY\n\nOrders: 0\nStatus: Online":
	set(value):
		display_text = value
		if is_node_ready():
			_update_viewport_content()

@export var text_color: Color = Color(0.7, 1.0, 0.72, 1.0):
	set(value):
		text_color = value
		if is_node_ready():
			_apply_text_style()

@export var screen_glow_color: Color = Color(0.03, 0.22, 0.08, 0.72):
	set(value):
		screen_glow_color = value
		if is_node_ready():
			_update_viewport_content()

@export_range(8, 96, 1) var font_size: int = 20:
	set(value):
		font_size = value
		if is_node_ready():
			_update_viewport_content()

@export var viewport_size: Vector2i = Vector2i(512, 384):
	set(value):
		viewport_size = Vector2i(max(value.x, 64), max(value.y, 64))
		if is_node_ready():
			_update_viewport_content()

@export_range(0.0, 0.08, 0.001) var horizontal_padding: float = 0.018:
	set(value):
		horizontal_padding = value
		if is_node_ready():
			_rebuild_display()

@export_range(0.0, 0.08, 0.001) var vertical_padding: float = 0.018:
	set(value):
		vertical_padding = value
		if is_node_ready():
			_rebuild_display()

@export_range(0.0, 0.02, 0.0005) var surface_offset: float = 0.004:
	set(value):
		surface_offset = value
		if is_node_ready():
			_rebuild_display()

@export_range(2, 32, 1) var curve_segments: int = 12:
	set(value):
		curve_segments = value
		if is_node_ready():
			_rebuild_screen_mesh()

@export_enum("Horizontal", "Vertical") var curve_axis: String = "Horizontal":
	set(value):
		curve_axis = value
		if is_node_ready():
			_rebuild_display()

@export var bottom_left_path: NodePath = ^"root/bottom_left"
@export var bottom_right_path: NodePath = ^"root/bottom_right"
@export var top_left_path: NodePath = ^"root/top_left"
@export var top_right_path: NodePath = ^"root/top_right"
@export var center_left_path: NodePath = ^"root/center_left"
@export var center_right_path: NodePath = ^"root/center_right"
@export var center_top_path: NodePath
@export var center_bottom_path: NodePath
@export var center_path: NodePath = ^"root/center"
@export_range(1, 12, 1) var max_order_lines := 7
@export_range(0.1, 5.0, 0.1) var order_refresh_seconds := 0.5

var _display_root: Node3D
var _screen_mesh: MeshInstance3D
var _screen_viewport: SubViewport
var _screen_background: ColorRect
var _screen_label: Label
var _surface_parent: Node3D
var _bottom_left: Node3D
var _bottom_right: Node3D
var _top_left: Node3D
var _top_right: Node3D
var _center_left: Node3D
var _center_right: Node3D
var _center_top: Node3D
var _center_bottom: Node3D
var _center: Node3D
var _right_axis := Vector3.RIGHT
var _up_axis := Vector3.UP
var _face_axis := Vector3.FORWARD
var _center_push := Vector3.ZERO
var _order_refresh_timer := 0.0


func _ready() -> void:
	_cache_markers()
	_connect_dynamic_sources()
	_update_dynamic_display_text()
	_rebuild_display()


func _process(delta: float) -> void:
	if display_mode != "Orders":
		return
	_order_refresh_timer -= delta
	if _order_refresh_timer <= 0.0:
		_order_refresh_timer = order_refresh_seconds
		_update_dynamic_display_text()


func set_display_text(value: String) -> void:
	display_mode = "Custom"
	display_text = value


func append_line(value: String) -> void:
	display_mode = "Custom"
	if display_text.is_empty():
		display_text = value
	else:
		display_text += "\n" + value


func clear_display() -> void:
	display_mode = "Custom"
	display_text = ""


func _connect_dynamic_sources() -> void:
	var restaurant_manager := get_node_or_null("/root/RestaurantManager")
	if restaurant_manager != null and restaurant_manager.has_signal("menu_prices_changed"):
		var price_callback := Callable(self, "_on_dynamic_source_changed")
		if not restaurant_manager.is_connected("menu_prices_changed", price_callback):
			restaurant_manager.connect("menu_prices_changed", price_callback)

	var task_manager := get_node_or_null("/root/TaskManager")
	if task_manager != null and task_manager.has_signal("tasks_changed"):
		var task_callback := Callable(self, "_on_dynamic_source_changed")
		if not task_manager.is_connected("tasks_changed", task_callback):
			task_manager.connect("tasks_changed", task_callback)


func _on_dynamic_source_changed() -> void:
	_update_dynamic_display_text()


func _update_dynamic_display_text() -> void:
	if display_mode == "Menu":
		display_text = _build_menu_text()
	elif display_mode == "Orders":
		display_text = _build_orders_text()


func _build_menu_text() -> String:
	var restaurant_manager := get_node_or_null("/root/RestaurantManager")
	var items: Array[Dictionary] = [
		{"label": "BURGER", "price": 5.0},
		{"label": "FRIES", "price": 2.0},
		{"label": "SODA", "price": 1.0},
	]
	if restaurant_manager != null and restaurant_manager.has_method("get_menu_items"):
		var menu_items: Variant = restaurant_manager.call("get_menu_items")
		if menu_items is Array:
			items.clear()
			for item in menu_items:
				if item is Dictionary:
					items.append(item)

	var lines: PackedStringArray = ["BIT MARKET MENU", ""]
	for item in items:
		lines.append("%-8s %s" % [String(item.get("label", "ITEM")), _format_price(float(item.get("price", 0.0)))])
	return "\n".join(lines)


func _build_orders_text() -> String:
	var task_manager := get_node_or_null("/root/TaskManager")
	if task_manager == null:
		return "BIT MARKET ORDERS\n\nTask manager offline"

	var order_lines: PackedStringArray = []
	_append_order_lines(order_lines, task_manager.active_tasks, "ACTIVE")
	_append_order_lines(order_lines, task_manager.pending_tasks, "PENDING")

	var lines: PackedStringArray = [
		"BIT MARKET ORDERS",
		"ACTIVE %d  WAITING %d" % [task_manager.active_tasks.size(), task_manager.pending_tasks.size()],
		"",
	]
	if order_lines.is_empty():
		lines.append("No orders")
	else:
		lines.append_array(order_lines)
	return "\n".join(lines)


func _append_order_lines(lines: PackedStringArray, tasks: Array, status_label: String) -> void:
	for task in tasks:
		if lines.size() >= max_order_lines:
			return
		if task == null:
			continue
		var food_type := String(task.args.get("food_type", ""))
		if food_type.is_empty() and task.type != 0:
			continue
		var task_label := _short_task_label(int(task.type))
		var food_label := food_type.to_upper() if not food_type.is_empty() else task_label
		var customer_label := _node_label(task.args.get("customer"))
		var worker_label := _node_label(task.assigned_worker)
		if worker_label == "-":
			worker_label = status_label
		lines.append("%s %-7s C:%s W:%s" % [task_label, food_label, customer_label, worker_label])


func _short_task_label(task_type: int) -> String:
	match task_type:
		0:
			return "ORDER"
		1:
			return "MEAT "
		2:
			return "FRIES"
		3:
			return "BUILD"
		4:
			return "SERVE"
	return "TASK "


func _node_label(value: Variant) -> String:
	if value is Node and is_instance_valid(value):
		return String((value as Node).name)
	return "-"


func _format_price(price: float) -> String:
	return "$%.2f" % price


func _cache_markers() -> void:
	_bottom_left = get_node_or_null(bottom_left_path) as Node3D
	_bottom_right = get_node_or_null(bottom_right_path) as Node3D
	_top_left = get_node_or_null(top_left_path) as Node3D
	_top_right = get_node_or_null(top_right_path) as Node3D
	_center_left = get_node_or_null(center_left_path) as Node3D
	_center_right = get_node_or_null(center_right_path) as Node3D
	_center_top = get_node_or_null(center_top_path) as Node3D
	_center_bottom = get_node_or_null(center_bottom_path) as Node3D
	_center = get_node_or_null(center_path) as Node3D
	_surface_parent = get_node_or_null(^"root") as Node3D
	if _surface_parent == null:
		_surface_parent = self


func _rebuild_display() -> void:
	if not _markers_are_ready():
		push_warning("CRT TV display markers are missing.")
		return

	_update_axes()
	_ensure_display_root()
	_rebuild_screen_mesh()
	_update_viewport_content()


func _markers_are_ready() -> bool:
	return (
		_bottom_left != null
		and _bottom_right != null
		and _top_left != null
		and _top_right != null
		and _center != null
	)


func _ensure_display_root() -> void:
	if _display_root != null and is_instance_valid(_display_root):
		return

	_display_root = _surface_parent.get_node_or_null("ScreenDisplay") as Node3D
	if _display_root == null:
		_display_root = Node3D.new()
		_display_root.name = "ScreenDisplay"
		_surface_parent.add_child(_display_root)

	_screen_mesh = _display_root.get_node_or_null("ScreenGlow") as MeshInstance3D
	if _screen_mesh == null:
		_screen_mesh = MeshInstance3D.new()
		_screen_mesh.name = "ScreenGlow"
		_display_root.add_child(_screen_mesh)

	_screen_viewport = _display_root.get_node_or_null("ScreenViewport") as SubViewport
	if _screen_viewport == null:
		_screen_viewport = SubViewport.new()
		_screen_viewport.name = "ScreenViewport"
		_display_root.add_child(_screen_viewport)

	_screen_background = _screen_viewport.get_node_or_null("Background") as ColorRect
	if _screen_background == null:
		_screen_background = ColorRect.new()
		_screen_background.name = "Background"
		_screen_viewport.add_child(_screen_background)

	_screen_label = _screen_viewport.get_node_or_null("Text") as Label
	if _screen_label == null:
		_screen_label = Label.new()
		_screen_label.name = "Text"
		_screen_viewport.add_child(_screen_label)


func _update_axes() -> void:
	var left_center := _bottom_left.position.lerp(_top_left.position, 0.5)
	var right_center := _bottom_right.position.lerp(_top_right.position, 0.5)
	if _center_left != null:
		left_center = _center_left.position
	if _center_right != null:
		right_center = _center_right.position

	_right_axis = (right_center - left_center).normalized()
	_up_axis = (_top_left.position - _bottom_left.position).normalized()

	var flat_center := left_center.lerp(right_center, 0.5)
	_center_push = _center.position - flat_center
	if _center_push.length_squared() < 0.000001:
		_face_axis = _right_axis.cross(_up_axis).normalized()
	else:
		_face_axis = _center_push.normalized()


func _rebuild_screen_mesh() -> void:
	if _screen_mesh == null:
		return

	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rows := 2
	var columns: int = max(curve_segments, 2) + 1
	if curve_axis == "Vertical":
		rows = max(curve_segments, 2) + 1
		columns = 2

	for row in range(rows):
		var v := float(row) / float(rows - 1)
		for column in range(columns):
			var u := float(column) / float(columns - 1)
			vertices.append(_screen_point(u, v))
			uvs.append(Vector2(u, 1.0 - v))

	for row in range(rows - 1):
		for column in range(columns - 1):
			var a := (row * columns) + column
			var b := a + 1
			var c := ((row + 1) * columns) + column
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_screen_mesh.mesh = mesh
	_screen_mesh.material_override = _screen_material()


func _update_viewport_content() -> void:
	if _screen_viewport == null or _screen_background == null or _screen_label == null:
		return

	_screen_viewport.size = viewport_size
	_screen_viewport.transparent_bg = false
	_screen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var margin := Vector2(28.0, 22.0)
	_screen_background.position = viewport_rect.position
	_screen_background.size = viewport_rect.size
	_screen_background.color = screen_glow_color

	var label_settings := LabelSettings.new()
	label_settings.font_size = font_size
	label_settings.font_color = text_color
	label_settings.outline_size = 4
	label_settings.outline_color = Color(0.0, 0.05, 0.0, 1.0)

	_screen_label.position = margin
	_screen_label.size = viewport_rect.size - (margin * 2.0)
	_screen_label.text = display_text
	_screen_label.label_settings = label_settings
	_screen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_screen_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_screen_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_screen_label.clip_text = true


func _apply_text_style() -> void:
	_update_viewport_content()


func _usable_screen_width() -> float:
	var left := _bottom_left.position.lerp(_top_left.position, 0.5)
	var right := _bottom_right.position.lerp(_top_right.position, 0.5)
	return max(left.distance_to(right) * (1.0 - horizontal_padding * 2.0), 0.001)


func _usable_screen_height() -> float:
	var bottom := _bottom_left.position.lerp(_bottom_right.position, 0.5)
	var top := _top_left.position.lerp(_top_right.position, 0.5)
	return max(bottom.distance_to(top) * (1.0 - vertical_padding * 2.0), 0.001)


func _screen_point(u: float, v: float) -> Vector3:
	var padded_u := lerpf(horizontal_padding, 1.0 - horizontal_padding, clampf(u, 0.0, 1.0))
	var padded_v := lerpf(vertical_padding, 1.0 - vertical_padding, clampf(v, 0.0, 1.0))
	var left := _bottom_left.position.lerp(_top_left.position, padded_v)
	var right := _bottom_right.position.lerp(_top_right.position, padded_v)
	var flat := left.lerp(right, padded_u)
	var curve_offset := Vector3.ZERO
	if curve_axis == "Vertical":
		var flat_mid := left.lerp(right, 0.5)
		var raw_offset := _vertical_curve_midpoint(padded_v) - flat_mid
		curve_offset = raw_offset - (_right_axis * raw_offset.dot(_right_axis))
	else:
		var curve := sin(padded_u * PI)
		curve_offset = _center_push * curve
	return flat + curve_offset + (_face_axis * surface_offset)


func _vertical_curve_midpoint(v: float) -> Vector3:
	var bottom_mid := _bottom_left.position.lerp(_bottom_right.position, 0.5)
	var top_mid := _top_left.position.lerp(_top_right.position, 0.5)
	if _center_bottom != null:
		bottom_mid = _center_bottom.position
	if _center_top != null:
		top_mid = _center_top.position

	var bottom_weight := (2.0 * v * v) - (3.0 * v) + 1.0
	var center_weight := (-4.0 * v * v) + (4.0 * v)
	var top_weight := (2.0 * v * v) - v
	return (bottom_mid * bottom_weight) + (_center.position * center_weight) + (top_mid * top_weight)


func _screen_basis() -> Basis:
	return Basis(_right_axis, _up_axis, -_face_axis).orthonormalized()


func _screen_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	if _screen_viewport != null:
		material.albedo_texture = _screen_viewport.get_texture()
	material.emission_enabled = true
	material.emission = Color.WHITE
	if _screen_viewport != null:
		material.emission_texture = _screen_viewport.get_texture()
	material.emission_energy_multiplier = 0.65
	material.no_depth_test = false
	return material
