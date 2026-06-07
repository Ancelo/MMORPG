## Legionary-specific mechanics: shield block, formation bonuses, taunt.
class_name LegionaryClass
extends Node

var _character: Character
var _shield_equipped: bool = true
var _in_formation: bool = false

func _ready() -> void:
	_character = get_parent() as Character
	if _character:
		# Extra block chance when shield is equipped
		_character.stats.block_chance = 0.20

func set_formation(active: bool) -> void:
	_in_formation = active
	if active:
		_character.stats.add_modifier("formation_bonus", {
			"armor": 100,
			"magic_resist": 50,
			"speed": -1.5
		})
	else:
		_character.stats.remove_modifier("formation_bonus")

func apply_testudo() -> void:
	_character.stats.add_modifier("testudo", {
		"armor": 500,
		"magic_resist": 200,
		"speed": -3.0
	})
	await _character.get_tree().create_timer(10.0).timeout
	_character.stats.remove_modifier("testudo")

func apply_furia_romana() -> void:
	_character.stats.add_modifier("furia_romana", {
		"strength": 8,
		"armor": -50
	})
	await _character.get_tree().create_timer(15.0).timeout
	_character.stats.remove_modifier("furia_romana")
