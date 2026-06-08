## A destructible gate on a Keep. Can only be damaged by siege weapons or melee.
## Repairs slowly when unchallenged and owned by a faction.
class_name KeepGate
extends StaticBody3D

signal gate_broken(gate: KeepGate)
signal gate_repaired(gate: KeepGate)
signal health_changed(current: int, maximum: int)

enum GateState { INTACT, DAMAGED, BROKEN }

@export var gate_id: String = "main_gate"
@export var display_name: String = "Portone Principale"
@export var max_health: int = 5000
@export var repair_rate: float = 10.0  # HP per second when no attacker nearby
@export var repair_range: float = 20.0 # no repair if enemy within this range

var current_health: int = max_health
var state: GateState = GateState.INTACT
var owner_faction: GameManager.Faction = GameManager.Faction.NONE

@onready var mesh: MeshInstance3D     = $GateMesh
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var broken_mesh: MeshInstance3D = $BrokenGateMesh

func _ready() -> void:
	broken_mesh.visible = false
	add_to_group("keep_gates")

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if state == GateState.BROKEN:
		return
	if owner_faction == GameManager.Faction.NONE:
		return
	if _has_nearby_enemy():
		return
	_repair(delta)

func take_damage(amount: int, attacker_faction: GameManager.Faction) -> void:
	if not multiplayer.is_server():
		return
	if state == GateState.BROKEN:
		return
	if attacker_faction == owner_faction:
		return  # can't damage your own gate

	current_health = max(0, current_health - amount)
	health_changed.emit(current_health, max_health)

	if current_health == 0:
		_break()
	elif current_health < max_health * 0.5:
		state = GateState.DAMAGED
		_update_visual()

func _break() -> void:
	state = GateState.BROKEN
	collision.disabled = true
	mesh.visible = false
	broken_mesh.visible = true
	gate_broken.emit(self)
	EventBus.notification_pushed.emit(
		"%s è stato abbattuto!" % display_name, "keep_assault"
	)

func repair_fully() -> void:
	current_health = max_health
	state = GateState.INTACT
	collision.disabled = false
	mesh.visible = true
	broken_mesh.visible = false
	health_changed.emit(current_health, max_health)
	gate_repaired.emit(self)

func _repair(delta: float) -> void:
	var old := current_health
	current_health = min(max_health, current_health + int(repair_rate * delta))
	if current_health != old:
		health_changed.emit(current_health, max_health)
	if current_health >= max_health:
		state = GateState.INTACT
		_update_visual()

func _update_visual() -> void:
	match state:
		GateState.INTACT:
			mesh.modulate = Color.WHITE
		GateState.DAMAGED:
			mesh.modulate = Color(0.8, 0.5, 0.3)

func _has_nearby_enemy() -> bool:
	for character in get_tree().get_nodes_in_group("characters"):
		var c := character as Character
		if not c or c.is_dead:
			continue
		if GameManager.is_enemy(owner_faction, c.faction):
			if global_position.distance_to(c.global_position) <= repair_range:
				return true
	return false

func health_percent() -> float:
	return float(current_health) / float(max_health) if max_health > 0 else 0.0

func is_broken() -> bool:
	return state == GateState.BROKEN
