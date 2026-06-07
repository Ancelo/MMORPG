## Manages all character stats with support for buffs, debuffs, and equipment bonuses.
class_name CharacterStats
extends Resource

signal stat_changed(stat_name: String, old_value: float, new_value: float)
signal health_changed(current: int, maximum: int)
signal endurance_changed(current: int, maximum: int)
signal power_changed(current: int, maximum: int)

# --- Primary stats ---
@export var strength: int = 10       # Melee damage
@export var dexterity: int = 10      # Ranged damage, parry chance
@export var constitution: int = 10   # Health pool
@export var intelligence: int = 10   # Magic damage / power pool
@export var piety: int = 10          # Healing power, divine power
@export var charisma: int = 10       # Social abilities, minstrel songs

# --- Derived stats (computed) ---
var max_health: int = 100
var max_endurance: int = 100
var max_power: int = 100

var current_health: int = 100
var current_endurance: int = 100
var current_power: int = 100

var melee_damage_bonus: int = 0
var ranged_damage_bonus: int = 0
var magic_damage_bonus: int = 0
var healing_bonus: int = 0

var armor: int = 0
var magic_resist: int = 0
var parry_chance: float = 0.0       # 0.0 - 1.0
var block_chance: float = 0.0
var evade_chance: float = 0.0

var speed: float = 5.0              # m/s base movement
var attack_speed: float = 1.0       # attacks per second
var cast_speed_modifier: float = 1.0

var regen_health: float = 1.0       # HP per second
var regen_endurance: float = 2.0
var regen_power: float = 0.5

# --- Level scaling ---
var level: int = 1

# Active modifiers from buffs/equipment
var _modifiers: Dictionary = {}

func compute_from_primary() -> void:
	max_health     = constitution * 20 + level * 10
	max_endurance  = constitution * 5 + 80
	max_power      = (intelligence + piety) * 8 + level * 5

	melee_damage_bonus  = (strength - 10) * 2
	ranged_damage_bonus = (dexterity - 10) * 2
	magic_damage_bonus  = (intelligence - 10) * 2
	healing_bonus       = (piety - 10) * 2

	parry_chance = clampf((dexterity - 10) * 0.005, 0.0, 0.35)
	regen_health = 1.0 + constitution * 0.05

	current_health    = min(current_health, max_health)
	current_endurance = min(current_endurance, max_endurance)
	current_power     = min(current_power, max_power)

func add_modifier(id: String, modifiers: Dictionary) -> void:
	_modifiers[id] = modifiers
	_apply_all_modifiers()

func remove_modifier(id: String) -> void:
	_modifiers.erase(id)
	_apply_all_modifiers()

func _apply_all_modifiers() -> void:
	compute_from_primary()
	for mod in _modifiers.values():
		for key in mod:
			if key in self:
				set(key, get(key) + mod[key])

func modify_health(delta: int) -> int:
	var old := current_health
	current_health = clampi(current_health + delta, 0, max_health)
	if current_health != old:
		health_changed.emit(current_health, max_health)
	return current_health - old

func modify_endurance(delta: int) -> void:
	current_endurance = clampi(current_endurance + delta, 0, max_endurance)
	endurance_changed.emit(current_endurance, max_endurance)

func modify_power(delta: int) -> void:
	current_power = clampi(current_power + delta, 0, max_power)
	power_changed.emit(current_power, max_power)

func is_alive() -> bool:
	return current_health > 0

func health_percent() -> float:
	if max_health == 0:
		return 0.0
	return float(current_health) / float(max_health)

func to_dict() -> Dictionary:
	return {
		"strength": strength, "dexterity": dexterity, "constitution": constitution,
		"intelligence": intelligence, "piety": piety, "charisma": charisma,
		"current_health": current_health, "max_health": max_health,
		"current_endurance": current_endurance, "max_endurance": max_endurance,
		"current_power": current_power, "max_power": max_power,
		"level": level, "speed": speed,
	}

func from_dict(d: Dictionary) -> void:
	for key in d:
		if key in self:
			set(key, d[key])
