## Entry point for the dedicated server mode.
## Run with: godot --headless --dedicated-server
extends Node

const WORLD_STATE_INTERVAL := 1.0 / 20.0  # 20 Hz broadcast

var _world_state_timer: float = 0.0
var _rvr_manager: RvRManager

func _ready() -> void:
	if not OS.has_feature("dedicated_server"):
		return

	print("=== Roma Aeterna Dedicated Server ===")
	var port := int(OS.get_environment("SERVER_PORT")) if OS.get_environment("SERVER_PORT") != "" else NetworkManager.DEFAULT_PORT
	var max_players := int(OS.get_environment("MAX_PLAYERS")) if OS.get_environment("MAX_PLAYERS") != "" else NetworkManager.MAX_PLAYERS

	var err := NetworkManager.host_server(port)
	if err != OK:
		push_error("Failed to start server: %s" % error_string(err))
		get_tree().quit(1)
		return

	print("Server ready. Port=%d MaxPlayers=%d" % [port, max_players])

	_rvr_manager = RvRManager.new()
	add_child(_rvr_manager)

	var party_manager := PartyManager.new()
	add_child(party_manager)

	var loot_manager := LootManager.new()
	add_child(loot_manager)

	var dungeon_manager := DungeonManager.new()
	add_child(dungeon_manager)

	var guild_manager := GuildManager.new()
	add_child(guild_manager)

	var keep_assault_manager := KeepAssaultManager.new()
	add_child(keep_assault_manager)

	var chat_parser := load("res://scripts/chat/ChatCommandParser.gd").new()
	add_child(chat_parser)

	EventBus.player_connected.connect(_on_player_connected)
	EventBus.player_disconnected.connect(_on_player_disconnected)

	_load_world()

func _process(delta: float) -> void:
	if not OS.has_feature("dedicated_server"):
		return
	_world_state_timer += delta
	if _world_state_timer >= WORLD_STATE_INTERVAL:
		_world_state_timer -= WORLD_STATE_INTERVAL
		_broadcast_world_state()

func _load_world() -> void:
	var world_scene := load("res://scenes/game/World.tscn") as PackedScene
	if world_scene:
		add_child(world_scene.instantiate())
		print("[Server] World loaded")
	else:
		push_error("[Server] World scene not found")

func _on_player_connected(peer_id: int) -> void:
	print("[Server] Player connected: peer_id=%d" % peer_id)
	_spawn_player(peer_id)

func _spawn_player(peer_id: int) -> void:
	var player_scene := load("res://scenes/game/PlayerCharacter.tscn") as PackedScene
	if not player_scene:
		push_error("[Server] PlayerCharacter scene not found")
		return
	var player := player_scene.instantiate() as PlayerCharacter
	player.name = str(peer_id)
	# TODO: load saved character data from database
	player.character_name = "Gladiator_%d" % peer_id
	player.character_class = "legionary"
	player.faction = GameManager.Faction.ROMAN
	player.level = 1
	get_node("World/SpawnPoints/Roman").add_child(player)
	GameManager.register_player(peer_id, player)
	print("[Server] Spawned player %d as %s" % [peer_id, player.character_name])

func _on_player_disconnected(peer_id: int) -> void:
	print("[Server] Player disconnected: peer_id=%d" % peer_id)
	# TODO: save character data to database

func _broadcast_world_state() -> void:
	var state: Dictionary = {}
	for peer_id in GameManager.players:
		var character := GameManager.players[peer_id]
		state[str(peer_id)] = character.get_network_state()
	NetworkManager.broadcast_world_state(state)
