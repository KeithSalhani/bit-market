extends Node

@export var enabled := true
@export var npc_path: NodePath = ^"../RogueNPC"
@export var target_seat_path: NodePath = ^"../SeatingMap/Table_01/Table_01_Seat_01"
@export var sit_key := KEY_F
@export var stand_key := KEY_R
@export var sit_on_ready := false

@onready var npc: Node = get_node_or_null(npc_path)

func _ready() -> void:
	if sit_on_ready:
		call_deferred("send_npc_to_target_seat")

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == sit_key:
			send_npc_to_target_seat()
		elif event.keycode == stand_key:
			stand_npc_up()

func send_npc_to_target_seat() -> void:
	if npc == null:
		npc = get_node_or_null(npc_path)
	if npc == null:
		push_warning("NPC seating demo could not find NPC at path: %s" % String(npc_path))
		return

	if not npc.has_method("sit_at_seat"):
		push_warning("NPC does not implement sit_at_seat")
		return

	var seat := get_node_or_null(target_seat_path) as Node3D
	if seat == null:
		push_warning("NPC seating demo could not find seat at path: %s" % String(target_seat_path))
		return

	npc.sit_at_seat(seat)

func stand_npc_up() -> void:
	if npc == null:
		npc = get_node_or_null(npc_path)
	if npc != null and npc.has_method("stand_up"):
		npc.stand_up()
