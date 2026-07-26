## NetworkManager.gd
## Autoload singleton that abstracts the multiplayer transport layer.
## Supports seamless toggling between ENet (local testing) and Steam Sockets.
##
## Usage:
##   NetworkManager.transport = NetworkManager.TransportLayer.ENET  # or STEAM
##   NetworkManager.host_game()
##   NetworkManager.join_game("127.0.0.1")  # ENet: IP string
##   NetworkManager.join_game(76561198012345678)  # Steam: Steam ID integer
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when any remote peer connects to this instance (client or server).
signal peer_connected(peer_id: int)

## Emitted when a remote peer disconnects.
signal peer_disconnected(peer_id: int)

## Emitted on a client when the server disconnects.
signal server_disconnected()

## Emitted on a client when the connection attempt to the server failed.
signal connection_failed()

## Emitted after host_game() or join_game() succeeds.
signal transport_ready(transport: TransportLayer)

## Emitted when Steam initializes successfully.
signal steam_initialized()

## Emitted when Steam fails to initialize; carries a human-readable reason.
signal steam_init_failed(reason: String)

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum TransportLayer { ENET, STEAM }

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

## Set this before calling host_game() / join_game() to choose the backend.
## ENET  – standard UDP sockets, ideal for LAN / "Multiplayer Gym" testing.
## STEAM – routes through Steam's relay network; requires a valid Steam session.
var transport: TransportLayer = TransportLayer.ENET

## Steam App ID used during development / testing (Spacewar demo app).
const STEAM_APP_ID: int = 480

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _steam_active: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _init() -> void:
	OS.set_environment("SteamAppId", str(STEAM_APP_ID))
	OS.set_environment("SteamGameId", str(STEAM_APP_ID))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Keep networking alive during scene-tree pause
	_init_steam()


func _process(_delta: float) -> void:
	if _steam_active:
		Steam.run_callbacks()

# ---------------------------------------------------------------------------
# Steam initialization
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Host
# ---------------------------------------------------------------------------

## Start hosting a game session.
## [param port]  TCP/UDP port for ENet (ignored for Steam transport).
func host_game(port: int = 7777) -> void:
	var peer: MultiplayerPeer

	match transport:
		TransportLayer.ENET:
			var enet := ENetMultiplayerPeer.new()
			var err: Error = enet.create_server(port)
			if err != OK:
				push_error("NetworkManager: ENet create_server failed (error %d)" % err)
				return
			peer = enet
			print("NetworkManager: ENet server listening on port %d" % port)

		TransportLayer.STEAM:
			if not _steam_active:
				push_error("NetworkManager: Cannot host via Steam – Steam is not initialized.")
				return
			var steam_peer := SteamMultiplayerPeer.new()
			# create_host(virtual_port) – pass 0 for default virtual port.
			var err: Error = steam_peer.create_host(0)
			if err != OK:
				push_error("NetworkManager: SteamMultiplayerPeer create_host failed (error %d)" % err)
				return
			peer = steam_peer
			print("NetworkManager: Steam host created (virtual port 0)")

	_assign_peer(peer)
	transport_ready.emit(transport)

# ---------------------------------------------------------------------------
# Join
# ---------------------------------------------------------------------------

## Connect to an existing game session.
## [param target_id]  IP address string (ENet) or Steam ID integer (Steam).
## [param port]       TCP/UDP port for ENet (ignored for Steam transport).
func join_game(target_id: Variant, port: int = 7777) -> void:
	var peer: MultiplayerPeer

	match transport:
		TransportLayer.ENET:
			var ip: String = str(target_id)
			var enet := ENetMultiplayerPeer.new()
			var err: Error = enet.create_client(ip, port)
			if err != OK:
				push_error("NetworkManager: ENet create_client failed (error %d)" % err)
				return
			peer = enet
			print("NetworkManager: ENet client connecting to %s:%d" % [ip, port])

		TransportLayer.STEAM:
			if not _steam_active:
				push_error("NetworkManager: Cannot join via Steam – Steam is not initialized.")
				return
			var steam_id: int = int(target_id)
			var steam_peer := SteamMultiplayerPeer.new()
			# create_client(steam_id, virtual_port) – pass 0 for default virtual port.
			var err: Error = steam_peer.create_client(steam_id, 0)
			if err != OK:
				push_error("NetworkManager: SteamMultiplayerPeer create_client failed (error %d)" % err)
				return
			peer = steam_peer
			print("NetworkManager: Steam client connecting to Steam ID %d" % steam_id)

	_assign_peer(peer)
	transport_ready.emit(transport)

# ---------------------------------------------------------------------------
# Disconnect / cleanup
# ---------------------------------------------------------------------------

## Gracefully close the current connection and reset the multiplayer peer.
func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_disconnect_multiplayer_signals()
	print("NetworkManager: Disconnected and peer cleared.")

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Assigns [param peer] to the scene tree's MultiplayerAPI and wires signals.
func _assign_peer(peer: MultiplayerPeer) -> void:
	# Disconnect previously wired signals to avoid duplicate callbacks if this
	# function is called more than once (e.g., reconnecting).
	_disconnect_multiplayer_signals()

	multiplayer.multiplayer_peer = peer

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)


## Safely disconnects all HLM signals so they can be re-wired cleanly.
func _disconnect_multiplayer_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)

# ---------------------------------------------------------------------------
# HLM signal callbacks → re-emit as NetworkManager signals
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	print("NetworkManager: Peer connected – ID %d" % id)
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Peer disconnected – ID %d" % id)
	peer_disconnected.emit(id)


func _on_server_disconnected() -> void:
	print("NetworkManager: Server disconnected.")
	server_disconnected.emit()


func _on_connection_failed() -> void:
	push_warning("NetworkManager: Connection to server failed.")
	connection_failed.emit()
