extends Node3D

@export var preview_spin_enabled := true
@export var preview_spin_speed := 7.5
@export var wheel_spin_multiplier := 2.4
@export var engine_min_pitch := 0.82
@export var engine_max_pitch := 1.18
@export var engine_min_volume_db := -10.0
@export var engine_max_volume_db := -1.5
@export var drive_loop_stream: AudioStream = preload("res://assets/vehicles/Sound effects/Car_Acceleration_2.ogg")
@export var drive_loop_min_volume_db := -24.0
@export var drive_loop_max_volume_db := -11.0
@export var audible_distance := 170.0
@export var audible_unit_size := 1.0

var drive_speed := 0.0

@onready var _wheels: Array[Node3D] = [
	get_node_or_null(^"WheelFrontLeft") as Node3D,
	get_node_or_null(^"WheelFrontRight") as Node3D,
	get_node_or_null(^"WheelRearLeft") as Node3D,
	get_node_or_null(^"WheelRearRight") as Node3D,
]
@onready var _engine_loop := get_node_or_null(^"EngineLoop") as AudioStreamPlayer3D
var _drive_loop: AudioStreamPlayer3D

func _ready() -> void:
	_wheels = _wheels.filter(func(wheel: Node3D) -> bool: return wheel != null)
	_configure_engine_loop()
	_create_drive_loop()

func _process(delta: float) -> void:
	var effective_speed := drive_speed
	if is_zero_approx(effective_speed) and preview_spin_enabled:
		effective_speed = preview_spin_speed

	var spin_amount := effective_speed * wheel_spin_multiplier * delta
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.RIGHT, spin_amount)

	if _engine_loop != null:
		var speed_factor: float = clampf(abs(effective_speed) / 16.0, 0.0, 1.0)
		_engine_loop.pitch_scale = lerpf(engine_min_pitch, engine_max_pitch, speed_factor)
		_engine_loop.volume_db = lerpf(engine_min_volume_db, engine_max_volume_db, speed_factor)

	if _drive_loop != null:
		var drive_speed_factor: float = clampf(abs(effective_speed) / 16.0, 0.0, 1.0)
		_drive_loop.pitch_scale = lerpf(0.78, 1.08, drive_speed_factor)
		_drive_loop.volume_db = lerpf(drive_loop_min_volume_db, drive_loop_max_volume_db, drive_speed_factor)

func set_drive_speed(speed: float) -> void:
	drive_speed = speed

func apply_audio_settings(
	audio_range: float,
	audio_unit_size: float,
	engine_min_db: float,
	engine_max_db: float,
	drive_min_db: float,
	drive_max_db: float
) -> void:
	audible_distance = audio_range
	audible_unit_size = audio_unit_size
	engine_min_volume_db = engine_min_db
	engine_max_volume_db = engine_max_db
	drive_loop_min_volume_db = drive_min_db
	drive_loop_max_volume_db = drive_max_db
	if _engine_loop != null:
		_configure_traffic_audio_player(_engine_loop)
	if _drive_loop != null:
		_configure_traffic_audio_player(_drive_loop)

func _configure_engine_loop() -> void:
	if _engine_loop == null:
		return

	_configure_traffic_audio_player(_engine_loop)
	_force_stream_loop(_engine_loop.stream)
	if not _engine_loop.playing:
		_engine_loop.play()

func _create_drive_loop() -> void:
	if drive_loop_stream == null:
		return

	_drive_loop = AudioStreamPlayer3D.new()
	_drive_loop.name = "DriveLoop"
	_drive_loop.stream = drive_loop_stream
	_drive_loop.autoplay = true
	_drive_loop.volume_db = drive_loop_min_volume_db
	add_child(_drive_loop)
	_configure_traffic_audio_player(_drive_loop)
	_force_stream_loop(_drive_loop.stream)
	_drive_loop.play()

func _configure_traffic_audio_player(player: AudioStreamPlayer3D) -> void:
	player.max_distance = audible_distance
	player.unit_size = audible_unit_size

func _force_stream_loop(stream: AudioStream) -> void:
	if stream == null:
		return
	stream.set("loop", true)
