## Represents a single ability/skill definition loaded from JSON data.
class_name Ability
extends Resource

enum TargetType { SELF, SINGLE_ENEMY, SINGLE_ALLY, AREA_ENEMY, AREA_ALLY, NONE }
enum DamageType { PHYSICAL, SLASHING, PIERCING, BLUNT, FIRE, COLD, SPIRIT, MATTER, ENERGY, BODY, MIND, DIVINE }

@export var ability_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var character_class: String = ""
@export var required_level: int = 1

@export var target_type: TargetType = TargetType.SINGLE_ENEMY
@export var range_max: float = 2.5      # meters (melee ~2.5, ranged ~30)
@export var area_radius: float = 0.0   # for AoE abilities
@export var cast_time: float = 0.0     # 0 = instant
@export var cooldown: float = 0.0
@export var reuse_timer: float = 0.0   # extra lockout after cast
@export var power_cost: int = 0
@export var endurance_cost: int = 0

# Damage/heal values (before stat modifiers)
@export var base_damage: int = 0
@export var base_heal: int = 0
@export var damage_type: String = "physical"
@export var stat_coefficient: float = 1.0  # multiplier applied to relevant stat

# Status effects to apply on hit
@export var apply_effects: Array = []  # Array of effect_id strings

# Visual / audio
@export var projectile_scene: String = ""
@export var impact_effect: String = ""
@export var cast_animation: String = "cast"
@export var hit_animation: String = "hit"

static func from_dict(data: Dictionary) -> Ability:
	var a := Ability.new()
	a.ability_id     = data.get("id", "")
	a.display_name   = data.get("name", "")
	a.description    = data.get("description", "")
	a.icon_path      = data.get("icon", "")
	a.character_class = data.get("class_id", "")
	a.required_level = data.get("required_level", 1)
	a.target_type    = TargetType[data.get("target_type", "SINGLE_ENEMY").to_upper()]
	a.range_max      = data.get("range", 2.5)
	a.area_radius    = data.get("area_radius", 0.0)
	a.cast_time      = data.get("cast_time", 0.0)
	a.cooldown       = data.get("cooldown", 0.0)
	a.power_cost     = data.get("power_cost", 0)
	a.endurance_cost = data.get("endurance_cost", 0)
	a.base_damage    = data.get("base_damage", 0)
	a.base_heal      = data.get("base_heal", 0)
	a.damage_type    = data.get("damage_type", "physical")
	a.stat_coefficient = data.get("stat_coefficient", 1.0)
	a.apply_effects  = data.get("apply_effects", [])
	a.projectile_scene = data.get("projectile_scene", "")
	a.cast_animation = data.get("cast_animation", "cast")
	return a

func calculate_damage(caster_stats: CharacterStats) -> int:
	if base_damage <= 0:
		return 0
	var stat_bonus: int = 0
	match damage_type:
		"physical", "slashing", "blunt", "piercing":
			stat_bonus = caster_stats.melee_damage_bonus
		"fire", "cold", "spirit", "energy":
			stat_bonus = caster_stats.magic_damage_bonus
		"divine":
			stat_bonus = caster_stats.healing_bonus
	var raw := int((base_damage + stat_bonus) * stat_coefficient)
	# ±15% variance
	var variance := randf_range(-0.15, 0.15)
	return max(1, int(raw * (1.0 + variance)))

func calculate_heal(caster_stats: CharacterStats) -> int:
	if base_heal <= 0:
		return 0
	var raw := int((base_heal + caster_stats.healing_bonus) * stat_coefficient)
	var variance := randf_range(-0.10, 0.10)
	return max(1, int(raw * (1.0 + variance)))

func is_melee() -> bool:
	return range_max <= 3.0

func is_instant() -> bool:
	return cast_time <= 0.0
