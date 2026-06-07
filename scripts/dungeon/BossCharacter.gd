## Extended NPC for boss encounters: phases, special abilities, enrage timer.
class_name BossCharacter
extends NPCCharacter

signal phase_changed(new_phase: int)
signal enraged()

@export var boss_id: String = ""
@export var boss_name: String = ""
@export var phase_thresholds: Array[float] = [0.5]  # HP% triggers for new phases
@export var enrage_timer: float = 600.0  # 10 minutes
@export var phase_abilities: Array[Array] = []  # abilities unlocked per phase

var current_phase: int = 0
var is_enraged: bool = false
var _enrage_elapsed: float = 0.0
var _dungeon_instance_id: int = -1

func _ready() -> void:
	super._ready()
	aggro_radius = 30.0
	leash_radius = 999.0  # bosses never leash

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not multiplayer.is_server() or is_dead:
		return
	_check_phase_transitions()
	_tick_enrage(delta)

func _check_phase_transitions() -> void:
	if current_phase >= phase_thresholds.size():
		return
	var hp_pct := stats.health_percent()
	if hp_pct <= phase_thresholds[current_phase]:
		current_phase += 1
		_trigger_phase(current_phase)

func _trigger_phase(phase: int) -> void:
	phase_changed.emit(phase)
	EventBus.notification_pushed.emit(
		"%s passa alla FASE %d!" % [boss_name, phase],
		"boss_phase"
	)
	# Apply phase-specific stat changes
	match phase:
		1:
			stats.add_modifier("phase_2", {"strength": 5, "speed": 0.5})
		2:
			stats.add_modifier("phase_3", {"strength": 10, "speed": 1.0, "armor": -50})
	# Unlock phase abilities
	if phase < phase_abilities.size():
		for ability_id in phase_abilities[phase]:
			if ability_manager:
				ability_manager.learn_ability(ability_id)

func _tick_enrage(delta: float) -> void:
	if is_enraged:
		return
	_enrage_elapsed += delta
	if _enrage_elapsed >= enrage_timer:
		_trigger_enrage()

func _trigger_enrage() -> void:
	is_enraged = true
	stats.add_modifier("enrage", {
		"strength": 30,
		"speed": 2.0,
		"attack_speed": 1.5,
	})
	enraged.emit()
	EventBus.notification_pushed.emit(
		"%s si è INVIPERИТО! Danni e velocità raddoppiati!" % boss_name,
		"boss_enrage"
	)

func _on_death(killer: Character) -> void:
	super._on_death(killer)
	EventBus.notification_pushed.emit(
		"%s è stato sconfitto!" % boss_name,
		"boss_kill"
	)
	if _dungeon_instance_id >= 0:
		var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
		if dm:
			dm.on_boss_defeated(_dungeon_instance_id, boss_id)

func set_dungeon_instance(instance_id: int) -> void:
	_dungeon_instance_id = instance_id
