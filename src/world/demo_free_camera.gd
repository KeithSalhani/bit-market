extends Camera3D

@export var enabled := true
@export var move_speed := 12.0
@export var fast_multiplier := 3.0
@export var mouse_sensitivity := 0.003
@export var capture_mouse_while_rotating := true

var _rotating := false
var _yaw := 0.0
var _pitch := 0.0

func _ready() -> void:
	var euler := global_rotation
	_pitch = euler.x
	_yaw = euler.y
	current = true

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_rotating = event.pressed
		if capture_mouse_while_rotating:
			if _rotating:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseMotion and _rotating:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		global_rotation = Vector3(_pitch, _yaw, 0.0)

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

	if input_dir == Vector3.ZERO:
		return

	input_dir = input_dir.normalized()
	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier

	var movement := (global_transform.basis * input_dir) * speed * delta
	global_position += movement
