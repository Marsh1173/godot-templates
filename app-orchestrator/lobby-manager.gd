class_name LobbyManager
extends Node

@onready var network_manager: NetworkManager = $"../NetworkManager"

var current_lobby_id: int = -1

const STEAM_APP_ID: int = 5245800
var _steam_active: bool = false

#region signals
signal steam_initialized()
signal steam_init_failed(reason: String)
signal lobby_list_updated(lobby_ids: Array[int])
signal lobby_joined(lobby_id: int)
signal lobby_left(lobby_id: int)
signal lobby_created(connect_status: Steam.Result, lobby_id: int)
signal lobby_data_changed(lobby_id: int, member_id: int)
#endregion

func _ready() -> void:
	OS.set_environment("SteamAppId", str(STEAM_APP_ID))
	OS.set_environment("SteamGameId", str(STEAM_APP_ID))
	process_mode = Node.PROCESS_MODE_ALWAYS

	_init_steam()

	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobbies_list)
	Steam.lobby_data_update.connect(_on_lobby_data_changed)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	if Steam.has_signal("lobby_kicked"):
		Steam.lobby_kicked.connect(_on_lobby_leave)

	if network_manager != null:
		network_manager.server_disconnected.connect(_leave_current_lobby)
		network_manager.connection_failed.connect(_leave_current_lobby)

func _process(_delta: float) -> void:
	if _steam_active:
		Steam.run_callbacks()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		_leave_current_lobby()

#region interface
var _pending_lobby_metadata: Dictionary = {}
func create_lobby(visibility: Steam.LobbyType, max_players: int) -> void:
	_pending_lobby_metadata = {
		LobbyDataKey.Visibility: str(visibility),
		LobbyDataKey.CreatorId: str(Steam.getSteamID()),
		LobbyDataKey.Name: Steam.getFriendPersonaName(Steam.getSteamID()) + "'s Game"
	}
	print("Attempting to create lobby")
	Steam.createLobby(Steam.LobbyType.LOBBY_TYPE_PUBLIC, max_players)

func get_lobby_list() -> void:
	print("Searching for lobbies…")
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()

func join_lobby(lobby_id: int) -> void:
	print("Attempting to join lobby %s from the lobby list" % lobby_id)
	Steam.joinLobby(lobby_id)

func leave_lobby(lobby_id: int) -> void:
	print("Attempting to leave lobby %s" % lobby_id)
	Steam.leaveLobby(lobby_id)
	_on_lobby_leave(lobby_id)

func _leave_current_lobby() -> void:
	if current_lobby_id != -1:
		leave_lobby(current_lobby_id)

enum LobbyDataKey {
	InProgress,
	Name,
	NumMaxPlayers,
	NumCurrentPlayers,
	Visibility,
	CreatorId
}

func get_lobby_data(lobby_id: int, key: LobbyDataKey) -> String:
	if key == LobbyDataKey.NumMaxPlayers:
		return str(Steam.getLobbyMemberLimit(lobby_id))
	if key == LobbyDataKey.NumCurrentPlayers:
		return str(Steam.getNumLobbyMembers(lobby_id))
	return Steam.getLobbyData(lobby_id, str(key))

func set_lobby_data(lobby_id: int, key: LobbyDataKey, value: String) -> void:
	if not Steam.setLobbyData(lobby_id, str(key), value):
		printerr("Failed to set lobby data. Key: %s, value: %s" % [key, value])

func is_host() -> bool:
	return current_lobby_id != -1 and Steam.getLobbyOwner(current_lobby_id) == Steam.getSteamID()

func is_member_connected(member_steam_id: int) -> bool:
	if network_manager == null or current_lobby_id == -1:
		return false
	var host_id: int = Steam.getLobbyOwner(current_lobby_id)
	return network_manager.is_steam_id_connected(member_steam_id, host_id)

