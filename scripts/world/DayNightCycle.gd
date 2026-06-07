## Real-time day/night cycle synced with server time.
## Controls sun position, sky color, ambient light, and time-gated events.
class_name DayNightCycle
extends Node

signal hour_changed(hour: int)
signal dawn()
signal dusk()
signal midnight()

# One real minute = one in-game hour (24 min real = 24h in-game)
const REAL_SECONDS_PER_GAME_HOUR := 60.0
const HOURS_PER_DAY := 24

@export var sun: DirectionalLight3D = null
@export var environment: Environment = null

var _game_hour: float = 8.0  # start at 8:00
var _last_full_hour: int = 8

# Sky gradient: hour -> Color
const SKY_COLORS := {
	0:  Color(0.02, 0.02, 0.08),  # mezzanotte
	4:  Color(0.05, 0.05, 0.15),  # notte profonda
	5:  Color(0.4, 0.25, 0.15),   # alba
	6:  Color(0.7, 0.5, 0.3),     # mattino presto
	8:  Color(0.5, 0.7, 1.0),     # mattina
	12: Color(0.4, 0.6, 1.0),     # mezzogiorno
	17: Color(0.7, 0.5, 0.3),     # pomeriggio
	19: Color(0.8, 0.3, 0.1),     # tramonto
	21: Color(0.15, 0.1, 0.2),    # sera
	23: Color(0.02, 0.02, 0.08),  # notte
}

func _ready() -> void:
	add_to_group("day_night_cycle")
	# Sync with server if client
	if not multiplayer.is_server():
		_request_time_sync()

func _physics_process(delta: float) -> void:
	_game_hour += delta / REAL_SECONDS_PER_GAME_HOUR
	if _game_hour >= HOURS_PER_DAY:
		_game_hour -= HOURS_PER_DAY
	_apply_time()
	_check_hour_events()

func _apply_time() -> void:
	var hour := _game_hour
	if sun:
		# Sun angle: 0 at midnight, -90 at 6:00, 0 at noon, 90 at 18:00
		var sun_angle := (hour / HOURS_PER_DAY) * 360.0 - 90.0
		sun.rotation_degrees.x = sun_angle
		sun.light_energy = _sun_intensity(hour)
		sun.light_color = _sun_color(hour)
	if environment:
		environment.background_color = _sky_color(hour)

func _sun_intensity(hour: float) -> float:
	if hour < 5.0 or hour > 21.0:
		return 0.0  # night, no sun
	if hour < 6.0:
		return (hour - 5.0) * 0.5   # dawn ramp
	if hour > 20.0:
		return (21.0 - hour) * 0.5  # dusk ramp
	return 1.2 if (hour > 10.0 and hour < 16.0) else 0.8

func _sun_color(hour: float) -> Color:
	if hour < 6.0 or hour > 20.0:
		return Color(0.8, 0.4, 0.2)  # dawn/dusk orange
	return Color(1.0, 0.97, 0.9)    # white daylight

func _sky_color(hour: float) -> Color:
	var sorted_hours := SKY_COLORS.keys()
	sorted_hours.sort()
	var prev_hour: int = sorted_hours[0]
	var next_hour: int = sorted_hours[0]
	for h in sorted_hours:
		if h <= int(hour):
			prev_hour = h
		else:
			next_hour = h
			break
	if prev_hour == next_hour:
		return SKY_COLORS[prev_hour]
	var t := (hour - prev_hour) / (next_hour - prev_hour)
	return SKY_COLORS[prev_hour].lerp(SKY_COLORS[next_hour], t)

func _check_hour_events() -> void:
	var full_hour := int(_game_hour)
	if full_hour == _last_full_hour:
		return
	_last_full_hour = full_hour
	hour_changed.emit(full_hour)
	match full_hour:
		6: dawn.emit()
		20: dusk.emit()
		0: midnight.emit()

func get_time_string() -> String:
	var h := int(_game_hour)
	var m := int((_game_hour - h) * 60)
	return "%02d:%02d" % [h, m]

func get_hour() -> float:
	return _game_hour

func is_nighttime() -> bool:
	return _game_hour < 5.5 or _game_hour > 21.5

func set_time(hour: float) -> void:
	_game_hour = fmod(hour, HOURS_PER_DAY)

func _request_time_sync() -> void:
	pass  # TODO: RPC to server to get current game time
