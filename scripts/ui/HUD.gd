## Main HUD: health/endurance/power bars, target frame, ability bar, chat, minimap.
extends CanvasLayer

@onready var health_bar: ProgressBar  = $VitalsPanel/HealthBar
@onready var endurance_bar: ProgressBar = $VitalsPanel/EnduranceBar
@onready var power_bar: ProgressBar   = $VitalsPanel/PowerBar
@onready var health_label: Label      = $VitalsPanel/HealthLabel
@onready var xp_bar: ProgressBar      = $XPBar
@onready var level_label: Label       = $LevelLabel

@onready var target_frame: Control    = $TargetFrame
@onready var target_name_label: Label = $TargetFrame/NameLabel
@onready var target_health_bar: ProgressBar = $TargetFrame/HealthBar
@onready var target_faction_icon: TextureRect = $TargetFrame/FactionIcon

@onready var ability_bar: HBoxContainer = $AbilityBar
@onready var chat_panel: Control       = $ChatPanel
@onready var chat_input: LineEdit      = $ChatPanel/InputLine
@onready var chat_log: RichTextLabel   = $ChatPanel/Log

@onready var notification_container: VBoxContainer = $Notifications
@onready var cast_bar: Control         = $CastBar
@onready var cast_bar_fill: ProgressBar = $CastBar/Fill
@onready var cast_bar_label: Label     = $CastBar/Label

@onready var rvr_scores: Control       = $RvRScores
@onready var score_roman: Label        = $RvRScores/Roman
@onready var score_galli: Label        = $RvRScores/Galli
@onready var score_germani: Label      = $RvRScores/Germani

var _local_character: Character = null
var _ability_slots: Array = []
const ABILITY_SLOT_COUNT := 10

func _ready() -> void:
	_setup_ability_bar()
	_connect_signals()
	target_frame.visible = false
	cast_bar.visible = false
	rvr_scores.visible = false

func _setup_ability_bar() -> void:
	for i in range(ABILITY_SLOT_COUNT):
		var slot := _create_ability_slot(i)
		ability_bar.add_child(slot)
		_ability_slots.append(slot)

func _create_ability_slot(index: int) -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(56, 56)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_FILL
	icon.size_flags_vertical = Control.SIZE_FILL
	slot.add_child(icon)
	var cooldown_overlay := ColorRect.new()
	cooldown_overlay.color = Color(0, 0, 0, 0.6)
	cooldown_overlay.visible = false
	cooldown_overlay.name = "CooldownOverlay"
	slot.add_child(cooldown_overlay)
	var key_label := Label.new()
	key_label.text = str(index + 1) if index < 9 else "0"
	key_label.add_theme_font_size_override("font_size", 10)
	key_label.position = Vector2(2, 2)
	slot.add_child(key_label)
	return slot

func _connect_signals() -> void:
	EventBus.chat_message_received.connect(_on_chat_received)
	EventBus.notification_pushed.connect(_on_notification)
	EventBus.rvr_score_updated.connect(_on_rvr_score_updated)
	EventBus.character_spawned.connect(_on_character_spawned)
	EventBus.target_changed.connect(_on_target_changed)
	EventBus.ability_cooldown_changed.connect(_on_cooldown_changed)
	chat_input.text_submitted.connect(_on_chat_submitted)

func _on_character_spawned(character: Node, peer_id: int) -> void:
	if peer_id != GameManager.local_peer_id:
		return
	_local_character = character as Character
	_local_character.stats.health_changed.connect(_on_health_changed)
	_local_character.stats.endurance_changed.connect(_on_endurance_changed)
	_local_character.stats.power_changed.connect(_on_power_changed)
	_local_character.target_acquired.connect(_on_target_acquired)
	_local_character.target_lost.connect(_on_target_lost)
	if _local_character.has_node("AbilityManager"):
		_local_character.get_node("AbilityManager").cast_started.connect(_on_cast_started)
		_local_character.get_node("AbilityManager").cast_completed.connect(_on_cast_completed)
		_local_character.get_node("AbilityManager").cast_interrupted.connect(_on_cast_interrupted)
	_refresh_all()
	rvr_scores.visible = true

