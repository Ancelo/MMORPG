## Server-side chat command parser.  Call parse() before broadcasting a message.
## Returns true if the text was a command (and should not be broadcast as chat).
extends Node

func _ready() -> void:
	add_to_group("chat_command_parser")

func parse(text: String, sender: Character) -> bool:
	if not text.begins_with("/"):
		return false
	var parts := text.split(" ", false)
	if parts.is_empty():
		return false
	var cmd := parts[0].to_lower()
	var args: Array = parts.slice(1)

	match cmd:
		"/invite":       _cmd_invite(args, sender)
		"/party":        _cmd_party(args, sender)
		"/guild":        _cmd_guild(args, sender)
		"/tell", "/t":   _cmd_tell(args, sender)
		"/yell", "/y":   _cmd_yell(text.substr(text.find(" ") + 1), sender)
		"/zone", "/z":   _cmd_zone(text.substr(text.find(" ") + 1), sender)
		"/who":          _cmd_who(sender)
		"/help":         _cmd_help(sender)
		_:
			_reply(sender, "Comando sconosciuto. Digita /help per l'elenco.")
	return true

# ----- Commands -----

func _cmd_invite(args: Array, sender: Character) -> void:
	if args.is_empty():
		_reply(sender, "Uso: /invite <nome>")
		return
	var target_name: String = args[0]
	var target := _find_player_by_name(target_name)
	if not target:
		_reply(sender, "Giocatore '%s' non trovato." % target_name)
		return
	var pm := _party_manager()
	if pm:
		pm.rpc_send_invite.rpc_id(GameManager.peer_id_for(target), sender.name.to_int())
	_reply(sender, "Invito inviato a %s." % target_name)

func _cmd_party(args: Array, sender: Character) -> void:
	if args.is_empty():
		_reply(sender, "Uso: /party leave | /party kick <nome> | /party leader <nome>")
		return
	match args[0].to_lower():
		"leave":
			var pm := _party_manager()
			if pm:
				pm.rpc_leave_party.rpc_id(1, sender.name.to_int())
		"kick":
			if args.size() < 2:
				_reply(sender, "Uso: /party kick <nome>")
				return
			var target := _find_player_by_name(args[1])
			if target:
				var pm := _party_manager()
				if pm:
					pm.rpc_kick_member.rpc_id(1, sender.name.to_int(), target.name.to_int())
		_:
			_reply(sender, "Subcomando sconosciuto. Usa: leave, kick.")

func _cmd_guild(args: Array, sender: Character) -> void:
	if args.is_empty():
		_reply(sender, "Uso: /guild create <nome> | /guild invite <nome> | /guild leave")
		return
	var gm := _get_node_in_group("guild_manager")
	match args[0].to_lower():
		"create":
			if args.size() < 2:
				_reply(sender, "Uso: /guild create <nome>")
				return
			var guild_name := " ".join(args.slice(1))
			if gm:
				gm.create_guild(guild_name, sender.name.to_int())
		"leave":
			if gm:
				gm.leave_guild(sender.name.to_int())
		_:
			_reply(sender, "Subcomando sconosciuto.")

func _cmd_tell(args: Array, sender: Character) -> void:
	if args.size() < 2:
		_reply(sender, "Uso: /tell <nome> <messaggio>")
		return
	var target := _find_player_by_name(args[0])
	if not target:
		_reply(sender, "Giocatore '%s' non trovato." % args[0])
		return
	var msg := " ".join(args.slice(1))
	var target_peer := target.name.to_int()
	# Send only to sender and recipient
	NetworkManager._rpc_broadcast_chat.rpc_id(
		target_peer, sender.character_name, msg, "tell", sender.faction)
	_reply(sender, "[a %s]: %s" % [target.character_name, msg])

func _cmd_yell(message: String, sender: Character) -> void:
	if message.strip_edges().is_empty():
		return
	# Broadcast to all players in the same zone (simplified: broadcast to all)
	NetworkManager._rpc_broadcast_chat.rpc(sender.character_name, message, "yell", sender.faction)

func _cmd_zone(message: String, sender: Character) -> void:
	if message.strip_edges().is_empty():
		return
	NetworkManager._rpc_broadcast_chat.rpc(sender.character_name, message, "zone", sender.faction)

func _cmd_who(sender: Character) -> void:
	var lines: Array[String] = []
	for peer_id in GameManager.players:
		var c: Character = GameManager.players[peer_id]
		lines.append("%s (lv%d %s, %s)" % [
			c.character_name, c.level, c.character_class,
			GameManager.faction_name(c.faction)
		])
	_reply(sender, "Online (%d): %s" % [lines.size(), ", ".join(lines)])

func _cmd_help(sender: Character) -> void:
	var cmds := [
		"/invite <nome>     - Invita un giocatore nella tua gruppo",
		"/party leave|kick  - Gestisci il gruppo",
		"/guild create|leave- Gestisci la gilda",
		"/tell <nome> <msg> - Messaggio privato",
		"/yell <msg>        - Grida (zona intera)",
		"/zone <msg>        - Chat di zona",
		"/who               - Lista giocatori online",
	]
	_reply(sender, "\n".join(cmds))

# ----- Helpers -----

func _reply(sender: Character, text: String) -> void:
	var peer_id := sender.name.to_int()
	NetworkManager._rpc_broadcast_chat.rpc_id(peer_id, "Sistema", text, "system", 0)

func _find_player_by_name(player_name: String) -> Character:
	for peer_id in GameManager.players:
		var c: Character = GameManager.players[peer_id]
		if c.character_name.to_lower() == player_name.to_lower():
			return c
	return null

func _party_manager() -> Node:
	return _get_node_in_group("party_manager")

func _get_node_in_group(group: String) -> Node:
	var nodes := get_tree().get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null
