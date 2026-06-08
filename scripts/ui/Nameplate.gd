## 3D nameplate above a character: name in faction colour + health percentage.
## Billboard so it always faces the camera.
class_name Nameplate
extends Node3D

@onready var name_label: Label3D  = $NameLabel
@onready var health_label: Label3D = $HealthLabel

var _character: Character = null

func setup(character: Character) -> void:
	_character = character
	name_label.text = character.character_name
	name_label.modulate = GameManager.faction_color(character.faction)
	character.stats.health_changed.connect(_on_health_changed)
	character.died.connect(_on_character_died)
	character.respawned.connect(_on_character_respawned)
	_refresh_health(character.stats.current_health, character.stats.max_health)

func _on_health_changed(current: int, maximum: int) -> void:
	_refresh_health(current, maximum)

func _on_character_died() -> void:
	visible = false

func _on_character_respawned() -> void:
	visible = true
	if _character:
		_refresh_health(_character.stats.current_health, _character.stats.max_health)

func _refresh_health(current: int, maximum: int) -> void:
	if maximum <= 0:
		health_label.text = ""
		return
	var pct := int(float(current) / float(maximum) * 100.0)
	health_label.text = "%d%%" % pct
	# Colour shifts from green → red as HP falls
	health_label.modulate = Color(1.0 - pct / 100.0, pct / 100.0, 0.1, 1.0)
