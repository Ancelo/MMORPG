## Manages instanced dungeons: creation, player assignment, boss spawning, rewards.
## Each dungeon instance is a separate scene loaded on the server.
class_name DungeonManager
extends Node

const MAX_PLAYERS_PER_INSTANCE := 8
const INSTANCE_TIMEOUT := 7200.0  # 2 hours, then instance resets

# Active instances: instance_id -> DungeonInstance data
var _instances: Dictionary = {}
var _instance_counter: int = 0

# Dungeon definitions (loaded from data/dungeons/)
var _dungeon_data: Dictionary = {}

func _ready() -> void:
	add_to_group("dungeon_manager")
	_load_dungeon_data()

func _load_dungeon_data() -> void:
	var dir := DirAccess.open("res://data/dungeons/")
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var file := FileAccess.open("res://data/dungeons/" + fname, FileAccess.READ)
			if file:
				var parsed := JSON.parse_string(file.get_as_text())
				if parsed is Dictionary:
					_dungeon_data[parsed["id"]] = parsed
		fname = dir.get_next()

# ----- Instance lifecycle -----

func request_enter(dungeon_id: String, players: Array) -> int:
	if not multiplayer.is_server():
		return -1
	var dungeon := _dungeon_data.get(dungeon_id, {})
	if dungeon.is_empty():
		push_error("[Dungeon] Unknown dungeon: %s" % dungeon_id)
		return -1

	var min_players: int = dungeon.get("min_players", 1)
	var max_players: int = dungeon.get("max_players", MAX_PLAYERS_PER_INSTANCE)
	if players.size() < min_players or players.size() > max_players:
		EventBus.notification_pushed.emit(
			"Servono %d-%d giocatori per %s" % [min_players, max_players, dungeon.get("name","?")],
			"dungeon"
		)
		return -1

	_instance_counter += 1
	var instance_id := _instance_counter
	var instance := _create_instance(instance_id, dungeon, players)
	_instances[instance_id] = instance
	return instance_id

func _create_instance(instance_id: int, dungeon: Dictionary, players: Array) -> Dictionary:
	var scene_path: String = dungeon.get("scene", "")
	var scene_node: Node = null
	if scene_path != "":
		var packed := load(scene_path) as PackedScene
		if packed:
			scene_node = packed.instantiate()
			scene_node.name = "Dungeon_%d" % instance_id
			add_child(scene_node)

	var instance := {
		"id": instance_id,
		"dungeon_id": dungeon["id"],
		"dungeon_name": dungeon.get("name", ""),
		"scene_node": scene_node,
		"players": players.duplicate(),
		"bosses_defeated": [],
		"state": "active",
		"elapsed": 0.0,
		"timeout": dungeon.get("time_limit", INSTANCE_TIMEOUT),
		"boss_states": {},
	}

	# Teleport players in
	for player in players:
		var entry: Array = dungeon.get("entry_point", [0.0, 1.0, 0.0])
		player.global_position = Vector3(entry[0], entry[1], entry[2])
		player.respawn_point   = player.global_position

	EventBus.notification_pushed.emit(
		"Benvenuto in %s!" % dungeon.get("name","?"),
		"dungeon"
	)
	return instance

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for instance_id in _instances.keys():
		var instance: Dictionary = _instances[instance_id]
		if instance["state"] != "active":
			continue
		instance["elapsed"] += delta
		if instance["elapsed"] >= instance["timeout"]:
			_expire_instance(instance_id)

func _expire_instance(instance_id: int) -> void:
	var instance: Dictionary = _instances[instance_id]
	instance["state"] = "expired"
	EventBus.notification_pushed.emit("Il dungeon è scaduto. I giocatori vengono teletrasportati.", "dungeon")
	for player in instance["players"]:
		if is_instance_valid(player):
			player.global_position = player.respawn_point
	if instance["scene_node"] and is_instance_valid(instance["scene_node"]):
		instance["scene_node"].queue_free()
	_instances.erase(instance_id)

# ----- Boss events -----

func on_boss_defeated(instance_id: int, boss_id: String) -> void:
	var instance: Dictionary = _instances.get(instance_id, {})
	if instance.is_empty():
		return
	instance["bosses_defeated"].append(boss_id)

	var dungeon := _dungeon_data.get(instance["dungeon_id"], {})
	var all_bosses: Array = dungeon.get("bosses", [])
	var all_defeated := true
	for b in all_bosses:
		if b not in instance["bosses_defeated"]:
			all_defeated = false
			break

	if all_defeated:
		_complete_instance(instance_id)

func _complete_instance(instance_id: int) -> void:
	var instance: Dictionary = _instances[instance_id]
	instance["state"] = "complete"
	EventBus.notification_pushed.emit(
		"Dungeon completato: %s!" % instance["dungeon_name"],
		"dungeon_complete"
	)
	var dungeon := _dungeon_data.get(instance["dungeon_id"], {})
	_grant_dungeon_rewards(instance["players"], dungeon.get("completion_rewards", {}))
	await get_tree().create_timer(30.0).timeout
	_expire_instance(instance_id)

func _grant_dungeon_rewards(players: Array, rewards: Dictionary) -> void:
	for player in players:
		if not is_instance_valid(player):
			continue
		if rewards.has("xp") and player.get_node_or_null("QuestManager"):
			player.experience += rewards["xp"]
			EventBus.xp_gained.emit(rewards["xp"], player.experience, player.level)
		if rewards.has("items") and player.get_node_or_null("Inventory"):
			for item_id in rewards["items"]:
				if randf() < rewards["items"][item_id]:
					player.get_node("Inventory").add_item(item_id)

func get_instance(instance_id: int) -> Dictionary:
	return _instances.get(instance_id, {})

func find_instance_for_player(player: Character) -> int:
	for instance_id in _instances:
		if player in _instances[instance_id]["players"]:
			return instance_id
	return -1
