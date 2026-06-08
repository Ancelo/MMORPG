## A destructible wall section on a Keep. Breaching creates a path for attackers.
class_name KeepWall
extends StaticBody3D

signal wall_breached(wall: KeepWall)
signal health_changed(current: int, maximum: int)

@export var wall_id: String = "wall_north"
@export var display_name: String = "Mura Nord"
@export var max_health: int = 8000
@export var repair_rate: float = 5.0
@export var is_outer_wall: bool = true

var current_health: int = max_health
var is_breached: bool = false
var owner_faction: GameManager.Faction = GameManager.Faction.NONE

@onready var wall_mesh: MeshInstance3D    = $WallMesh
@onready var rubble_mesh: MeshInstance3D  = $RubbleMesh
@onready var collision: CollisionShape3D  = $CollisionShape3D

func _ready() -> void:
	rubble_mesh.visible = false
	add_to_group("keep_walls")

func _process(delta: float) -> void:
	if not multiplayer.is_server() or is_breached:
		return
	if owner_faction == GameManager.Faction.NONE:
		return
	if not _has_nearby_enemy():
		current_health = min(max_health, current_health + int(repair_rate * delta))
		health_changed.emit(current_health, max_health)

func take_damage(amount: int, attacker_faction: GameManager.Faction) -> void:
	if not multiplayer.is_server() or is_breached:
		return
	if attacker_faction == owner_faction:
		return
	current_health = max(0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		_breach()

func _breach() -> void:
	is_breached = true
	collision.disabled = true
	wall_mesh.visible = false
	rubble_mesh.visible = true
	wall_breached.emit(self)
	EventBus.notification_pushed.emit("%s è stata abbattuta!" % display_name, "keep_assault")

func repair_fully() -> void:
	is_breached = false
	current_health = max_health
	collision.disabled = false
	wall_mesh.visible = true
	rubble_mesh.visible = false
	health_changed.emit(current_health, max_health)

func _has_nearby_enemy() -> bool:
	for character in get_tree().get_nodes_in_group("characters"):
		var c := character as Character
		if not c or c.is_dead:
			continue
		if GameManager.is_enemy(owner_faction, c.faction) and \
		   global_position.distance_to(c.global_position) <= 30.0:
			return true
	return false

func health_percent() -> float:
	return float(current_health) / float(max_health) if max_health > 0 else 0.0
