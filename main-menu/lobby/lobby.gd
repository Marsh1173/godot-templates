extends Control
class_name Lobby

const PLAYER_ENTRY = preload("uid://birt6wunr6sbl")

@onready var leave_button: Button = $CenterContainer/VBoxContainer/ActionButtons/LeaveButton
@onready var start_button: Button = $CenterContainer/VBoxContainer/ActionButtons/StartButton
@onready var player_entry_container: Control = $CenterContainer/VBoxContainer/PlayerEntryContainer

var lobby_manager: LobbyManager
var network_manager: NetworkManager

var lobby_id: int = -1

func _ready():
	var orchestrator: AppOrchestrator = AppOrchestrator.get_or_error(self)
	lobby_manager = orchestrator.lobby_manager
	network_manager = orchestrator.network_manager

	leave_button.pressed.connect(_leave_lobby)
	start_button.pressed.connect(_start_game_as_host)
	lobby_manager.lobby_data_changed.connect(_on_lobby_data_changed)
	
	if network_manager != null:
		network_manager.peer_connected.connect(func(_id): _update_player_statuses())
		network_manager.peer_disconnected.connect(func(_id): _update_player_statuses())
		network_manager.connected_to_server.connect(_update_player_statuses)

func load_lobby_to_ui(_lobby_id: int):
	lobby_id = _lobby_id
	_create_player_list()

func _on_lobby_data_changed(updated_lobby_id: int, _member_id: int):
	if updated_lobby_id != lobby_id:
		return
	_create_player_list()

func _create_player_list():
	for child in player_entry_container.get_children():
		child.queue_free()
	
	var num_lobby_members: int = Steam.getNumLobbyMembers(lobby_id)
	for player_index in range(0, num_lobby_members):
		var player_entry := PLAYER_ENTRY.instantiate()
		var player_id = Steam.getLobbyMemberByIndex(lobby_id, player_index)
		player_entry_container.add_child(player_entry)
		player_entry._ready_with_data(player_id)
		player_entry.is_peer_connected = lobby_manager.is_member_connected(player_id)
	
	_update_start_button()

func _update_player_statuses():
	for child in player_entry_container.get_children():
		if child is PlayerEntry and not child.is_queued_for_deletion():
			child.is_peer_connected = lobby_manager.is_member_connected(child.player_id)
	_update_start_button()

func _update_start_button():
	if not lobby_manager.is_host():
		start_button.disabled = true
		start_button.text = "Start Game"
		return
	
	var all_connected: bool = lobby_manager.are_all_members_connected()
	start_button.disabled = not all_connected
	start_button.text = "Start Game" if all_connected else "Waiting for players..."

func _leave_lobby():
	lobby_manager.leave_lobby(lobby_id)
	lobby_id = -1

# called on host
func _start_game_as_host():
	if not lobby_manager.are_all_members_connected():
		return
	var agent_id_to_peer_id: Dictionary[int, int]
	var agent_id_to_steam_id: Dictionary[int, int]
	var agent_datas: Array[Array]
	
	var current_agent_id: int = 1
	
	var num_lobby_members: int = Steam.getNumLobbyMembers(lobby_id)
	for player_index in range(0, num_lobby_members):
		var player_id = Steam.getLobbyMemberByIndex(lobby_id, player_index)
		
		agent_id_to_steam_id.set(current_agent_id, player_id)
		
		var peer_id: int = network_manager.get_peer_id_for_steam_id(player_id)
		agent_id_to_peer_id.set(current_agent_id, peer_id)
		
		var agent_name = Steam.getFriendPersonaName(player_id)
		agent_datas.append([
			current_agent_id,
			agent_name
		])
		
		current_agent_id += 1
	
	_start_game.rpc()
	AppOrchestrator.get_or_error(self).show_game_as_host(agent_id_to_peer_id, agent_id_to_steam_id, agent_datas)
	lobby_manager.set_lobby_data(lobby_id, LobbyManager.LobbyDataKey.InProgress, "true")

# called on peers, not host
@rpc("authority", 'call_remote', 'reliable')
func _start_game():
	AppOrchestrator.get_or_error(self).show_game()
