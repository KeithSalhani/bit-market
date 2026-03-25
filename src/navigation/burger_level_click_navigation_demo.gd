extends NavigationRegion3D

@export var click_navigation_demo_enabled := true
@export var npc_path: NodePath = ^"RogueNPC"
@export var demo_camera_path: NodePath = ^"DemoCamera3D"
@export var ray_length := 1000.0
@export var navigation_plane_y := 0.4
@export var print_debug_messages := true

@onready var npc: Node = get_node_or_null(npc_path)
@onready var demo_camera: Camera3D = get_node_or_null(demo_camera_path) as Camera3D

func _ready() -> void:
	if not click_navigation_demo_enabled:
		return

	if npc == null:
		push_warning("Click navigation demo could not find NPC at path: %s" % String(npc_path))
	if demo_camera == null:
		push_warning("Click navigation demo could not find camera at path: %s" % String(demo_camera_path))

	if demo_camera != null and get_viewport().get_camera_3d() == null:
		demo_camera.current = true

	if demo_camera != null and npc is Node3D:
		demo_camera.look_at((npc as Node3D).global_position, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if not click_navigation_demo_enabled:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var click_position: Variant = _get_click_world_position(event.position)
		if click_position == null:
			return

		var navigation_map := get_world_3d().navigation_map
		var target_position: Vector3 = click_position
		var closest_point := NavigationServer3D.map_get_closest_point(navigation_map, target_position)
		if npc != null and npc.has_method("set_navigation_target"):
			npc.set_navigation_target(closest_point)
			if print_debug_messages:
				print("Click navigation target: ", closest_point)
		elif print_debug_messages:
			print("Click navigation ignored: NPC target method not available")

func _get_click_world_position(screen_position: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null

	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * ray_length)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.has("position"):
		return hit["position"]

	var navigation_plane := Plane(Vector3.UP, navigation_plane_y)
	return navigation_plane.intersects_ray(ray_origin, ray_direction)
