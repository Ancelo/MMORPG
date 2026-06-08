## Loot window: shows items in a nearby LootBody. Opens on F key near corpse.
extends Control

@onready var item_list: ItemList   = $Panel/ItemList
@onready var loot_all_btn: Button  = $Panel/Buttons/LootAllBtn
@onready var close_btn: Button     = $Panel/Buttons/CloseBtn
@onready var body_label: Label     = $Panel/BodyLabel
@onready var ng_panel: Control     = $NGPanel
@onready var ng_item_label: Label  = $NGPanel/ItemLabel
@onready var ng_need_btn: Button   = $NGPanel/NeedBtn
@onready var ng_greed_btn: Button  = $NGPanel/GreedBtn
@onready var ng_pass_btn: Button   = $NGPanel/PassBtn
@onready var ng_timer_bar: ProgressBar = $NGPanel/TimerBar

var _current_body: LootBody = null

func _ready() -> void:
	visible = false
	ng_panel.visible = false
	loot_all_btn.pressed.connect(_on_loot_all)
	close_btn.pressed.connect(func(): visible = false)
	ng_need_btn.pressed.connect(func(): _cast_ng_vote("need"))
	ng_greed_btn.pressed.connect(func(): _cast_ng_vote("greed"))
	ng_pass_btn.pressed.connect(func(): _cast_ng_vote("pass"))
	EventBus.notification_pushed.connect(_on_notification)

func open_body(body: LootBody) -> void:
	_current_body = body
	body.looted.connect(_on_item_looted)
	body.body_empty.connect(func(): visible = false)
	body.body_despawned.connect(func(): visible = false)
	_refresh_list()
	visible = true

func _refresh_list() -> void:
	if not _current_body:
		return
	item_list.clear()
	for entry in _current_body.get_item_list():
		var data := DataManager.get_item(entry["item_id"])
		var name: String = data.get("name", entry["item_id"])
		var count: int   = entry.get("count", 1)
		var display := "%s x%d" % [name, count] if count > 1 else name
		item_list.add_item(display)
		item_list.set_item_metadata(item_list.item_count - 1, entry["item_id"])
		# Color by rarity
		var rarity := data.get("rarity", "COMMON")
		match rarity:
			"UNCOMMON": item_list.set_item_custom_fg_color(item_list.item_count - 1, Color(0.3, 0.8, 0.3))
			"RARE":     item_list.set_item_custom_fg_color(item_list.item_count - 1, Color(0.3, 0.5, 1.0))
			"EPIC":     item_list.set_item_custom_fg_color(item_list.item_count - 1, Color(0.7, 0.3, 1.0))
			"LEGENDARY":item_list.set_item_custom_fg_color(item_list.item_count - 1, Color(1.0, 0.6, 0.1))

func _on_loot_all() -> void:
	if not _current_body:
		return
	_current_body.request_loot(GameManager.local_peer_id)
	_refresh_list()

func _on_item_looted(_peer_id: int, _item_id: String) -> void:
	_refresh_list()

# Need/Greed popup
func _on_notification(_text: String, category: String) -> void:
	if category != "loot_ng":
		return
	ng_panel.visible = true
	ng_item_label.text = _text
	# Animate timer bar
	ng_timer_bar.max_value = 30.0
	ng_timer_bar.value = 30.0
	var tween := create_tween()
	tween.tween_property(ng_timer_bar, "value", 0.0, 30.0)

func _cast_ng_vote(vote: String) -> void:
	if not _current_body:
		return
	_current_body.rpc_cast_ng_vote.rpc_id(1, vote)
	ng_panel.visible = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_open_nearby_body()

func _try_open_nearby_body() -> void:
	if not GameManager.local_player:
		return
	var origin := GameManager.local_player.global_position
	for body in get_tree().get_nodes_in_group("loot_bodies"):
		var lb := body as LootBody
		if lb and lb.global_position.distance_to(origin) <= LootBody.LOOT_RANGE:
			open_body(lb)
			return
