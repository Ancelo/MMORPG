## Base class for all characters (players and NPCs).
## Handles movement, combat state, status effects, and network replication.
class_name Character
extends CharacterBody3D

signal died()
signal respawned()
signal target_acquired(target: Node)
signal target_lost()

# Identity
@export var character_name: String = "Unknown"
@export var character_class: String = ""
@export var faction: GameManager.Faction = GameManager.Faction.NONE
@export var level: int = 1

# Components
@onready var stats: CharacterStats = CharacterStats.new()
@onready var ability_manager: Node = $AbilityManager
@onready var inventory: Node = $Inventory
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var mesh_root: Node3D = $MeshRoot
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var nameplate_anchor: Node3D = $NameplateAnchor

# Combat state
var current_target: Character = null
var is_in_combat: bool = false
var _combat_timer: float = 0.0
const COMBAT_TIMEOUT := 10.0

# Movement
const GRAVITY := -20.0
var move_direction: Vector3 = Vector3.ZERO
var _velocity_y: float = 0.0

# Status effects
var status_effects: Dictionary = {}  # effect_id -> {data, timer}

# XP & progression
var experience: int = 0
var experience_to_next: int = 1000

# Death / respawn
var is_dead: bool = false
var respawn_timer: float = 0.0
var respawn_point: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("characters")
	stats.level = level
	stats.compute_from_primary()
	stats.current_health = stats.max_health
	stats.current_endurance = stats.max_endurance
	stats.current_power = stats.max_power
	_load_class_data()
	_setup_regen()
	call_deferred("_setup_nameplate")

func _setup_nameplate() -> void:
	if not nameplate_anchor:
		return
	var nameplate := nameplate_anchor.get_node_or_null("Nameplate")
	if nameplate and nameplate.has_method("setup"):
		nameplate.setup(self)

func _load_class_data() -> void:
	if character_class.is_empty():
		return
	var class_data := DataManager.get_class_data(character_class)
	if class_data.is_empty():
		return
	stats.strength     = class_data.get("base_strength", 10)
	stats.dexterity    = class_data.get("base_dexterity", 10)
	stats.constitution = class_data.get("base_constitution", 10)
	stats.intelligence = class_data.get("base_intelligence", 10)
	stats.piety        = class_data.get("base_piety", 10)
	stats.charisma     = class_data.get("base_charisma", 10)
	stats.speed        = class_data.get("base_speed", 5.0)
	stats.compute_from_primary()

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_process_gravity(delta)
	_process_movement(delta)
	_process_combat_timer(delta)
	_process_status_effects(delta)

func _process_gravity(delta: float) -> void:
	if not is_on_floor():
		_velocity_y += GRAVITY * delta
	else:
		_velocity_y = -1.0

func _process_movement(delta: float) -> void:
	var horizontal := move_direction * stats.speed
	velocity = Vector3(horizontal.x, _velocity_y, horizontal.z)
	move_and_slide()

func _process_combat_timer(delta: float) -> void:
	if is_in_combat:
		_combat_timer += delta
		if _combat_timer >= COMBAT_TIMEOUT:
			leave_combat()

func _process_status_effects(delta: float) -> void:
	var expired: Array = []
	for effect_id in status_effects:
		var effect: Dictionary = status_effects[effect_id]
		effect["remaining"] -= delta
		# Tick damage/heal
		if effect.has("tick_interval"):
			effect["tick_acc"] = effect.get("tick_acc", 0.0) + delta
			if effect["tick_acc"] >= effect["tick_interval"]:
				effect["tick_acc"] -= effect["tick_interval"]
				_apply_effect_tick(effect)
		if effect["remaining"] <= 0.0:
			expired.append(effect_id)
	for id in expired:
		remove_status_effect(id)

func _apply_effect_tick(effect: Dictionary) -> void:
	if effect.has("dot_damage"):
		take_damage(effect["dot_damage"], effect.get("damage_type", "magic"), null)
	elif effect.has("hot_heal"):
		heal(effect["hot_heal"], null)

# ----- Combat -----

