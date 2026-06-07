## Manages a game zone: NPC spawning, ambient life, zone transitions, and weather.
class_name WorldZone
extends Node3D

@export var zone_id: String = ""
@export var zone_name: String = ""
@export var zone_level_min: int = 1
@export var zone_level_max: int = 10
@export var allowed_factions: Array[int] = [1, 2, 3]
@export var is_rvr_zone: bool = false
@export var ambient_music: AudioStream = null
@export var sky_override: Environment = null

@onready var spawn_manager: Node = $SpawnManager
@onready var ambient_audio: AudioStreamPlayer3D = $AmbientAudio
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var _players_in_zone: Dictionary = {}  # peer_id -> Character
var _zone_data: Dictionary = {}

func _ready() -> void:
	add_to_group("zones")
	_zone_data = DataManager.get_zone(zone_id)
	if ambient_music:
		ambient_audio.stream = ambient_music
		ambient_audio.play()
	if sky_override and world_environment:
		world_environment.environment = sky_override

func player_enter(peer_id: int, character: Character, entry_point: String) -> void:
	_players_in_zone[peer_id] = character
	var spawn_pos := _get_entry_position(entry_point)
	character.global_position = spawn_pos
	character.respawn_point = spawn_pos
	print("[Zone] %s entered %s at %s" % [character.character_name, zone_name, entry_point])

func player_leave(peer_id: int) -> void:
	_players_in_zone.erase(peer_id)

func get_players() -> Array:
	return _players_in_zone.values()

func _get_entry_position(entry_point: String) -> Vector3:
	var entries: Dictionary = _zone_data.get("entry_points", {})
	if entries.has(entry_point):
		var p: Array = entries[entry_point]
		return Vector3(p[0], p[1], p[2])
	return Vector3.ZERO
