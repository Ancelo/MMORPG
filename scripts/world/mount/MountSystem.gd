## Handles mounting and dismounting for a character.
## Attach as child of a PlayerCharacter.  Mount data lives in data/mounts/*.json.
class_name MountSystem
extends Node

signal mounted(mount_id: String)
signal dismounted()

var current_mount_id: String = ""
var is_mounted: bool = false

var _owner: Character
var _base_speed: float = 0.0

func _ready() -> void:
	_owner = get_parent() as Character
	if _owner:
		_owner.entered_combat = _on_entered_combat if _owner.has_signal("entered_combat") else Callable()
		# Listen to EventBus instead since Character doesn't have entered_combat signal
		EventBus.damage_dealt.connect(_on_damage_dealt)

func mount(mount_id: String) -> bool:
	if is_mounted or not _owner or _owner.is_in_combat or _owner.is_dead:
		return false
	var data := _get_mount_data(mount_id)
	if data.is_empty():
		push_warning("[MountSystem] Mount not found: %s" % mount_id)
		return false
	_base_speed = _owner.stats.speed
	_owner.stats.speed += float(data.get("speed_bonus", 6))
	current_mount_id = mount_id
	is_mounted = true
	mounted.emit(mount_id)
	return true

func dismount() -> void:
	if not is_mounted or not _owner:
		return
	_owner.stats.speed = _base_speed
	current_mount_id = ""
	is_mounted = false
	dismounted.emit()

func _on_damage_dealt(_attacker: Node, target: Node, _amount: int, _type: String) -> void:
	if target == _owner and is_mounted:
		dismount()

func _get_mount_data(mount_id: String) -> Dictionary:
	return DataManager.get_item(mount_id)

func _get_owner_peer_id() -> int:
	return _owner.name.to_int() if _owner else -1
