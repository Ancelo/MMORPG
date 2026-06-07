## Represents a single item definition with stat bonuses and requirements.
class_name Item
extends Resource

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum Slot { NONE, HEAD, CHEST, LEGS, FEET, HANDS, SHOULDER, BACK, NECK, RING, WEAPON_MAIN, WEAPON_OFF, RANGED }
enum ItemType { WEAPON, ARMOR, JEWELRY, CONSUMABLE, QUEST, CURRENCY }

@export var item_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var model_path: String = ""

@export var item_type: ItemType = ItemType.ARMOR
@export var rarity: Rarity = Rarity.COMMON
@export var equip_slot: Slot = Slot.NONE
@export var stack_max: int = 1

# Requirements
@export var required_level: int = 1
@export var required_class: String = ""
@export var required_faction: int = 0

# Stat bonuses when equipped
@export var stat_bonuses: Dictionary = {}

# Weapon-specific
@export var weapon_damage_min: int = 0
@export var weapon_damage_max: int = 0
@export var weapon_damage_type: String = "physical"
@export var weapon_speed: float = 2.0  # seconds per swing

# Armor-specific
@export var armor_value: int = 0
@export var absorb_factor: float = 0.0

# Consumable
@export var use_effect: String = ""
@export var use_cooldown: float = 30.0

# Economy
@export var gold_value: int = 0

static func from_dict(data: Dictionary) -> Item:
	var item := Item.new()
	item.item_id      = data.get("id", "")
	item.display_name = data.get("name", "")
	item.description  = data.get("description", "")
	item.icon_path    = data.get("icon", "")
	item.item_type    = ItemType[data.get("type", "ARMOR").to_upper()]
	item.rarity       = Rarity[data.get("rarity", "COMMON").to_upper()]
	item.equip_slot   = Slot[data.get("slot", "NONE").to_upper()]
	item.stack_max    = data.get("stack_max", 1)
	item.required_level = data.get("required_level", 1)
	item.required_class = data.get("required_class", "")
	item.stat_bonuses = data.get("stat_bonuses", {})
	item.armor_value  = data.get("armor", 0)
	item.weapon_damage_min = data.get("damage_min", 0)
	item.weapon_damage_max = data.get("damage_max", 0)
	item.weapon_speed = data.get("speed", 2.0)
	item.gold_value   = data.get("value", 0)
	return item

func rarity_color() -> Color:
	match rarity:
		Rarity.COMMON:    return Color.WHITE
		Rarity.UNCOMMON:  return Color(0.3, 0.8, 0.3)
		Rarity.RARE:      return Color(0.3, 0.5, 1.0)
		Rarity.EPIC:      return Color(0.7, 0.3, 1.0)
		Rarity.LEGENDARY: return Color(1.0, 0.6, 0.1)
		_: return Color.WHITE

func can_equip(character: Character) -> bool:
	if character.level < required_level:
		return false
	if required_class != "" and character.character_class != required_class:
		return false
	if required_faction > 0 and int(character.faction) != required_faction:
		return false
	return true
