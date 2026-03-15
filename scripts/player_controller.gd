extends CharacterBody3D

@export var move_speed := 6.5
@export var jump_velocity := 4.8
@export var ground_acceleration := 30.0
@export var air_acceleration := 10.0
@export var mouse_sensitivity := 0.0025

var _pitch := 0.0

@onready var pivot: Node3D = $Pivot

func _ready() -> void:
	_ensure_input_actions()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		pivot.rotation.x = _pitch
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	if event.is_action_pressed("ui_cancel"):
		var next_mode := Input.MOUSE_MODE_VISIBLE
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			next_mode = Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(next_mode)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var local_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	var move_direction := (basis * local_direction).normalized()
	var target_velocity := move_direction * move_speed
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration

	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	move_and_slide()


func _ensure_input_actions() -> void:
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("jump", [KEY_SPACE])


func _bind_keys(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for keycode in keys:
		var exists := false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and event.physical_keycode == keycode:
				exists = true
				break

		if exists:
			continue

		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode
		InputMap.action_add_event(action, key_event)
