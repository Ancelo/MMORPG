## Handles player interaction with NPCs: dialogue, quest pickup/turnin, shopping.
## Attach to NPCCharacter nodes that have interaction capabilities.
class_name NPCInteraction
extends Node

signal interaction_opened(npc: Node, type: String)
signal interaction_closed()
signal dialogue_line(speaker: String, text: String, options: Array)

enum NPCRole { NONE, QUEST_GIVER, MERCHANT, TRAINER, GUARD, INNKEEPER }

@export var npc_role: NPCRole = NPCRole.NONE
@export var dialogue_id: String = ""
@export var merchant_inventory: Array = []   # item_id strings
@export var trainable_abilities: Array = []  # ability_id strings
@export var interaction_radius: float = 3.0

var _owner_npc: Character
var _interacting_player: Character = null

func _ready() -> void:
	_owner_npc = get_parent() as Character
	add_to_group("interactable_npcs")

func can_interact(player: Character) -> bool:
	if _interacting_player != null:
		return false
	return _owner_npc.global_position.distance_to(player.global_position) <= interaction_radius

func begin_interaction(player: Character) -> void:
	if not can_interact(player):
		return
	_interacting_player = player
	match npc_role:
		NPCRole.QUEST_GIVER: _open_quest_menu(player)
		NPCRole.MERCHANT:    _open_merchant(player)
		NPCRole.TRAINER:     _open_trainer(player)
		NPCRole.INNKEEPER:   _open_innkeeper(player)
		_:                   _open_dialogue(player)
	interaction_opened.emit(_owner_npc, NPCRole.keys()[npc_role])

func end_interaction() -> void:
	_interacting_player = null
	interaction_closed.emit()

# ----- Quest NPC -----

func _open_quest_menu(player: Character) -> void:
	if not player.get_node_or_null("QuestManager"):
		return
	var qm := player.get_node("QuestManager") as QuestManager
	var available: Array = []
	var completable: Array = []
	var zone_data := DataManager.get_zone("forum_romanum")  # TODO: get current zone
	for quest_id in zone_data.get("quests_available", []):
		if qm.can_accept(quest_id):
			available.append(quest_id)
	for quest_id in qm.active_quests:
		if qm.active_quests[quest_id].is_complete():
			completable.append(quest_id)
	EventBus.notification_pushed.emit(
		"[%s] — %d missioni disponibili, %d da consegnare" % [
			_owner_npc.character_name, available.size(), completable.size()
		], "npc"
	)

func offer_quest(quest_id: String, player: Character) -> bool:
	if not player.get_node_or_null("QuestManager"):
		return false
	return player.get_node("QuestManager").accept_quest(quest_id)

func complete_quest(quest_id: String, player: Character) -> bool:
	if not player.get_node_or_null("QuestManager"):
		return false
	return player.get_node("QuestManager").complete_quest(quest_id)

# ----- Merchant -----

func _open_merchant(player: Character) -> void:
	# Signal picked up by MerchantUI
	interaction_opened.emit(_owner_npc, "MERCHANT")

func get_merchant_items() -> Array:
	var result: Array = []
	for item_id in merchant_inventory:
		var data := DataManager.get_item(item_id)
		if not data.is_empty():
			result.append(data)
	return result

func buy_item(item_id: String, player: Character) -> bool:
	if not player.get_node_or_null("Inventory"):
		return false
	var item_data := DataManager.get_item(item_id)
	if item_data.is_empty():
		return false
	var price: int = item_data.get("value", 0)
	var inventory := player.get_node("Inventory") as Inventory
	if not inventory.spend_gold(price):
		EventBus.notification_pushed.emit("Oro insufficiente!", "error")
		return false
	return inventory.add_item(item_id)

func sell_item(bag_slot: int, player: Character) -> bool:
	if not player.get_node_or_null("Inventory"):
		return false
	var inventory := player.get_node("Inventory") as Inventory
	var entry: Dictionary = inventory.bags[bag_slot] if bag_slot < inventory.bags.size() else {}
	if entry == null or entry.is_empty():
		return false
	var sell_price: int = int(entry["item"].gold_value * 0.5)
	inventory.remove_item(bag_slot)
	inventory.add_gold(sell_price)
	return true

# ----- Trainer -----

func _open_trainer(player: Character) -> void:
	interaction_opened.emit(_owner_npc, "TRAINER")

func get_trainable_abilities(player: Character) -> Array:
	var result: Array = []
	for ability_id in trainable_abilities:
		var data := DataManager.get_ability(ability_id)
		if data.is_empty():
			continue
		if data.get("class_id", "") not in ["", player.character_class]:
			continue
		if data.get("required_level", 1) <= player.level:
			result.append(data)
	return result

func train_ability(ability_id: String, player: Character) -> bool:
	if not player.get_node_or_null("AbilityManager"):
		return false
	var data := DataManager.get_ability(ability_id)
	var training_cost: int = data.get("training_cost", 10) * player.level
	if not player.get_node("Inventory").spend_gold(training_cost):
		EventBus.notification_pushed.emit("Oro insufficiente per l'addestramento!", "error")
		return false
	return player.get_node("AbilityManager").learn_ability(ability_id)

# ----- Innkeeper -----

func _open_innkeeper(player: Character) -> void:
	# Full rest: restore HP/EP/PP completely, costs gold
	var rest_cost := 5
	if player.get_node_or_null("Inventory") and player.get_node("Inventory").spend_gold(rest_cost):
		player.stats.current_health    = player.stats.max_health
		player.stats.current_endurance = player.stats.max_endurance
		player.stats.current_power     = player.stats.max_power
		EventBus.notification_pushed.emit("Hai riposato. Vita, resistenza e potere completamente ripristinati.", "inn")
	end_interaction()

func _open_dialogue(player: Character) -> void:
	# Load from data/dialogues/<dialogue_id>.json if present
	EventBus.notification_pushed.emit("%s: Salve, viaggiatore!" % _owner_npc.character_name, "npc")
