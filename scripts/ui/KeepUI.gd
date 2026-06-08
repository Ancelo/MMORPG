## HUD overlay showing nearby keep status: owner, wall/gate health, assault progress.
## Also provides siege weapon placement interface.
extends Control

@onready var keep_panel: Control           = $KeepPanel
@onready var keep_name_label: Label        = $KeepPanel/KeepName
@onready var owner_label: Label            = $KeepPanel/OwnerLabel
@onready var assault_label: Label          = $KeepPanel/AssaultLabel
@onready var outer_gate_bar: ProgressBar   = $KeepPanel/OuterGateBar
@onready var inner_gate_bar: ProgressBar   = $KeepPanel/InnerGateBar
@onready var wall_bar: ProgressBar         = $KeepPanel/WallBar
@onready var lord_label: Label             = $KeepPanel/LordLabel

@onready var siege_panel: Control          = $SiegePanel
@onready var trebuchet_btn: Button         = $SiegePanel/TrebuchetBtn
@onready var ballista_btn: Button          = $SiegePanel/BallistaBtn
@onready var ram_btn: Button               = $SiegePanel/RamBtn
@onready var oil_btn: Button               = $SiegePanel/OilBtn
@onready var siege_cost_label: Label       = $SiegePanel/CostLabel

const SIEGE_COSTS := {
	SiegeWeapon.SiegeType.TREBUCHET:     500,
	SiegeWeapon.SiegeType.BALLISTA:      200,
	SiegeWeapon.SiegeType.BATTERING_RAM: 150,
	SiegeWeapon.SiegeType.BOILING_OIL:  100,
}

var _tracked_keep: KeepStructure = null
var _keep_assault_manager: KeepAssaultManager = null
var _selected_siege_type: int = SiegeWeapon.SiegeType.TREBUCHET

func _ready() -> void:
	keep_panel.visible = false
	siege_panel.visible = false
	trebuchet_btn.pressed.connect(func(): _select_siege(SiegeWeapon.SiegeType.TREBUCHET))
	ballista_btn.pressed.connect(func():  _select_siege(SiegeWeapon.SiegeType.BALLISTA))
	ram_btn.pressed.connect(func():       _select_siege(SiegeWeapon.SiegeType.BATTERING_RAM))
	oil_btn.pressed.connect(func():       _select_siege(SiegeWeapon.SiegeType.BOILING_OIL))

	_keep_assault_manager = get_tree().get_first_node_in_group("keep_assault_manager")
	if _keep_assault_manager:
		_keep_assault_manager.keep_status_changed.connect(_on_keep_status_changed)

func _process(_delta: float) -> void:
	_update_nearby_keep()

func _update_nearby_keep() -> void:
	if not GameManager.local_player:
		return
	var nearest := _find_nearest_keep()
	if nearest != _tracked_keep:
		_tracked_keep = nearest
		keep_panel.visible = nearest != null
		siege_panel.visible = nearest != null and _is_enemy_of_keep(nearest)

	if _tracked_keep:
		_refresh_keep_display()

func _find_nearest_keep() -> KeepStructure:
	if not GameManager.local_player:
		return null
	var origin := GameManager.local_player.global_position
	var best: KeepStructure = null
	var best_dist := 150.0
	for node in get_tree().get_nodes_in_group("keep_structures"):
		var keep := node as KeepStructure
		if not keep:
			continue
		var d := origin.distance_to(keep.global_position)
		if d < best_dist:
			best_dist = d
			best = keep
	return best

func _is_enemy_of_keep(keep: KeepStructure) -> bool:
	if not GameManager.local_player:
		return false
	var local_faction := GameManager.local_player.faction
	return keep.owner_faction != GameManager.Faction.NONE and \
		   GameManager.is_enemy(keep.owner_faction, local_faction)

func _refresh_keep_display() -> void:
	var keep := _tracked_keep
	keep_name_label.text = keep.keep_name
	owner_label.text = "Proprietario: %s" % GameManager.faction_name(keep.owner_faction)
	owner_label.modulate = GameManager.faction_color(keep.owner_faction)

	var assault_texts := ["Pacifico", "Contestato", "Sotto Assedio", "Breccia Interna"]
	assault_label.text = assault_texts[int(keep.assault_state)]
	match keep.assault_state:
		KeepStructure.AssaultState.PEACEFUL:    assault_label.modulate = Color.GREEN
		KeepStructure.AssaultState.CONTESTED:   assault_label.modulate = Color.YELLOW
		KeepStructure.AssaultState.UNDER_ASSAULT: assault_label.modulate = Color.ORANGE
		KeepStructure.AssaultState.INNER_BREACH: assault_label.modulate = Color.RED

	# Gate health bars
	var outer_pct := 1.0
	for gate in keep.outer_gates:
		outer_pct = min(outer_pct, (gate as KeepGate).health_percent())
	outer_gate_bar.value = outer_pct * 100.0

	if keep.inner_gate:
		inner_gate_bar.value = keep.inner_gate.health_percent() * 100.0

	# Wall health (average)
	var wall_total := 0.0
	for wall in keep.outer_walls:
		wall_total += (wall as KeepWall).health_percent()
	if not keep.outer_walls.is_empty():
		wall_bar.value = (wall_total / keep.outer_walls.size()) * 100.0

	lord_label.text = "Lord: %s" % ("VIVO" if keep.keep_lord else "—")
	lord_label.modulate = Color.RED if keep.keep_lord else Color.GRAY

func _on_keep_status_changed(_keep_id: String, _status: Dictionary) -> void:
	pass  # refresh happens in _process

# ----- Siege placement -----

func _select_siege(type: int) -> void:
	_selected_siege_type = type
	siege_cost_label.text = "Costo: %d oro" % SIEGE_COSTS.get(type, 0)

func _input(event: InputEvent) -> void:
	if not siege_panel.visible:
		return
	if event is InputEventMouseButton and event.pressed and \
	   event.button_index == MOUSE_BUTTON_RIGHT and \
	   Input.is_key_pressed(KEY_SHIFT):
		_place_siege_at_cursor()

func _place_siege_at_cursor() -> void:
	if not GameManager.local_player or not _tracked_keep:
		return
	var cost: int = SIEGE_COSTS.get(_selected_siege_type, 0)
	var inventory := GameManager.local_player.get_node_or_null("Inventory") as Inventory
	if not inventory or not inventory.spend_gold(cost):
		EventBus.notification_pushed.emit("Oro insufficiente per l'arma d'assedio.", "siege")
		return

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var screen_center := get_viewport().get_visible_rect().size / 2.0
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_dir := camera.project_ray_normal(screen_center)
	var plane := Plane(Vector3.UP, 0.0)
	var hit := plane.intersects_ray(ray_origin, ray_dir)
	if not hit:
		return

	var am := get_tree().get_first_node_in_group("keep_assault_manager") as KeepAssaultManager
	if am:
		am.rpc_request_place_siege.rpc_id(1, _tracked_keep.keep_id,
			_selected_siege_type, hit)
