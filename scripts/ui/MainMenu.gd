## Main menu: connect to server or host a local game.
extends Control

@onready var host_btn: Button     = $MenuPanel/HostButton
@onready var connect_btn: Button  = $MenuPanel/ConnectButton
@onready var address_input: LineEdit = $MenuPanel/AddressInput
@onready var port_input: LineEdit  = $MenuPanel/PortInput
@onready var status_label: Label  = $MenuPanel/StatusLabel
@onready var faction_selector: Control = $FactionSelector
@onready var class_selector: Control   = $ClassSelector

const GAME_SCENE := "res://scenes/game/World.tscn"

func _ready() -> void:
	host_btn.pressed.connect(_on_host)
	connect_btn.pressed.connect(_on_connect)
	EventBus.connection_failed.connect(_on_connection_failed)
	EventBus.character_spawned.connect(_on_spawned)
	address_input.text = "127.0.0.1"
	port_input.text = str(NetworkManager.DEFAULT_PORT)

func _on_host() -> void:
	_set_status("Avvio server locale...")
	var port := int(port_input.text)
	var err := NetworkManager.host_server(port)
	if err != OK:
		_set_status("Errore avvio server: %s" % error_string(err))
		return
	_set_status("Server avviato. Caricamento mondo...")
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_connect() -> void:
	var address := address_input.text.strip_edges()
	var port := int(port_input.text)
	_set_status("Connessione a %s:%d..." % [address, port])
	host_btn.disabled = true
	connect_btn.disabled = true
	var err := NetworkManager.connect_to_server(address, port)
	if err != OK:
		_set_status("Errore connessione: %s" % error_string(err))
		host_btn.disabled = false
		connect_btn.disabled = false

func _on_connection_failed() -> void:
	_set_status("Connessione fallita. Riprovare.")
	host_btn.disabled = false
	connect_btn.disabled = false

func _on_spawned(_character, _peer_id: int) -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _set_status(text: String) -> void:
	status_label.text = text
