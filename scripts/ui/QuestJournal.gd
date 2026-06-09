## Quest journal UI: shows active and completed quests with objective progress.
extends Control

@onready var quest_list: ItemList        = $Split/Left/QuestList
@onready var quest_detail: RichTextLabel = $Split/Right/Detail
@onready var tab_bar: TabBar            = $TabBar

var _quest_manager: QuestManager = null

func _ready() -> void:
	visible = false
	quest_list.item_selected.connect(_on_quest_selected)
	tab_bar.tab_changed.connect(_on_tab_changed)
	EventBus.quest_updated.connect(_refresh)
	EventBus.character_spawned.connect(_on_character_spawned)

func _on_character_spawned(_character: Node, peer_id: int) -> void:
	if peer_id != GameManager.local_peer_id:
		return
	var character := GameManager.local_player
	if character and character.get_node_or_null("QuestManager"):
		_quest_manager = character.get_node("QuestManager") as QuestManager

func _refresh(_quest_id: String = "") -> void:
	if not visible or not _quest_manager:
		return
	quest_list.clear()
	quest_detail.clear()
	var show_active := tab_bar.current_tab == 0
	if show_active:
		for qid in _quest_manager.active_quests:
			var quest: Quest = _quest_manager.active_quests[qid]
			var prefix := "✓ " if quest.is_complete() else ""
			quest_list.add_item(prefix + quest.display_name)
			quest_list.set_item_metadata(quest_list.item_count - 1, qid)
	else:
		for qid in _quest_manager.completed_quests:
			var data := DataManager.get_quest(qid)
			quest_list.add_item(data.get("name", qid))
			quest_list.set_item_metadata(quest_list.item_count - 1, qid)

func _on_quest_selected(index: int) -> void:
	var qid: String = quest_list.get_item_metadata(index)
	_show_quest_detail(qid)

func _show_quest_detail(quest_id: String) -> void:
	quest_detail.clear()
	if not _quest_manager:
		return
	var quest: Quest = _quest_manager.active_quests.get(quest_id)
	var data := DataManager.get_quest(quest_id)
	if data.is_empty():
		return

	quest_detail.append_text("[b]%s[/b]\n\n" % data.get("name",""))
	quest_detail.append_text(data.get("description","") + "\n\n")
	quest_detail.append_text("[b]Obiettivi:[/b]\n")
	for obj in data.get("objectives", []):
		var status_str := ""
		if quest:
			var progress: int = quest.progress.get(obj["id"], 0)
			var target: int = obj.get("count", 1)
			var done := progress >= target
			status_str = " [color=%s][%d/%d][/color]" % [
				"#00ff00" if done else "#ffaa00",
				progress, target
			]
		quest_detail.append_text("• %s%s\n" % [obj.get("description",""), status_str])

	var rewards: Dictionary = data.get("rewards", {})
	if not rewards.is_empty():
		quest_detail.append_text("\n[b]Ricompense:[/b]\n")
		if rewards.has("xp"):
			quest_detail.append_text("• XP: %d\n" % rewards["xp"])
		if rewards.has("gold"):
			quest_detail.append_text("• Oro: %d\n" % rewards["gold"])
		for item_id in rewards.get("items", []):
			var item_data := DataManager.get_item(item_id)
			quest_detail.append_text("• %s\n" % item_data.get("name", item_id))

func _on_tab_changed(_tab: int) -> void:
	_refresh()

func toggle_visible() -> void:
	visible = not visible
	if visible:
		_refresh()
