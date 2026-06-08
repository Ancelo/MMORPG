## Spawns LootBody nodes when NPCs die; handles loot table rolling server-side.
extends Node

const LOOT_BODY_SCENE := "res://scenes/game/LootBody.tscn"

func _ready() -> void:
	add_to_group("loot_manager")
	EventBus.character_died.connect(_on_character_died)

func _on_character_died(character: Character) -> void:
	if not multiplayer.is_server():
		return
	if character is PlayerCharacter:
		return  # players don't drop loot bodies (they can in PvP optionally)
	_spawn_loot_body(character)

func _spawn_loot_body(character: Character) -> void:
	var npc := character as NPCCharacter
	if not npc:
		return

	var items := _roll_loot_table(npc)
	var gold  := _roll_gold(npc)

	if items.is_empty() and gold == 0:
		return

	# Find who killed this NPC
	var killer_peer_id := _find_killer(npc)

	var body: LootBody
	# Try to use scene, fall back to inline creation
	var packed := load(LOOT_BODY_SCENE) as PackedScene
	if packed:
		body = packed.instantiate() as LootBody
	else:
		body = LootBody.new()

	body.global_position = npc.global_position + Vector3(0, 0.3, 0)
	get_tree().current_scene.add_child(body)
	body.setup(killer_peer_id, items, gold)

func _roll_loot_table(npc: NPCCharacter) -> Array:
	var result: Array = []
	if npc.loot_table.is_empty():
		return result
	var table_data := DataManager.get_item(npc.loot_table)
	if table_data.is_empty():
		return result
	for drop in table_data.get("drops", []):
		if randf() < drop.get("chance", 0.1):
			result.append({
				"item_id": drop["item_id"],
				"count": drop.get("count", 1),
			})
	return result

func _roll_gold(npc: NPCCharacter) -> int:
	var base_gold := npc.level * 2
	return randi_range(max(0, base_gold - 3), base_gold + 5)

func _find_killer(npc: NPCCharacter) -> int:
	# Best-effort: use the NPC's last aggro target
	if npc.current_target and is_instance_valid(npc.current_target):
		for peer_id in GameManager.players:
			if GameManager.players[peer_id] == npc.current_target:
				return peer_id
	return -1
