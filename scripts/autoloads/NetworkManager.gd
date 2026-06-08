## Handles all multiplayer networking (ENet peer-to-peer with dedicated server).
## Server-authoritative: clients send input, server validates and broadcasts state.
extends Node

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 500
const SERVER_SEND_RATE := 20  # Hz

var peer: ENetMultiplayerPeer = null
var is_server: bool = false

# Sequence numbers for input ordering
var _input_sequence: int = 0
var _last_server_state: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ----- Connection management -----

func host_server(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to create server on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	GameManager.local_peer_id = 1
	print("[Server] Listening on port %d" % port)
	return OK

func connect_to_server(address: String, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("Failed to connect to %s:%d" % [address, port])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = false
	return OK

func disconnect_from_server() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	is_server = false

# ----- Input relay (client -> server) -----

func send_player_input(input_data: Dictionary) -> void:
	if is_server:
		return
	_input_sequence += 1
	input_data["seq"] = _input_sequence
	_receive_player_input.rpc_id(1, input_data)

@rpc("any_peer", "unreliable_ordered")
func _receive_player_input(input_data: Dictionary) -> void:
	if not is_server:
		return
	var character := GameManager.get_player(_get_sender_id())
	if character and character.has_method("apply_input"):
		character.apply_input(input_data)

# ----- State broadcast (server -> clients) -----

func broadcast_world_state(state_data: Dictionary) -> void:
	if not is_server:
		return
	_receive_world_state.rpc(state_data)

@rpc("authority", "unreliable_ordered")
func _receive_world_state(state_data: Dictionary) -> void:
	_last_server_state = state_data
	_apply_world_state(state_data)

func _apply_world_state(state: Dictionary) -> void:
	for peer_id_str in state:
		var peer_id := int(peer_id_str)
		var char_state: Dictionary = state[peer_id_str]
		var character := GameManager.get_player(peer_id)
		if character and character.has_method("apply_server_state"):
			character.apply_server_state(char_state)

# ----- Reliable RPCs -----

func request_use_ability(ability_id: String, target_id: int) -> void:
	_rpc_use_ability.rpc_id(1, ability_id, target_id)

@rpc("any_peer", "reliable")
func _rpc_use_ability(ability_id: String, target_id: int) -> void:
	if not is_server:
		return
	var character := GameManager.get_player(_get_sender_id())
	if character:
		character.get_node("AbilityManager").server_use_ability(ability_id, target_id)

func notify_ability_result(target_peer_id: int, ability_id: String, result: Dictionary) -> void:
	_rpc_ability_result.rpc_id(target_peer_id, ability_id, result)

@rpc("authority", "reliable")
func _rpc_ability_result(ability_id: String, result: Dictionary) -> void:
	EventBus.ability_used.emit(null, ability_id)

# ----- Chat -----

func send_chat_message(message: String, channel: String = "general") -> void:
	_rpc_chat_message.rpc_id(1, message, channel)

@rpc("any_peer", "reliable")
func _rpc_chat_message(message: String, channel: String) -> void:
	if not is_server:
		return
	var character := GameManager.get_player(_get_sender_id())
	if not character:
		return
	# Let command parser intercept slash-commands
	var parsers := get_tree().get_nodes_in_group("chat_command_parser")
	if not parsers.is_empty() and parsers[0].parse(message, character):
		return
	var sender_name: String = character.character_name
	var faction: int = character.faction
	_rpc_broadcast_chat.rpc(sender_name, message, channel, faction)

@rpc("authority", "reliable")
func _rpc_broadcast_chat(sender_name: String, message: String, channel: String, faction: int) -> void:
	EventBus.chat_message_received.emit(sender_name, message, channel, faction)

# ----- Callbacks -----

func _on_peer_connected(id: int) -> void:
	print("[Network] Peer connected: %d" % id)
	if is_server:
		EventBus.player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("[Network] Peer disconnected: %d" % id)
	if is_server:
		GameManager.unregister_player(id)
		EventBus.player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	GameManager.local_peer_id = multiplayer.get_unique_id()
	print("[Network] Connected to server, peer_id=%d" % GameManager.local_peer_id)

func _on_connection_failed() -> void:
	push_error("[Network] Connection failed")
	EventBus.connection_failed.emit()

func _get_sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()

func _on_server_disconnected() -> void:
	push_error("[Network] Server disconnected")
	EventBus.server_disconnected.emit()
	disconnect_from_server()