func _refresh_all() -> void:
	if not _local_character:
		return
	var s := _local_character.stats
	_update_health_bar(s.current_health, s.max_health)
	_update_endurance_bar(s.current_endurance, s.max_endurance)
	_update_power_bar(s.current_power, s.max_power)
	level_label.text = "Liv. %d" % _local_character.level
	_refresh_ability_bar()

func _refresh_ability_bar() -> void:
	if not _local_character or not _local_character.has_node("AbilityManager"):
		return
	var am := _local_character.get_node("AbilityManager") as AbilityManager
	for i in range(ABILITY_SLOT_COUNT):
		var ability_id := am.get_slot_ability(i)
		if ability_id.is_empty():
			continue
		var data := DataManager.get_ability(ability_id)
		if data.is_empty():
			continue
		var icon_node := _ability_slots[i].get_node("TextureRect") as TextureRect
		var tex := load(data.get("icon", "")) as Texture2D
		if tex:
			icon_node.texture = tex

func _process(_delta: float) -> void:
	if _local_character and cast_bar.visible:
		# update cast bar via signal, no polling needed
		pass

# ----- Vitals -----

func _on_health_changed(current: int, maximum: int) -> void:
	_update_health_bar(current, maximum)

func _update_health_bar(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d / %d" % [current, maximum]

func _on_endurance_changed(current: int, maximum: int) -> void:
	endurance_bar.max_value = maximum
	endurance_bar.value = current

func _on_power_changed(current: int, maximum: int) -> void:
	power_bar.max_value = maximum
	power_bar.value = current

# ----- Target -----

func _on_target_changed(new_target) -> void:
	if new_target:
		_on_target_acquired(new_target)
	else:
		_on_target_lost()

func _on_target_acquired(target: Character) -> void:
	target_frame.visible = true
	target_name_label.text = target.character_name
	target_name_label.modulate = GameManager.faction_color(target.faction)
	target.stats.health_changed.connect(_on_target_health_changed)
	_on_target_health_changed(target.stats.current_health, target.stats.max_health)

func _on_target_lost() -> void:
	target_frame.visible = false

func _on_target_health_changed(current: int, maximum: int) -> void:
	target_health_bar.max_value = maximum
	target_health_bar.value = current

# ----- Cast bar -----

func _on_cast_started(ability: Ability, cast_time: float) -> void:
	cast_bar.visible = true
	cast_bar_fill.max_value = cast_time
	cast_bar_fill.value = 0.0
	cast_bar_label.text = ability.display_name
	var tween := create_tween()
	tween.tween_property(cast_bar_fill, "value", cast_time, cast_time)

func _on_cast_completed(_ability: Ability) -> void:
	cast_bar.visible = false

func _on_cast_interrupted() -> void:
	cast_bar.visible = false

# ----- Cooldowns -----

func _on_cooldown_changed(ability_id: String, remaining: float) -> void:
	for i in range(ABILITY_SLOT_COUNT):
		if not _local_character or not _local_character.has_node("AbilityManager"):
			return
		var am := _local_character.get_node("AbilityManager") as AbilityManager
		if am.get_slot_ability(i) == ability_id:
			var overlay := _ability_slots[i].get_node("CooldownOverlay") as ColorRect
			overlay.visible = remaining > 0.0

# ----- Chat -----

func _on_chat_received(sender: String, message: String, channel: String, faction: int) -> void:
	var color := GameManager.faction_color(faction as GameManager.Faction).to_html(false)
	chat_log.append_text("[color=#%s]%s[/color]: %s\n" % [color, sender, message])

func _on_chat_submitted(text: String) -> void:
	if text.is_empty():
		return
	NetworkManager.send_chat_message(text)
	chat_input.clear()

# ----- Notifications -----

func _on_notification(text: String, category: String) -> void:
	var label := Label.new()
	label.text = text
	match category:
		"rvr_major":   label.modulate = Color.GOLD
		"quest":       label.modulate = Color.YELLOW
		"campaign_victory": label.modulate = Color.WHITE
		_: label.modulate = Color.WHITE
	notification_container.add_child(label)
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

# ----- RvR Scores -----

func _on_rvr_score_updated(roman: int, galli: int, germani: int) -> void:
	score_roman.text   = "Romani: %d" % roman
	score_galli.text   = "Galli: %d" % galli
	score_germani.text = "Germani: %d" % germani
