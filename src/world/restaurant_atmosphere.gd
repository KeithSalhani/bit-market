extends Node3D

@export var vfx_enabled := true
@export var atmosphere_enabled := true
@export var sun_enabled := true
@export var ambient_particles_enabled := true
@export var imported_fixture_lights_enabled := true
@export var lamppost_marker_lights_enabled := true
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

var _environment_node: WorldEnvironment
var _sun: DirectionalLight3D
var _dust: GPUParticles3D
var _fixture_light_root: Node3D
var _fixture_glow_material: StandardMaterial3D
var _lamppost_pool_material: ShaderMaterial

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

func _setup_environment() -> void:
	_environment_node = find_child("RestaurantWorldEnvironment", false, false) as WorldEnvironment
	if _environment_node == null:
		_environment_node = WorldEnvironment.new()
		_environment_node.name = "RestaurantWorldEnvironment"
		add_child(_environment_node)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.68, 0.78, 0.92, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.72, 0.62, 1.0)
	environment.ambient_light_energy = 0.55
	environment.glow_enabled = true
	environment.glow_intensity = 0.22
	environment.glow_strength = 0.42
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.86, 0.75, 0.58, 1.0)
	environment.fog_density = 0.004
	_environment_node.environment = environment

func _setup_sun() -> void:
	_sun = find_child("RestaurantSun", false, false) as DirectionalLight3D
	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.name = "RestaurantSun"
		add_child(_sun)

	_sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	_sun.light_color = Color(1.0, 0.82, 0.56, 1.0)
	_sun.light_energy = 1.35
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS

func _setup_dust() -> void:
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
	light.light_energy = fixture_light_energy
	light.omni_range = fixture_light_range
	light.shadow_enabled = false
	_fixture_light_root.add_child(light)
	light.global_position = fixture.global_position + Vector3.DOWN * 0.18

	var spot := SpotLight3D.new()
	spot.name = "RuntimeFixtureSpot_%s" % fixture.name
	spot.light_color = Color(1.0, 0.76, 0.42, 1.0)
	spot.light_energy = fixture_spot_energy
	spot.spot_range = fixture_light_range + 1.5
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
	light.light_energy = lamppost_light_energy
	light.omni_range = lamppost_light_range
	light.shadow_enabled = false
	_fixture_light_root.add_child(light)
	light.global_position = origin

	var spot := SpotLight3D.new()
	spot.name = "RuntimeLamppostSpot_%s" % marker.name
	spot.light_color = Color(1.0, 0.72, 0.36, 1.0)
	spot.light_energy = lamppost_light_energy * 1.2
	spot.spot_range = lamppost_light_range + 1.5
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
