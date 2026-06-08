## Server-authoritative party manager: invites, formation, dungeon entry, loot control.
## Clients interact only via RPCs; no local state mutation.
extends Node

signal party_updated(party_id: int)
signal invite_received(from_name: String, party_id: int)

var _parties: Dictionary = {}          # party_id -> Party
var _peer_to_party: Dictionary = {}    # peer_id -> party_id
var _pending_invites: Dictionary = {}  # invitee_peer_id -> { party_id, inviter_peer_id, expires }
var _party_counter: int = 0

const INVITE_TIMEOUT := 30.0

func _ready() -> void:
	add_to_group("party_manager")
	EventBus.player_disconnected.connect(_on_player_disconnected)

func _process(delta: float) -> void:
	_expire_invites(delta)

# ----- Party creation -----

func create_party(leader_peer_id: int) -> Party:
	if _peer_to_party.has(leader_peer_id):
		return null  # already in a party
	_party_counter += 1
	var party := Party.new()
	party.party_id = _party_counter
	party.leader_peer_id = leader_peer_id
	var leader := GameManager.get_player(leader_peer_id) as Character
	party.add_member(leader_peer_id, leader.character_name if leader else "?")
	_parties[party.party_id] = party
	_peer_to_party[leader_peer_id] = party.party_id
	_broadcast_party_update(party)
	return party

func disband_party(party_id: int) -> void:
	var party: Party = _parties.get(party_id)
	if not party:
		return
	for peer_id in party.get_peer_ids():
		_peer_to_party.erase(peer_id)
		_notify_party_change.rpc_id(peer_id, {})
	_parties.erase(party_id)

# ----- Invites -----

@rpc("any_peer", "reliable")
func rpc_send_invite(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var sender := GameManager.get_player(sender_id) as Character
	if not sender:
		return

	# Get or create party
	var party_id: int = _peer_to_party.get(sender_id, -1)
	if party_id < 0:
		var new_party := create_party(sender_id)
		if not new_party:
			return
		party_id = new_party.party_id

	var party: Party = _parties.get(party_id)
	if not party or not party.is_leader(sender_id):
		return
	if party.size() >= Party.MAX_MEMBERS:
		EventBus.notification_pushed.emit("Gruppo al completo.", "party")
		return

	# Find target peer
	var target_peer_id := _find_peer_by_name(target_name)
	if target_peer_id < 0:
		return
	if _peer_to_party.has(target_peer_id):
		return

	_pending_invites[target_peer_id] = {
		"party_id": party_id,
		"inviter": sender_id,
		"expires": INVITE_TIMEOUT,
	}
	_notify_invite.rpc_id(target_peer_id, sender.character_name, party_id)

@rpc("authority", "reliable")
func _notify_invite(inviter_name: String, party_id: int) -> void:
	invite_received.emit(inviter_name, party_id)
	EventBus.notification_pushed.emit(
		"%s ti invita nel gruppo. /accetta o /rifiuta" % inviter_name, "party"
	)

@rpc("any_peer", "reliable")
func rpc_accept_invite() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var invite: Dictionary = _pending_invites.get(peer_id, {})
	if invite.is_empty():
		return
	_pending_invites.erase(peer_id)

	var party: Party = _parties.get(invite["party_id"])
	if not party:
		return
	var character := GameManager.get_player(peer_id) as Character
	if not character:
		return
	party.add_member(peer_id, character.character_name)
	_peer_to_party[peer_id] = party.party_id
	_broadcast_party_update(party)
	EventBus.notification_pushed.emit("%s si è unito al gruppo!" % character.character_name, "party")

@rpc("any_peer", "reliable")
func rpc_decline_invite() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_pending_invites.erase(peer_id)

# ----- Leave / Kick -----

@rpc("any_peer", "reliable")
func rpc_leave_party() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_remove_from_party(peer_id)

@rpc("any_peer", "reliable")
func rpc_kick_member(target_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var party := get_party_of(sender_id)
	if not party or not party.is_leader(sender_id):
		return
	_remove_from_party(target_peer_id)
	EventBus.notification_pushed.emit("Membro rimosso dal gruppo.", "party")

func _remove_from_party(peer_id: int) -> void:
	var party_id: int = _peer_to_party.get(peer_id, -1)
	if party_id < 0:
		return
	var party: Party = _parties.get(party_id)
	if not party:
		return
	party.remove_member(peer_id)
	_peer_to_party.erase(peer_id)
	_notify_party_change.rpc_id(peer_id, {})
	if party.size() <= 1:
		disband_party(party_id)
	else:
		_broadcast_party_update(party)

# ----- Role & settings -----

@rpc("any_peer", "reliable")
func rpc_set_role(role: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var party := get_party_of(peer_id)
	if party:
		party.set_role(peer_id, role as Party.MemberRole)
		_broadcast_party_update(party)

@rpc("any_peer", "reliable")
func rpc_set_loot_method(method: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var party := get_party_of(sender_id)
	if not party or not party.is_leader(sender_id):
		return
	party.loot_method = method as Party.LootMethod
	_broadcast_party_update(party)

@rpc("any_peer", "reliable")
func rpc_set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var party := get_party_of(peer_id)
	if not party:
		return
	party.set_ready(peer_id, ready)
	_broadcast_party_update(party)
	if party.all_ready():
		_on_party_all_ready(party)

func _on_party_all_ready(party: Party) -> void:
	EventBus.notification_pushed.emit("Tutti pronti! Il dungeon si apre.", "party")
	# DungeonManager picks this up
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm:
		# Use the zone/dungeon the leader is near — simplified: use first dungeon
		dm.request_enter("catacombe_romane", party.get_characters())

# ----- Broadcast -----

func _broadcast_party_update(party: Party) -> void:
	var data := party.to_dict()
	for peer_id in party.get_peer_ids():
		_notify_party_change.rpc_id(peer_id, data)
	party_updated.emit(party.party_id)

@rpc("authority", "reliable")
func _notify_party_change(party_data: Dictionary) -> void:
	EventBus.notification_pushed.emit("", "party_update")
	# PartyUI listens to this signal and refreshes
	get_tree().call_group("party_ui", "_on_party_data_received", party_data)

# ----- Queries -----

func get_party_of(peer_id: int) -> Party:
	var party_id: int = _peer_to_party.get(peer_id, -1)
	return _parties.get(party_id)

func in_same_party(peer_a: int, peer_b: int) -> bool:
	var pid_a: int = _peer_to_party.get(peer_a, -1)
	var pid_b: int = _peer_to_party.get(peer_b, -1)
	return pid_a >= 0 and pid_a == pid_b

func is_ally(peer_a: int, peer_b: int) -> bool:
	var char_a := GameManager.get_player(peer_a) as Character
	var char_b := GameManager.get_player(peer_b) as Character
	if not char_a or not char_b:
		return false
	return char_a.faction == char_b.faction or in_same_party(peer_a, peer_b)

# ----- Helpers -----

func _find_peer_by_name(name: String) -> int:
	for peer_id in GameManager.players:
		var c := GameManager.get_player(peer_id) as Character
		if c and c.character_name == name:
			return peer_id
	return -1

func _on_player_disconnected(peer_id: int) -> void:
	_remove_from_party(peer_id)
	_pending_invites.erase(peer_id)

func _expire_invites(delta: float) -> void:
	for peer_id in _pending_invites.keys():
		_pending_invites[peer_id]["expires"] -= delta
		if _pending_invites[peer_id]["expires"] <= 0.0:
			_pending_invites.erase(peer_id)
