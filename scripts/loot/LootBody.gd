## Spawned on the server when a character dies. Holds loot visible to nearby players.
## Disappears after DESPAWN_TIME seconds. Enforces party loot rules server-side.
class_name LootBody
extends Area3D

signal looted(peer_id: int, item_id: String)
signal body_empty()
signal body_despawned()

const DESPAWN_TIME     := 120.0  # 2 minutes
const LOOT_RANGE       := 3.0    # meters to interact
const GOLD_SHARE_RANGE := 50.0   # gold split radius

var _items: Array = []        # Array of { item_id, count }
var _gold: int = 0
var _owner_peer_id: int = -1  # peer who killed this — gets priority in FFA
var _party_id: int = -1       # party that gets loot rights
var _loot_method: Party.LootMethod = Party.LootMethod.FREE_FOR_ALL
var _need_greed_session: Dictionary = {}  # active NG vote
var _despawn_timer: float = 0.0
var _looted_by: Array = []    # peer_ids that already looted this body (round-robin tracking)

func _ready() -> void:
	_despawn_timer = DESPAWN_TIME
	add_to_group("loot_bodies")

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_despawn_timer -= delta
	if _despawn_timer <= 0.0:
		body_despawned.emit()
		queue_free()

# ----- Setup -----

func setup(killer_peer_id: int, items: Array, gold: int) -> void:
	_owner_peer_id = killer_peer_id
	_items = items.duplicate(true)
	_gold = gold

	var pm := _get_party_manager()
	if pm:
		var party := pm.get_party_of(killer_peer_id)
		if party:
			_party_id = party.party_id
			_loot_method = party.loot_method

	_distribute_gold()

func _distribute_gold() -> void:
	if _gold <= 0:
		return
	var pm := _get_party_manager()
	if pm and _party_id >= 0:
		var party := pm._parties.get(_party_id)
		if party:
			var split := _gold / party.size()
			for peer_id in party.get_peer_ids():
				var c := GameManager.get_player(peer_id) as Character
				if c and c.get_node_or_null("Inventory"):
					c.get_node("Inventory").add_gold(split)
			_gold = 0
			return
	# Solo kill — give gold directly
	var c := GameManager.get_player(_owner_peer_id) as Character
	if c and c.get_node_or_null("Inventory"):
		c.get_node("Inventory").add_gold(_gold)
	_gold = 0

# ----- Loot interaction -----

func can_loot(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	var character := GameManager.get_player(peer_id) as Character
	if not character:
		return false
	if character.global_position.distance_to(global_position) > LOOT_RANGE:
		return false
	if _items.is_empty():
		return false

	match _loot_method:
		Party.LootMethod.FREE_FOR_ALL:
			return true
		Party.LootMethod.ROUND_ROBIN:
			return peer_id not in _looted_by
		Party.LootMethod.MASTER_LOOTER:
			var pm := _get_party_manager()
			if pm:
				var party := pm._parties.get(_party_id)
				return party != null and party.master_looter_peer_id == peer_id
			return peer_id == _owner_peer_id
		Party.LootMethod.NEED_GREED:
			return _need_greed_session.is_empty()
	return false

func request_loot(peer_id: int) -> void:
	if not can_loot(peer_id):
		return
	match _loot_method:
		Party.LootMethod.FREE_FOR_ALL, Party.LootMethod.MASTER_LOOTER:
			_give_all_items_to(peer_id)
		Party.LootMethod.ROUND_ROBIN:
			_give_all_items_to(peer_id)
			_looted_by.append(peer_id)
		Party.LootMethod.NEED_GREED:
			_start_need_greed_vote(peer_id)

func _give_all_items_to(peer_id: int) -> void:
	var c := GameManager.get_player(peer_id) as Character
	if not c or not c.get_node_or_null("Inventory"):
		return
	var inventory := c.get_node("Inventory") as Inventory
	for entry in _items:
		inventory.add_item(entry["item_id"], entry.get("count", 1))
		looted.emit(peer_id, entry["item_id"])
	_items.clear()
	body_empty.emit()

# ----- Need / Greed -----

func _start_need_greed_vote(initiator_peer_id: int) -> void:
	if _items.is_empty():
		return
	var item_entry: Dictionary = _items[0]
	var item_data := DataManager.get_item(item_entry["item_id"])

	_need_greed_session = {
		"item_id": item_entry["item_id"],
		"count": item_entry.get("count", 1),
		"votes": {},         # peer_id -> "need" | "greed" | "pass"
		"timer": 30.0,
	}

	var pm := _get_party_manager()
	if pm and _party_id >= 0:
		var party := pm._parties.get(_party_id)
		if party:
			for peer_id in party.get_peer_ids():
				_send_ng_vote_request.rpc_id(peer_id, item_entry["item_id"], item_data.get("name","?"))
	else:
		_cast_ng_vote(initiator_peer_id, "need")

@rpc("authority", "reliable")
func _send_ng_vote_request(item_id: String, item_name: String) -> void:
	EventBus.notification_pushed.emit(
		"Bisogno/Avidità: [b]%s[/b] — premi N (bisogno) G (avidità) P (passa)" % item_name,
		"loot_ng"
	)

@rpc("any_peer", "reliable")
func rpc_cast_ng_vote(vote: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_cast_ng_vote(peer_id, vote)

func _cast_ng_vote(peer_id: int, vote: String) -> void:
	if _need_greed_session.is_empty():
		return
	_need_greed_session["votes"][peer_id] = vote
	_check_ng_resolution()

func _process_ng_timer(delta: float) -> void:
	if _need_greed_session.is_empty():
		return
	_need_greed_session["timer"] -= delta
	if _need_greed_session["timer"] <= 0.0:
		_resolve_ng_vote()

func _check_ng_resolution() -> void:
	var pm := _get_party_manager()
	if not pm or _party_id < 0:
		_resolve_ng_vote()
		return
	var party := pm._parties.get(_party_id)
	if not party:
		_resolve_ng_vote()
		return
	if _need_greed_session["votes"].size() >= party.size():
		_resolve_ng_vote()

func _resolve_ng_vote() -> void:
	if _need_greed_session.is_empty():
		return
	var item_id: String = _need_greed_session["item_id"]
	var count: int = _need_greed_session["count"]
	var votes: Dictionary = _need_greed_session["votes"]
	_need_greed_session.clear()

	# Need beats greed beats pass; ties broken randomly
	var need_rollers: Array = []
	var greed_rollers: Array = []
	for peer_id in votes:
		match votes[peer_id]:
			"need":  need_rollers.append(peer_id)
			"greed": greed_rollers.append(peer_id)

	var winner_pool := need_rollers if not need_rollers.is_empty() else greed_rollers
	if winner_pool.is_empty():
		# All passed — nobody gets it; leave it on body
		_items.erase(_items[0])
		return

	winner_pool.shuffle()
	var winner: int = winner_pool[0]
	var c := GameManager.get_player(winner) as Character
	if c and c.get_node_or_null("Inventory"):
		c.get_node("Inventory").add_item(item_id, count)
		looted.emit(winner, item_id)
		var item_data := DataManager.get_item(item_id)
		EventBus.notification_pushed.emit(
			"%s ha vinto: %s!" % [c.character_name, item_data.get("name", item_id)],
			"loot"
		)
	_items.remove_at(0)
	if _items.is_empty():
		body_empty.emit()
	else:
		# Start vote for next item
		_start_need_greed_vote(winner)

func get_item_list() -> Array:
	return _items.duplicate()

func _get_party_manager() -> PartyManager:
	return get_tree().get_first_node_in_group("party_manager") as PartyManager
