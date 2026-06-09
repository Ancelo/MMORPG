## Persistent storage for characters, guilds, and world state.
## Uses SQLite via Godot SQLite plugin (addons/godot-sqlite).
## Falls back to JSON files in user:// for dev builds without the plugin.
extends Node

const DB_PATH := "user://roma_aeterna.db"
const USE_JSON_FALLBACK := true  # set false when SQLite plugin is installed

var _db = null  # SQLite object when plugin is available

func _ready() -> void:
	if not USE_JSON_FALLBACK:
		_init_sqlite()
	else:
		_ensure_json_dirs()

# ----- Init -----

func _init_sqlite() -> void:
	# Requires: https://github.com/2shady4u/godot-sqlite
	_db = load("res://addons/godot-sqlite/bin/godot_sqlite.gdns").new()
	_db.path = DB_PATH
	_db.open_db()
	_create_tables()

func _create_tables() -> void:
	_db.query("""
		CREATE TABLE IF NOT EXISTS characters (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			account_id INTEGER,
			name TEXT UNIQUE,
			class TEXT,
			faction INTEGER,
			level INTEGER DEFAULT 1,
			experience INTEGER DEFAULT 0,
			zone TEXT DEFAULT 'forum_romanum',
			pos_x REAL DEFAULT 0, pos_y REAL DEFAULT 0, pos_z REAL DEFAULT 0,
			stats_json TEXT,
			equipment_json TEXT,
			inventory_json TEXT,
			hotbar_json TEXT,
			created_at TEXT DEFAULT (datetime('now')),
			last_seen TEXT DEFAULT (datetime('now'))
		)
	""")
	_db.query("""
		CREATE TABLE IF NOT EXISTS guilds (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT UNIQUE,
			faction INTEGER,
			leader_name TEXT,
			description TEXT,
			emblem TEXT,
			created_at TEXT DEFAULT (datetime('now'))
		)
	""")
	_db.query("""
		CREATE TABLE IF NOT EXISTS guild_members (
			guild_id INTEGER,
			character_name TEXT,
			rank INTEGER DEFAULT 0,
			joined_at TEXT DEFAULT (datetime('now')),
			PRIMARY KEY (guild_id, character_name)
		)
	""")
	_db.query("""
		CREATE TABLE IF NOT EXISTS character_quests (
			character_name TEXT,
			quest_id TEXT,
			status TEXT,
			progress_json TEXT,
			PRIMARY KEY (character_name, quest_id)
		)
	""")

func _ensure_json_dirs() -> void:
	DirAccess.make_dir_recursive_absolute("user://characters")
	DirAccess.make_dir_recursive_absolute("user://guilds")

# ----- Character CRUD -----

func save_character(character: Character) -> Error:
	var data := _character_to_dict(character)
	if USE_JSON_FALLBACK:
		return _save_json("user://characters/%s.json" % character.character_name, data)
	return _save_character_sqlite(data)

func load_character(character_name: String) -> Dictionary:
	if USE_JSON_FALLBACK:
		return _load_json("user://characters/%s.json" % character_name)
	return _load_character_sqlite(character_name)

func list_characters_for_account(account_id: int) -> Array:
	if USE_JSON_FALLBACK:
		return _list_json_characters()
	return _list_sqlite_characters(account_id)

func character_name_available(name: String) -> bool:
	if USE_JSON_FALLBACK:
		return not FileAccess.file_exists("user://characters/%s.json" % name)
	_db.query("SELECT id FROM characters WHERE name = '%s'" % name)
	return _db.query_result.size() == 0

func _character_to_dict(c: Character) -> Dictionary:
	var equip := {}
	var inv := []
	if c.get_node_or_null("Inventory"):
		var inventory := c.get_node("Inventory") as Inventory
		equip = inventory.to_dict().get("equipped", {})
		inv = inventory.to_dict().get("bags", [])

	var hotbar := []
	if c.get_node_or_null("AbilityManager"):
		var am := c.get_node("AbilityManager") as AbilityManager
		for i in range(AbilityManager.HOTBAR_SLOTS):
			hotbar.append(am.get_slot_ability(i))

	return {
		"name": c.character_name,
		"class": c.character_class,
		"faction": int(c.faction),
		"level": c.level,
		"experience": c.experience,
		"zone": "forum_romanum",  # TODO: track current zone
		"pos": [c.global_position.x, c.global_position.y, c.global_position.z],
		"stats": c.stats.to_dict(),
		"equipment": equip,
		"inventory": inv,
		"hotbar": hotbar,
	}

