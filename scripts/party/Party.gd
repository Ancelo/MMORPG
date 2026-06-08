## Party data object: members, roles, loot rules, leader.
class_name Party
extends RefCounted

enum LootMethod { FREE_FOR_ALL, ROUND_ROBIN, MASTER_LOOTER, NEED_GREED }
enum MemberRole { NONE, TANK, HEALER, DPS }

const MAX_MEMBERS := 8

var party_id: int = 0
var leader_peer_id: int = 0
var loot_method: LootMethod = LootMethod.NEED_GREED
var master_looter_peer_id: int = 0

# peer_id -> { "name", "role", "ready" }
var members: Dictionary = {}

# Round-robin loot cursor
var _rr_cursor: int = 0

func add_member(peer_id: int, character_name: String) -> bool:
	if members.size() >= MAX_MEMBERS:
		return false
	if members.has(peer_id):
		return false
	members[peer_id] = {
		"name": character_name,
		"role": MemberRole.NONE,
		"ready": false,
	}
	return true

func remove_member(peer_id: int) -> void:
	members.erase(peer_id)
	if peer_id == leader_peer_id and not members.is_empty():
		leader_peer_id = members.keys()[0]
	if peer_id == master_looter_peer_id:
		master_looter_peer_id = leader_peer_id

func set_role(peer_id: int, role: MemberRole) -> void:
	if members.has(peer_id):
		members[peer_id]["role"] = role

func set_ready(peer_id: int, ready: bool) -> void:
	if members.has(peer_id):
		members[peer_id]["ready"] = ready

func is_leader(peer_id: int) -> bool:
	return peer_id == leader_peer_id

func all_ready() -> bool:
	for m in members.values():
		if not m["ready"]:
			return false
	return not members.is_empty()

func get_peer_ids() -> Array:
	return members.keys()

func get_characters() -> Array:
	var result: Array = []
	for peer_id in members:
		var c := GameManager.get_player(peer_id)
		if c:
			result.append(c)
	return result

func size() -> int:
	return members.size()

func next_round_robin_peer() -> int:
	var ids := members.keys()
	if ids.is_empty():
		return -1
	_rr_cursor = _rr_cursor % ids.size()
	var peer_id: int = ids[_rr_cursor]
	_rr_cursor += 1
	return peer_id

func to_dict() -> Dictionary:
	return {
		"id": party_id,
		"leader": leader_peer_id,
		"loot_method": int(loot_method),
		"master_looter": master_looter_peer_id,
		"members": members.duplicate(true),
	}

static func role_name(role: MemberRole) -> String:
	match role:
		MemberRole.TANK:   return "Tank"
		MemberRole.HEALER: return "Guaritore"
		MemberRole.DPS:    return "DPS"
		_: return "—"
