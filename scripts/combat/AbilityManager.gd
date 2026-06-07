## Manages a character's available abilities, cooldowns, hotbar, and casting.
class_name AbilityManager
extends Node

signal cast_started(ability: Ability, cast_time: float)
signal cast_completed(ability: Ability)
signal cast_interrupted()
signal cooldown_updated(ability_id: String, remaining: float, total: float)

const HOTBAR_SLOTS := 10

var _owner_character: Character
var _available_abilities: Dictionary = {}   # id -> Ability
var _cooldowns: Dictionary = {}             # id -> remaining seconds
var _hotbar: Array = []                     # 10 slots, each: ability_id or ""
var _casting: Dictionary = {}              # {ability, target, elapsed, total}

func _ready() -> void:
	_owner_character = get_parent() as Character
	_hotbar.resize(HOTBAR_SLOTS)
	_hotbar.fill("")
	_load_class_abilities()

func _process(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_cast(delta)

func _load_class_abilities() -> void:
	if not _owner_character:
		return
	var class_id := _owner_character.character_class
	var data_list := DataManager.get_abilities_for_class(class_id, _owner_character.level)
	for data in data_list:
		var ability := Ability.from_dict(data)
		_available_abilities[ability.ability_id] = ability

func learn_ability(ability_id: String) -> bool:
	var data := DataManager.get_ability(ability_id)
	if data.is_empty():
		return false
	var ability := Ability.from_dict(data)
	_available_abilities[ability_id] = ability
	return true

func assign_hotbar(slot: int, ability_id: String) -> void:
	if slot < 0 or slot >= HOTBAR_SLOTS:
		return
	_hotbar[slot] = ability_id

func get_slot_ability(slot: int) -> String:
	if slot < 0 or slot >= HOTBAR_SLOTS:
		return ""
	return _hotbar[slot]

# ----- Ability use (called on server) -----

func server_use_ability(ability_id: String, target_id: int) -> void:
	if not multiplayer.is_server():
		return
	var ability := _available_abilities.get(ability_id)
	if not ability:
		return
	var target := _resolve_target(target_id)
	var reason := _validate_use(ability, target)
	if reason != "":
		return
	if ability.cast_time > 0.0:
		_begin_cast(ability, target)
	else:
		_execute_ability(ability, target)

func _validate_use(ability: Ability, target) -> String:
	if not _owner_character or _owner_character.is_dead:
		return "dead"
	if _cooldowns.get(ability.ability_id, 0.0) > 0.0:
		return "cooldown"
	if _owner_character.stats.current_power < ability.power_cost:
		return "no_power"
	if _owner_character.stats.current_endurance < ability.endurance_cost:
		return "no_endurance"
	if target and _owner_character.global_position.distance_to(target.global_position) > ability.range_max:
		return "out_of_range"
	return ""

func _begin_cast(ability: Ability, target) -> void:
	_casting = {
		"ability": ability,
		"target": target,
		"elapsed": 0.0,
		"total": ability.cast_time
	}
	cast_started.emit(ability, ability.cast_time)

func _tick_cast(delta: float) -> void:
	if _casting.is_empty():
		return
	_casting["elapsed"] += delta
	if _casting["elapsed"] >= _casting["total"]:
		_execute_ability(_casting["ability"], _casting["target"])
		_casting.clear()
		cast_completed.emit(_casting.get("ability"))

func interrupt_cast() -> void:
	if _casting.is_empty():
		return
	_casting.clear()
	cast_interrupted.emit()

func _execute_ability(ability: Ability, target) -> void:
	var stats := _owner_character.stats
	stats.modify_power(-ability.power_cost)
	stats.modify_endurance(-ability.endurance_cost)
	_set_cooldown(ability.ability_id, ability.cooldown)

	match ability.target_type:
		Ability.TargetType.SINGLE_ENEMY, Ability.TargetType.SINGLE_ALLY:
			if target:
				_apply_to_target(ability, target)
		Ability.TargetType.AREA_ENEMY, Ability.TargetType.AREA_ALLY:
			_apply_area(ability)
		Ability.TargetType.SELF:
			_apply_to_target(ability, _owner_character)

	EventBus.ability_used.emit(_owner_character, ability.ability_id)

func _apply_to_target(ability: Ability, target: Character) -> void:
	if ability.base_damage > 0:
		var dmg := ability.calculate_damage(_owner_character.stats)
		target.take_damage(dmg, ability.damage_type, _owner_character)
	if ability.base_heal > 0:
		var h := ability.calculate_heal(_owner_character.stats)
		target.heal(h, _owner_character)
	for effect_id in ability.apply_effects:
		var effect_data := DataManager.get_ability(effect_id)
		if not effect_data.is_empty():
			target.apply_status_effect(effect_id, effect_data)

func _apply_area(ability: Ability) -> void:
	var origin := _owner_character.global_position
	var nearby := GameManager.get_players_in_range(origin, ability.area_radius)
	for character in nearby:
		if character == _owner_character:
			continue
		var is_enemy := GameManager.is_enemy(_owner_character.faction, character.faction)
		if ability.target_type == Ability.TargetType.AREA_ENEMY and is_enemy:
			_apply_to_target(ability, character)
		elif ability.target_type == Ability.TargetType.AREA_ALLY and not is_enemy:
			_apply_to_target(ability, character)

func _resolve_target(target_id: int) -> Character:
	if target_id <= 0:
		return null
	var node := get_tree().get_root().find_child(str(target_id), true, false)
	if node is Character:
		return node as Character
	return null

# ----- Cooldowns -----

func _set_cooldown(ability_id: String, duration: float) -> void:
	if duration <= 0.0:
		return
	_cooldowns[ability_id] = duration
	cooldown_updated.emit(ability_id, duration, duration)

func _tick_cooldowns(delta: float) -> void:
	for id in _cooldowns.keys():
		_cooldowns[id] -= delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)
			cooldown_updated.emit(id, 0.0, 0.0)
		else:
			EventBus.ability_cooldown_changed.emit(id, _cooldowns[id])

func get_cooldown(ability_id: String) -> float:
	return _cooldowns.get(ability_id, 0.0)

func is_on_cooldown(ability_id: String) -> bool:
	return _cooldowns.get(ability_id, 0.0) > 0.0

func get_all_abilities() -> Array:
	return _available_abilities.values()
