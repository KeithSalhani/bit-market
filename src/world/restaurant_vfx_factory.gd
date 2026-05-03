class_name RestaurantVFXFactory
extends RefCounted

const HEAT_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.12, 0.18);
uniform float wave_speed = 3.0;
uniform float wave_strength = 0.035;
uniform float alpha = 0.16;

void vertex() {
	float wave = sin((VERTEX.y * 12.0) + (TIME * wave_speed));
	VERTEX.x += wave * wave_strength;
}

void fragment() {
	float vertical_fade = smoothstep(0.0, 0.22, UV.y) * (1.0 - smoothstep(0.76, 1.0, UV.y));
	float stripe = 0.72 + (sin((UV.y * 26.0) + (TIME * 5.0)) * 0.28);
	ALBEDO = tint.rgb;
	ALPHA = alpha * vertical_fade * stripe;
}
"""

static func create_continuous_particles(
	parent: Node3D,
	name: String,
	local_position: Vector3,
	color: Color,
	amount: int,
	lifetime: float,
	emission_extents: Vector3,
	velocity_min: float,
	velocity_max: float,
	scale_min: float,
	scale_max: float,
	gravity: Vector3 = Vector3(0.0, 0.24, 0.0),
	emissive: bool = false,
	mesh_radius: float = 0.025
) -> GPUParticles3D:
	if parent == null:
		return null

	var particles := GPUParticles3D.new()
	particles.name = name
	particles.amount = maxi(amount, 1)
	particles.lifetime = maxf(lifetime, 0.05)
	particles.one_shot = false
	particles.emitting = false
	particles.position = local_position
	particles.draw_pass_1 = _make_particle_mesh(color, mesh_radius, emissive)
	particles.process_material = _make_particle_process_material(emission_extents, velocity_min, velocity_max, scale_min, scale_max, gravity)
	parent.add_child(particles)
	return particles

static func spawn_burst(
	parent: Node3D,
	global_position: Vector3,
	color: Color,
	amount: int = 24,
	lifetime: float = 0.45,
	emission_radius: float = 0.08,
	velocity_min: float = 0.45,
	velocity_max: float = 1.1,
	scale_min: float = 0.25,
	scale_max: float = 0.8,
	emissive: bool = true,
	mesh_radius: float = 0.025
) -> GPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null

	var particles := GPUParticles3D.new()
	particles.name = "VFXBurst"
	particles.amount = maxi(amount, 1)
	particles.lifetime = maxf(lifetime, 0.05)
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.draw_pass_1 = _make_particle_mesh(color, mesh_radius, emissive)
	particles.process_material = _make_particle_process_material(
		Vector3.ONE * emission_radius,
		velocity_min,
		velocity_max,
		scale_min,
		scale_max,
		Vector3(0.0, -0.15, 0.0)
	)
	parent.add_child(particles)
	particles.global_position = global_position
	particles.emitting = true
	_queue_free_after(particles, lifetime + 0.35)
	return particles

static func create_heat_shimmer(parent: Node3D, name: String, local_position: Vector3, size: Vector2 = Vector2(0.8, 0.55)) -> MeshInstance3D:
	if parent == null:
		return null

	var quad := QuadMesh.new()
	quad.size = size

	var shader := Shader.new()
	shader.code = HEAT_SHADER_CODE

	var material := ShaderMaterial.new()
	material.shader = shader

	var mesh := MeshInstance3D.new()
	mesh.name = name
	mesh.mesh = quad
	mesh.material_override = material
	mesh.position = local_position
	mesh.rotation_degrees = Vector3(-62.0, 0.0, 0.0)
	mesh.visible = false
	parent.add_child(mesh)
	return mesh

static func create_flicker_light(parent: Node3D, name: String, local_position: Vector3, color: Color = Color(1.0, 0.48, 0.16, 1.0), energy: float = 0.0, radius: float = 2.0) -> OmniLight3D:
	if parent == null:
		return null

	var light := OmniLight3D.new()
	light.name = name
	light.position = local_position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	parent.add_child(light)
	return light

static func set_particles_emitting(particles_list: Array, value: bool) -> void:
	for item in particles_list:
		if item != null and is_instance_valid(item) and item is GPUParticles3D:
			(item as GPUParticles3D).emitting = value

static func set_node_visible(node: Node, value: bool) -> void:
	if node != null and is_instance_valid(node):
		node.visible = value

static func pulse_light(light: OmniLight3D, target_energy: float = 1.2, seconds: float = 0.35) -> void:
	if light == null or not is_instance_valid(light):
		return

	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", target_energy, seconds * 0.3)
	tween.tween_property(light, "light_energy", 0.0, seconds * 0.7)

static func _make_particle_mesh(color: Color, radius: float, emissive: bool) -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = maxf(radius, 0.004)
	mesh.height = maxf(radius * 2.0, 0.008)
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _make_particle_material(color, emissive)
	return mesh

static func _make_particle_material(color: Color, emissive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if emissive else BaseMaterial3D.BLEND_MODE_MIX
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emissive else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if emissive:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b, 1.0)
		material.emission_energy_multiplier = 0.65
	return material

static func _make_particle_process_material(
	emission_extents: Vector3,
	velocity_min: float,
	velocity_max: float,
	scale_min: float,
	scale_max: float,
	gravity: Vector3
) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = emission_extents
	material.direction = Vector3.UP
	material.spread = 32.0
	material.gravity = gravity
	material.initial_velocity_min = velocity_min
	material.initial_velocity_max = maxf(velocity_max, velocity_min)
	material.scale_min = scale_min
	material.scale_max = maxf(scale_max, scale_min)
	return material

static func _queue_free_after(node: Node, seconds: float) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	tree.create_timer(maxf(seconds, 0.05)).timeout.connect(Callable(node, "queue_free"))
