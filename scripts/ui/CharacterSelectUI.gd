## Character selection screen: lists saved characters, creates new ones, enters world.
extends Control

signal character_selected(character_data: Dictionary)

@onready var char_list: ItemList         = $Layout/CharList
@onready var preview_panel: Control      = $Layout/Preview
@onready var preview_name: Label         = $Layout/Preview/Name
@onready var preview_class: Label        = $Layout/Preview/Class
@onready var preview_level: Label        = $Layout/Preview/Level
@onready var preview_faction: Label      = $Layout/Preview/Faction
@onready var enter_btn: Button           = $Layout/Buttons/EnterBtn
@onready var create_btn: Button          = $Layout/Buttons/CreateBtn
@onready var delete_btn: Button          = $Layout/Buttons/DeleteBtn
@onready var back_btn: Button            = $Layout/Buttons/BackBtn
@onready var create_panel: Control       = $CreatePanel

var _characters: Array = []
var _selected_index: int = -1

func _ready() -> void:
	enter_btn.pressed.connect(_on_enter)
	create_btn.pressed.connect(_on_open_create)
	delete_btn.pressed.connect(_on_delete)
	back_btn.pressed.connect(_on_back)
	char_list.item_selected.connect(_on_char_selected)
	enter_btn.disabled = true
	delete_btn.disabled = true
	_load_character_list()

func _load_character_list() -> void:
	char_list.clear()
	_characters = DatabaseManager.list_characters_for_account(0)
	for data in _characters:
		var faction_name := GameManager.faction_name(data["faction"] as GameManager.Faction)
		char_list.add_item("[Liv.%d] %s — %s (%s)" % [
			data["level"], data["name"], data["class"].capitalize(), faction_name
		])

func _on_char_selected(index: int) -> void:
	_selected_index = index
	var data: Dictionary = _characters[index]
	preview_name.text = data["name"]
	preview_class.text = data.get("class", "?").capitalize()
	preview_level.text = "Livello %d" % data.get("level", 1)
	preview_faction.text = GameManager.faction_name(data.get("faction", 0) as GameManager.Faction)
	preview_faction.modulate = GameManager.faction_color(data.get("faction", 0) as GameManager.Faction)
	enter_btn.disabled = false
	delete_btn.disabled = false

func _on_enter() -> void:
	if _selected_index < 0:
		return
	var data := DatabaseManager.load_character(_characters[_selected_index]["name"])
	if data.is_empty():
		return
	character_selected.emit(data)
	get_tree().change_scene_to_file("res://scenes/game/World.tscn")

func _on_open_create() -> void:
	create_panel.visible = true

func _on_delete() -> void:
	if _selected_index < 0:
		return
	# TODO: confirmation dialog before delete
	var char_name: String = _characters[_selected_index]["name"]
	DirAccess.remove_absolute("user://characters/%s.json" % char_name)
	_load_character_list()
	_selected_index = -1
	enter_btn.disabled = true
	delete_btn.disabled = true

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
