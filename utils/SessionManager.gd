## SessionManager.gd
## Autoload singleton — the single source of truth for session/lobby state.
##
## Abstracts the transport backend so higher-level code (UI, game logic) never
## needs to know whether the session is running over Steam or ENet.
##
##   STEAM transport → delegates to SteamLobbyManager for all lobby/K-V work.
##   ENET  transport → manages metadata locally and syncs via authoritative RPC.
##
## All consumers should call SessionManager exclusively; SteamLobbyManager
## and NetworkManager are implementation details hidden behind this facade.
##
## Usage:
##   SessionManager.create_lobby()
##   SessionManager.join_lobby("192.168.1.50")   # ENet: IP string
##   SessionManager.join_lobby(109775241234567)   # Steam: lobby ID
##   SessionManager.set_global_data("map", "lava_rift")
##   SessionManager.set_member_data("ready", "true")
extends Node

# ---------------------------------------------------------------------------
# Unified signals — consumers listen here, never to SteamLobbyManager directly
# ---------------------------------------------------------------------------

## Emitted once the local peer has created and is hosting a session.
signal lobby_created(lobby_id: int)

## Emitted once the local peer has fully joined a session.
signal lobby_joined(lobby_id: int)

## Emitted whenever any global or member key-value pair changes.
## [param member_id] is 0 for lobby-level data; non-zero for a specific member.
## [param key] may be empty when the transport cannot surface which key changed
## (e.g., the GodotSteam lobby_data_update callback).
signal lobby_data_updated(lobby_id: int, member_id: int, key: String)

# ---------------------------------------------------------------------------
# ENet local state (bypasses Steam when transport == ENET)
# ---------------------------------------------------------------------------

## Lobby-level key-value store for ENet sessions.
var _local_global_data: Dictionary = {}

## Per-member key-value store for ENet sessions.
## Keyed by peer_id (int), value is a Dictionary of {key: value} strings.
var _local_member_data: Dictionary = {}

## Pseudo lobby ID used in ENet mode (always 1; there is no real Steam lobby).
const ENET_LOBBY_ID: int = 1

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_relay_steam_lobby_signals()

# ---------------------------------------------------------------------------
# Steam signal relay — forward SteamLobbyManager events through SessionManager
# ---------------------------------------------------------------------------

func _relay_steam_lobby_signals() -> void:
	SteamLobbyManager.lobby_created.connect(_on_steam_lobby_created)
	SteamLobbyManager.lobby_joined.connect(_on_steam_lobby_joined)
	SteamLobbyManager.lobby_data_updated.connect(_on_steam_lobby_data_updated)


func _on_steam_lobby_created(lobby_id: int) -> void:
	lobby_created.emit(lobby_id)


func _on_steam_lobby_joined(lobby_id: int) -> void:
	lobby_joined.emit(lobby_id)


func _on_steam_lobby_data_updated(lobby_id: int, member_id: int, key: String) -> void:
	lobby_data_updated.emit(lobby_id, member_id, key)

# ---------------------------------------------------------------------------
# Public API — Lobby lifecycle
# ---------------------------------------------------------------------------

## Create and host a new session.
##
## Steam: creates a Steam lobby then NetworkManager.host_game() is triggered
##        reactively by LobbyUI when lobby_created fires.
## ENet:  initialises local state, starts the transport, and emits the
##        session signals immediately (no Steam round-trip required).
func create_lobby(lobby_type: int = 1, max_members: int = 4) -> void:
	match NetworkManager.transport:
		NetworkManager.TransportLayer.STEAM:
			SteamLobbyManager.create_lobby(lobby_type, max_members)
			# LobbyUI reacts to lobby_created (relayed above) and calls host_game().

		NetworkManager.TransportLayer.ENET:
			print("SessionManager [ENet]: Creating local session.")
			_local_global_data.clear()
			_local_member_data.clear()
			NetworkManager.host_game()
			# Emit after transport is up so consumers receive a consistent state.
			lobby_created.emit(ENET_LOBBY_ID)
			lobby_joined.emit(ENET_LOBBY_ID)


