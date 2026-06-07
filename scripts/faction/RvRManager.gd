## Manages the Realm vs Realm system: objectives, scores, and rewards.
## Inspired by Dark Age of Camelot's frontier PvP system.
class_name RvRManager
extends Node

const SCORE_PER_KILL := 5
const SCORE_PER_OBJECTIVE := 100
const SCORE_TO_WIN := 5000  # campaign victory threshold

var scores: Dictionary = {
	GameManager.Faction.ROMAN:   0,
	GameManager.Faction.GALLI:   0,
	GameManager.Faction.GERMANI: 0,
}

# Objectives: id -> { "name", "position", "owner", "health", "max_health", "type" }
var objectives: Dictionary = {}

# Kill streak tracking: peer_id -> streak count
var kill_streaks: Dictionary = {}

func _ready() -> void:
	add_to_group("rvr_manager")
	EventBus.character_died.connect(_on_character_died)
	_load_objectives()

func _load_objectives() -> void:
	# Frontier zone objectives: towers, keeps, and relics
	var objective_defs := [
		{"id": "keep_rhenus",    "name": "Fortezza del Reno",       "type": "keep",  "faction": GameManager.Faction.NONE, "pos": Vector3(100, 0, 200)},
		{"id": "keep_danuvius",  "name": "Bastione del Danubio",    "type": "keep",  "faction": GameManager.Faction.NONE, "pos": Vector3(-150, 0, 300)},
		{"id": "tower_north_1",  "name": "Torre del Nord I",        "type": "tower", "faction": GameManager.Faction.NONE, "pos": Vector3(50, 0, 100)},
		{"id": "tower_north_2",  "name": "Torre del Nord II",       "type": "tower", "faction": GameManager.Faction.NONE, "pos": Vector3(-80, 0, 150)},
		{"id": "relic_aquila",   "name": "Aquila Imperiale (Relic)","type": "relic", "faction": GameManager.Faction.ROMAN, "pos": Vector3(300, 0, 0)},
		{"id": "relic_carnyx",   "name": "Carnyx di Guerra (Relic)", "type": "relic","faction": GameManager.Faction.GALLI, "pos": Vector3(-300, 0, 0)},
		{"id": "relic_ursa",     "name": "Stendardo dell'Orsa (Relic)","type":"relic","faction":GameManager.Faction.GERMANI,"pos": Vector3(0, 0, 400)},
	]
	for def in objective_defs:
		objectives[def["id"]] = {
			"name": def["name"],
			"type": def["type"],
			"owner": def["faction"],
			"pos": def["pos"],
			"health": _max_health_for(def["type"]),
			"max_health": _max_health_for(def["type"]),
			"capture_progress": {},  # faction -> accumulated seconds
		}

func _max_health_for(type: String) -> int:
	match type:
		"keep": return 20000
		"tower": return 5000
		"relic": return 10000
		_: return 1000

# ----- Kill tracking -----

func _on_character_died(character: Character) -> void:
	if not multiplayer.is_server():
		return
	if character.current_target and GameManager.is_enemy(character.faction, character.current_target.faction):
		_process_rvr_kill(character.current_target as Character, character)

func _process_rvr_kill(killer: Character, victim: Character) -> void:
	if not GameManager.is_enemy(killer.faction, victim.faction):
		return
	var points := CombatSystem.calculate_rvr_reward_points(victim, killer)
	_add_score(killer.faction, points)

	var streak: int = kill_streaks.get(killer.name.to_int(), 0) + 1
	kill_streaks[killer.name.to_int()] = streak

	EventBus.rvr_kill_announced.emit(killer.character_name, victim.character_name, killer.faction, victim.faction)
	EventBus.rvr_score_updated.emit(
		scores[GameManager.Faction.ROMAN],
		scores[GameManager.Faction.GALLI],
		scores[GameManager.Faction.GERMANI]
	)

# ----- Objectives -----

func damage_objective(obj_id: String, attacker: Character, amount: int) -> void:
	var obj: Dictionary = objectives.get(obj_id, {})
	if obj.is_empty():
		return
	if obj["owner"] == attacker.faction or obj["owner"] == GameManager.Faction.NONE:
		return  # can't damage your own or neutral while neutral
	obj["health"] = max(0, obj["health"] - amount)
	if obj["health"] <= 0:
		_capture_objective(obj_id, attacker.faction)

func tick_capture_progress(obj_id: String, faction: GameManager.Faction, players_present: int, delta: float) -> void:
	var obj: Dictionary = objectives.get(obj_id, {})
	if obj.is_empty():
		return
	if obj["owner"] == faction:
		return
	var rate := 10.0 * players_present * delta  # faster with more players
	obj["capture_progress"][faction] = obj.get("capture_progress", {}).get(faction, 0.0) + rate
	if obj["capture_progress"][faction] >= 100.0:
		_capture_objective(obj_id, faction)

func _capture_objective(obj_id: String, new_owner: GameManager.Faction) -> void:
	var obj: Dictionary = objectives[obj_id]
	var old_owner: GameManager.Faction = obj["owner"]
	obj["owner"] = new_owner
	obj["health"] = obj["max_health"]
	obj["capture_progress"].clear()

	_add_score(new_owner, SCORE_PER_OBJECTIVE)

	if obj["type"] == "relic":
		_handle_relic_capture(obj_id, new_owner, old_owner)

	EventBus.rvr_objective_captured.emit(obj_id, new_owner)
	EventBus.rvr_score_updated.emit(
		scores[GameManager.Faction.ROMAN],
		scores[GameManager.Faction.GALLI],
		scores[GameManager.Faction.GERMANI]
	)

func _handle_relic_capture(relic_id: String, captor: GameManager.Faction, _previous: GameManager.Faction) -> void:
	# Relic gives a faction-wide buff — notified via EventBus, applied by clients
	EventBus.notification_pushed.emit(
		"[%s] ha catturato una RELIQUIA! +10%% ai danni per tutta la fazione!" % GameManager.faction_name(captor),
		"rvr_major"
	)

func _add_score(faction: GameManager.Faction, amount: int) -> void:
	scores[faction] = scores.get(faction, 0) + amount
	if scores[faction] >= SCORE_TO_WIN:
		_trigger_campaign_victory(faction)

func _trigger_campaign_victory(winning_faction: GameManager.Faction) -> void:
	EventBus.notification_pushed.emit(
		"VITTORIA DI CAMPAGNA! %s ha conquistato le terre di frontiera!" % GameManager.faction_name(winning_faction),
		"campaign_victory"
	)
	# Reset scores after a brief delay
	await get_tree().create_timer(30.0).timeout
	for f in scores:
		scores[f] = 0
	EventBus.rvr_score_updated.emit(0, 0, 0)

func get_objective_status(obj_id: String) -> Dictionary:
	return objectives.get(obj_id, {})

func get_scores() -> Dictionary:
	return scores.duplicate()
