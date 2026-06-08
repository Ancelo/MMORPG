## The full keep structure: walls, gates, towers, lord room and NPC guards.
## Central authority for keep ownership and assault state transitions.
class_name KeepStructure
extends Node3D

signal ownership_changed(keep_id: String, old_faction: GameManager.Faction, new_faction: GameManager.Faction)
signal assault_started(attacking_faction: GameManager.Faction)
signal assault_ended(result: String)  # "captured" | "repelled"
signal keep_lord_died(keep_id: String)

enum AssaultState { PEACEFUL, CONTESTED, UNDER_ASSAULT, INNER_BREACH }

@export var keep_id: String   = "keep_rhenus"
@export var keep_name: String = "Fortezza del Reno"
@export var max_guards: int   = 12
@export var guard_scene: String = "res://scenes/characters/KeepGuard.tscn"
@export var lord_scene: String  = "res://scenes/characters/KeepLord.tscn"

var owner_faction: GameManager.Faction = GameManager.Faction.NONE
var assault_state: AssaultState = AssaultState.PEACEFUL
var _attacking_faction: GameManager.Faction = GameManager.Faction.NONE
var _assault_timer: float = 0.0
const ASSAULT_TIMEOUT := 300.0  # 5 min without attack → repelled

# Child structure nodes (assigned from scene or found by group)
var outer_gates: Array = []
var inner_gate: KeepGate = null
var outer_walls: Array = []
var inner_walls: Array = []
var keep_lord: Character = null
var _guards: Array = []
var _siege_weapons: Array = []

func _ready() -> void:
	add_to_group("keep_structures")
	_collect_structure_nodes()
	_connect_structure_signals()
	_spawn_guards()
	_spawn_siege_weapons()

func _collect_structure_nodes() -> void:
	for node in get_children():
		if node is KeepGate:
			var gate := node as KeepGate
			gate.owner_faction = owner_faction
			if gate.gate_id == "inner_gate":
				inner_gate = gate
			else:
				outer_gates.append(gate)
		elif node is KeepWall:
			var wall := node as KeepWall
			wall.owner_faction = owner_faction
			if wall.is_outer_wall:
				outer_walls.append(wall)
			else:
				inner_walls.append(wall)
		elif node is SiegeWeapon:
			_siege_weapons.append(node)

func _connect_structure_signals() -> void:
	for gate in outer_gates:
		(gate as KeepGate).gate_broken.connect(_on_outer_gate_broken)
	if inner_gate:
		inner_gate.gate_broken.connect(_on_inner_gate_broken)
	for wall in outer_walls:
		(wall as KeepWall).wall_breached.connect(_on_wall_breached)

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	match assault_state:
		AssaultState.CONTESTED, AssaultState.UNDER_ASSAULT, AssaultState.INNER_BREACH:
			_assault_timer -= delta
			if _assault_timer <= 0.0:
				_end_assault("repelled")
		AssaultState.PEACEFUL:
			_check_for_attackers()

func _check_for_attackers() -> void:
	for character in get_tree().get_nodes_in_group("characters"):
		var c := character as Character
		if not c or c.is_dead or c is NPCCharacter:
			continue
		if not GameManager.is_enemy(owner_faction, c.faction):
			continue
		if global_position.distance_to(c.global_position) <= 80.0:
			_begin_assault(c.faction)
			return

# ----- Assault lifecycle -----

func _begin_assault(attacker: GameManager.Faction) -> void:
	assault_state = AssaultState.CONTESTED
	_attacking_faction = attacker
	_assault_timer = ASSAULT_TIMEOUT
	assault_started.emit(attacker)
	_announce("[ASSEDIO] %s attacca %s!" % [
		GameManager.faction_name(attacker), keep_name
	])
	_alert_defenders()

func _on_outer_gate_broken(_gate: KeepGate) -> void:
	assault_state = AssaultState.UNDER_ASSAULT
	_assault_timer = ASSAULT_TIMEOUT
	_announce("[ASSEDIO] Il portone esterno di %s è stato abbattuto!" % keep_name)

func _on_wall_breached(_wall: KeepWall) -> void:
	if assault_state == AssaultState.PEACEFUL:
		_begin_assault(_attacking_faction)
	_assault_timer = ASSAULT_TIMEOUT
	_announce("[ASSEDIO] Le mura di %s sono state violate!" % keep_name)

func _on_inner_gate_broken(_gate: KeepGate) -> void:
	assault_state = AssaultState.INNER_BREACH
	_assault_timer = ASSAULT_TIMEOUT
	_announce("[ASSEDIO] Il portone interno di %s è caduto! Il Lord è vulnerabile!" % keep_name)
	_spawn_keep_lord()

func _on_keep_lord_died(_lord: Character) -> void:
	keep_lord = null
	_capture_keep(_attacking_faction)

