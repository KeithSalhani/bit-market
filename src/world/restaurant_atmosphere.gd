extends Node3D

@export var vfx_enabled := true
@export var atmosphere_enabled := true
@export var sun_enabled := true
@export var ambient_particles_enabled := true
@export var imported_fixture_lights_enabled := true
@export var lamppost_marker_lights_enabled := true
@export var rainy_night_enabled := true
@export var rain_enabled := true
@export var rain_audio_enabled := true
@export var rain_sound_path: NodePath = ^"../rain-sound"
@export_range(0.25, 2.0, 0.05) var quality_scale := 1.0
@export_range(0.0, 8.0, 0.05) var fixture_light_energy := 2.4
@export_range(1.0, 12.0, 0.1) var fixture_light_range := 5.2
@export_range(0.0, 8.0, 0.05) var fixture_spot_energy := 3.2
@export_range(10.0, 85.0, 1.0) var fixture_spot_angle := 58.0
@export_range(0.0, 12.0, 0.05) var lamppost_light_energy := 5.0
@export_range(1.0, 20.0, 0.1) var lamppost_light_range := 11.0
@export_range(10.0, 85.0, 1.0) var lamppost_spot_angle := 48.0
@export_range(0.25, 7.0, 0.05) var lamppost_pool_radius := 3.6
@export_range(0.01, 0.45, 0.01) var lamppost_pool_alpha := 0.12
@export_range(0.0, 2.0, 0.01) var rain_intensity := 1.45
@export var rain_center := Vector3(52.0, 14.0, 24.0)
@export var rain_extents := Vector3(115.0, 1.0, 70.0)
@export var rain_roof_padding := Vector3(-3.0, 0.0, -3.0)
@export_range(0.05, 1.0, 0.01) var rain_roof_density_scale := 0.34
@export_range(0.4, 4.0, 0.05) var rain_roof_clearance := 1.65
@export_range(8.0, 36.0, 0.5) var rain_spawn_height := 28.0
@export_range(3.0, 18.0, 0.25) var rain_roof_spawn_height := 10.0
@export_range(-30.0, 6.0, 0.5) var rain_outside_volume_db := -2.0
@export_range(-40.0, 0.0, 0.5) var rain_inside_volume_db := -11.0
@export_range(500.0, 12000.0, 50.0) var rain_outside_cutoff_hz := 10500.0
@export_range(300.0, 6000.0, 50.0) var rain_inside_cutoff_hz := 1450.0
@export_range(1.0, 12.0, 0.25) var rain_audio_muffle_speed := 4.5
@export var rain_audio_right_boundary_path: NodePath = ^"../BurgerPiz2/Door_F_001"
@export var rain_audio_back_boundary_path: NodePath = ^"../BurgerPiz2/Windows_002"
@export var rain_audio_left_boundary_path: NodePath = ^"../BurgerPiz2/Windows"
@export var rain_audio_front_boundary_path: NodePath = ^"../BurgerPiz2/Door"
@export_range(0.0, 4.0, 0.05) var rain_audio_boundary_padding := 0.35

var _environment_node: WorldEnvironment
var _sun: DirectionalLight3D
var _dust: GPUParticles3D
var _rain_emitters: Array[GPUParticles3D] = []
var _rain_mist_emitters: Array[GPUParticles3D] = []
var _fixture_light_root: Node3D
var _fixture_glow_material: StandardMaterial3D
var _lamppost_pool_material: ShaderMaterial
var _rain_material: StandardMaterial3D
var _rain_mist_material: StandardMaterial3D
var _rain_audio_player: AudioStreamPlayer3D
var _rain_audio_filter: AudioEffectLowPassFilter
var _rain_audio_bus_name := &"RuntimeRainAmbience"
var _rain_audio_muffle := 0.0
var _restaurant_inside_bounds := AABB()
var _has_restaurant_inside_bounds := false

