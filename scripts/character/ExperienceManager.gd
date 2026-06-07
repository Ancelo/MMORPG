## Handles XP gain, level-up logic, and ability unlocking per level.
class_name ExperienceManager
extends Node

const XP_BASE := 1000
const XP_SCALING := 1.15  # multiplier per level

var _character: Character

func _ready() -> void:
	_character = get_parent() as Character
	EventBus.xp_gained.connect(_on_xp_gained)

func _on_xp_gained(amount: int, total: int, level: int) -> void:
	if not _character or _character.level != level:
		return
	_character.experience += amount
	_check_level_up()

func add_xp(amount: int) -> void:
	if not _character or _character.is_dead:
		return
	_character.experience += amount
	EventBus.xp_gained.emit(amount, _character.experience, _character.level)
	_check_level_up()

func _check_level_up() -> void:
	while _character.level < GameManager.MAX_LEVEL:
		var needed := xp_for_level(_character.level + 1)
		if _character.experience < needed:
			break
		_character.experience -= needed
		_level_up()

func _level_up() -> void:
	_character.level += 1
	_character.stats.level = _character.level
	_character.stats.compute_from_primary()

	# Restore vitals on level up
	_character.stats.current_health    = _character.stats.max_health
	_character.stats.current_endurance = _character.stats.max_endurance
	_character.stats.current_power     = _character.stats.max_power

	_unlock_abilities_for_level(_character.level)

	EventBus.level_up.emit(_character.level, _character.character_class)
	EventBus.notification_pushed.emit(
		"LEVEL UP! Sei ora al livello %d!" % _character.level,
		"level_up"
	)

func _unlock_abilities_for_level(new_level: int) -> void:
	var class_data := DataManager.get_class_data(_character.character_class)
	for unlock in class_data.get("abilities_unlocked", []):
		if unlock.get("level", 0) == new_level:
			var ability_id: String = unlock.get("ability_id", "")
			if ability_id.is_empty():
				continue
			if _character.get_node_or_null("AbilityManager"):
				var learned := _character.get_node("AbilityManager").learn_ability(ability_id)
				if learned:
					var ability_data := DataManager.get_ability(ability_id)
					EventBus.notification_pushed.emit(
						"Nuova abilità appresa: %s!" % ability_data.get("name", ability_id),
						"ability_learned"
					)
					_auto_assign_hotbar(ability_id)

func _auto_assign_hotbar(ability_id: String) -> void:
	var am := _character.get_node_or_null("AbilityManager") as AbilityManager
	if not am:
		return
	for i in range(AbilityManager.HOTBAR_SLOTS):
		if am.get_slot_ability(i).is_empty():
			am.assign_hotbar(i, ability_id)
			return

func xp_for_level(level: int) -> int:
	return int(XP_BASE * pow(XP_SCALING, level - 1))

func xp_progress() -> float:
	if _character.level >= GameManager.MAX_LEVEL:
		return 1.0
	var needed := xp_for_level(_character.level + 1)
	if needed == 0:
		return 1.0
	return float(_character.experience) / float(needed)