## Join an existing session.
##
## [param target]  Steam lobby ID (int or numeric string) for Steam transport,
##                 or an IP address string for ENet (defaults to "127.0.0.1").
func join_lobby(target: Variant = "127.0.0.1") -> void:
	match NetworkManager.transport:
		NetworkManager.TransportLayer.STEAM:
			var lobby_id: int = int(target)
			SteamLobbyManager.join_lobby(lobby_id)
			# LobbyUI reacts to lobby_joined (relayed above) and calls join_game().

		NetworkManager.TransportLayer.ENET:
			# Resolve the target address; fall back to loopback if nothing provided.
			var address: String = "127.0.0.1"
			if target != null and str(target).strip_edges() != "":
				address = str(target).strip_edges()
			print("SessionManager [ENet]: Joining session at '%s'." % address)
			_local_global_data.clear()
			_local_member_data.clear()
			NetworkManager.join_game(address)
			lobby_joined.emit(ENET_LOBBY_ID)

# ---------------------------------------------------------------------------
# Public API — Global lobby data (K/V on the session itself)
# ---------------------------------------------------------------------------

## Set a lobby-level key-value pair visible to all members.
## On ENet this is host-authoritative and synced via RPC.
func set_global_data(key: String, value: String) -> void:
	match NetworkManager.transport:
		NetworkManager.TransportLayer.STEAM:
			SteamLobbyManager.set_global_data(key, value)

		NetworkManager.TransportLayer.ENET:
			if not multiplayer.is_server():
				push_warning("SessionManager [ENet]: set_global_data() ignored — only the host may write global data.")
				return
			# Write locally then broadcast to all peers.
			_local_global_data[key] = value
			_sync_enet_global_data.rpc(key, value)


## Read a lobby-level key-value pair.
func get_global_data(key: String) -> String:
	match NetworkManager.transport:
		NetworkManager.TransportLayer.STEAM:
			return SteamLobbyManager.get_global_data(key)

		NetworkManager.TransportLayer.ENET:
			return _local_global_data.get(key, "")

	return ""

# ---------------------------------------------------------------------------
# Public API — Per-member data (K/V on an individual session member)
# ---------------------------------------------------------------------------

## Set a key-value pair on the local peer's member slot.
## Visible to all session members.
func set_member_data(key: String, value: String) -> void:
	match NetworkManager.transport:
		NetworkManager.TransportLayer.STEAM:
			SteamLobbyManager.set_member_data(key, value)

		NetworkManager.TransportLayer.ENET:
			var local_peer: int = multiplayer.get_unique_id()
			if not _local_member_data.has(local_peer):
				_local_member_data[local_peer] = {}
			_local_member_data[local_peer][key] = value
			# Notify listeners that member data changed for this peer.
			lobby_data_updated.emit(ENET_LOBBY_ID, local_peer, key)


## Read a key-value pair from a specific session member's slot.
## [param peer_id]  Multiplayer peer ID (ENet) or Steam ID (Steam).
func get_member_data(peer_id: int, key: String) -> String:
	match NetworkManager.transport:
		NetworkManager.TransportLayer.STEAM:
			return SteamLobbyManager.get_member_data(peer_id, key)

		NetworkManager.TransportLayer.ENET:
			return _local_member_data.get(peer_id, {}).get(key, "")

	return ""

# ---------------------------------------------------------------------------
# ENet global-data sync RPC
# ---------------------------------------------------------------------------

## Broadcast a global data change from the host to all connected ENet clients.
##
## Annotation:
##   "any_peer"   — the host sends this; any_peer allows it to originate from
##                  peer 1 without needing authority restrictions.
##   "call_local" — the host applies the write locally as well as remotely.
##   "reliable"   — guaranteed ordered delivery; critical for roster integrity.
##
## Called internally by set_global_data() on the host; never call directly.
@rpc("any_peer", "call_local", "reliable")
func _sync_enet_global_data(key: String, value: String) -> void:
	_local_global_data[key] = value
	lobby_data_updated.emit(ENET_LOBBY_ID, 0, key)
