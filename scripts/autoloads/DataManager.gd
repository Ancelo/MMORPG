## Loads and caches all static game data (classes, abilities, items, quests).
## Recursively scans subdirectories. JSON files may contain a single object {id:...}
## or an Array of objects, each with an "id" field.
extends Node

var classes: Dictionary = {}
var abilities: Dictionary = {}
var items: Dictionary = {}
var quests: Dictionary = {}
var zones: Dictionary = {}
var dungeons: Dictionary = {}

const DATA_PATHS := {
	"classes":   "res://data/classes/",
	"abilities": "res://data/abilities/",
	"items":     "res://data/items/",
	"quests":    "res://data/quests/",
	"zones":     "res://data/zones/",
	"dungeons":  "res://data/dungeons/",
}

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_load_directory_recursive(DATA_PATHS["classes"],   classes)
	_load_directory_recursive(DATA_PATHS["abilities"],  abilities)
	_load_directory_recursive(DATA_PATHS["items"],      items)
	_load_directory_recursive(DATA_PATHS["quests"],     quests)
	_load_directory_recursive(DATA_PATHS["zones"],      zones)
	_load_directory_recursive(DATA_PATHS["dungeons"],   dungeons)
	print("[DataManager] Loaded: %d classes, %d abilities, %d items, %d quests, %d zones, %d dungeons" % [
		classes.size(), abilities.size(), items.size(), quests.size(), zones.size(), dungeons.size()
	])

func _load_directory_recursive(base_path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(base_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			_load_directory_recursive(base_path + entry + "/", target)
		elif entry.ends_with(".json"):
			_load_json_into(base_path + entry, target)
		entry = dir.get_next()

func _load_json_into(path: String, target: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		if parsed.has("id"):
			target[parsed["id"]] = parsed
	elif parsed is Array:
		for item in parsed:
			if item is Dictionary and item.has("id"):
				target[item["id"]] = item

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[DataManager] Cannot read: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("[DataManager] Invalid JSON: %s" % path)
	return {}

func get_class_data(class_id: String) -> Dictionary:
	return classes.get(class_id, {})

func get_ability(ability_id: String) -> Dictionary:
	return abilities.get(ability_id, {})

func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})

func get_quest(quest_id: String) -> Dictionary:
	return quests.get(quest_id, {})

func get_zone(zone_id: String) -> Dictionary:
	return zones.get(zone_id, {})

func get_dungeon(dungeon_id: String) -> Dictionary:
	return dungeons.get(dungeon_id, {})

func get_abilities_for_class(class_id: String, max_level: int = 50) -> Array:
	var result: Array = []
	for ability in abilities.values():
		if ability.get("class_id") == class_id and ability.get("required_level", 1) <= max_level:
			result.append(ability)
	result.sort_custom(func(a, b): return a.get("required_level", 1) < b.get("required_level", 1))
	return result
