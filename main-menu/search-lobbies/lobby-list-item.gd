extends Button
class_name LobbyListItem

@onready var name_label: Label = $MarginContainer/HBoxContainer/Name
@onready var player_count_label: Label = $MarginContainer/HBoxContainer/PlayerCount

var lobby_manager: LobbyManager
var lobby_id: int

var in_progress: bool = false

signal joining_lobby()

func _ready():
	lobby_manager = AppOrchestrator.get_or_error(self).lobby_manager

func ready_with_data(_lobby_id: int):
	lobby_id = _lobby_id
	
	lobby_manager.lobby_data_changed.connect(_on_lobby_data_changed)
	_set_text()
	
	pressed.connect(attempt_join)

func attempt_join():
	joining_lobby.emit()
	lobby_manager.join_lobby(lobby_id)

func _on_lobby_data_changed(changed_lobby_id: int, _member_id: int):
	if lobby_id == changed_lobby_id:
		_set_text();

func _set_text():
	name_label.text = lobby_manager.get_lobby_data(lobby_id, LobbyManager.DataKey.Name)
	
	in_progress = lobby_manager.get_lobby_data(lobby_id, LobbyManager.DataKey.InProgress) == "true"

	if in_progress:
		player_count_label.text = "Spectate"
	else:
		var current_players = int(lobby_manager.get_lobby_data(lobby_id, LobbyManager.DataKey.NumCurrentPlayers))
		var max_players = int(lobby_manager.get_lobby_data(lobby_id, LobbyManager.DataKey.NumMaxPlayers))
		player_count_label.text = str(current_players) + "/" + str(max_players)
	
