class_name LobbyManager
extends Node

static var instance: LobbyManager = null

var current_lobby_id: int = -1

const DEFAULT_ENET_PORT: int = 8321
const STEAM_APP_ID: int = 5245800
var _steam_active: bool = false

var current_ping: float = 0.0
var _ping_timer: float = 0.0
const PING_INTERVAL: float = 1.0

# Used to track a lobby ID from Steam invites or joining via Friends List
# var invite_lobby_id: int = 0

func _ready() -> void:
	instance = self
	OS.set_environment("SteamAppId", str(STEAM_APP_ID))
	OS.set_environment("SteamGameId", str(STEAM_APP_ID))
	
	process_mode = Node.PROCESS_MODE_ALWAYS # Keep networking alive during scene-tree pause
	
	_init_steam()

	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobbies_list)
	Steam.lobby_data_update.connect(_on_lobby_data_changed)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	if Steam.has_signal("lobby_kicked"):
		Steam.lobby_kicked.connect(_on_lobby_leave)

	multiplayer.connected_to_server.connect(func(): print("CLIENT: Successfully connected to host!"))
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(func(id): print("PEER CONNECTED: ", id))
	multiplayer.peer_disconnected.connect(func(id): print("PEER DISCONNECTED: ", id))

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _process(delta: float) -> void:
	if _steam_active:
		Steam.run_callbacks()
	
	if multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != 1:
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_ping_timer -= delta
			if _ping_timer <= 0.0:
				_ping_timer = PING_INTERVAL
				_ping_server.rpc_id(1, Time.get_ticks_msec())

# Leave the lobby if the app closes via X button or crashes
func _notification(what):
	if current_lobby_id == -1:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		leave_lobby(current_lobby_id)

#region signals
## Emitted when Steam initializes successfully.
signal steam_initialized()

## Emitted when Steam fails to initialize; carries a human-readable reason.
signal steam_init_failed(reason: String)

signal lobby_list_updated(lobby_ids: Array[int])
signal lobby_joined(lobby_id: int)
signal lobby_left(lobby_id: int)
signal lobby_created(connect_status: Steam.Result, lobby_id: int)
signal lobby_data_changed(lobby_id: int, member_id: int)
#endregion

#region interface
var _pending_lobby_metadata: Dictionary = {}
func create_lobby(visibility: Steam.LobbyType, max_players: int):
	# 1. Stage the metadata locally before sending the request to Steam
	_pending_lobby_metadata = {
		LobbyDataKey.Visibility: str(visibility),
		LobbyDataKey.CreatorId: str(Steam.getSteamID()),
		LobbyDataKey.Name: Steam.getFriendPersonaName(Steam.getSteamID()) + "'s Game"
	}
	
	# 2. Trigger the asynchronous creation process
	print("Attempting to create lobby")
	Steam.createLobby(Steam.LobbyType.LOBBY_TYPE_PUBLIC, max_players)

func get_lobby_list():
	print("Searching for lobbies…")
	# Re-apply the distance filter every time — Steam flushes it after each call.
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()

func join_lobby(lobby_id: int):
	print("Attempting to join lobby %s from the lobby list" % lobby_id)
	Steam.joinLobby(lobby_id)

func leave_lobby(lobby_id: int):
	print("Attempting to leave lobby %s" % lobby_id)
	Steam.leaveLobby(lobby_id)
	_on_lobby_leave(lobby_id)

enum LobbyDataKey {
	InProgress,
	Name,
	NumMaxPlayers,
	NumCurrentPlayers,
	Visibility,
	CreatorId
}

# Returns an empty string if key or lobby doesn't exist
func get_lobby_data(lobby_id: int, key: LobbyDataKey) -> String:
	if key == LobbyDataKey.NumMaxPlayers:
		return str(Steam.getLobbyMemberLimit(lobby_id))
	if key == LobbyDataKey.NumCurrentPlayers:
		return str(Steam.getNumLobbyMembers(lobby_id))
	return Steam.getLobbyData(lobby_id, str(key))

func set_lobby_data(lobby_id: int, key: LobbyDataKey, value: String):
	if not Steam.setLobbyData(lobby_id, str(key), value):
		printerr("Failed to set lobby data. Key: " + str(key) + ", value: " + value)

enum MemberDataKey {
}

func get_member_data(lobby_id: int, member_id: int, key: MemberDataKey) -> String:
	return Steam.getLobbyMemberData(lobby_id, member_id, str(key))

func set_member_data(lobby_id: int, key: MemberDataKey, value: String):
	Steam.setLobbyMemberData(lobby_id, str(key), value)
#endregion

#region business logic
func _init_steam() -> void:
	# GodotSteam's steamInitEx returns a Dictionary:
	# { "status": int, "verbal": String }
	# status 0 = OK; anything else is an error code.
	var init_result: Dictionary = Steam.steamInitEx(false, STEAM_APP_ID)

	if init_result.get("status", -1) != Steam.STEAM_API_INIT_RESULT_OK:
		var reason: String = init_result.get("verbal", "Unknown Steam init error (code %d)" % init_result.get("status", -1))
		push_warning("NetworkManager: Steam failed to initialize – %s" % reason)
		steam_init_failed.emit(reason)
		return

	_steam_active = true
	print("NetworkManager: Steam initialized OK (App ID %d)" % STEAM_APP_ID)
	steam_initialized.emit()

