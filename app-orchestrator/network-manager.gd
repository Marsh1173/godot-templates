class_name NetworkManager
extends Node

signal connected_to_server()
signal connection_failed()
signal server_disconnected()
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)

var current_ping: float = 0.0
var _ping_timer: float = 0.0
const PING_INTERVAL: float = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != 1:
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_ping_timer -= delta
			if _ping_timer <= 0.0:
				_ping_timer = PING_INTERVAL
				_ping_server.rpc_id(1, Time.get_ticks_msec())

#region Network Operations
func host_steam_lobby(lobby_id: int) -> Error:
	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var err: Error = peer.host_with_lobby(lobby_id)
	if err != OK:
		printerr("Steam host_with_lobby failed: ", err)
		return err

	peer.set_debug_level(SteamMultiplayerPeer.DEBUG_LEVEL_PEER)
	peer.no_nagle = true
	multiplayer.set_multiplayer_peer(peer)
	print("NetworkManager: Hosting with Steam lobby %d" % lobby_id)
	return OK

func connect_steam_lobby(lobby_id: int) -> Error:
	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var err: Error = peer.connect_to_lobby(lobby_id)
	if err != OK:
		printerr("Steam connect_to_lobby failed: ", err)
		return err

	peer.set_debug_level(SteamMultiplayerPeer.DEBUG_LEVEL_PEER)
	peer.no_nagle = true
	multiplayer.set_multiplayer_peer(peer)
	print("NetworkManager: Connecting to Steam lobby %d" % lobby_id)
	return OK

func stop() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.set_multiplayer_peer(null)
	current_ping = 0.0
	print("NetworkManager: Stopped multiplayer peer")

func is_active() -> bool:
	return multiplayer.has_multiplayer_peer()

func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()

func is_connected_to_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func get_peer_id_for_steam_id(steam_id: int) -> int:
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer is SteamMultiplayerPeer:
		return multiplayer.multiplayer_peer.get_peer_id_for_steam_id(steam_id)
	return 0

func is_steam_id_connected(steam_id: int, host_steam_id: int) -> bool:
	# Host is always connected to self
	if steam_id == host_steam_id and Steam.getSteamID() == host_steam_id:
		return true

	# If we are host, check if peer exists for this client
	if host_steam_id == Steam.getSteamID():
		if multiplayer.has_multiplayer_peer():
			if multiplayer.multiplayer_peer is SteamMultiplayerPeer:
				return multiplayer.multiplayer_peer.get_peer_id_for_steam_id(steam_id) > 0
			return true
		return false

	# If we are client checking ourselves or the host
	if steam_id == Steam.getSteamID() or steam_id == host_steam_id:
		return is_connected_to_host()

	# Other peers from client's perspective
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer is SteamMultiplayerPeer:
		return multiplayer.multiplayer_peer.get_peer_id_for_steam_id(steam_id) > 0
	return false
#endregion

#region Internal Callbacks
func _on_connected_to_server() -> void:
	print("CLIENT: Successfully connected to host!")
	connected_to_server.emit()

func _on_connection_failed() -> void:
	printerr("CLIENT: Connection failed!")
	stop()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	printerr("CLIENT: Disconnected from host!")
	stop()
	server_disconnected.emit()

func _on_peer_connected(id: int) -> void:
	print("PEER CONNECTED: ", id)
	peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("PEER DISCONNECTED: ", id)
	peer_disconnected.emit(id)
#endregion

#region Ping RPCs
@rpc("any_peer", "call_remote", "unreliable")
func _ping_server(client_time: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	_pong_client.rpc_id(sender_id, client_time)

@rpc("authority", "call_remote", "unreliable")
func _pong_client(sent_time: int) -> void:
	current_ping = float(Time.get_ticks_msec() - sent_time)
#endregion
