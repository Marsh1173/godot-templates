extends Control
class_name PlayerEntry

var player_id: int = -1
var is_peer_connected: bool = false:
	set(val):
		is_peer_connected = val
		_update_status()

@onready var name_text: Label = $MarginContainer/HBoxContainer/Name
@onready var status_text: Label = $MarginContainer/HBoxContainer/Status

func _ready():
	_update_status()

func _ready_with_data(_player_id: int):
	player_id = _player_id
	
	_update_ui(player_id)
	
	Steam.persona_state_change.connect(_update_ui)

func _update_status():
	if status_text:
		status_text.text = "" if is_peer_connected else "Connecting..."

func _update_ui(_steam_id: int, _flags: int = 0):
	name_text.text = Steam.getFriendPersonaName(player_id)
	
