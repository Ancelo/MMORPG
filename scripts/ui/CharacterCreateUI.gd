## Character creation: choose faction, class, name, and appearance.
extends Control

signal creation_confirmed(character_data: Dictionary)
signal creation_cancelled()

@onready var name_input: LineEdit      = $Scroll/VBox/NameInput
@onready var name_error: Label         = $Scroll/VBox/NameError
@onready var faction_tabs: TabContainer = $Scroll/VBox/FactionTabs
@onready var class_list: ItemList      = $Scroll/VBox/ClassList
@onready var class_desc: RichTextLabel = $Scroll/VBox/ClassDescription
@onready var stat_display: GridContainer = $Scroll/VBox/Stats
@onready var confirm_btn: Button       = $Buttons/ConfirmBtn
@onready var cancel_btn: Button        = $Buttons/CancelBtn

const FACTION_CLASSES := {
	GameManager.Faction.ROMAN:   ["legionary", "sagittarius", "medicus", "gladiator"],
	GameManager.Faction.GALLI:   ["guerriero_celtico", "druida", "cacciatore"],
	GameManager.Faction.GERMANI: ["berserker", "sciamano", "guardia"],
}

var _selected_faction: GameManager.Faction = GameManager.Faction.ROMAN
var _selected_class: String = ""

func _ready() -> void:
	confirm_btn.pressed.connect(_on_confirm)
	cancel_btn.pressed.connect(_on_cancel)
	faction_tabs.tab_changed.connect(_on_faction_changed)
	class_list.item_selected.connect(_on_class_selected)
	name_input.text_changed.connect(_on_name_changed)
	confirm_btn.disabled = true
	_populate_class_list(GameManager.Faction.ROMAN)

func _on_faction_changed(tab: int) -> void:
	_selected_faction = [
		GameManager.Faction.ROMAN,
		GameManager.Faction.GALLI,
		GameManager.Faction.GERMANI
	][tab]
	_selected_class = ""
	_populate_class_list(_selected_faction)
	_update_confirm()

func _populate_class_list(faction: GameManager.Faction) -> void:
	class_list.clear()
	class_desc.text = ""
	for class_id in FACTION_CLASSES.get(faction, []):
		var data := DataManager.get_class_data(class_id)
		var label: String = data.get("name", class_id.capitalize())
		var role: String = data.get("role", "")
		class_list.add_item("%s  [%s]" % [label, role])
		class_list.set_item_metadata(class_list.item_count - 1, class_id)

func _on_class_selected(index: int) -> void:
	_selected_class = class_list.get_item_metadata(index)
	var data := DataManager.get_class_data(_selected_class)
	_show_class_info(data)
	_update_confirm()

func _show_class_info(data: Dictionary) -> void:
	class_desc.clear()
	class_desc.append_text("[b]%s[/b]\n" % data.get("name", ""))
	class_desc.append_text(data.get("description", "") + "\n\n")
	class_desc.append_text("[b]Statistiche Base:[/b]\n")
	class_desc.append_text("FOR %d  DES %d  COS %d\n" % [
		data.get("base_strength", 10),
		data.get("base_dexterity", 10),
		data.get("base_constitution", 10),
	])
	class_desc.append_text("INT %d  PIE %d  CAR %d\n" % [
		data.get("base_intelligence", 10),
		data.get("base_piety", 10),
		data.get("base_charisma", 10),
	])
	class_desc.append_text("\n[b]Armatura:[/b] %s\n" % data.get("armor_type", "?").capitalize())
	class_desc.append_text("[b]Armi:[/b] %s" % ", ".join(data.get("weapon_types", [])))

func _on_name_changed(_text: String) -> void:
	name_error.text = ""
	_update_confirm()

func _update_confirm() -> void:
	confirm_btn.disabled = _selected_class.is_empty() or name_input.text.strip_edges().length() < 3

func _on_confirm() -> void:
	var char_name := name_input.text.strip_edges()
	if char_name.length() < 3 or char_name.length() > 20:
		name_error.text = "Nome: 3-20 caratteri"
		return
	if not char_name.is_valid_identifier():
		name_error.text = "Solo lettere, numeri e trattino basso"
		return
	if not DatabaseManager.character_name_available(char_name):
		name_error.text = "Nome già in uso"
		return

	var class_data := DataManager.get_class_data(_selected_class)
	var new_char := {
		"name": char_name,
		"class": _selected_class,
		"faction": int(_selected_faction),
		"level": 1,
		"experience": 0,
		"zone": _starting_zone(_selected_faction),
		"pos": [0.0, 1.0, 0.0],
		"stats": {
			"strength":     class_data.get("base_strength", 10),
			"dexterity":    class_data.get("base_dexterity", 10),
			"constitution": class_data.get("base_constitution", 10),
			"intelligence": class_data.get("base_intelligence", 10),
			"piety":        class_data.get("base_piety", 10),
			"charisma":     class_data.get("base_charisma", 10),
			"level": 1,
			"speed": class_data.get("base_speed", 5.0),
		},
		"equipment": {},
		"inventory": [],
		"hotbar": _default_hotbar(_selected_class),
	}
	DatabaseManager.save_character_dict(new_char)
	creation_confirmed.emit(new_char)
	visible = false

func _on_cancel() -> void:
	visible = false
	creation_cancelled.emit()

func _starting_zone(faction: GameManager.Faction) -> String:
	match faction:
		GameManager.Faction.ROMAN:   return "forum_romanum"
		GameManager.Faction.GALLI:   return "foreste_galliche"
		GameManager.Faction.GERMANI: return "selva_nera"
		_: return "forum_romanum"

func _default_hotbar(class_id: String) -> Array:
	var abilities := DataManager.get_abilities_for_class(class_id, 1)
	var hotbar := []
	for i in range(10):
		if i < abilities.size():
			hotbar.append(abilities[i]["id"])
		else:
			hotbar.append("")
	return hotbar
