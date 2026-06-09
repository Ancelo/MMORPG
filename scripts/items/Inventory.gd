## Manages character inventory and equipment slots.
class_name Inventory
extends Node

signal item_added(item: Item, slot: int)
signal item_removed(item: Item, slot: int)
signal item_equipped(item: Item, equip_slot: Item.Slot)
signal item_unequipped(item: Item, equip_slot: Item.Slot)

const BAG_SIZE := 40

var bags: Array = []          # Array of {item: Item, count: int} or null
var equipped: Dictionary = {} # Item.Slot -> Item
var gold: int = 0

var _owner_character: Character

func _ready() -> void:
	_owner_character = get_parent() as Character
	bags.resize(BAG_SIZE)
	bags.fill(null)

# ----- Bag management -----

func add_item(item_id: String, count: int = 1) -> bool:
	var item_data := DataManager.get_item(item_id)
	if item_data.is_empty():
		return false
	var item := Item.from_dict(item_data)
	if item.stack_max > 1:
		if _stack_into_existing(item, count):
			return true
	var free_slot := _find_free_slot()
	if free_slot < 0:
		return false
	bags[free_slot] = {"item": item, "count": count}
	item_added.emit(item, free_slot)
	EventBus.inventory_changed.emit()
	return true

func remove_item(slot: int, count: int = 1) -> bool:
	if slot < 0 or slot >= BAG_SIZE or bags[slot] == null:
		return false
	var entry: Dictionary = bags[slot]
	entry["count"] -= count
	if entry["count"] <= 0:
		var item: Item = entry["item"]
		bags[slot] = null
		item_removed.emit(item, slot)
	EventBus.inventory_changed.emit()
	return true

func _stack_into_existing(item: Item, count: int) -> bool:
	for i in range(BAG_SIZE):
		if bags[i] == null:
			continue
		var entry: Dictionary = bags[i]
		if entry["item"].item_id == item.item_id and entry["count"] < item.stack_max:
			entry["count"] = min(entry["count"] + count, item.stack_max)
			EventBus.inventory_changed.emit()
			return true
	return false

func _find_free_slot() -> int:
	for i in range(BAG_SIZE):
		if bags[i] == null:
			return i
	return -1

# ----- Equipment -----

func equip_item(bag_slot: int) -> bool:
	if bag_slot < 0 or bag_slot >= BAG_SIZE or bags[bag_slot] == null:
		return false
	var entry: Dictionary = bags[bag_slot]
	var item: Item = entry["item"]
	if not item.can_equip(_owner_character):
		return false
	if item.equip_slot == Item.Slot.NONE:
		return false
	if equipped.has(item.equip_slot):
		unequip_slot(item.equip_slot)
	equipped[item.equip_slot] = item
	bags[bag_slot] = null
	_apply_item_stats(item, 1)
	item_equipped.emit(item, item.equip_slot)
	EventBus.inventory_changed.emit()
	return true

func unequip_slot(slot: Item.Slot) -> bool:
	var item: Item = equipped.get(slot)
	if not item:
		return false
	var free := _find_free_slot()
	if free < 0:
		return false
	equipped.erase(slot)
	bags[free] = {"item": item, "count": 1}
	_apply_item_stats(item, -1)
	item_unequipped.emit(item, slot)
	EventBus.inventory_changed.emit()
	return true

func _apply_item_stats(item: Item, sign: int) -> void:
	if not _owner_character:
		return
	var mods: Dictionary = {}
	for stat in item.stat_bonuses:
		mods[stat] = item.stat_bonuses[stat] * sign
	if sign > 0:
		_owner_character.stats.add_modifier(item.item_id, mods)
	else:
		_owner_character.stats.remove_modifier(item.item_id)

func get_equipped(slot: Item.Slot) -> Item:
	return equipped.get(slot)

func get_weapon_damage() -> Vector2i:
	var weapon: Item = equipped.get(Item.Slot.WEAPON_MAIN)
	if weapon:
		return Vector2i(weapon.weapon_damage_min, weapon.weapon_damage_max)
	return Vector2i(5, 10)  # unarmed

# ----- Economy -----

func add_gold(amount: int) -> void:
	gold += amount
	EventBus.inventory_changed.emit()

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	EventBus.inventory_changed.emit()
	return true

# ----- Serialization -----

func to_dict() -> Dictionary:
	var bag_data: Array = []
	for entry in bags:
		if entry == null:
			bag_data.append(null)
		else:
			bag_data.append({"id": entry["item"].item_id, "count": entry["count"]})
	var equip_data: Dictionary = {}
	for slot in equipped:
		equip_data[str(slot)] = equipped[slot].item_id
	return {"bags": bag_data, "equipped": equip_data, "gold": gold}
