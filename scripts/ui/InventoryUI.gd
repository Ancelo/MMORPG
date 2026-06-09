## Inventory and equipment UI panel.
extends Control

@onready var bag_grid: GridContainer       = $Split/BagPanel/Grid
@onready var equip_panel: Control          = $Split/EquipPanel
@onready var gold_label: Label             = $Split/BagPanel/GoldLabel
@onready var char_stats_label: RichTextLabel = $Split/EquipPanel/StatsLabel
@onready var tooltip: PanelContainer       = $Tooltip
@onready var tooltip_label: RichTextLabel  = $Tooltip/Label

const SLOT_SCENE := preload("res://scenes/ui/InventorySlot.tscn")

var _inventory: Inventory = null
var _dragged_slot: int = -1

# Equipment slot button names -> Item.Slot mapping
const EQUIP_SLOT_MAP := {
	"Head":       Item.Slot.HEAD,
	"Chest":      Item.Slot.CHEST,
	"Legs":       Item.Slot.LEGS,
	"Feet":       Item.Slot.FEET,
	"Hands":      Item.Slot.HANDS,
	"Shoulder":   Item.Slot.SHOULDER,
	"Neck":       Item.Slot.NECK,
	"Ring":       Item.Slot.RING,
	"WeaponMain": Item.Slot.WEAPON_MAIN,
	"WeaponOff":  Item.Slot.WEAPON_OFF,
	"Ranged":     Item.Slot.RANGED,
}

func _ready() -> void:
	visible = false
	tooltip.visible = false
	EventBus.inventory_changed.connect(_refresh)
	EventBus.character_spawned.connect(_on_character_spawned)
	_build_bag_grid()
	_connect_equip_slots()

func _on_character_spawned(_character: Node, peer_id: int) -> void:
	if peer_id != GameManager.local_peer_id:
		return
	var character: Node = GameManager.local_player
	if character and character.get_node_or_null("Inventory"):
		_inventory = character.get_node("Inventory") as Inventory
		_refresh()

func _build_bag_grid() -> void:
	for i in range(Inventory.BAG_SIZE):
		var slot := _create_slot_button(i)
		bag_grid.add_child(slot)

func _create_slot_button(index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(50, 50)
	btn.name = "Slot_%d" % index
	btn.pressed.connect(func(): _on_slot_clicked(index))
	btn.mouse_entered.connect(func(): _show_tooltip(index))
	btn.mouse_exited.connect(func(): tooltip.visible = false)
	return btn

func _connect_equip_slots() -> void:
	for slot_name in EQUIP_SLOT_MAP:
		var btn := equip_panel.get_node_or_null(slot_name) as Button
		if btn:
			var item_slot: Item.Slot = EQUIP_SLOT_MAP[slot_name]
			btn.pressed.connect(func(): _on_equip_slot_clicked(item_slot))

func _refresh() -> void:
	if not _inventory:
		return
	for i in range(Inventory.BAG_SIZE):
		var btn := bag_grid.get_child(i) as Button
		if btn:
			_update_slot_display(btn, i)
	gold_label.text = "Oro: %d" % _inventory.gold
	_update_stats_display()
	_update_equip_display()

func _update_slot_display(btn: Button, index: int) -> void:
	var entry: Dictionary = _inventory.bags[index] if index < _inventory.bags.size() else {}
	if entry == null or entry.is_empty():
		btn.text = ""
		btn.icon = null
		return
	var item: Item = entry["item"]
	var count: int = entry["count"]
	btn.text = str(count) if count > 1 else ""
	var tex := load(item.icon_path) as Texture2D if item.icon_path != "" else null
	btn.icon = tex
	btn.modulate = item.rarity_color()

func _update_equip_display() -> void:
	for slot_name in EQUIP_SLOT_MAP:
		var btn := equip_panel.get_node_or_null(slot_name) as Button
		if not btn:
			continue
		var item_slot: Item.Slot = EQUIP_SLOT_MAP[slot_name]
		var item := _inventory.get_equipped(item_slot)
		if item:
			btn.text = item.display_name
			btn.modulate = item.rarity_color()
		else:
			btn.text = "[vuoto]"
			btn.modulate = Color.GRAY

func _update_stats_display() -> void:
	if not GameManager.local_player:
		return
	var s := GameManager.local_player.stats
	var weapon_dmg := _inventory.get_weapon_damage()
	char_stats_label.clear()
	char_stats_label.append_text("[b]%s[/b] — Liv. %d\n\n" % [
		GameManager.local_player.character_name,
		GameManager.local_player.level
	])
	char_stats_label.append_text("FOR: %d  DES: %d  COS: %d\n" % [s.strength, s.dexterity, s.constitution])
	char_stats_label.append_text("INT: %d  PIE: %d  CAR: %d\n\n" % [s.intelligence, s.piety, s.charisma])
	char_stats_label.append_text("Vita: %d / %d\n" % [s.current_health, s.max_health])
	char_stats_label.append_text("Resistenza: %d / %d\n" % [s.current_endurance, s.max_endurance])
	char_stats_label.append_text("Potere: %d / %d\n\n" % [s.current_power, s.max_power])
	char_stats_label.append_text("Danno arma: %d - %d\n" % [weapon_dmg.x, weapon_dmg.y])
	char_stats_label.append_text("Armatura: %d\n" % s.armor)
	char_stats_label.append_text("Resist. Magia: %d\n" % s.magic_resist)
	char_stats_label.append_text("Parata: %.1f%%\n" % (s.parry_chance * 100))
	char_stats_label.append_text("Blocco: %.1f%%\n" % (s.block_chance * 100))

func _on_slot_clicked(index: int) -> void:
	if not _inventory:
		return
	var entry: Dictionary = _inventory.bags[index] if index < _inventory.bags.size() else {}
	if entry == null or entry.is_empty():
		return
	var item: Item = entry["item"]
	if item.equip_slot != Item.Slot.NONE:
		_inventory.equip_item(index)

func _on_equip_slot_clicked(equip_slot: Item.Slot) -> void:
	if not _inventory:
		return
	_inventory.unequip_slot(equip_slot)

func _show_tooltip(index: int) -> void:
	if not _inventory:
		return
	var entry: Dictionary = _inventory.bags[index] if index < _inventory.bags.size() else {}
	if entry == null or entry.is_empty():
		tooltip.visible = false
		return
	var item: Item = entry["item"]
	tooltip_label.clear()
	tooltip_label.append_text("[color=#%s][b]%s[/b][/color]\n" % [
		item.rarity_color().to_html(false), item.display_name
	])
	tooltip_label.append_text("%s\n\n" % item.description)
	for stat in item.stat_bonuses:
		var val: int = item.stat_bonuses[stat]
		tooltip_label.append_text("%s: %s%d\n" % [stat, "+" if val > 0 else "", val])
	if item.armor_value > 0:
		tooltip_label.append_text("Armatura: +%d\n" % item.armor_value)
	tooltip_label.append_text("\nLiv. richiesto: %d" % item.required_level)
	tooltip.global_position = get_global_mouse_position() + Vector2(10, 10)
	tooltip.visible = true

func toggle_visible() -> void:
	visible = not visible
	if visible:
		_refresh()