func _on_lobby_created(connect_status: Steam.Result, lobby_id: int) -> void:
	lobby_created.emit(connect_status, lobby_id)
	
	# Error check on creation
	if connect_status != Steam.Result.RESULT_OK:
		# Our lobby creation failed
		printerr("Failed to create a lobby: %s" % connect_status)
		return
	print("Successfully created lobby %s" % lobby_id)
	
	# Flush the staged data into Steam's backend using the fresh lobby_id
	for key: LobbyDataKey in _pending_lobby_metadata.keys():
		var value: String = _pending_lobby_metadata[key]
		set_lobby_data(lobby_id, key, value)
	# Clear the staging area now that it's live
	_pending_lobby_metadata.clear()
	
	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var err = peer.host_with_lobby(lobby_id)
	if err != OK:
		printerr("Steam host_with_lobby failed: ", err)
		return

	peer.set_debug_level(SteamMultiplayerPeer.DEBUG_LEVEL_PEER)
	peer.no_nagle = true
	multiplayer.set_multiplayer_peer(peer)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: int, response: Steam.ChatRoomEnterResponse) -> void:
	if response == Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("Lobby %s joined successfully" % lobby_id)
		lobby_joined.emit(lobby_id)
		current_lobby_id = lobby_id
		
		var id = Steam.getLobbyOwner(lobby_id)
		# Only create a client if this player is not the host.
		if id != Steam.getSteamID():
			var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
			var err = peer.connect_to_lobby(lobby_id)
			if err != OK:
				printerr("Steam connect_to_lobby failed: ", err)
				return

			peer.set_debug_level(SteamMultiplayerPeer.DEBUG_LEVEL_PEER)
			peer.no_nagle = true
			multiplayer.set_multiplayer_peer(peer)
	else:
		match response:
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:
				printerr("Failed joining lobby %s, this lobby no longer exists.")
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED:
				printerr("Failed joining lobby %s, you don't have permission to join this Lobbies.")
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_FULL:
				printerr("Failed joining lobby %s, the lobby is now full.")
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_ERROR:
				printerr("Failed joining lobby %s, something unexpected happened!")
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_BANNED:
				printerr("Failed joining lobby %s, you are banned from this lobby.")
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_LIMITED:
				printerr("Failed joining lobby %s, you cannot join due to having a limited account.")
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_CLAN_DISABLED:
				printerr("Failed joining lobby %s, this lobby is locked or disabled.")
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_COMMUNITY_BAN:
				printerr("Failed joining lobby %s, this lobby is community locked.")
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_MEMBER_BLOCKED_YOU:
				printerr("Failed joining lobby %s, a user in the lobby has blocked you from joining.")
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_YOU_BLOCKED_MEMBER:
				printerr("Failed joining lobby %s, a user you have blocked is in the lobby.")
			Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_RATE_LIMIT_EXCEEDED:
				printerr("Failed joining lobby %s, you have exceeded the rate limit.")

func _on_lobby_leave(lobby_id: int):
	print("Left lobby %d" % lobby_id)
	multiplayer.set_multiplayer_peer(null)
	current_ping = 0.0
	lobby_left.emit(lobby_id)
	current_lobby_id = -1

func _on_server_disconnected() -> void:
	printerr("CLIENT: Disconnected from host!")
	if current_lobby_id != -1:
		leave_lobby(current_lobby_id)
	else:
		multiplayer.set_multiplayer_peer(null)
		current_ping = 0.0

func _on_connection_failed() -> void:
	printerr("CLIENT: Connection failed!")
	if current_lobby_id != -1:
		leave_lobby(current_lobby_id)
	else:
		multiplayer.set_multiplayer_peer(null)
		current_ping = 0.0

func _on_lobbies_list(lobby_ids: Array) -> void:
	var filtered_lobby_ids: Array[int] = []
	
	for lobby_id: int in lobby_ids:
		
		var visibility: Steam.LobbyType = int(get_lobby_data(lobby_id, LobbyDataKey.Visibility)) as Steam.LobbyType
		if visibility == Steam.LobbyType.LOBBY_TYPE_PUBLIC:
			filtered_lobby_ids.append(lobby_id)
		elif visibility == Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY:
			var lobby_creator_id: int = int(get_lobby_data(lobby_id, LobbyDataKey.CreatorId))
			var relationship_to_me: Steam.FriendRelationship = Steam.getFriendRelationship(lobby_creator_id)
			if relationship_to_me == Steam.FriendRelationship.FRIEND_RELATION_FRIEND:
				filtered_lobby_ids.push_front(lobby_id)
	
	print("Received %d lobbies from Steam" % filtered_lobby_ids.size())
	lobby_list_updated.emit(filtered_lobby_ids)

func _on_lobby_data_changed(success: int, lobby_id: int, member_id: int):
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

@rpc("any_peer", "call_remote", "unreliable")
func _ping_server(client_time: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	_pong_client.rpc_id(sender_id, client_time)

@rpc("authority", "call_remote", "unreliable")
func _pong_client(sent_time: int) -> void:
	current_ping = float(Time.get_ticks_msec() - sent_time)
#endregion
