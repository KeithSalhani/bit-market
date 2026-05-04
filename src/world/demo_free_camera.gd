extends Camera3D

@export var enabled := true
@export var move_speed := 12.0
@export var fast_multiplier := 3.0
@export var min_move_speed := 1.0
@export var max_move_speed := 80.0
@export var scroll_speed_multiplier := 1.15
@export var mouse_sensitivity := 0.003
@export var capture_mouse_while_rotating := true
@export var movement_smoothing := 7.5
@export var rotation_smoothing := 14.0
@export var fov_smoothing := 4.0
@export var speed_fov_boost := 5.0

var _rotating := false
var _yaw := 0.0
var _pitch := 0.0
var _target_yaw := 0.0
var _target_pitch := 0.0
var _velocity := Vector3.ZERO
var _base_fov := 75.0

func _ready() -> void:
	var euler := global_rotation
	_pitch = euler.x
	_yaw = euler.y
	_target_pitch = _pitch
	_target_yaw = _yaw
	_base_fov = fov
	current = true

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			move_speed = minf(move_speed * scroll_speed_multiplier, max_move_speed)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			move_speed = maxf(move_speed / scroll_speed_multiplier, min_move_speed)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_rotating = event.pressed
		if capture_mouse_while_rotating:
			if _rotating:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseMotion and _rotating:
		_target_yaw -= event.relative.x * mouse_sensitivity
		_target_pitch -= event.relative.y * mouse_sensitivity
		_target_pitch = clamp(_target_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))

	if event.is_action_pressed("ui_cancel") and capture_mouse_while_rotating:
		_rotating = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if not enabled:
		return

	var input_dir := Vector3.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_dir.z = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")

	if Input.is_action_pressed("jump"):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C):
		input_dir.y -= 1.0

	if input_dir.length_squared() > 1.0:
		input_dir = input_dir.normalized()
	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier

	var target_velocity := (global_transform.basis * input_dir) * speed
	_velocity = _velocity.lerp(target_velocity, _smoothing_weight(movement_smoothing, delta))
	global_position += _velocity * delta

	_yaw = lerp_angle(_yaw, _target_yaw, _smoothing_weight(rotation_smoothing, delta))
	_pitch = lerp_angle(_pitch, _target_pitch, _smoothing_weight(rotation_smoothing, delta))
	global_rotation = Vector3(_pitch, _yaw, 0.0)

	var speed_factor := clampf(_velocity.length() / (move_speed * fast_multiplier), 0.0, 1.0)
	fov = lerpf(fov, _base_fov + speed_factor * speed_fov_boost, _smoothing_weight(fov_smoothing, delta))

func _smoothing_weight(rate: float, delta: float) -> float:
	return 1.0 - exp(-maxf(rate, 0.0) * delta)
