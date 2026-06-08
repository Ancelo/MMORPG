## Party frames: shows each member's name, role icon, HP/EP/PP bars and status effects.
extends Control

add_to_group("party_ui")

@onready var frames_container: VBoxContainer = $Frames
@onready var invite_popup: Control           = $InvitePopup
@onready var invite_label: Label             = $InvitePopup/Label
@onready var accept_btn: Button              = $InvitePopup/AcceptBtn
@onready var decline_btn: Button             = $InvitePopup/DeclineBtn
@onready var loot_method_btn: MenuButton     = $Controls/LootMethodBtn
@onready var role_btn: MenuButton            = $Controls/RoleBtn
@onready var ready_btn: CheckButton          = $Controls/ReadyBtn
@onready var leave_btn: Button               = $Controls/LeaveBtn

const FRAME_SCENE := "res://scenes/ui/PartyMemberFrame.tscn"

var _current_party: Dictionary = {}
var _member_frames: Dictionary = {}  # peer_id -> Control
var _local_peer_id: int = 0

func _ready() -> void:
	add_to_group("party_ui")
	invite_popup.visible = false
	visible = false
	_local_peer_id = GameManager.local_peer_id

	EventBus.player_connected.connect(func(_id): pass)

	accept_btn.pressed.connect(_on_accept_invite)
	decline_btn.pressed.connect(_on_decline_invite)
	leave_btn.pressed.connect(_on_leave_party)
	ready_btn.toggled.connect(_on_ready_toggled)

	_setup_loot_method_menu()
	_setup_role_menu()

	var pm := _get_party_manager()
	if pm:
		pm.invite_received.connect(_on_invite_received)

func _setup_loot_method_menu() -> void:
	var popup := loot_method_btn.get_popup()
	popup.clear()
	popup.add_item("Libero per tutti",  Party.LootMethod.FREE_FOR_ALL)
	popup.add_item("Round Robin",       Party.LootMethod.ROUND_ROBIN)
	popup.add_item("Master Looter",     Party.LootMethod.MASTER_LOOTER)
	popup.add_item("Bisogno/Avidità",   Party.LootMethod.NEED_GREED)
	popup.id_pressed.connect(_on_loot_method_selected)

func _setup_role_menu() -> void:
	var popup := role_btn.get_popup()
	popup.clear()
	popup.add_item("—",        Party.MemberRole.NONE)
	popup.add_item("Tank",     Party.MemberRole.TANK)
	popup.add_item("Guaritore",Party.MemberRole.HEALER)
	popup.add_item("DPS",      Party.MemberRole.DPS)
	popup.id_pressed.connect(_on_role_selected)

# Called by server RPC broadcast
func _on_party_data_received(party_data: Dictionary) -> void:
	_current_party = party_data
	if party_data.is_empty():
		visible = false
		_clear_frames()
		return
	visible = true
	_rebuild_frames(party_data)
	_update_controls(party_data)

func _rebuild_frames(party_data: Dictionary) -> void:
	var members: Dictionary = party_data.get("members", {})
	# Remove frames for members no longer in party
	for pid in _member_frames.keys():
		if str(pid) not in members and pid not in members:
			_member_frames[pid].queue_free()
			_member_frames.erase(pid)
	# Add/update frames
	for peer_id_str in members:
		var peer_id := int(peer_id_str)
		if peer_id == _local_peer_id:
			continue  # own vitals shown in main HUD
		if not _member_frames.has(peer_id):
			_add_member_frame(peer_id, members[peer_id_str])
		else:
			_update_member_frame(peer_id, members[peer_id_str])

func _add_member_frame(peer_id: int, member_data: Dictionary) -> void:
	var frame := _build_frame(peer_id, member_data)
	frames_container.add_child(frame)
	_member_frames[peer_id] = frame

func _build_frame(peer_id: int, member_data: Dictionary) -> Control:
	var container := VBoxContainer.new()
	container.name = "Frame_%d" % peer_id

	var name_row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = member_data.get("name", "?")
	name_lbl.name = "NameLabel"
	var role_lbl := Label.new()
	role_lbl.text = "[%s]" % Party.role_name(member_data.get("role", 0) as Party.MemberRole)
	role_lbl.name = "RoleLabel"
	role_lbl.modulate = Color.GRAY
	name_row.add_child(name_lbl)
	name_row.add_child(role_lbl)
	container.add_child(name_row)

	for bar_name in ["HP", "EP", "PP"]:
		var bar := ProgressBar.new()
		bar.name = bar_name + "Bar"
		bar.max_value = 100
		bar.value = 100
		bar.custom_minimum_size = Vector2(160, 12)
		match bar_name:
			"HP": bar.modulate = Color(0.8, 0.15, 0.15)
			"EP": bar.modulate = Color(0.9, 0.7, 0.1)
			"PP": bar.modulate = Color(0.2, 0.4, 0.9)
		container.add_child(bar)

	return container

func _update_member_frame(peer_id: int, _member_data: Dictionary) -> void:
	var frame := _member_frames.get(peer_id)
	if not frame:
		return
	var character := GameManager.get_player(peer_id) as Character
	if not character:
		return
	var s := character.stats
	_set_bar(frame, "HPBar", s.current_health,    s.max_health)
	_set_bar(frame, "EPBar", s.current_endurance,  s.max_endurance)
	_set_bar(frame, "PPBar", s.current_power,      s.max_power)

func _set_bar(frame: Control, bar_name: String, current: int, maximum: int) -> void:
	var bar := frame.get_node_or_null(bar_name) as ProgressBar
	if bar and maximum > 0:
		bar.max_value = maximum
		bar.value = current

func _process(_delta: float) -> void:
	if not visible:
		return
	for peer_id in _member_frames:
		_update_member_frame(peer_id, {})

func _clear_frames() -> void:
	for frame in _member_frames.values():
		frame.queue_free()
	_member_frames.clear()

func _update_controls(party_data: Dictionary) -> void:
	var is_leader: bool = party_data.get("leader", -1) == _local_peer_id
	loot_method_btn.visible = is_leader
	var method: int = party_data.get("loot_method", Party.LootMethod.NEED_GREED)
	loot_method_btn.text = ["Libero", "Round Robin", "Master", "Bisogno/Avid."][method]

# ----- Invite popup -----

func _on_invite_received(inviter_name: String, _party_id: int) -> void:
	invite_label.text = "%s ti invita nel gruppo!" % inviter_name
	invite_popup.visible = true

func _on_accept_invite() -> void:
	invite_popup.visible = false
	var pm := _get_party_manager()
	if pm:
		pm.rpc_accept_invite.rpc_id(1)

func _on_decline_invite() -> void:
	invite_popup.visible = false
	var pm := _get_party_manager()
	if pm:
		pm.rpc_decline_invite.rpc_id(1)

# ----- Controls -----

func _on_leave_party() -> void:
	var pm := _get_party_manager()
	if pm:
		pm.rpc_leave_party.rpc_id(1)

func _on_ready_toggled(pressed: bool) -> void:
	var pm := _get_party_manager()
	if pm:
		pm.rpc_set_ready.rpc_id(1, pressed)

func _on_loot_method_selected(id: int) -> void:
	var pm := _get_party_manager()
	if pm:
		pm.rpc_set_loot_method.rpc_id(1, id)

func _on_role_selected(id: int) -> void:
	var pm := _get_party_manager()
	if pm:
		pm.rpc_set_role.rpc_id(1, id)

func _get_party_manager() -> PartyManager:
	return get_tree().get_first_node_in_group("party_manager") as PartyManager