func are_all_members_connected() -> bool:
	if current_lobby_id == -1:
		return false
	var num_lobby_members: int = Steam.getNumLobbyMembers(current_lobby_id)
	for i in range(num_lobby_members):
		var member_id = Steam.getLobbyMemberByIndex(current_lobby_id, i)
		if not is_member_connected(member_id):
			return false
	return true
#endregion

#region business logic
func _init_steam() -> void:
	# GodotSteam's steamInitEx returns a Dictionary:
	# { "status": int, "verbal": String }
	# status 0 = OK; anything else is an error code.
	var init_result: Dictionary = Steam.steamInitEx(false, STEAM_APP_ID)

	if init_result.get("status", -1) != Steam.STEAM_API_INIT_RESULT_OK:
		var reason: String = init_result.get("verbal", "Unknown Steam init error (code %d)" % init_result.get("status", -1))
		push_warning("LobbyManager: Steam failed to initialize – %s" % reason)
		steam_init_failed.emit(reason)
		return

	_steam_active = true
	print("LobbyManager: Steam initialized OK (App ID %d)" % STEAM_APP_ID)
	steam_initialized.emit()

func _on_lobby_created(connect_status: Steam.Result, lobby_id: int) -> void:
	lobby_created.emit(connect_status, lobby_id)

	if connect_status != Steam.Result.RESULT_OK:
		printerr("Failed to create a lobby: %s" % connect_status)
		return
	print("Successfully created lobby %s" % lobby_id)

	for key: LobbyDataKey in _pending_lobby_metadata.keys():
		set_lobby_data(lobby_id, key, _pending_lobby_metadata[key])
	_pending_lobby_metadata.clear()

	if network_manager != null:
		network_manager.host_steam_lobby(lobby_id)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: int, response: Steam.ChatRoomEnterResponse) -> void:
	if response == Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("Lobby %s joined successfully" % lobby_id)
		lobby_joined.emit(lobby_id)
		current_lobby_id = lobby_id

		var owner_id = Steam.getLobbyOwner(lobby_id)
		if owner_id != Steam.getSteamID() and network_manager != null:
			network_manager.connect_steam_lobby(lobby_id)
	else:
		printerr("Failed joining lobby %d, response code: %d" % [lobby_id, response])

func _on_lobby_leave(lobby_id: int) -> void:
	print("Left lobby %d" % lobby_id)
	if network_manager != null:
		network_manager.stop()
	lobby_left.emit(lobby_id)
	current_lobby_id = -1

func _on_lobbies_list(lobby_ids: Array) -> void:
	var filtered_lobby_ids: Array[int] = []

	for lobby_id: int in lobby_ids:
		var visibility: Steam.LobbyType = int(get_lobby_data(lobby_id, LobbyDataKey.Visibility)) as Steam.LobbyType
		if visibility == Steam.LobbyType.LOBBY_TYPE_PUBLIC:
			filtered_lobby_ids.append(lobby_id)
		elif visibility == Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY:
			var lobby_creator_id: int = int(get_lobby_data(lobby_id, LobbyDataKey.CreatorId))
			if Steam.getFriendRelationship(lobby_creator_id) == Steam.FriendRelationship.FRIEND_RELATION_FRIEND:
				filtered_lobby_ids.push_front(lobby_id)

	print("Received %d lobbies from Steam" % filtered_lobby_ids.size())
	lobby_list_updated.emit(filtered_lobby_ids)

func _on_lobby_data_changed(success: int, lobby_id: int, member_id: int) -> void:
	if success == Steam.Result.RESULT_OK:
		lobby_data_changed.emit(lobby_id, member_id)
	else:
		print("_on_lobby_data_changed failed, error code: ", str(success))

func _on_lobby_chat_update(lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if changed_id == Steam.getSteamID() and (chat_state & (Steam.CHAT_MEMBER_STATE_CHANGE_KICKED | Steam.CHAT_MEMBER_STATE_CHANGE_BANNED)):
		print("Kicked/banned from lobby %d" % lobby_id)
		_on_lobby_leave(lobby_id)
		return

	lobby_data_changed.emit(lobby_id, changed_id)
#endregion
