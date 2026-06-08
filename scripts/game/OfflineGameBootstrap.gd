## Bootstraps a self-hosted offline session for local testing.
## Attach this script to the root node of TestScene.tscn.
extends Node3D

@export var character_class: String = "legionary"
@export var character_faction: GameManager.Faction = GameManager.Faction.ROMAN
@export var character_level: int = 10
@export var spawn_position: Vector3 = Vector3(0, 1, 0)

const _MANAGER_SCRIPTS := [
	"res://scripts/party/PartyManager.gd",
	"res://scripts/loot/LootManager.gd",
	"res://scripts/dungeon/DungeonManager.gd",
	"res://scripts/guild/GuildManager.gd",
	"res://scripts/rvr/KeepAssaultManager.gd",
	"res://scripts/chat/ChatCommandParser.gd",
]

func _ready() -> void:
	print("[Bootstrap] Starting offline session...")
	var err := NetworkManager.host_server()
	if err != OK:
		push_error("[Bootstrap] Failed to start server: %s" % error_string(err))
		return


	_add_managers()
	GameManager.change_state(GameManager.GameState.IN_GAME)
	call_deferred("_spawn_player")

func _add_managers() -> void:
	for path in _MANAGER_SCRIPTS:
		var scr := load(path) as GDScript
		if scr:
			add_child(scr.new())
		else:
			push_warning("[Bootstrap] Manager script not found: %s" % path)

func _spawn_player() -> void:
	var scene := load("res://scenes/game/PlayerCharacter.tscn") as PackedScene
	if not scene:
		push_error("[Bootstrap] PlayerCharacter.tscn not found")
		return

	var player := scene.instantiate() as PlayerCharacter
	player.name = "1"
	player.character_name = "Testatore"
	player.character_class = character_class
	player.faction = character_faction
	player.level = character_level
	player.global_position = spawn_position
	add_child(player)

	GameManager.register_player(1, player)  # also emits character_spawned
	print("[Bootstrap] Player spawned: %s lv%d (%s)" % [
		player.character_name, player.level,
		GameManager.faction_name(player.faction)
	])
