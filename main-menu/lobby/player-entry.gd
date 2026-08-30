extends Control
class_name PlayerEntry

var player_id: int = -1

@onready var name_text: Label = $MarginContainer/HBoxContainer/Name

func _ready_with_data(_player_id: int):
	player_id = _player_id
	
	_update_ui(player_id)
	
	Steam.persona_state_change.connect(_update_ui)

func _update_ui(_steam_id: int, _flags: int = 0):
	name_text.text = Steam.getFriendPersonaName(player_id)
	
