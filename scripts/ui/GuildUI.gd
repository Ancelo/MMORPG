## Guild panel: member list, ranks, chat, MOTD, and guild management.
extends Control

@onready var guild_name_label: Label     = $Header/GuildName
@onready var motd_label: Label           = $Header/MOTD
@onready var member_list: ItemList       = $Body/MemberList
@onready var guild_chat_log: RichTextLabel = $Body/Chat/Log
@onready var guild_chat_input: LineEdit  = $Body/Chat/Input
@onready var create_panel: Control       = $CreatePanel
@onready var create_name_input: LineEdit = $CreatePanel/NameInput
@onready var create_confirm_btn: Button  = $CreatePanel/ConfirmBtn
@onready var create_cancel_btn: Button   = $CreatePanel/CancelBtn
@onready var create_guild_btn: Button    = $Header/CreateBtn
@onready var leave_guild_btn: Button     = $Header/LeaveBtn

var _guild_manager: GuildManager = null

func _ready() -> void:
	visible = false
	guild_chat_input.text_submitted.connect(_on_guild_chat_submitted)
	create_guild_btn.pressed.connect(func(): create_panel.visible = true)
	create_confirm_btn.pressed.connect(_on_create_confirmed)
	create_cancel_btn.pressed.connect(func(): create_panel.visible = false)
	leave_guild_btn.pressed.connect(_on_leave_guild)
	EventBus.chat_message_received.connect(_on_chat_received)
	EventBus.character_spawned.connect(_on_character_spawned)

func _on_character_spawned(_character: Node, peer_id: int) -> void:
	if peer_id != GameManager.local_peer_id:
		return
	_guild_manager = get_tree().get_first_node_in_group("guild_manager") as GuildManager
	_refresh()

func _refresh() -> void:
	if not visible or not GameManager.local_player:
		return
	var guild := _guild_manager.get_guild_of(GameManager.local_player.character_name) if _guild_manager else {}
	if guild.is_empty():
		guild_name_label.text = "Nessuna Gilda"
		motd_label.text = ""
		member_list.clear()
		create_guild_btn.visible = true
		leave_guild_btn.visible = false
		return

	create_guild_btn.visible = false
	leave_guild_btn.visible = true
	guild_name_label.text = guild["name"]
	motd_label.text = guild.get("motd", "")
	member_list.clear()
	for member in guild.get("members", []):
		var rank_name := GuildManager.get_guild_rank_name_static(member.get("rank", 0))
		member_list.add_item("[%s] %s" % [rank_name, member["name"]])

func _on_guild_chat_submitted(text: String) -> void:
	if text.is_empty() or not _guild_manager:
		return
	if GameManager.local_player:
		_guild_manager.send_guild_chat(GameManager.local_player, text)
	guild_chat_input.clear()

func _on_chat_received(sender: String, message: String, channel: String, _faction: int) -> void:
	if channel != "guild":
		return
	guild_chat_log.append_text("%s: %s\n" % [sender, message])

func _on_create_confirmed() -> void:
	if not _guild_manager or not GameManager.local_player:
		return
	var name := create_name_input.text.strip_edges()
	if name.length() < 3:
		return
	_guild_manager.create_guild(name, GameManager.local_player, GameManager.local_player.faction)
	create_panel.visible = false
	_refresh()

func _on_leave_guild() -> void:
	if not _guild_manager or not GameManager.local_player:
		return
	_guild_manager.leave_guild(GameManager.local_player)
	_refresh()

static func get_guild_rank_name_static(rank: int) -> String:
	match rank:
		5: return "Comandante Supremo"
		4: return "Comandante"
		3: return "Centurione"
		2: return "Veterano"
		1: return "Membro"
		_: return "Recluta"

func toggle_visible() -> void:
	visible = not visible
	if visible:
		_refresh()
