## Player-controlled character with input handling, camera, and client-side prediction.
class_name PlayerCharacter
extends Character

@onready var camera_arm: SpringArm3D = $CameraArm
@onready var camera: Camera3D = $CameraArm/Camera3D
@onready var hud: CanvasLayer = $HUD

const CAMERA_SENSITIVITY := 0.003
const CAMERA_ARM_MIN := 2.0
const CAMERA_ARM_MAX := 15.0
const JUMP_FORCE := 7.0
const DODGE_FORCE := 10.0
const DODGE_ENDURANCE_COST := 20

var _is_local_player: bool = false
var _mouse_captured: bool = false
var _camera_rotation: Vector2 = Vector2.ZERO
var _dodge_cooldown: float = 0.0
var _auto_attack_timer: float = 0.0
var _auto_attack_interval: float = 2.5  # seconds between auto attacks

# Client-side prediction buffer
var _input_buffer: Array = []
const MAX_INPUT_BUFFER := 64

func _ready() -> void:
	super._ready()
	var my_id := name.to_int()
	if my_id > 0 and multiplayer.get_unique_id() == my_id:
		_setup_as_local_player()
	else:
		_setup_as_remote_player()

func _setup_as_local_player() -> void:
	_is_local_player = true
	camera.current = true
	hud.visible = true
	_capture_mouse()
	GameManager.local_player = self
	add_to_group("local_player")

func _setup_as_remote_player() -> void:
	camera.current = false
	hud.visible = false

func _input(event: InputEvent) -> void:
	if not _is_local_player or is_dead:
		return
	if event is InputEventMouseMotion and _mouse_captured:
		_camera_rotation.x -= event.relative.y * CAMERA_SENSITIVITY
		_camera_rotation.y -= event.relative.x * CAMERA_SENSITIVITY
		_camera_rotation.x = clampf(_camera_rotation.x, -PI / 2.5, PI / 4.0)
		camera_arm.rotation.x = _camera_rotation.x
		rotation.y = _camera_rotation.y

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				camera_arm.spring_length = maxf(CAMERA_ARM_MIN, camera_arm.spring_length - 0.5)
			MOUSE_BUTTON_WHEEL_DOWN:
				camera_arm.spring_length = minf(CAMERA_ARM_MAX, camera_arm.spring_length + 0.5)

	if event.is_action_pressed("toggle_ui"):
		_toggle_mouse_capture()
	if event.is_action_pressed("target_nearest"):
		_target_nearest_enemy()

func _physics_process(delta: float) -> void:
	if not _is_local_player:
		super._physics_process(delta)
		return

	if is_dead:
		return

	_dodge_cooldown = maxf(0.0, _dodge_cooldown - delta)
	_auto_attack_timer = maxf(0.0, _auto_attack_timer - delta)

	_gather_and_send_input()
	super._physics_process(delta)

	# Process ability hotkeys
	for i in range(1, 6):
		if Input.is_action_just_pressed("ability_%d" % i):
			_use_ability_slot(i - 1)

	# Auto-attack
	if Input.is_action_pressed("attack_primary") and current_target and _auto_attack_timer <= 0.0:
		_perform_auto_attack()

func _gather_and_send_input() -> void:
	var raw_dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):  raw_dir.y -= 1.0
	if Input.is_action_pressed("move_backward"): raw_dir.y += 1.0
	if Input.is_action_pressed("move_left"):     raw_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):    raw_dir.x += 1.0

	var camera_basis := camera.global_transform.basis
	var forward := -Vector3(camera_basis.z.x, 0, camera_basis.z.z).normalized()
	var right   := Vector3(camera_basis.x.x, 0, camera_basis.x.z).normalized()
	move_direction = (forward * -raw_dir.y + right * raw_dir.x).normalized()

	var input_data := {
		"dir": [move_direction.x, move_direction.z],
		"rot": rotation.y,
		"jump": Input.is_action_just_pressed("jump"),
		"dodge": Input.is_action_just_pressed("dodge"),
	}
	if NetworkManager.is_server:
		apply_input(input_data)
	else:
		NetworkManager.send_player_input(input_data)

func apply_input(input_data: Dictionary) -> void:
	if input_data.has("dir"):
		var d: Array = input_data["dir"]
		move_direction = Vector3(d[0], 0.0, d[1])
	if input_data.has("rot"):
		rotation.y = input_data["rot"]
	if input_data.get("jump", false) and is_on_floor():
		_velocity_y = JUMP_FORCE
	if input_data.get("dodge", false):
		_try_dodge()

func _try_dodge() -> void:
	if _dodge_cooldown > 0.0 or stats.current_endurance < DODGE_ENDURANCE_COST:
		return
	stats.modify_endurance(-DODGE_ENDURANCE_COST)
	_dodge_cooldown = 1.5
	var dodge_dir := move_direction if move_direction.length() > 0.1 else -global_transform.basis.z
	velocity = dodge_dir * DODGE_FORCE + Vector3(0, 3.0, 0)

func _perform_auto_attack() -> void:
	if not current_target or current_target.is_dead:
		return
	var dist := global_position.distance_to(current_target.global_position)
	var range_max := 2.5  # melee range in meters
	# Check class for ranged
	if character_class in ["sagittarius", "cacciatore"]:
		range_max = 30.0
	if dist > range_max:
		return
	_auto_attack_timer = 1.0 / stats.attack_speed
	if NetworkManager.is_server:
		ability_manager.server_use_ability("auto_attack", current_target.name.to_int())
	else:
		NetworkManager.request_use_ability("auto_attack", current_target.name.to_int())

func _use_ability_slot(slot: int) -> void:
	if not ability_manager:
		return
	var ability_id: String = ability_manager.get_slot_ability(slot)
	if ability_id.is_empty():
		return
	var target_id := current_target.name.to_int() if current_target else -1
	if NetworkManager.is_server:
		ability_manager.server_use_ability(ability_id, target_id)
	else:
		NetworkManager.request_use_ability(ability_id, target_id)

func _target_nearest_enemy() -> void:
	var best: Character = null
	var best_dist := INF
	for character in get_tree().get_nodes_in_group("characters"):
		if character == self:
			continue
		if character is not Character:
			continue
		var c := character as Character
		if not GameManager.is_enemy(faction, c.faction):
			continue
		if c.is_dead:
			continue
		var d := global_position.distance_to(c.global_position)
		if d < best_dist and d < 50.0:
			best_dist = d
			best = c
	set_target(best)

func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = true

func _toggle_mouse_capture() -> void:
	if _mouse_captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = not _mouse_captured

func _on_death(_killer) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_mouse_captured = false
