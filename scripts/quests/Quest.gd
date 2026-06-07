## Quest definition and progress tracker.
class_name Quest
extends Resource

enum Status { AVAILABLE, ACTIVE, COMPLETED, FAILED }

@export var quest_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var giver_npc: String = ""
@export var required_level: int = 1
@export var required_faction: int = 0
@export var required_quests: Array = []  # prerequisite quest_ids

@export var objectives: Array = []  # Array of objective dicts
@export var rewards: Dictionary = {}

var status: Status = Status.AVAILABLE
var progress: Dictionary = {}  # objective_id -> current_count

static func from_dict(data: Dictionary) -> Quest:
	var q := Quest.new()
	q.quest_id       = data.get("id", "")
	q.display_name   = data.get("name", "")
	q.description    = data.get("description", "")
	q.giver_npc      = data.get("giver", "")
	q.required_level = data.get("required_level", 1)
	q.required_faction = data.get("required_faction", 0)
	q.required_quests = data.get("prerequisites", [])
	q.objectives     = data.get("objectives", [])
	q.rewards        = data.get("rewards", {})
	return q

func start() -> void:
	status = Status.ACTIVE
	for obj in objectives:
		progress[obj["id"]] = 0

func update_objective(objective_id: String, amount: int = 1) -> void:
	if status != Status.ACTIVE:
		return
	if not progress.has(objective_id):
		return
	progress[objective_id] = min(progress[objective_id] + amount, _get_objective_target(objective_id))
	if is_complete():
		status = Status.COMPLETED

func _get_objective_target(objective_id: String) -> int:
	for obj in objectives:
		if obj["id"] == objective_id:
			return obj.get("count", 1)
	return 1

func is_complete() -> bool:
	for obj in objectives:
		var needed: int = obj.get("count", 1)
		if progress.get(obj["id"], 0) < needed:
			return false
	return true

func get_objective_text(obj: Dictionary) -> String:
	var current: int = progress.get(obj["id"], 0)
	var target: int = obj.get("count", 1)
	return "%s: %d/%d" % [obj.get("description", ""), current, target]