const LAMPPOST_POOL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 light_color : source_color = vec4(1.0, 0.68, 0.26, 0.12);

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float distance_from_center = length(centered_uv) * 2.0;
	float falloff = smoothstep(1.0, 0.05, distance_from_center);
	ALBEDO = light_color.rgb;
	EMISSION = light_color.rgb * falloff;
	ALPHA = light_color.a * falloff;
}
"""

func _ready() -> void:
	if not vfx_enabled:
		return
	set_process(rain_audio_enabled)
	if atmosphere_enabled:
		_setup_environment()
	if sun_enabled:
		_setup_sun()
	if imported_fixture_lights_enabled:
		_setup_imported_fixture_lights()
	if lamppost_marker_lights_enabled:
		_setup_lamppost_marker_lights()
	if ambient_particles_enabled:
		_setup_dust()
	if rain_enabled:
		_setup_rain()
	if rain_audio_enabled:
		_setup_rain_audio()

func _process(delta: float) -> void:
	if rain_audio_enabled:
		_update_rain_audio(delta)

func _setup_environment() -> void:
	_environment_node = find_child("RestaurantWorldEnvironment", false, false) as WorldEnvironment
	if _environment_node == null:
		_environment_node = WorldEnvironment.new()
		_environment_node.name = "RestaurantWorldEnvironment"
		add_child(_environment_node)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.027, 0.052, 1.0) if rainy_night_enabled else Color(0.68, 0.78, 0.92, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.14, 0.18, 0.28, 1.0) if rainy_night_enabled else Color(0.8, 0.72, 0.62, 1.0)
	environment.ambient_light_energy = 0.18 if rainy_night_enabled else 0.55
	environment.glow_enabled = true
	environment.glow_intensity = 0.42 if rainy_night_enabled else 0.22
	environment.glow_strength = 0.7 if rainy_night_enabled else 0.42
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.11, 0.14, 0.22, 1.0) if rainy_night_enabled else Color(0.86, 0.75, 0.58, 1.0)
	environment.fog_density = 0.014 if rainy_night_enabled else 0.004
	_environment_node.environment = environment

func _setup_sun() -> void:
	_sun = find_child("RestaurantSun", false, false) as DirectionalLight3D
	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.name = "RestaurantSun"
		add_child(_sun)

	_sun.rotation_degrees = Vector3(-28.0, 145.0, 0.0) if rainy_night_enabled else Vector3(-52.0, -38.0, 0.0)
	_sun.light_color = Color(0.42, 0.55, 0.9, 1.0) if rainy_night_enabled else Color(1.0, 0.82, 0.56, 1.0)
	_sun.light_energy = 0.24 if rainy_night_enabled else 1.35
	_sun.shadow_enabled = not rainy_night_enabled
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS

func _setup_dust() -> void:
	if rainy_night_enabled:
		return

	_dust = find_child("RestaurantDustMotes", false, false) as GPUParticles3D
	if _dust == null:
		_dust = RestaurantVFXFactory.create_continuous_particles(
			self,
			"RestaurantDustMotes",
			Vector3(0.0, 2.2, 4.5),
			Color(1.0, 0.78, 0.45, 0.22),
			int(90.0 * quality_scale),
			4.0,
			Vector3(5.0, 1.6, 4.0),
			0.025,
			0.09,
			0.2,
			0.55,
			Vector3(0.0, 0.015, 0.0),
			true,
			0.012
		)
	if _dust != null:
		_dust.emitting = true

func _setup_rain() -> void:
	if rain_intensity <= 0.0:
		return

	_disable_legacy_rain_emitters()

	var roof_bounds := _get_roof_rain_bounds()
	var outdoor_zones := _get_outdoor_rain_zones(roof_bounds)
	var total_outdoor_area := _get_total_zone_area(outdoor_zones)
	for zone_index in range(outdoor_zones.size()):
		var zone := outdoor_zones[zone_index]
		var share := _get_zone_area(zone) / total_outdoor_area
		_add_rain_emitter(
			"RestaurantOutdoorRain_%d" % zone_index,
			Vector3(zone.get_center().x, rain_center.y + rain_spawn_height, zone.get_center().z),
			zone.size * 0.5,
			maxi(int(1350.0 * quality_scale * rain_intensity * share), 1),
			1.75,
			1.75,
			_make_rain_process_material(zone.size * 0.5, 13.0, 18.0, Vector3(-1.1, -32.0, -0.48))
		)
		_add_rain_mist_emitter(
			"RestaurantOutdoorRainMist_%d" % zone_index,
			Vector3(zone.get_center().x, 0.45, zone.get_center().z),
			Vector3(zone.size.x * 0.5, 0.12, zone.size.z * 0.5),
			maxi(int(320.0 * quality_scale * rain_intensity * share), 1)
		)

	for roof_zone_index in roof_bounds.size():
		var bounds := roof_bounds[roof_zone_index]
		var center := bounds.get_center()
		var extents := Vector3((bounds.size.x + rain_roof_padding.x) * 0.5, 0.1, (bounds.size.z + rain_roof_padding.z) * 0.5)
		var roof_area_share := (extents.x * 2.0 * extents.z * 2.0) / total_outdoor_area
		_add_rain_emitter(
			"RestaurantRoofRain_%d" % roof_zone_index,
			Vector3(center.x, bounds.position.y + bounds.size.y + rain_roof_clearance + rain_roof_spawn_height, center.z),
			extents,
			maxi(int(1350.0 * quality_scale * rain_intensity * roof_area_share * rain_roof_density_scale), 1),
			0.62,
			0.62,
			_make_rain_process_material(extents, 7.5, 10.5, Vector3(-0.55, -22.0, -0.22))
		)

func _setup_rain_audio() -> void:
	_rain_audio_player = get_node_or_null(rain_sound_path) as AudioStreamPlayer3D
	if _rain_audio_player == null:
		_rain_audio_player = _find_rain_audio_player()
	if _rain_audio_player == null:
		return

	_setup_rain_audio_bus()
	_cache_restaurant_inside_bounds()
	_rain_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_rain_audio_player.max_distance = 100000.0
	_rain_audio_player.bus = _rain_audio_bus_name
	_rain_audio_player.volume_db = rain_outside_volume_db
	if not _rain_audio_player.playing:
		_rain_audio_player.play()

func _find_rain_audio_player() -> AudioStreamPlayer3D:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return null

	var found := scene_root.find_child("rain-sound", true, false) as AudioStreamPlayer3D
	if found != null:
		return found
	return scene_root.find_child("*rain*", true, false) as AudioStreamPlayer3D

func _setup_rain_audio_bus() -> void:
	var bus_index := AudioServer.get_bus_index(_rain_audio_bus_name)
	if bus_index == -1:
		AudioServer.add_bus()
		bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_index, _rain_audio_bus_name)
		AudioServer.set_bus_send(bus_index, &"Master")

	_rain_audio_filter = null
	for effect_index in range(AudioServer.get_bus_effect_count(bus_index)):
		var effect := AudioServer.get_bus_effect(bus_index, effect_index)
		if effect is AudioEffectLowPassFilter:
			_rain_audio_filter = effect as AudioEffectLowPassFilter
			break

	if _rain_audio_filter == null:
		_rain_audio_filter = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(bus_index, _rain_audio_filter)
	_rain_audio_filter.cutoff_hz = rain_outside_cutoff_hz
	_rain_audio_filter.resonance = 0.55

func _update_rain_audio(delta: float) -> void:
	if _rain_audio_player == null or not is_instance_valid(_rain_audio_player):
		_setup_rain_audio()
		return

	if not _rain_audio_player.playing:
		_rain_audio_player.play()

	var target_muffle := 1.0 if _is_listener_inside_restaurant() else 0.0
	var blend := 1.0 - exp(-rain_audio_muffle_speed * delta)
	_rain_audio_muffle = lerpf(_rain_audio_muffle, target_muffle, blend)
	_rain_audio_player.volume_db = lerpf(rain_outside_volume_db, rain_inside_volume_db, _rain_audio_muffle)
	if _rain_audio_filter != null:
		_rain_audio_filter.cutoff_hz = lerpf(rain_outside_cutoff_hz, rain_inside_cutoff_hz, _rain_audio_muffle)

func _is_listener_inside_restaurant() -> bool:
	if not _has_restaurant_inside_bounds:
		_cache_restaurant_inside_bounds()
	if not _has_restaurant_inside_bounds:
		return false

	var listener_position := _get_listener_position()
	var min_pos := _restaurant_inside_bounds.position
	var max_pos := _restaurant_inside_bounds.position + _restaurant_inside_bounds.size
	return (
		listener_position.x >= min_pos.x
		and listener_position.x <= max_pos.x
		and listener_position.z >= min_pos.z
		and listener_position.z <= max_pos.z
		and listener_position.y <= max_pos.y + 2.4
	)

func _get_listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return global_position

	var player := scene_root.find_child("CharacterBody3D", true, false) as Node3D
	if player != null:
		return player.global_position
	return global_position

func _cache_restaurant_inside_bounds() -> void:
	var right_boundary := get_node_or_null(rain_audio_right_boundary_path) as Node3D
	var back_boundary := get_node_or_null(rain_audio_back_boundary_path) as Node3D
	var left_boundary := get_node_or_null(rain_audio_left_boundary_path) as Node3D
	var front_boundary := get_node_or_null(rain_audio_front_boundary_path) as Node3D
	if right_boundary == null or back_boundary == null or left_boundary == null or front_boundary == null:
		_has_restaurant_inside_bounds = false
		return

	var min_x := minf(left_boundary.global_position.x, right_boundary.global_position.x) - rain_audio_boundary_padding
	var max_x := maxf(left_boundary.global_position.x, right_boundary.global_position.x) + rain_audio_boundary_padding
	var min_z := minf(front_boundary.global_position.z, back_boundary.global_position.z) - rain_audio_boundary_padding
	var max_z := maxf(front_boundary.global_position.z, back_boundary.global_position.z) + rain_audio_boundary_padding
	_restaurant_inside_bounds = AABB(
		Vector3(min_x, -20.0, min_z),
		Vector3(max_x - min_x, 60.0, max_z - min_z)
	)
	_has_restaurant_inside_bounds = true

func _disable_legacy_rain_emitters() -> void:
	for node_name in [&"RestaurantRain", &"RestaurantRainMist"]:
		var old_emitter := find_child(String(node_name), false, false) as GPUParticles3D
		if old_emitter != null:
			old_emitter.emitting = false
			old_emitter.visible = false

func _get_roof_rain_bounds() -> Array[AABB]:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return []

	var map_root := scene_root.get_node_or_null(^"BurgerPiz2")
	if map_root == null:
		return []

	var roof_bounds: Array[AABB] = []
	for roof_name in [&"Ceiling", &"Ceiling_A", &"RooftilesMetal"]:
		var roof := map_root.get_node_or_null(NodePath(roof_name)) as MeshInstance3D
		if roof == null:
			continue
		roof_bounds.append(_get_global_aabb(roof))
	return roof_bounds

func _get_outdoor_rain_zones(roof_bounds: Array[AABB]) -> Array[AABB]:
	var world_min := rain_center - rain_extents
	var world_max := rain_center + rain_extents
	if roof_bounds.is_empty():
		return [AABB(world_min, rain_extents * 2.0)]

	var exclusion := roof_bounds[0]
	for index in range(1, roof_bounds.size()):
		exclusion = exclusion.merge(roof_bounds[index])

	var exclude_min := Vector3(exclusion.position.x - rain_roof_padding.x, rain_center.y - rain_extents.y, exclusion.position.z - rain_roof_padding.z)
	var exclude_max := Vector3(exclusion.position.x + exclusion.size.x + rain_roof_padding.x, rain_center.y + rain_extents.y, exclusion.position.z + exclusion.size.z + rain_roof_padding.z)
	var zones: Array[AABB] = []
	_append_rain_zone(zones, Vector3(world_min.x, world_min.y, world_min.z), Vector3(exclude_min.x - world_min.x, rain_extents.y * 2.0, world_max.z - world_min.z))
	_append_rain_zone(zones, Vector3(exclude_max.x, world_min.y, world_min.z), Vector3(world_max.x - exclude_max.x, rain_extents.y * 2.0, world_max.z - world_min.z))
	_append_rain_zone(zones, Vector3(exclude_min.x, world_min.y, world_min.z), Vector3(exclude_max.x - exclude_min.x, rain_extents.y * 2.0, exclude_min.z - world_min.z))
	_append_rain_zone(zones, Vector3(exclude_min.x, world_min.y, exclude_max.z), Vector3(exclude_max.x - exclude_min.x, rain_extents.y * 2.0, world_max.z - exclude_max.z))
	return zones

func _append_rain_zone(zones: Array[AABB], position: Vector3, size: Vector3) -> void:
	if size.x <= 0.1 or size.z <= 0.1:
		return
	zones.append(AABB(position, size))

func _get_total_zone_area(zones: Array[AABB]) -> float:
	var total := 0.0
	for zone in zones:
		total += _get_zone_area(zone)
	return maxf(total, 1.0)

func _get_zone_area(zone: AABB) -> float:
	return maxf(zone.size.x * zone.size.z, 1.0)

func _add_rain_emitter(node_name: String, position: Vector3, extents: Vector3, amount: int, lifetime: float, preprocess: float, process_material: ParticleProcessMaterial) -> void:
	var emitter := find_child(node_name, false, false) as GPUParticles3D
	if emitter == null:
		emitter = GPUParticles3D.new()
		emitter.name = node_name
		emitter.local_coords = false
		emitter.fixed_fps = 30
		emitter.draw_pass_1 = _make_rain_streak_mesh()
		add_child(emitter)
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.preprocess = preprocess
	emitter.process_material = process_material
	emitter.visibility_aabb = AABB(-extents, extents * 2.0 + Vector3(0.0, 22.0, 0.0))
	emitter.global_position = position
	emitter.visible = true
	emitter.emitting = true
	_rain_emitters.append(emitter)

func _add_rain_mist_emitter(node_name: String, position: Vector3, extents: Vector3, amount: int) -> void:
	var emitter := find_child(node_name, false, false) as GPUParticles3D
	if emitter == null:
		emitter = GPUParticles3D.new()
		emitter.name = node_name
		emitter.local_coords = false
		emitter.lifetime = 1.15
		emitter.preprocess = 1.15
		emitter.fixed_fps = 20
		emitter.draw_pass_1 = _make_rain_mist_mesh()
		add_child(emitter)
	emitter.amount = amount
	emitter.process_material = _make_rain_mist_process_material(extents)
	emitter.visibility_aabb = AABB(-extents, extents * 2.0 + Vector3(0.0, 3.0, 0.0))
	emitter.global_position = position
	emitter.visible = true
	emitter.emitting = true
	_rain_mist_emitters.append(emitter)

func _get_global_aabb(mesh_instance: MeshInstance3D) -> AABB:
	var local_bounds := mesh_instance.get_aabb()
	var global_bounds := AABB(mesh_instance.global_transform * local_bounds.position, Vector3.ZERO)
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				var local_point := local_bounds.position + Vector3(local_bounds.size.x * x, local_bounds.size.y * y, local_bounds.size.z * z)
				global_bounds = global_bounds.expand(mesh_instance.global_transform * local_point)
	return global_bounds

func _setup_imported_fixture_lights() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var map_root := scene_root.get_node_or_null(^"BurgerPiz2")
	if map_root == null:
		return

	_fixture_light_root = find_child("RuntimeFixtureLights", false, false) as Node3D
	if _fixture_light_root == null:
		_fixture_light_root = Node3D.new()
		_fixture_light_root.name = "RuntimeFixtureLights"
		add_child(_fixture_light_root)

	for child in map_root.get_children():
		if not (child is MeshInstance3D):
			continue
		var fixture := child as MeshInstance3D
		if not _is_imported_light_fixture(fixture.name):
			continue
		_add_runtime_fixture_light(fixture)

func _setup_lamppost_marker_lights() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var lampposts := scene_root.get_node_or_null(^"BurgerPiz2/Lampposts")
	if lampposts == null:
		return

	_fixture_light_root = find_child("RuntimeFixtureLights", false, false) as Node3D
	if _fixture_light_root == null:
		_fixture_light_root = Node3D.new()
		_fixture_light_root.name = "RuntimeFixtureLights"
		add_child(_fixture_light_root)

	for child in lampposts.get_children():
		if child is Node3D:
			_add_runtime_lamppost_light(child as Node3D)

func _is_imported_light_fixture(node_name: StringName) -> bool:
	var text := String(node_name)
	return text == "Light" or text.begins_with("Light_")

func _add_runtime_fixture_light(fixture: MeshInstance3D) -> void:
	if _fixture_light_root == null or _fixture_light_root.get_node_or_null(NodePath("RuntimeFixtureLight_%s" % fixture.name)) != null:
		return

	var light := OmniLight3D.new()
	light.name = "RuntimeFixtureLight_%s" % fixture.name
	light.light_color = Color(1.0, 0.78, 0.46, 1.0)
	light.light_energy = fixture_light_energy * 1.75 if rainy_night_enabled else fixture_light_energy
	light.omni_range = fixture_light_range + 1.8 if rainy_night_enabled else fixture_light_range
	light.shadow_enabled = false
	_fixture_light_root.add_child(light)
	light.global_position = fixture.global_position + Vector3.DOWN * 0.18

	var spot := SpotLight3D.new()
	spot.name = "RuntimeFixtureSpot_%s" % fixture.name
	spot.light_color = Color(1.0, 0.76, 0.42, 1.0)
	spot.light_energy = fixture_spot_energy * 1.8 if rainy_night_enabled else fixture_spot_energy
	spot.spot_range = fixture_light_range + 2.6 if rainy_night_enabled else fixture_light_range + 1.5
	spot.spot_angle = fixture_spot_angle
	spot.shadow_enabled = false
	_fixture_light_root.add_child(spot)
	spot.global_position = fixture.global_position + Vector3.DOWN * 0.1
	spot.look_at(spot.global_position + Vector3.DOWN, Vector3.FORWARD)

	fixture.material_overlay = _get_fixture_glow_material()

	var glow := GPUParticles3D.new()
	glow.name = "RuntimeFixtureGlow"
	glow.amount = maxi(int(12.0 * quality_scale), 1)
	glow.lifetime = 1.4
	glow.one_shot = false
	glow.emitting = true
	glow.draw_pass_1 = _make_fixture_glow_mesh()
	glow.process_material = _make_fixture_glow_process()
	fixture.add_child(glow)

func _add_runtime_lamppost_light(marker: Node3D) -> void:
	if _fixture_light_root == null or _fixture_light_root.get_node_or_null(NodePath("RuntimeLamppostLight_%s" % marker.name)) != null:
		return

	var origin := marker.global_position

	var light := OmniLight3D.new()
	light.name = "RuntimeLamppostLight_%s" % marker.name
	light.light_color = Color(1.0, 0.76, 0.42, 1.0)
	light.light_energy = lamppost_light_energy * 1.5 if rainy_night_enabled else lamppost_light_energy
	light.omni_range = lamppost_light_range + 2.0 if rainy_night_enabled else lamppost_light_range
	light.shadow_enabled = false
	_fixture_light_root.add_child(light)
	light.global_position = origin

	var spot := SpotLight3D.new()
	spot.name = "RuntimeLamppostSpot_%s" % marker.name
	spot.light_color = Color(1.0, 0.72, 0.36, 1.0)
	spot.light_energy = lamppost_light_energy * 2.0 if rainy_night_enabled else lamppost_light_energy * 1.2
	spot.spot_range = lamppost_light_range + 3.0 if rainy_night_enabled else lamppost_light_range + 1.5
	spot.spot_angle = maxf(lamppost_spot_angle, 54.0)
	spot.shadow_enabled = false
	_fixture_light_root.add_child(spot)
	spot.global_position = origin
	spot.look_at(origin + Vector3.DOWN, Vector3.FORWARD)

	var pool := MeshInstance3D.new()
	pool.name = "RuntimeLamppostPool_%s" % marker.name
	pool.mesh = _make_lamppost_pool_mesh()
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fixture_light_root.add_child(pool)
	pool.global_position = origin + Vector3.DOWN * (lamppost_light_range * 0.72)

	var glow := MeshInstance3D.new()
	glow.name = "RuntimeLamppostGlow_%s" % marker.name
	glow.mesh = _make_lamppost_glow_mesh()
	_fixture_light_root.add_child(glow)
	glow.global_position = origin

	var motes := GPUParticles3D.new()
	motes.name = "RuntimeLamppostMotes_%s" % marker.name
	motes.amount = maxi(int(10.0 * quality_scale), 1)
	motes.lifetime = 1.8
	motes.one_shot = false
	motes.emitting = true
	motes.draw_pass_1 = _make_fixture_glow_mesh()
	motes.process_material = _make_lamppost_mote_process()
	_fixture_light_root.add_child(motes)
	motes.global_position = origin

func _get_fixture_glow_material() -> StandardMaterial3D:
	if _fixture_glow_material != null:
		return _fixture_glow_material

	_fixture_glow_material = StandardMaterial3D.new()
	_fixture_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fixture_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fixture_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fixture_glow_material.albedo_color = Color(1.0, 0.78, 0.38, 0.42)
	_fixture_glow_material.emission_enabled = true
	_fixture_glow_material.emission = Color(1.0, 0.72, 0.32, 1.0)
	_fixture_glow_material.emission_energy_multiplier = 1.8
	return _fixture_glow_material

func _make_fixture_glow_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(1.0, 0.72, 0.28, 0.42)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.72, 0.28, 1.0)
	material.emission_energy_multiplier = 1.2
	mesh.material = material
	return mesh

func _make_lamppost_glow_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(1.0, 0.66, 0.24, 0.55)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.62, 0.22, 1.0)
	material.emission_energy_multiplier = 2.4
	mesh.material = material
	return mesh

func _make_lamppost_pool_mesh() -> Mesh:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(lamppost_pool_radius * 2.0, lamppost_pool_radius * 2.0)
	mesh.subdivide_width = 1
	mesh.subdivide_depth = 1
	mesh.material = _get_lamppost_pool_material()
	return mesh

func _get_lamppost_pool_material() -> ShaderMaterial:
	if _lamppost_pool_material != null:
		return _lamppost_pool_material

	var shader := Shader.new()
	shader.code = LAMPPOST_POOL_SHADER
	_lamppost_pool_material = ShaderMaterial.new()
	_lamppost_pool_material.shader = shader
	_lamppost_pool_material.set_shader_parameter("light_color", Color(1.0, 0.68, 0.26, lamppost_pool_alpha))
	return _lamppost_pool_material

func _make_rain_streak_mesh() -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.011
	mesh.bottom_radius = 0.011
	mesh.height = 0.95
	mesh.radial_segments = 5
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.material = _get_rain_material()
	return mesh

func _get_rain_material() -> StandardMaterial3D:
	if _rain_material != null:
		return _rain_material

	_rain_material = StandardMaterial3D.new()
	_rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_rain_material.albedo_color = Color(0.64, 0.76, 0.98, 0.42)
	_rain_material.emission_enabled = true
	_rain_material.emission = Color(0.45, 0.58, 0.88, 1.0)
	_rain_material.emission_energy_multiplier = 0.72
	return _rain_material

func _make_rain_process_material(emission_extents: Vector3, velocity_min: float, velocity_max: float, rain_gravity: Vector3) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = emission_extents
	material.direction = Vector3(-0.16, -1.0, -0.08)
	material.spread = 4.0
	material.gravity = rain_gravity
	material.initial_velocity_min = velocity_min
	material.initial_velocity_max = velocity_max
	material.scale_min = 0.85
	material.scale_max = 1.55
	return material

func _make_rain_mist_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.04
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _get_rain_mist_material()
	return mesh

func _get_rain_mist_material() -> StandardMaterial3D:
	if _rain_mist_material != null:
		return _rain_mist_material

	_rain_mist_material = StandardMaterial3D.new()
	_rain_mist_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mist_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mist_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_rain_mist_material.albedo_color = Color(0.5, 0.64, 0.86, 0.18)
	_rain_mist_material.emission_enabled = true
	_rain_mist_material.emission = Color(0.36, 0.48, 0.7, 1.0)
	_rain_mist_material.emission_energy_multiplier = 0.48
	return _rain_mist_material

func _make_rain_mist_process_material(emission_extents: Vector3) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = emission_extents
	material.direction = Vector3(0.0, 1.0, 0.0)
	material.spread = 80.0
	material.gravity = Vector3(0.0, -0.45, 0.0)
	material.initial_velocity_min = 0.08
	material.initial_velocity_max = 0.55
	material.scale_min = 0.5
	material.scale_max = 1.8
	return material

func _make_fixture_glow_process() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.12
	material.direction = Vector3.DOWN
	material.spread = 80.0
	material.gravity = Vector3(0.0, -0.012, 0.0)
	material.initial_velocity_min = 0.015
	material.initial_velocity_max = 0.07
	material.scale_min = 0.6
	material.scale_max = 1.35
	return material

func _make_lamppost_mote_process() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.45
	material.direction = Vector3.DOWN
	material.spread = 70.0
	material.gravity = Vector3(0.0, -0.02, 0.0)
	material.initial_velocity_min = 0.02
	material.initial_velocity_max = 0.09
	material.scale_min = 0.8
	material.scale_max = 1.8
	return material
