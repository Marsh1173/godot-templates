extends Control
class_name Lobby

const PLAYER_ENTRY = preload("uid://birt6wunr6sbl")

@onready var leave_button: Button = $CenterContainer/VBoxContainer/ActionButtons/LeaveButton
@onready var start_button: Button = $CenterContainer/VBoxContainer/ActionButtons/StartButton
@onready var player_entry_container: Control = $CenterContainer/VBoxContainer/PlayerEntryContainer

var lobby_manager: LobbyManager

var lobby_id: int = -1

func _ready():
	lobby_manager = AppOrchestrator.get_or_error(self).lobby_manager
	leave_button.pressed.connect(_leave_lobby)
	start_button.pressed.connect(_start_game_as_host)
	lobby_manager.lobby_data_changed.connect(_on_lobby_data_changed)

func load_lobby_to_ui(_lobby_id: int):
	lobby_id = _lobby_id
	_create_player_list()
	
	var lobby_owner_id = Steam.getLobbyOwner(lobby_id)
	start_button.disabled = lobby_owner_id != Steam.getSteamID()

func _on_lobby_data_changed(updated_lobby_id: int, _member_id: int):
	if updated_lobby_id != lobby_id:
		return
	_create_player_list()
	
	var lobby_owner_id = Steam.getLobbyOwner(lobby_id)
	start_button.disabled = lobby_owner_id != Steam.getSteamID()

func _create_player_list():
	for child in player_entry_container.get_children():
		child.queue_free()
	
	var num_lobby_members: int = Steam.getNumLobbyMembers(lobby_id)
	for player_index in range(0, num_lobby_members):
		var player_entry := PLAYER_ENTRY.instantiate()
		var player_id = Steam.getLobbyMemberByIndex(lobby_id, player_index)
		player_entry_container.add_child(player_entry)
		player_entry._ready_with_data(player_id)

func _leave_lobby():
	lobby_manager.leave_lobby(lobby_id)
	lobby_id = -1

# called on host
func _start_game_as_host():
	var agent_id_to_peer_id: Dictionary[int, int]
	var agent_id_to_steam_id: Dictionary[int, int]
	var agent_datas: Array[Array]
	
	var current_agent_id: int = 1
	
	var num_lobby_members: int = Steam.getNumLobbyMembers(lobby_id)
	for player_index in range(0, num_lobby_members):
		var player_id = Steam.getLobbyMemberByIndex(lobby_id, player_index)
		
		agent_id_to_steam_id.set(current_agent_id, player_id)
		
		var peer_id_str: String = lobby_manager.get_member_data(lobby_id, player_id, LobbyManager.MemberDataKey.PeerId)
		agent_id_to_peer_id.set(current_agent_id, int(peer_id_str))
		
		var agent_name = Steam.getFriendPersonaName(player_id)
		agent_datas.append([
			current_agent_id,
			agent_name
		])
		
		current_agent_id += 1
	
	_start_game.rpc()
	AppOrchestrator.get_or_error(self).show_game_as_host(agent_id_to_peer_id, agent_id_to_steam_id, agent_datas)

# called on peers, not host
@rpc("authority", 'call_remote', 'reliable')
func _start_game():
	AppOrchestrator.get_or_error(self).show_game()
