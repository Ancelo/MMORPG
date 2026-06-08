## Server-side coordinator for all keeps in the RvR zone.
## Handles siege weapon placement, assault notifications, and coordinates with RvRManager.
extends Node

signal keep_status_changed(keep_id: String, status: Dictionary)

# keep_id -> KeepStructure
var keeps: Dictionary = {}

# Placeable siege weapon definitions per faction per keep
# faction -> list of { type, position, deployed }
var _siege_placements: Dictionary = {}

const SIEGE_PLACEMENT_RANGE := 60.0  # meters from keep walls to place siege

func _ready() -> void:
	add_to_group("keep_assault_manager")
	_discover_keeps()
	_connect_keep_signals()

func _discover_keeps() -> void:
	for node in get_tree().get_nodes_in_group("keep_structures"):
		var keep := node as KeepStructure
		if keep:
			keeps[keep.keep_id] = keep

func _connect_keep_signals() -> void:
	for keep in keeps.values():
		var ks := keep as KeepStructure
		ks.ownership_changed.connect(_on_ownership_changed)
		ks.assault_started.connect(func(faction): _on_assault_started(ks.keep_id, faction))
		ks.assault_ended.connect(func(result): _on_assault_ended(ks.keep_id, result))

# ----- Siege weapon placement -----

@rpc("any_peer", "reliable")
func rpc_request_place_siege(keep_id: String, siege_type: int, position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var sender := GameManager.get_player(sender_id) as Character
	if not sender:
		return

	var keep: KeepStructure = keeps.get(keep_id)
	if not keep:
		return

	# Must be enemy of keep owner to place siege, or keep is neutral
	if keep.owner_faction != GameManager.Faction.NONE and \
	   not GameManager.is_enemy(keep.owner_faction, sender.faction):
		return

	# Must be within siege range of the keep
	if keep.global_position.distance_to(position) > SIEGE_PLACEMENT_RANGE:
		EventBus.notification_pushed.emit("Troppo lontano per posizionare l'arma d'assedio.", "siege")
		return

	# Spawn siege weapon
	_spawn_siege_weapon(keep_id, siege_type as SiegeWeapon.SiegeType, position, sender.faction)

func _spawn_siege_weapon(keep_id: String, siege_type: SiegeWeapon.SiegeType,
						  position: Vector3, faction: GameManager.Faction) -> void:
	var scene_path := _siege_scene_path(siege_type)
	var packed := load(scene_path) as PackedScene
	var weapon: SiegeWeapon
	if packed:
		weapon = packed.instantiate() as SiegeWeapon
	else:
		weapon = SiegeWeapon.new()
		weapon.siege_type = siege_type
		weapon.display_name = _siege_display_name(siege_type)

	weapon.global_position = position
	weapon.owner_faction   = faction
	weapon.begin_deploy()
	get_tree().current_scene.add_child(weapon)

	EventBus.notification_pushed.emit(
		"%s posizionato!" % _siege_display_name(siege_type), "siege"
	)

func _siege_scene_path(siege_type: SiegeWeapon.SiegeType) -> String:
	match siege_type:
		SiegeWeapon.SiegeType.TREBUCHET:    return "res://scenes/siege/Trebuchet.tscn"
		SiegeWeapon.SiegeType.BALLISTA:     return "res://scenes/siege/Ballista.tscn"
		SiegeWeapon.SiegeType.BATTERING_RAM:return "res://scenes/siege/BatteringRam.tscn"
		SiegeWeapon.SiegeType.BOILING_OIL: return "res://scenes/siege/BoilingOil.tscn"
		_: return ""

func _siege_display_name(siege_type: SiegeWeapon.SiegeType) -> String:
	match siege_type:
		SiegeWeapon.SiegeType.TREBUCHET:     return "Trebuchet"
		SiegeWeapon.SiegeType.BALLISTA:      return "Balista"
		SiegeWeapon.SiegeType.BATTERING_RAM: return "Ariete"
		SiegeWeapon.SiegeType.BOILING_OIL:  return "Olio Bollente"
		_: return "Arma d'Assedio"

# ----- Siege weapon firing -----

@rpc("any_peer", "reliable")
func rpc_fire_siege(weapon_path: String, target_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var weapon := get_node_or_null(weapon_path) as SiegeWeapon
	if not weapon:
		return
	if sender_id not in weapon.operators:
		return
	weapon.fire(target_pos)

@rpc("any_peer", "reliable")
func rpc_operate_siege(weapon_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var weapon := get_node_or_null(weapon_path) as SiegeWeapon
	if weapon:
		weapon.try_operate(sender_id)

@rpc("any_peer", "reliable")
func rpc_leave_siege(weapon_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var weapon := get_node_or_null(weapon_path) as SiegeWeapon
	if weapon:
		weapon.stop_operating(sender_id)

# ----- Event callbacks -----

func _on_ownership_changed(keep_id: String, old_faction: GameManager.Faction,
							new_faction: GameManager.Faction) -> void:
	var keep: KeepStructure = keeps.get(keep_id)
	if keep:
		keep_status_changed.emit(keep_id, keep.get_status_summary())
	_broadcast_keep_status(keep_id)

func _on_assault_started(keep_id: String, faction: GameManager.Faction) -> void:
	_broadcast_keep_status(keep_id)

func _on_assault_ended(keep_id: String, _result: String) -> void:
	_broadcast_keep_status(keep_id)

func _broadcast_keep_status(keep_id: String) -> void:
	var keep: KeepStructure = keeps.get(keep_id)
	if not keep:
		return
	var status := keep.get_status_summary()
	_rpc_keep_status_update.rpc(keep_id, status)

@rpc("authority", "reliable")
func _rpc_keep_status_update(keep_id: String, status: Dictionary) -> void:
	keep_status_changed.emit(keep_id, status)

# ----- State queries -----

func get_all_keep_statuses() -> Array:
	var result: Array = []
	for keep in keeps.values():
		result.append((keep as KeepStructure).get_status_summary())
	return result

func get_keeps_owned_by(faction: GameManager.Faction) -> Array:
	var result: Array = []
	for keep in keeps.values():
		if (keep as KeepStructure).owner_faction == faction:
			result.append(keep)
	return result
