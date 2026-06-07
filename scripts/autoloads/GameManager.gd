## Central game state manager.
extends Node

enum GameState { MAIN_MENU, CHARACTER_SELECT, LOADING, IN_GAME, PAUSED }
enum Faction { NONE = 0, ROMAN = 1, GALLI = 2, GERMANI = 3 }

const MAX_LEVEL := 50
const TICK_RATE := 20  # server physics ticks per second

var state: GameState = GameState.MAIN_MENU
var local_player: Node = null
var local_peer_id: int = 0
var local_faction: Faction = Faction.NONE

# Server-side: peer_id -> character node
var players: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func change_state(new_state: GameState) -> void:
	state = new_state
	match state:
		GameState.IN_GAME:
			Engine.physics_ticks_per_second = TICK_RATE
		_:
			Engine.physics_ticks_per_second = 60

func register_player(peer_id: int, character: Node) -> void:
	players[peer_id] = character
	EventBus.character_spawned.emit(character, peer_id)

func unregister_player(peer_id: int) -> void:
	if peer_id in players:
		EventBus.character_despawned.emit(peer_id)
		players.erase(peer_id)

func get_player(peer_id: int) -> Node:
	return players.get(peer_id)

func get_players_in_range(origin: Vector3, radius: float) -> Array:
	var result: Array = []
	for character in players.values():
		if character.global_position.distance_to(origin) <= radius:
			result.append(character)
	return result

func get_enemies_of(faction: Faction) -> Array[Faction]:
	match faction:
		Faction.ROMAN:  return [Faction.GALLI, Faction.GERMANI]
		Faction.GALLI:  return [Faction.ROMAN, Faction.GERMANI]
		Faction.GERMANI: return [Faction.ROMAN, Faction.GALLI]
		_: return []

func is_enemy(a: Faction, b: Faction) -> bool:
	if a == Faction.NONE or b == Faction.NONE:
		return false
	return a != b

func faction_name(faction: Faction) -> String:
	match faction:
		Faction.ROMAN: return "Romani"
		Faction.GALLI: return "Galli"
		Faction.GERMANI: return "Germani"
		_: return "Senza Fazione"

func faction_color(faction: Faction) -> Color:
	match faction:
		Faction.ROMAN:   return Color(0.8, 0.1, 0.1)   # Rosso imperiale
		Faction.GALLI:   return Color(0.1, 0.6, 0.2)   # Verde celtico
		Faction.GERMANI: return Color(0.2, 0.4, 0.8)   # Blu germanico
		_: return Color.WHITE
