## Minimap and world map overlay.
## Minimap shows nearby players/NPCs. World map shows zones and RvR objectives.
extends Control

@onready var minimap_canvas: SubViewport   = $MinimapViewport
@onready var minimap_display: TextureRect  = $MinimapDisplay
@onready var world_map_panel: Control      = $WorldMapPanel
@onready var world_map_image: TextureRect  = $WorldMapPanel/MapImage
@onready var objective_markers: Node2D     = $WorldMapPanel/Markers
@onready var player_marker: ColorRect      = $MinimapDisplay/PlayerMarker
@onready var zone_label: Label             = $ZoneLabel
@onready var clock_label: Label            = $ClockLabel

const MINIMAP_RANGE := 100.0
const MINIMAP_SIZE := 150.0
const MARKER_DOT_SIZE := 6.0

var _day_night: DayNightCycle = null

func _ready() -> void:
	world_map_panel.visible = false
	EventBus.zone_loaded.connect(_on_zone_loaded)
	EventBus.rvr_objective_captured.connect(_on_objective_captured)

func _process(_delta: float) -> void:
	_update_minimap()
	_update_clock()

func _update_minimap() -> void:
	if not GameManager.local_player:
		return
	var origin := GameManager.local_player.global_position
	for child in minimap_canvas.get_children():
		if child.name != "PlayerMarker":
			child.queue_free()

	for character in get_tree().get_nodes_in_group("characters"):
		if character == GameManager.local_player:
			continue
		var c := character as Character
		if not c:
			continue
		var offset := c.global_position - origin
		if abs(offset.x) > MINIMAP_RANGE or abs(offset.z) > MINIMAP_RANGE:
			continue
		var dot := ColorRect.new()
		dot.size = Vector2(MARKER_DOT_SIZE, MARKER_DOT_SIZE)
		var map_x := (offset.x / MINIMAP_RANGE) * (MINIMAP_SIZE / 2.0) + MINIMAP_SIZE / 2.0
		var map_y := (offset.z / MINIMAP_RANGE) * (MINIMAP_SIZE / 2.0) + MINIMAP_SIZE / 2.0
		dot.position = Vector2(map_x - MARKER_DOT_SIZE / 2.0, map_y - MARKER_DOT_SIZE / 2.0)
		dot.color = GameManager.faction_color(c.faction) if c is PlayerCharacter else Color.WHITE
		minimap_canvas.add_child(dot)

func _update_clock() -> void:
	if not _day_night:
		_day_night = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle
	if _day_night:
		clock_label.text = _day_night.get_time_string()
		clock_label.modulate = Color.GRAY if _day_night.is_nighttime() else Color.WHITE

func _on_zone_loaded(zone_id: String) -> void:
	var data := DataManager.get_zone(zone_id)
	zone_label.text = data.get("name", zone_id)

func _on_objective_captured(objective_id: String, faction: int) -> void:
	_update_objective_marker(objective_id, faction as GameManager.Faction)

func _update_objective_marker(objective_id: String, faction: GameManager.Faction) -> void:
	var marker := objective_markers.get_node_or_null(objective_id) as ColorRect
	if marker:
		marker.color = GameManager.faction_color(faction)

func toggle_world_map() -> void:
	world_map_panel.visible = not world_map_panel.visible
