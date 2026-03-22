extends CharacterBody3D

@export var move_speed := 4.5
@export var acceleration := 18.0
@export var deceleration := 22.0
@export var turn_speed := 10.0
@export var jump_velocity := 4.5
@export var camera_pivot_offset := Vector3(0.0, 1.7, 0.0)
@export var camera_distance := 5.2
@export var camera_shoulder_offset := 0.8
@export var mouse_sensitivity := 0.0035
@export_range(-80.0, 80.0, 0.1) var min_pitch_degrees := -35.0
@export_range(-80.0, 80.0, 0.1) var max_pitch_degrees := 55.0
@export var camera_position_smoothing := 8.0
@export var camera_look_smoothing := 10.0

@onready var rogue_visual: Node3D = $Rogue
@onready var animation_player: AnimationPlayer = $Rogue/AnimationPlayer
@onready var camera: Camera3D = $Camera3D

const ANIMATION_LIBRARY := &"Player"

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var camera_look_target: Vector3 = Vector3.ZERO
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(12.0)

func _ready() -> void:
	camera.top_level = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera_look_target = global_position + camera_pivot_offset
	_snap_camera_to_target()
	_play_animation("Idle_A", 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * mouse_sensitivity
		camera_pitch -= event.relative.y * mouse_sensitivity
		camera_pitch = clamp(camera_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var was_grounded: bool = is_on_floor()
	var camera_basis := Basis(Vector3.UP, camera_yaw)
	var camera_forward: Vector3 = (camera_basis * Vector3.FORWARD)
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var camera_right: Vector3 = (camera_basis * Vector3.RIGHT)
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var direction: Vector3 = (camera_right * input_dir.x) - (camera_forward * input_dir.y)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	if direction != Vector3.ZERO:
		var target_rotation: float = atan2(direction.x, direction.z)
		rogue_visual.rotation.y = rotate_toward(rogue_visual.rotation.y, target_rotation, turn_speed * delta)

	var target_velocity: Vector3 = direction * move_speed
	var blend_rate: float = deceleration
	if direction != Vector3.ZERO:
		blend_rate = acceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, blend_rate * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, blend_rate * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		_play_animation("Jump_Start")

	move_and_slide()
	_update_camera(delta)
	_update_animation(direction, was_grounded)

func _update_camera(delta: float) -> void:
	var pivot_position: Vector3 = global_position + camera_pivot_offset
	var yaw_basis := Basis(Vector3.UP, camera_yaw)
	var pitch_basis := Basis(Vector3.RIGHT, camera_pitch)
	var camera_rotation := yaw_basis * pitch_basis
	var shoulder_offset: Vector3 = yaw_basis * Vector3.RIGHT * camera_shoulder_offset
	var desired_offset: Vector3 = camera_rotation * Vector3(0.0, 0.0, camera_distance)
	var desired_position: Vector3 = pivot_position + shoulder_offset + desired_offset
	camera.global_position = camera.global_position.lerp(desired_position, camera_position_smoothing * delta)
	camera_look_target = camera_look_target.lerp(pivot_position + shoulder_offset * 0.35, camera_look_smoothing * delta)
	camera.look_at(camera_look_target, Vector3.UP)

func _update_animation(direction: Vector3, was_grounded: bool) -> void:
	if not is_on_floor():
		if velocity.y > 0.1:
			_play_animation("Jump_Idle")
		else:
			_play_animation("Jump_Full_Long")
		return

	if not was_grounded and is_on_floor():
		_play_animation("Jump_Land")
		return

	if direction != Vector3.ZERO:
		_play_animation("Running_A")
		animation_player.speed_scale = clamp(Vector2(velocity.x, velocity.z).length() / move_speed, 0.85, 1.3)
	else:
		_play_animation("Idle_A")
		animation_player.speed_scale = 1.0

func _play_animation(name: StringName, blend: float = 0.15) -> void:
	var resolved_name: StringName = _resolve_animation_name(name)
	if resolved_name.is_empty():
		push_warning("Animation not found: %s" % String(name))
		return

	if animation_player.current_animation == resolved_name and animation_player.is_playing():
		return
	animation_player.play(resolved_name, blend)

func _resolve_animation_name(name: StringName) -> StringName:
	if animation_player.has_animation(name):
		return name

	var library_name := StringName("%s/%s" % [String(ANIMATION_LIBRARY), String(name)])
	if animation_player.has_animation(library_name):
		return library_name

	return StringName()

func _snap_camera_to_target() -> void:
	var pivot_position: Vector3 = global_position + camera_pivot_offset
	var yaw_basis := Basis(Vector3.UP, camera_yaw)
	var pitch_basis := Basis(Vector3.RIGHT, camera_pitch)
	var camera_rotation := yaw_basis * pitch_basis
	var shoulder_offset: Vector3 = yaw_basis * Vector3.RIGHT * camera_shoulder_offset
	var initial_offset: Vector3 = camera_rotation * Vector3(0.0, 0.0, camera_distance)
	camera.global_position = pivot_position + shoulder_offset + initial_offset
	camera.look_at(camera_look_target, Vector3.UP)
