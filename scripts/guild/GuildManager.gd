## Guild (Legione/Tribù) system: creation, membership, ranks, bank, and chat.
class_name GuildManager
extends Node

const MAX_MEMBERS := 300
const MAX_RANK := 5  # 0=recruit 1=member 2=veteran 3=officer 4=commander 5=leader

enum GuildRank {
	RECRUIT   = 0,
	MEMBER    = 1,
	VETERAN   = 2,
	OFFICER   = 3,
	COMMANDER = 4,
	LEADER    = 5,
}

# Active guilds loaded into memory (server-side)
var _guilds: Dictionary = {}  # guild_name -> guild_data dict

# Per-player guild lookup: character_name -> guild_name
var _player_guild: Dictionary = {}

func _ready() -> void:
	add_to_group("guild_manager")
	_load_guilds_from_disk()

func _load_guilds_from_disk() -> void:
	var dir := DirAccess.open("user://guilds")
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var data := DatabaseManager.load_guild(fname.get_basename())
			if not data.is_empty():
				_guilds[data["name"]] = data
				for member in data.get("members", []):
					_player_guild[member["name"]] = data["name"]
		fname = dir.get_next()

# ----- Guild creation -----

func create_guild(guild_name: String, founder: Character, faction: GameManager.Faction) -> bool:
	if _guilds.has(guild_name):
		EventBus.notification_pushed.emit("Nome già in uso da un'altra gilda.", "guild")
		return false
	if guild_name.length() < 3 or guild_name.length() > 30:
		EventBus.notification_pushed.emit("Nome gilda: 3-30 caratteri.", "guild")
		return false
	if _player_guild.has(founder.character_name):
		EventBus.notification_pushed.emit("Sei già in una gilda.", "guild")
		return false

	var data := {
		"name": guild_name,
		"faction": int(faction),
		"leader": founder.character_name,
		"description": "",
		"emblem": "",
		"bank_gold": 0,
		"bank_items": [],
		"members": [
			{"name": founder.character_name, "rank": GuildRank.LEADER, "joined": Time.get_date_string_from_system()}
		],
		"motd": "Benvenuto nella gilda %s!" % guild_name,
		"kill_points": 0,
		"created": Time.get_date_string_from_system(),
	}
	_guilds[guild_name] = data
	_player_guild[founder.character_name] = guild_name
	DatabaseManager.save_guild(data)
	EventBus.notification_pushed.emit("Gilda '%s' fondata!" % guild_name, "guild")
	return true

# ----- Membership -----

func invite_member(inviter: Character, target_name: String) -> bool:
	var guild_name: String = _player_guild.get(inviter.character_name, "")
	if guild_name.is_empty():
		return false
	var guild: Dictionary = _guilds[guild_name]
	var inviter_rank := _get_member_rank(guild, inviter.character_name)
	if inviter_rank < GuildRank.OFFICER:
		EventBus.notification_pushed.emit("Devi essere Ufficiale per invitare.", "guild")
		return false
	if _player_guild.has(target_name):
		EventBus.notification_pushed.emit("%s è già in una gilda." % target_name, "guild")
		return false
	if guild["members"].size() >= MAX_MEMBERS:
		EventBus.notification_pushed.emit("Gilda al completo (%d/%d)." % [guild["members"].size(), MAX_MEMBERS], "guild")
		return false
	# TODO: send invite request to target player via RPC
	EventBus.notification_pushed.emit("Invito inviato a %s." % target_name, "guild")
	return true

func accept_invite(character: Character, guild_name: String) -> bool:
	if not _guilds.has(guild_name):
		return false
	var guild: Dictionary = _guilds[guild_name]
	guild["members"].append({
		"name": character.character_name,
		"rank": GuildRank.RECRUIT,
		"joined": Time.get_date_string_from_system()
	})
	_player_guild[character.character_name] = guild_name
	DatabaseManager.save_guild(guild)
	EventBus.notification_pushed.emit(
		"%s si è unito a %s!" % [character.character_name, guild_name],
		"guild"
	)
	return true

func leave_guild(character: Character) -> bool:
	var guild_name: String = _player_guild.get(character.character_name, "")
	if guild_name.is_empty():
		return false
	var guild: Dictionary = _guilds[guild_name]
	if guild["leader"] == character.character_name:
		EventBus.notification_pushed.emit("Il leader non può abbandonare. Trasferisci prima la leadership.", "guild")
		return false
	guild["members"] = guild["members"].filter(func(m): return m["name"] != character.character_name)
	_player_guild.erase(character.character_name)
	DatabaseManager.save_guild(guild)
	EventBus.notification_pushed.emit("Hai abbandonato %s." % guild_name, "guild")
	return true

func promote_member(promoter: Character, target_name: String) -> bool:
	return _change_rank(promoter, target_name, 1)

func demote_member(demoter: Character, target_name: String) -> bool:
	return _change_rank(demoter, target_name, -1)

func _change_rank(actor: Character, target_name: String, delta: int) -> bool:
	var guild_name: String = _player_guild.get(actor.character_name, "")
	if guild_name.is_empty():
		return false
	var guild: Dictionary = _guilds[guild_name]
	var actor_rank  := _get_member_rank(guild, actor.character_name)
	var target_rank := _get_member_rank(guild, target_name)
	if actor_rank <= target_rank:
		EventBus.notification_pushed.emit("Non puoi modificare il rango di qualcuno di pari o superiore grado.", "guild")
		return false
	for member in guild["members"]:
		if member["name"] == target_name:
			member["rank"] = clampi(member["rank"] + delta, 0, MAX_RANK - 1)
			DatabaseManager.save_guild(guild)
			return true
	return false

func _get_member_rank(guild: Dictionary, char_name: String) -> int:
	for member in guild.get("members", []):
		if member["name"] == char_name:
			return member.get("rank", 0)
	return -1

# ----- Guild chat -----

func send_guild_chat(sender: Character, message: String) -> void:
	var guild_name: String = _player_guild.get(sender.character_name, "")
	if guild_name.is_empty():
		return
	var guild: Dictionary = _guilds[guild_name]
	for member in guild["members"]:
		var peer_char := _find_online_player(member["name"])
		if peer_char:
			EventBus.chat_message_received.emit(
				"[GILDA] %s" % sender.character_name,
				message, "guild", int(sender.faction)
			)

func _find_online_player(char_name: String) -> Character:
	for character in GameManager.players.values():
		if character.character_name == char_name:
			return character
	return null

# ----- Info -----

func get_guild_of(character_name: String) -> Dictionary:
	var guild_name: String = _player_guild.get(character_name, "")
	if guild_name.is_empty():
		return {}
	return _guilds.get(guild_name, {})

func get_guild_rank_name(rank: int) -> String:
	match rank:
		GuildRank.LEADER:    return "Comandante Supremo"
		GuildRank.COMMANDER: return "Comandante"
		GuildRank.OFFICER:   return "Centurione"
		GuildRank.VETERAN:   return "Veterano"
		GuildRank.MEMBER:    return "Membro"
		GuildRank.RECRUIT:   return "Recluta"
		_: return "?"

func add_rvr_kill_points(guild_name: String, points: int) -> void:
	if not _guilds.has(guild_name):
		return
	_guilds[guild_name]["kill_points"] = _guilds[guild_name].get("kill_points", 0) + points
