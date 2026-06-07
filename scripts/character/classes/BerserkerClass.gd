## Berserker-specific mechanic: RAGE. More damage as health drops.
## Also handles berserk state where the character ignores CC and gains speed.
class_name BerserkerClass
extends Node

var _character: Character
var _is_berserk: bool = false
var _rage: float = 0.0
const MAX_RAGE := 100.0

signal rage_changed(current: float, maximum: float)

func _ready() -> void:
	_character = get_parent() as Character
	if _character:
		_character.stats.health_changed.connect(_on_health_changed)

func _process(_delta: float) -> void:
	if not _character:
		return
	# Rage decays out of combat
	if not _character.is_in_combat and _rage > 0.0:
		_rage = maxf(0.0, _rage - 5.0 * get_process_delta_time())
		_update_rage_bonus()
		rage_changed.emit(_rage, MAX_RAGE)

func _on_health_changed(current: int, maximum: int) -> void:
	if maximum == 0:
		return
	# Low health generates rage and increases damage
	var hp_pct := float(current) / float(maximum)
	var missing_pct := 1.0 - hp_pct
	_rage = minf(MAX_RAGE, _rage + missing_pct * 10.0)
	_update_rage_bonus()
	rage_changed.emit(_rage, MAX_RAGE)

func _update_rage_bonus() -> void:
	var bonus := int(_rage * 0.3)  # up to +30 strength at max rage
	_character.stats.add_modifier("rage_bonus", {"strength": bonus})

func activate_berserk() -> void:
	if _is_berserk or _rage < 50.0:
		return
	_is_berserk = true
	_rage = 0.0
	_character.stats.add_modifier("berserk", {
		"strength": 20,
		"speed": 2.0,
		"armor": -80,
	})
	_character.stats.remove_modifier("rage_bonus")
	await _character.get_tree().create_timer(12.0).timeout
	_character.stats.remove_modifier("berserk")
	_is_berserk = false
	rage_changed.emit(_rage, MAX_RAGE)

func add_rage(amount: float) -> void:
	_rage = minf(MAX_RAGE, _rage + amount)
	_update_rage_bonus()
	rage_changed.emit(_rage, MAX_RAGE)
