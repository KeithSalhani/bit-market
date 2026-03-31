@tool
extends "res://src/movement/npc_movement.gd"

const CHARACTER_ROOT := "res://assets/characters/psx/"
const CHARACTER_EXTENSION := ".fbx"
const ANIMATION_TEMPLATE_SCENE := preload("res://scenes/characters/character_01.tscn")

@export_enum(
	"Character_01", "Character_02", "Character_03", "Character_04", "Character_05", "Character_06", "Character_07", "Character_08",
	"Character_09", "Character_10", "Character_11", "Character_12", "Character_13", "Character_14", "Character_15", "Character_16",
	"Character_17_Female_Police", "Character_17_Police", "Character_18_Female_Police", "Character_18_Police",
	"Character_19_Female_Police", "Character_19_Police", "Character_20_Female_Police", "Character_20_Police",
	"Character_21_Female_Firefighter", "Character_21_Police", "Character_22_Female_Firefighter", "Character_22_Police",
	"Character_23_Female_Doctor", "Character_23_Firefighter", "Character_24_Female_Doctor", "Character_24_Firefighter",
	"Character_25_Doctor", "Character_25_Female_Police", "Character_26_Doctor", "Character_26_Female_Police",
	"Character_27_Female_HM", "Character_27_HM", "Character_28_Female_HM", "Character_28_HM",
	"Character_29", "Character_29_Female", "Character_30", "Character_30_Female", "Character_31", "Character_31_Female",
	"Character_32", "Character_32_Female", "Character_33_Female",
	"Character_Female_02", "Character_Female_03", "Character_Female_04", "Character_Female_05", "Character_Female_06",
	"Character_Female_07", "Character_Female_08", "Character_Female_09", "Character_Female_10", "Character_Female_11",
	"Character_Female_12", "Character_Female_13", "Character_Female_14", "Character_Female_15", "Character_Female_16"
)
var character_id := "Character_02":
	set(value):
		if character_id == value:
			return
		character_id = value
		_apply_animation_names()
		if is_inside_tree():
			_load_character_visual()
			_refresh_visual_references()

@export_range(0.05, 2.0, 0.01) var character_visual_scale := 0.42:
	set(value):
		character_visual_scale = value
		if visual_root == null:
			return
		var character_visual := visual_root.get_node_or_null(^"CharacterVisual") as Node3D
		if character_visual != null:
			character_visual.scale = Vector3.ONE * character_visual_scale

@onready var visual_root: Node3D = $VisualRoot

func _ready() -> void:
	_apply_animation_names()
	_load_character_visual()
	super._ready()

func _refresh_visual_references() -> void:
	visual_node = get_node_or_null(^"VisualRoot") as Node3D
	animation_player = _find_animation_player(visual_node)
	_attach_animation_libraries()

func _load_character_visual() -> void:
	if visual_root == null:
		return

	for child in visual_root.get_children():
		child.free()

	var character_scene := _get_character_scene()
	if character_scene == null:
		push_warning("Character NPC could not load character: %s" % character_id)
		return

	var character_instance := character_scene.instantiate() as Node3D
	if character_instance == null:
		push_warning("Character NPC character is not a Node3D: %s" % character_id)
		return

	character_instance.name = "CharacterVisual"
	character_instance.scale = Vector3.ONE * character_visual_scale
	visual_root.add_child(character_instance)
	if Engine.is_editor_hint():
		character_instance.owner = get_tree().edited_scene_root

func _get_character_scene() -> PackedScene:
	if character_id == "Character_01":
		return ANIMATION_TEMPLATE_SCENE
	return load(CHARACTER_ROOT + character_id + CHARACTER_EXTENSION) as PackedScene

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer

	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found

	return null

func _attach_animation_libraries() -> void:
	if animation_player == null or character_id == "Character_01":
		return

	var template_instance := ANIMATION_TEMPLATE_SCENE.instantiate()
	var template_player := _find_animation_player(template_instance)
	if template_player == null:
		push_warning("Character NPC could not find AnimationPlayer in character_01 animation template.")
		template_instance.free()
		return

	_remove_character_animation_libraries()
	var prefix := _animation_library_prefix()
	for library_name in template_player.get_animation_library_list():
		var library_key := StringName(library_name)
		if not _should_copy_animation_library(String(library_key), prefix):
			continue

		var library := template_player.get_animation_library(library_key)
		if library == null:
			continue

		if animation_player.has_animation_library(library_key):
			animation_player.remove_animation_library(library_key)
		animation_player.add_animation_library(library_key, library)

	template_instance.free()

func _remove_character_animation_libraries() -> void:
	for library_name in animation_player.get_animation_library_list():
		var library_text := String(library_name)
		if library_text.begins_with("HumanF@") or library_text.begins_with("HumanM@"):
			animation_player.remove_animation_library(StringName(library_name))

func _apply_animation_names() -> void:
	if _uses_female_animations():
		idle_animation = &"HumanF@Idle01"
		move_animation = &"HumanF@Walk01_Forward"
		fall_animation = &"HumanF@Fall01"
	else:
		idle_animation = &"HumanM@Idle01"
		move_animation = &"HumanM@Walk01_Forward"
		fall_animation = &"HumanM@Fall01"

func _animation_library_prefix() -> String:
	if _uses_female_animations():
		return "HumanF@"
	return "HumanM@"

func _should_copy_animation_library(library_name: String, gender_prefix: String) -> bool:
	return library_name.begins_with(gender_prefix) or library_name == "custom"

func _uses_female_seated_animations() -> bool:
	return _uses_female_animations()

func _uses_female_animations() -> bool:
	return character_id.contains("Female")