func enter_combat(aggressor: Character) -> void:
	is_in_combat = true
	_combat_timer = 0.0

func leave_combat() -> void:
	is_in_combat = false
	_combat_timer = 0.0

func set_target(new_target: Character) -> void:
	if new_target == current_target:
		return
	current_target = new_target
	if new_target:
		target_acquired.emit(new_target)
	else:
		target_lost.emit()

func take_damage(amount: int, damage_type: String, source: Character) -> int:
	if is_dead:
		return 0

	var mitigated := _calculate_mitigation(amount, damage_type)
	var actual := max(1, mitigated)

	enter_combat(source)
	var actual_delta := stats.modify_health(-actual)

	EventBus.damage_dealt.emit(source, self, actual, damage_type)

	if not stats.is_alive():
		die(source)

	return actual

func _calculate_mitigation(raw: int, damage_type: String) -> int:
	match damage_type:
		"physical":
			var mitigation := clampf(float(stats.armor) / float(stats.armor + 100 + level * 15), 0.0, 0.75)
			return int(raw * (1.0 - mitigation))
		"magic":
			var mitigation := clampf(float(stats.magic_resist) / 300.0, 0.0, 0.60)
			return int(raw * (1.0 - mitigation))
		_:
			return raw

func heal(amount: int, source: Character) -> int:
	if is_dead:
		return 0
	var actual := stats.modify_health(amount)
	EventBus.heal_applied.emit(source, self, actual)
	return actual

func die(killer: Character) -> void:
	if is_dead:
		return
	is_dead = true
	leave_combat()
	current_target = null
	status_effects.clear()
	died.emit()
	EventBus.character_died.emit(self)
	_on_death(killer)

func _on_death(killer: Character) -> void:
	pass  # Override in subclasses

func respawn() -> void:
	is_dead = false
	stats.current_health = stats.max_health
	stats.current_endurance = stats.max_endurance
	stats.current_power = stats.max_power
	global_position = respawn_point
	respawned.emit()
	EventBus.character_respawned.emit(self)

# ----- Status effects -----

func apply_status_effect(effect_id: String, effect_data: Dictionary) -> void:
	status_effects[effect_id] = effect_data.duplicate(true)
	status_effects[effect_id]["remaining"] = effect_data.get("duration", 5.0)

	if effect_data.has("stat_modifiers"):
		stats.add_modifier(effect_id, effect_data["stat_modifiers"])

	EventBus.status_effect_applied.emit(self, effect_id, effect_data.get("duration", 5.0))

func remove_status_effect(effect_id: String) -> void:
	if not status_effects.has(effect_id):
		return
	var effect := status_effects[effect_id]
	if effect.has("stat_modifiers"):
		stats.remove_modifier(effect_id)
	status_effects.erase(effect_id)
	EventBus.status_effect_removed.emit(self, effect_id)

func has_status_effect(effect_id: String) -> bool:
	return status_effects.has(effect_id)

# ----- Regen -----

func _setup_regen() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_regen_tick)
	add_child(timer)

func _on_regen_tick() -> void:
	if is_dead or is_in_combat:
		return
	stats.modify_health(int(stats.regen_health))
	stats.modify_endurance(int(stats.regen_endurance))
	stats.modify_power(int(stats.regen_power))

# ----- Serialization (for network state) -----

func get_network_state() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"rot": rotation.y,
		"vel": [velocity.x, velocity.y, velocity.z],
		"hp":  stats.current_health,
		"ep":  stats.current_endurance,
		"pp":  stats.current_power,
		"dead": is_dead,
		"combat": is_in_combat,
		"effects": status_effects.keys(),
	}

func apply_server_state(state: Dictionary) -> void:
	if state.has("pos"):
		var p: Array = state["pos"]
		global_position = Vector3(p[0], p[1], p[2])
	if state.has("rot"):
		rotation.y = state["rot"]
	if state.has("hp"):
		stats.current_health = state["hp"]
	if state.has("ep"):
		stats.current_endurance = state["ep"]
	if state.has("pp"):
		stats.current_power = state["pp"]
	if state.get("dead", false) and not is_dead:
		die(null)
