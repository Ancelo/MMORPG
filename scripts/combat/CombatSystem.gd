## Server-side combat resolution: hit/miss, crits, parry, block, evade.
## All combat math runs here so clients cannot cheat.
class_name CombatSystem
extends Node

const CRIT_DAMAGE_MULTIPLIER := 1.75
const CRIT_BASE_CHANCE := 0.05        # 5% base
const LEVEL_DIFFERENCE_PENALTY := 0.05  # per level above attacker

static func resolve_hit(attacker: Character, defender: Character, base_damage: int, damage_type: String) -> Dictionary:
	var result := {
		"hit": false,
		"damage": 0,
		"crit": false,
		"parried": false,
		"blocked": false,
		"evaded": false,
		"resisted": false,
		"damage_type": damage_type,
	}

	# Evade check
	if randf() < defender.stats.evade_chance:
		result["evaded"] = true
		return result

	# Parry check (melee only)
	if damage_type in ["physical", "slashing", "blunt", "piercing"]:
		if randf() < defender.stats.parry_chance:
			result["parried"] = true
			return result

	# Block check
	if randf() < defender.stats.block_chance:
		result["blocked"] = true
		base_damage = int(base_damage * 0.3)

	# Level difference modifier
	var level_diff := defender.level - attacker.level
	var level_modifier := 1.0 - (max(0, level_diff) * LEVEL_DIFFERENCE_PENALTY)
	base_damage = int(base_damage * level_modifier)

	# Crit check
	var crit_chance := CRIT_BASE_CHANCE + (attacker.stats.dexterity - 10) * 0.002
	var is_crit := randf() < clampf(crit_chance, 0.0, 0.50)
	if is_crit:
		base_damage = int(base_damage * CRIT_DAMAGE_MULTIPLIER)
		result["crit"] = true

	result["hit"] = true
	result["damage"] = max(1, base_damage)
	return result

static func resolve_heal(healer: Character, base_heal: int) -> int:
	var variance := randf_range(-0.10, 0.10)
	return max(1, int(base_heal * (1.0 + variance)))

static func calculate_xp_reward(killed: Character, killer: Character) -> int:
	var base_xp: int = 10 + killed.level * 5
	var level_diff := killed.level - killer.level
	if level_diff > 0:
		base_xp = int(base_xp * (1.0 + level_diff * 0.15))
	elif level_diff < -10:
		return 0  # trivial kill
	return base_xp

static func calculate_rvr_reward_points(killed: Character, killer: Character) -> int:
	if not GameManager.is_enemy(killer.faction, killed.faction):
		return 0
	var base_points := 10 + killed.level * 2
	return base_points