func _capture_keep(new_owner: GameManager.Faction) -> void:
	var old_owner := owner_faction
	owner_faction = new_owner
	_set_all_factions(new_owner)
	_repair_all()
	_despawn_guards()
	_spawn_guards()
	_end_assault("captured")
	ownership_changed.emit(keep_id, old_owner, new_owner)
	keep_lord_died.emit(keep_id)
	_announce("[ASSEDIO] %s ha conquistato %s!" % [
		GameManager.faction_name(new_owner), keep_name
	])
	var rvr := get_tree().get_first_node_in_group("rvr_manager") as RvRManager
	if rvr:
		rvr._capture_objective(keep_id, new_owner)

func _end_assault(result: String) -> void:
	assault_state = AssaultState.PEACEFUL
	_attacking_faction = GameManager.Faction.NONE
	_assault_timer = 0.0
	assault_ended.emit(result)
	if result == "repelled":
		_announce("[ASSEDIO] L'assalto a %s è stato respinto!" % keep_name)
		_repair_all()

# ----- Guards -----

func _spawn_guards() -> void:
	if guard_scene.is_empty():
		return
	var packed := load(guard_scene) as PackedScene
	if not packed:
		return
	var spawn_points := get_tree().get_nodes_in_group("keep_guard_spawns_%s" % keep_id)
	var count := min(max_guards, spawn_points.size() if not spawn_points.is_empty() else max_guards)
	for i in range(count):
		var guard := packed.instantiate() as NPCCharacter
		guard.faction = owner_faction
		guard.character_name = "Guardia di %s" % keep_name
		guard.level = 40  # keeps have strong guards
		var pos := Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
		if i < spawn_points.size():
			pos = (spawn_points[i] as Node3D).global_position
		guard.global_position = global_position + pos
		guard.respawn_point = guard.global_position
		add_child(guard)
		_guards.append(guard)

func _spawn_keep_lord() -> void:
	if lord_scene.is_empty():
		return
	var packed := load(lord_scene) as PackedScene
	if not packed:
		return
	keep_lord = packed.instantiate() as Character
	keep_lord.faction = owner_faction
	keep_lord.character_name = "Lord di %s" % keep_name
	keep_lord.level = 50
	keep_lord.global_position = global_position
	add_child(keep_lord)
	keep_lord.died.connect(func(): _on_keep_lord_died(keep_lord))
	_announce("[ASSEDIO] Il Lord di %s è entrato in battaglia!" % keep_name)

func _despawn_guards() -> void:
	for guard in _guards:
		if is_instance_valid(guard):
			guard.queue_free()
	_guards.clear()
	if keep_lord and is_instance_valid(keep_lord):
		keep_lord.queue_free()
		keep_lord = null

func _set_all_factions(faction: GameManager.Faction) -> void:
	for gate in outer_gates:
		(gate as KeepGate).owner_faction = faction
	if inner_gate:
		inner_gate.owner_faction = faction
	for wall in outer_walls + inner_walls:
		(wall as KeepWall).owner_faction = faction

func _repair_all() -> void:
	for gate in outer_gates:
		(gate as KeepGate).repair_fully()
	if inner_gate:
		inner_gate.repair_fully()
	for wall in outer_walls + inner_walls:
		(wall as KeepWall).repair_fully()

func _alert_defenders() -> void:
	for character in get_tree().get_nodes_in_group("characters"):
		var c := character as Character
		if c and c.faction == owner_faction:
			EventBus.notification_pushed.emit(
				"[ASSEDIO] %s è sotto attacco!" % keep_name, "keep_alert"
			)
			break

func _announce(message: String) -> void:
	EventBus.notification_pushed.emit(message, "keep_assault")

# ----- Siege weapon interaction -----

func get_available_siege_weapons(faction: GameManager.Faction) -> Array:
	var result: Array = []
	for weapon in _siege_weapons:
		var sw := weapon as SiegeWeapon
		if sw and (sw.owner_faction == faction or sw.owner_faction == GameManager.Faction.NONE):
			result.append(sw)
	return result

# ----- State queries -----

func is_outer_wall_breached() -> bool:
	for gate in outer_gates:
		if (gate as KeepGate).is_broken():
			return true
	for wall in outer_walls:
		if (wall as KeepWall).is_breached:
			return true
	return false

func get_status_summary() -> Dictionary:
	return {
		"keep_id": keep_id,
		"name": keep_name,
		"owner": int(owner_faction),
		"assault_state": int(assault_state),
		"attacker": int(_attacking_faction),
		"outer_gate_hp": [
			(g as KeepGate).health_percent() for g in outer_gates
		],
		"inner_gate_hp": inner_gate.health_percent() if inner_gate else 1.0,
		"lord_alive": keep_lord != null and is_instance_valid(keep_lord),
	}
