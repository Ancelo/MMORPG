## Handles NPC spawn cycles within a zone. Respawns after configurable delays.
class_name SpawnManager
extends Node

@export var spawn_groups: Array[Dictionary] = []

# Runtime: spawn_group_id -> list of active NPC nodes
var _active_npcs: Dictionary = {}
var _respawn_timers: Dictionary = {}  # spawn_group_id -> remaining seconds

func _ready() -> void:
	for group in spawn_groups:
		_active_npcs[group["id"]] = []
	_initial_spawn_all()

func _process(delta: float) -> void:
	for group_id in _respawn_timers.keys():
		_respawn_timers[group_id] -= delta
		if _respawn_timers[group_id] <= 0.0:
			_respawn_timers.erase(group_id)
			_spawn_group(group_id)

func _initial_spawn_all() -> void:
	for group in spawn_groups:
		_spawn_group(group["id"])

func _spawn_group(group_id: String) -> void:
	var group := _find_group(group_id)
	if not group:
		return
	var count: int = group.get("count", 1)
	var npc_scene_path: String = group.get("npc_scene", "")
	if npc_scene_path.is_empty():
		return
	var npc_scene := load(npc_scene_path) as PackedScene
	if not npc_scene:
		push_warning("[SpawnManager] Cannot load NPC scene: %s" % npc_scene_path)
		return
	var spawned: Array = []
	for i in range(count):
		var npc := npc_scene.instantiate()
		var spawn_pos := _pick_spawn_position(group)
		npc.global_position = spawn_pos
		npc.respawn_point = spawn_pos
		get_parent().add_child(npc)
		npc.died.connect(func(): _on_npc_died(group_id, npc))
		spawned.append(npc)
	_active_npcs[group_id] = spawned

func _on_npc_died(group_id: String, npc: Node) -> void:
	var group := _find_group(group_id)
	if not group:
		return
	_active_npcs[group_id].erase(npc)
	var respawn_delay: float = group.get("respawn_seconds", 60.0)
	_respawn_timers[group_id] = respawn_delay

func _find_group(group_id: String) -> Dictionary:
	for g in spawn_groups:
		if g["id"] == group_id:
			return g
	return {}

func _pick_spawn_position(group: Dictionary) -> Vector3:
	var center: Array = group.get("center", [0.0, 0.0, 0.0])
	var radius: float = group.get("radius", 5.0)
	var angle := randf() * TAU
	var dist := sqrt(randf()) * radius
	return Vector3(
		center[0] + cos(angle) * dist,
		center[1],
		center[2] + sin(angle) * dist
	)
