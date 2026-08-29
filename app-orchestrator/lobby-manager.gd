class_name LobbyManager
extends Node

var current_lobby_id: int = -1

const DEFAULT_ENET_PORT: int = 8321
const STEAM_APP_ID: int = 5034360
var _steam_active: bool = false

# Used to track a lobby ID from Steam invites or joining via Friends List
# var invite_lobby_id: int = 0

func _ready() -> void:
	OS.set_environment("SteamAppId", str(STEAM_APP_ID))
	OS.set_environment("SteamGameId", str(STEAM_APP_ID))
	
	process_mode = Node.PROCESS_MODE_ALWAYS # Keep networking alive during scene-tree pause
	
	_init_steam()

	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobbies_list)
	Steam.lobby_data_update.connect(_on_lobby_data_changed)
	Steam.lobby_kicked.connect(_on_lobby_leave)

func _process(_delta: float) -> void:
	if _steam_active:
		Steam.run_callbacks()

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
func create_lobby(visibility: Steam.LobbyType, max_players: int):
	print("Attempting to create lobby")
	Steam.createLobby(visibility, max_players)

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

enum DataKey {
	InProgress,
	Name,
	NumMaxPlayers,
	NumCurrentPlayers,
}

func get_lobby_data(lobby_id: int, key: DataKey) -> String:
	if key == DataKey.NumMaxPlayers:
		return str(Steam.getLobbyMemberLimit(lobby_id))
	if key == DataKey.NumCurrentPlayers:
		return str(Steam.getNumLobbyMembers(lobby_id))
	return Steam.getLobbyData(lobby_id, str(key))

func set_lobby_data(lobby_id: int, key: DataKey, value: String):
	if not Steam.setLobbyData(lobby_id, str(key), value):
		printerr("Failed to set lobby data. Key: " + str(key) + ", value: " + value)

enum MemberDataKey {
	PeerId
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
	if connect_status != Steam.Result.RESULT_OK:
		# Our lobby creation failed
		printerr("Failed to create a lobby: %s" % connect_status)
		return
	
	print("Successfully created lobby %s" % lobby_id)
	set_lobby_data(lobby_id, DataKey.Name, Steam.getFriendPersonaName(Steam.getSteamID()) + "'s Game")
	
	var peer: MultiplayerPeer
	if OS.is_debug_build():
		peer = ENetMultiplayerPeer.new()
		var err = peer.create_server(DEFAULT_ENET_PORT)
		if err != OK:
			printerr("ENet create_server failed: ", err)
			return
	else:
		peer = SteamMultiplayerPeer.new()
		
		#peer.server_relay = true # Note: GodotSteam defaults to SDR/relay automatically, but if you set it, do it before create_*
		var err = peer.create_host(0)
		if err != OK:
			printerr("Steam create_server failed: ", err)
			return
	
	multiplayer.set_multiplayer_peer(peer)
	set_member_data(lobby_id, MemberDataKey.PeerId, str(multiplayer.get_unique_id()))

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: int, response: Steam.ChatRoomEnterResponse) -> void:
	if response == Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("Lobby %s joined successfully" % lobby_id)
		lobby_joined.emit(lobby_id)
		current_lobby_id = lobby_id
		
		var id = Steam.getLobbyOwner(lobby_id)
		# Only create a client if this player is not the host.
		if id != Steam.getSteamID():
			var peer: MultiplayerPeer
			if OS.is_debug_build():
				peer = ENetMultiplayerPeer.new()
				var err = peer.create_client("127.0.0.1", DEFAULT_ENET_PORT)
				if err != OK:
					printerr("ENet create_client failed: ", err)
					return
			else:
				peer = SteamMultiplayerPeer.new()
				
				var server_steam_id: int = Steam.getLobbyOwner(lobby_id)
				#peer.server_relay = true # Note: GodotSteam defaults to SDR/relay automatically, but if you set it, do it before create_*
				var err = peer.create_client(server_steam_id, 0)
				if err != OK:
					printerr("Steam create_client failed: ", err)
					return
			multiplayer.set_multiplayer_peer(peer)
			set_member_data(lobby_id, MemberDataKey.PeerId, str(multiplayer.get_unique_id()))
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
	lobby_left.emit(lobby_id)
	current_lobby_id = -1

func _on_lobbies_list(lobby_ids: Array) -> void:
	print("Received %d lobbies from Steam" % lobby_ids.size())
	
	# I love Godot's type system
	var typed_lobby_ids: Array[int]
	typed_lobby_ids.assign(lobby_ids)
	
	lobby_list_updated.emit(typed_lobby_ids)

func _on_lobby_data_changed(success: int, lobby_id: int, member_id: int):
	if success == Steam.Result.RESULT_OK:
		lobby_data_changed.emit(lobby_id, member_id)
	else:
		print("_on_lobby_data_changed failed, error code: ", str(success))
#endregion
