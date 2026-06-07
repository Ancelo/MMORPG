## Server-controlled NPC with basic FSM AI: idle, patrol, chase, attack, return.
class_name NPCCharacter
extends Character

enum AIState { IDLE, PATROL, CHASE, ATTACK, RETURN, DEAD }

@export var npc_id: String = ""
@export var aggro_radius: float = 15.0
@export var leash_radius: float = 40.0    # returns to spawn if too far
@export var patrol_radius: float = 10.0
@export var ai_tick_rate: float = 0.25    # seconds between AI decisions
@export var xp_reward: int = 50
@export var loot_table: String = ""
@export var is_friendly: bool = false     # guards, merchants

var _ai_state: AIState = AIState.IDLE
var _spawn_position: Vector3 = Vector3.ZERO
var _aggro_target: Character = null
var _patrol_target: Vector3 = Vector3.ZERO
var _ai_timer: float = 0.0
var _path: Array = []

func _ready() -> void:
	super._ready()
	_spawn_position = global_position
	respawn_point = global_position
	if not multiplayer.is_server():
		set_process(false)
		set_physics_process(false)
		return
	_ai_timer = randf() * ai_tick_rate  # stagger ticks across NPCs

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not multiplayer.is_server() or is_dead:
		return
	_ai_timer -= delta
	if _ai_timer <= 0.0:
		_ai_timer = ai_tick_rate
		_run_ai()

func _run_ai() -> void:
	match _ai_state:
		AIState.IDLE:    _ai_idle()
		AIState.PATROL:  _ai_patrol()
		AIState.CHASE:   _ai_chase()
		AIState.ATTACK:  _ai_attack()
		AIState.RETURN:  _ai_return()

func _ai_idle() -> void:
	if not is_friendly:
		var target := _scan_for_enemies()
		if target:
			_aggro_target = target
			_ai_state = AIState.CHASE
			return
	if patrol_radius > 0.5:
		_pick_patrol_point()
		_ai_state = AIState.PATROL

func _ai_patrol() -> void:
	if not is_friendly:
		var target := _scan_for_enemies()
		if target:
			_aggro_target = target
			_ai_state = AIState.CHASE
			return
	if global_position.distance_to(_patrol_target) < 1.5:
		_ai_state = AIState.IDLE
		move_direction = Vector3.ZERO
		return
	move_direction = ((_patrol_target - global_position) * Vector3(1, 0, 1)).normalized()
	rotation.y = atan2(move_direction.x, move_direction.z)

func _ai_chase() -> void:
	if not _is_target_valid():
		_aggro_target = null
		_ai_state = AIState.RETURN
		return
	if global_position.distance_to(_spawn_position) > leash_radius:
		_aggro_target = null
		_ai_state = AIState.RETURN
		return
	var dist := global_position.distance_to(_aggro_target.global_position)
	var attack_range: float = 2.5
	if dist <= attack_range:
		move_direction = Vector3.ZERO
		_ai_state = AIState.ATTACK
		return
	move_direction = ((_aggro_target.global_position - global_position) * Vector3(1, 0, 1)).normalized()
	rotation.y = atan2(move_direction.x, move_direction.z)

func _ai_attack() -> void:
	if not _is_target_valid():
		_aggro_target = null
		_ai_state = AIState.RETURN
		return
	look_at(_aggro_target.global_position * Vector3(1, 0, 1) + Vector3(0, global_position.y, 0), Vector3.UP)
	var dist := global_position.distance_to(_aggro_target.global_position)
	if dist > 3.5:
		_ai_state = AIState.CHASE
		return
	if ability_manager:
		ability_manager.server_use_ability("auto_attack", _aggro_target.name.to_int())

func _ai_return() -> void:
	var dist := global_position.distance_to(_spawn_position)
	if dist < 1.0:
		global_position = _spawn_position
		move_direction = Vector3.ZERO
		# Restore health on return
		stats.current_health = stats.max_health
		_ai_state = AIState.IDLE
		return
	move_direction = ((_spawn_position - global_position) * Vector3(1, 0, 1)).normalized()

func _scan_for_enemies() -> Character:
	var best: Character = null
	var best_dist := aggro_radius
	for character in get_tree().get_nodes_in_group("characters"):
		if character == self or character is NPCCharacter:
			continue
		var c := character as Character
		if not c or c.is_dead:
			continue
		if not GameManager.is_enemy(faction, c.faction):
			continue
		var d := global_position.distance_to(c.global_position)
		if d < best_dist:
			best_dist = d
			best = c
	return best

func _is_target_valid() -> bool:
	return _aggro_target != null and not _aggro_target.is_dead and is_instance_valid(_aggro_target)

func _pick_patrol_point() -> void:
	var angle := randf() * TAU
	var dist := randf() * patrol_radius
	_patrol_target = _spawn_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

func _on_death(killer: Character) -> void:
	_ai_state = AIState.DEAD
	move_direction = Vector3.ZERO
	_aggro_target = null
	if killer:
		var xp := CombatSystem.calculate_xp_reward(self, killer)
		killer.experience += xp
		EventBus.xp_gained.emit(xp, killer.experience, killer.level)
		if killer.get_node_or_null("QuestManager"):
			killer.get_node("QuestManager").notify_kill(npc_id)
		_roll_loot(killer)

func _roll_loot(recipient: Character) -> void:
	if loot_table.is_empty():
		return
	var table_data := DataManager.get_item(loot_table)
	if table_data.is_empty():
		return
	for drop in table_data.get("drops", []):
		if randf() < drop.get("chance", 0.1):
			if recipient.get_node_or_null("Inventory"):
				recipient.get_node("Inventory").add_item(drop["item_id"], drop.get("count", 1))
