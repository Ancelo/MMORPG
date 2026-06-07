## Manages active quests for a character and handles objective tracking.
class_name QuestManager
extends Node

const MAX_ACTIVE_QUESTS := 25

var active_quests: Dictionary = {}    # quest_id -> Quest
var completed_quests: Array = []      # quest_id strings

var _owner_character: Character

func _ready() -> void:
	_owner_character = get_parent() as Character
	EventBus.character_died.connect(_on_character_died)

func can_accept(quest_id: String) -> bool:
	var data := DataManager.get_quest(quest_id)
	if data.is_empty():
		return false
	if active_quests.size() >= MAX_ACTIVE_QUESTS:
		return false
	if quest_id in active_quests or quest_id in completed_quests:
		return false
	var quest := Quest.from_dict(data)
	if _owner_character.level < quest.required_level:
		return false
	if quest.required_faction > 0 and int(_owner_character.faction) != quest.required_faction:
		return false
	for prereq in quest.required_quests:
		if prereq not in completed_quests:
			return false
	return true

func accept_quest(quest_id: String) -> bool:
	if not can_accept(quest_id):
		return false
	var data := DataManager.get_quest(quest_id)
	var quest := Quest.from_dict(data)
	quest.start()
	active_quests[quest_id] = quest
	EventBus.quest_updated.emit(quest_id)
	return true

func complete_quest(quest_id: String) -> bool:
	var quest: Quest = active_quests.get(quest_id)
	if not quest or not quest.is_complete():
		return false
	active_quests.erase(quest_id)
	completed_quests.append(quest_id)
	_grant_rewards(quest.rewards)
	EventBus.quest_updated.emit(quest_id)
	EventBus.notification_pushed.emit("Missione completata: %s" % quest.display_name, "quest")
	return true

func abandon_quest(quest_id: String) -> void:
	active_quests.erase(quest_id)
	EventBus.quest_updated.emit(quest_id)

func notify_kill(npc_id: String) -> void:
	for quest in active_quests.values():
		for obj in quest.objectives:
			if obj.get("type") == "kill" and obj.get("target") == npc_id:
				quest.update_objective(obj["id"])
				EventBus.quest_updated.emit(quest.quest_id)

func notify_item_collected(item_id: String) -> void:
	for quest in active_quests.values():
		for obj in quest.objectives:
			if obj.get("type") == "collect" and obj.get("item") == item_id:
				quest.update_objective(obj["id"])
				EventBus.quest_updated.emit(quest.quest_id)

func notify_location_reached(location_id: String) -> void:
	for quest in active_quests.values():
		for obj in quest.objectives:
			if obj.get("type") == "location" and obj.get("location") == location_id:
				quest.update_objective(obj["id"])
				EventBus.quest_updated.emit(quest.quest_id)

func _grant_rewards(rewards: Dictionary) -> void:
	if not _owner_character:
		return
	if rewards.has("xp"):
		_owner_character.experience += rewards["xp"]
		EventBus.xp_gained.emit(rewards["xp"], _owner_character.experience, _owner_character.level)
	if rewards.has("gold"):
		_owner_character.get_node("Inventory").add_gold(rewards["gold"])
	if rewards.has("items"):
		for item_id in rewards["items"]:
			_owner_character.get_node("Inventory").add_item(item_id)

func _on_character_died(character: Character) -> void:
	if character != _owner_character:
		return
	# Fail time-limited quests
	for quest_id in active_quests.keys():
		var quest: Quest = active_quests[quest_id]
		var data := DataManager.get_quest(quest_id)
		if data.get("fail_on_death", false):
			quest.status = Quest.Status.FAILED
			active_quests.erase(quest_id)
			EventBus.quest_updated.emit(quest_id)
