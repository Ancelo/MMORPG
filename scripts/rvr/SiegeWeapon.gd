## Base class for all siege weapons. Interactable by players; deals heavy structure damage.
class_name SiegeWeapon
extends Node3D

signal fired(weapon: SiegeWeapon)

enum SiegeType { TREBUCHET, BALLISTA, BATTERING_RAM, BOILING_OIL }

@export var siege_type: SiegeType = SiegeType.TREBUCHET
@export var display_name: String  = "Trebuchet"
@export var max_operators: int    = 2
@export var structure_damage: int = 500    # damage to gates/walls per shot
@export var player_damage: int    = 200    # AoE damage to players
@export var area_radius: float    = 8.0
@export var reload_time: float    = 8.0
@export var max_range: float      = 150.0
@export var min_range: float      = 20.0
@export var deploy_time: float    = 3.0    # seconds to set up

var operators: Array = []       # peer_ids currently operating
var owner_faction: GameManager.Faction = GameManager.Faction.NONE
var is_deployed: bool = false
var _reload_timer: float = 0.0
var _deploy_timer: float = 0.0

@onready var interaction_area: Area3D      = $InteractionArea
@onready var aim_pivot: Node3D             = $AimPivot
@onready var projectile_spawn: Marker3D   = $AimPivot/ProjectileSpawn

func _ready() -> void:
	add_to_group("siege_weapons")

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_deployed:
		_deploy_timer -= delta
		if _deploy_timer <= 0.0:
			is_deployed = true
			_on_deployed()
		return
	if _reload_timer > 0.0:
		_reload_timer = maxf(0.0, _reload_timer - delta)

func try_operate(peer_id: int) -> bool:
	if operators.size() >= max_operators:
		return false
	if peer_id in operators:
		return false
	var c := GameManager.get_player(peer_id) as Character
	if not c:
		return false
	# Faction check — can only operate own or neutral siege weapons
	if owner_faction != GameManager.Faction.NONE and \
	   GameManager.is_enemy(owner_faction, c.faction):
		return false
	operators.append(peer_id)
	if owner_faction == GameManager.Faction.NONE:
		owner_faction = c.faction
	return true

func stop_operating(peer_id: int) -> void:
	operators.erase(peer_id)
	if operators.is_empty():
		owner_faction = GameManager.Faction.NONE

func can_fire() -> bool:
	return is_deployed and _reload_timer <= 0.0 and not operators.is_empty()

func fire(target_position: Vector3) -> void:
	if not can_fire() or not multiplayer.is_server():
		return
	_reload_timer = reload_time
	_execute_fire(target_position)
	fired.emit(self)

func _execute_fire(target: Vector3) -> void:
	match siege_type:
		SiegeType.TREBUCHET:
			_fire_trebuchet(target)
		SiegeType.BALLISTA:
			_fire_ballista(target)
		SiegeType.BATTERING_RAM:
			_swing_ram()
		SiegeType.BOILING_OIL:
			_pour_oil(target)

func _fire_trebuchet(target: Vector3) -> void:
	# AoE at target: damages structures AND players in radius
	_damage_structures_at(target, area_radius, structure_damage)
	_damage_players_at(target, area_radius, player_damage)
	EventBus.notification_pushed.emit("Il trebuchet lancia una pietra!", "siege")

func _fire_ballista(target: Vector3) -> void:
	# Piercing bolt — high player damage, some structure damage
	_damage_players_at(target, 2.0, player_damage * 2)
	_damage_structures_at(target, 2.0, structure_damage / 4)

func _swing_ram() -> void:
	# Battering ram — only damages gates, must be adjacent
	var gates := get_tree().get_nodes_in_group("keep_gates")
	for gate_node in gates:
		var gate := gate_node as KeepGate
		if not gate or gate.owner_faction == owner_faction:
			continue
		if global_position.distance_to(gate.global_position) <= 6.0:
			gate.take_damage(structure_damage, owner_faction)
			EventBus.notification_pushed.emit("Il ariete colpisce il portone!", "siege")
			return

func _pour_oil(target: Vector3) -> void:
	# Boiling oil — slow + DoT for players in area, no structure damage
	_damage_players_at(target, area_radius, player_damage / 2)
	for character in get_tree().get_nodes_in_group("characters"):
		var c := character as Character
		if not c or c.is_dead:
			continue
		if GameManager.is_enemy(owner_faction, c.faction):
			if c.global_position.distance_to(target) <= area_radius:
				c.apply_status_effect("olio_bollente", {
					"duration": 8.0, "tick_interval": 2.0,
					"dot_damage": 30, "damage_type": "fire",
					"stat_modifiers": {"speed": -2.0},
				})

func _damage_structures_at(origin: Vector3, radius: float, amount: int) -> void:
	for gate in get_tree().get_nodes_in_group("keep_gates"):
		var g := gate as KeepGate
		if g and g.global_position.distance_to(origin) <= radius:
			g.take_damage(amount, owner_faction)
	for wall in get_tree().get_nodes_in_group("keep_walls"):
		var w := wall as KeepWall
		if w and w.global_position.distance_to(origin) <= radius:
			w.take_damage(amount, owner_faction)

func _damage_players_at(origin: Vector3, radius: float, amount: int) -> void:
	for character in get_tree().get_nodes_in_group("characters"):
		var c := character as Character
		if not c or c.is_dead:
			continue
		if GameManager.is_enemy(owner_faction, c.faction):
			if c.global_position.distance_to(origin) <= radius:
				c.take_damage(amount, "physical", null)

func _on_deployed() -> void:
	EventBus.notification_pushed.emit("%s deployato!" % display_name, "siege")

func begin_deploy() -> void:
	is_deployed = false
	_deploy_timer = deploy_time
