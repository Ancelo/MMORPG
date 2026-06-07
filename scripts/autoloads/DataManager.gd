## Loads and caches all static game data (classes, abilities, items, quests).
extends Node

var classes: Dictionary = {}
var abilities: Dictionary = {}
var items: Dictionary = {}
var quests: Dictionary = {}
var zones: Dictionary = {}

const DATA_PATHS := {
	"classes":   "res://data/classes/",
	"abilities": "res://data/abilities/",
	"items":     "res://data/items/",
	"quests":    "res://data/quests/",
	"zones":     "res://data/zones/",
}

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_load_directory("classes", classes)
	_load_directory("abilities", abilities)
	_load_directory("items", items)
	_load_directory("quests", quests)
	_load_directory("zones", zones)
	print("[DataManager] Loaded: %d classes, %d abilities, %d items, %d quests, %d zones" % [
		classes.size(), abilities.size(), items.size(), quests.size(), zones.size()
	])

func _load_directory(category: String, target: Dictionary) -> void:
	var dir := DirAccess.open(DATA_PATHS[category])
	if not dir:
		push_warning("[DataManager] Cannot open data dir: %s" % DATA_PATHS[category])
		return
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if filename.ends_with(".json"):
			var path := DATA_PATHS[category] + filename
			var data := _load_json(path)
			if data and data.has("id"):
				target[data["id"]] = data
		filename = dir.get_next()

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[DataManager] Cannot read: %s" % path)
		return {}
	var parsed := JSON.parse_string(file.get_as_text())
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

func get_abilities_for_class(class_id: String, max_level: int = 50) -> Array:
	var result: Array = []
	for ability in abilities.values():
		if ability.get("class_id") == class_id and ability.get("required_level", 1) <= max_level:
			result.append(ability)
	result.sort_custom(func(a, b): return a.get("required_level", 1) < b.get("required_level", 1))
	return result