func save_character_dict(data: Dictionary) -> Error:
	if USE_JSON_FALLBACK:
		return _save_json("user://characters/%s.json" % data["name"], data)
	return _save_character_sqlite(data)

func apply_character_data(character: Character, data: Dictionary) -> void:
	character.character_name  = data.get("name", "Unknown")
	character.character_class = data.get("class", "")
	character.faction         = data.get("faction", 0) as GameManager.Faction
	character.level           = data.get("level", 1)
	character.experience      = data.get("experience", 0)
	if data.has("stats"):
		character.stats.from_dict(data["stats"])
	if data.has("pos"):
		var p: Array = data["pos"]
		character.global_position = Vector3(p[0], p[1], p[2])
	if data.has("hotbar") and character.get_node_or_null("AbilityManager"):
		var am := character.get_node("AbilityManager") as AbilityManager
		for i in range(mini(data["hotbar"].size(), AbilityManager.HOTBAR_SLOTS)):
			am.assign_hotbar(i, data["hotbar"][i])

# ----- SQLite helpers -----

func _save_character_sqlite(data: Dictionary) -> Error:
	var q := """
		INSERT OR REPLACE INTO characters
		(name, class, faction, level, experience, zone, pos_x, pos_y, pos_z,
		 stats_json, equipment_json, inventory_json, hotbar_json, last_seen)
		VALUES ('%s','%s',%d,%d,%d,'%s',%f,%f,%f,'%s','%s','%s','%s',datetime('now'))
	""" % [
		data["name"], data["class"], data["faction"], data["level"],
		data["experience"], data.get("zone","forum_romanum"),
		data["pos"][0], data["pos"][1], data["pos"][2],
		JSON.stringify(data["stats"]),
		JSON.stringify(data["equipment"]),
		JSON.stringify(data["inventory"]),
		JSON.stringify(data["hotbar"]),
	]
	return OK if _db.query(q) else FAILED

func _load_character_sqlite(name: String) -> Dictionary:
	_db.query("SELECT * FROM characters WHERE name = '%s'" % name)
	if _db.query_result.is_empty():
		return {}
	var row: Dictionary = _db.query_result[0]
	return {
		"name": row["name"], "class": row["class"],
		"faction": row["faction"], "level": row["level"],
		"experience": row["experience"], "zone": row["zone"],
		"pos": [row["pos_x"], row["pos_y"], row["pos_z"]],
		"stats": JSON.parse_string(row["stats_json"]),
		"equipment": JSON.parse_string(row["equipment_json"]),
		"inventory": JSON.parse_string(row["inventory_json"]),
		"hotbar": JSON.parse_string(row["hotbar_json"]),
	}

func _list_sqlite_characters(account_id: int) -> Array:
	_db.query("SELECT name, class, faction, level FROM characters WHERE account_id = %d" % account_id)
	return _db.query_result.duplicate()

# ----- JSON fallback -----

func _save_json(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ERR_FILE_CANT_WRITE
	file.store_string(JSON.stringify(data, "\t"))
	return OK

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _list_json_characters() -> Array:
	var result: Array = []
	var dir := DirAccess.open("user://characters")
	if not dir:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var data := _load_json("user://characters/" + fname)
			if not data.is_empty():
				result.append({
					"name": data.get("name",""),
					"class": data.get("class",""),
					"faction": data.get("faction", 0),
					"level": data.get("level", 1),
				})
		fname = dir.get_next()
	return result

# ----- Guild persistence -----

func save_guild(guild_data: Dictionary) -> Error:
	if USE_JSON_FALLBACK:
		return _save_json("user://guilds/%s.json" % guild_data["name"], guild_data)
	return OK  # TODO: SQLite guild save

func load_guild(guild_name: String) -> Dictionary:
	if USE_JSON_FALLBACK:
		return _load_json("user://guilds/%s.json" % guild_name)
	return {}
