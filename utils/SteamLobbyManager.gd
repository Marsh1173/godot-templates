## SteamLobbyManager.gd
## Autoload singleton that wraps the GodotSteam Matchmaking API.
## Handles lobby creation, searching, joining, and key-value data synchronization.
## This script is a reactive data store — it owns no transport or UI logic.
##
## Usage:
##   SteamLobbyManager.create_lobby(Steam.LOBBY_TYPE_PUBLIC, 8)
##   SteamLobbyManager.search_lobbies()
##   SteamLobbyManager.join_lobby(lobby_id)
##   SteamLobbyManager.set_global_data("map", "lava_rift")
##   SteamLobbyManager.set_member_data("ready", "true")
extends Node

# ---------------------------------------------------------------------------
# Signals — the UI layer listens to these; nothing inside this script does.
# ---------------------------------------------------------------------------

## Emitted after Steam confirms the lobby was created.
signal lobby_created(lobby_id: int)

## Emitted when Steam returns a list of matching lobbies from requestLobbyList.
## [param lobbies] is an Array of lobby-ID integers.
signal lobby_list_received(lobbies: Array)

## Emitted when this client has successfully joined a lobby.
signal lobby_joined(lobby_id: int)

## Emitted when any lobby or member key-value entry changes.
## [param member_id] is 0 when the changed data belongs to the lobby itself.
signal lobby_data_updated(lobby_id: int, member_id: int, key: String)

# ---------------------------------------------------------------------------
# Public state
# ---------------------------------------------------------------------------

## The lobby this client is currently in. 0 means not in a lobby.
var current_lobby_id: int = 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Lobby state must survive scene-tree pauses
	_connect_steam_signals()


# ---------------------------------------------------------------------------
# Steam callback wiring
# ---------------------------------------------------------------------------

func _connect_steam_signals() -> void:
	# lobby_created  → { result: int, lobby_id: int }
	Steam.lobby_created.connect(_on_lobby_created)
	# lobby_match_list → { lobbies: Array }
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	# lobby_joined → { lobby_id: int, permissions: int, locked: bool, response: int }
	Steam.lobby_joined.connect(_on_lobby_joined)
	# lobby_data_update → { success: bool, lobby_id: int, member_id: int }
	Steam.lobby_data_update.connect(_on_lobby_data_update)

# ---------------------------------------------------------------------------
# Lobby management — public API
# ---------------------------------------------------------------------------

## Create a new Steam lobby.
## [param lobby_type]   One of the Steam.LOBBY_TYPE_* constants
##                      (e.g., Steam.LOBBY_TYPE_PUBLIC, Steam.LOBBY_TYPE_FRIENDS_ONLY).
## [param max_members]  Maximum number of players allowed (Steam hard-cap is 250).
func create_lobby(lobby_type: int, max_members: int) -> void:
	if current_lobby_id != 0:
		push_warning("SteamLobbyManager: Already in lobby %d — leave it before creating a new one." % current_lobby_id)
		return
	print("SteamLobbyManager: Creating lobby (type=%d, max=%d)" % [lobby_type, max_members])
	Steam.createLobby(lobby_type, max_members)


## Request a list of available lobbies from Steam.
## IMPORTANT: Steam discards distance filters after every request, so
## addRequestLobbyListDistanceFilter is called here unconditionally before
## every requestLobbyList call to guarantee the filter is always applied.
func search_lobbies() -> void:
	print("SteamLobbyManager: Searching for lobbies…")
	# Re-apply the distance filter every time — Steam flushes it after each call.
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()


## Join an existing Steam lobby by its lobby ID.
func join_lobby(lobby_id: int) -> void:
	if current_lobby_id != 0:
		push_warning("SteamLobbyManager: Already in lobby %d — leave it before joining another." % current_lobby_id)
		return
	print("SteamLobbyManager: Joining lobby %d" % lobby_id)
	Steam.joinLobby(lobby_id)


## Leave the current lobby and reset local state.
func leave_lobby() -> void:
	if current_lobby_id == 0:
		push_warning("SteamLobbyManager: leave_lobby() called but not currently in a lobby.")
		return
	print("SteamLobbyManager: Leaving lobby %d" % current_lobby_id)
	Steam.leaveLobby(current_lobby_id)
	current_lobby_id = 0

# ---------------------------------------------------------------------------
# Global lobby data (K/V attached to the lobby itself)
# ---------------------------------------------------------------------------

## Set a key-value pair on the lobby that all members can read.
## Requires this client to be the lobby owner.
func set_global_data(key: String, value: String) -> void:
	if current_lobby_id == 0:
		push_error("SteamLobbyManager: set_global_data() called with no active lobby.")
		return
	Steam.setLobbyData(current_lobby_id, key, value)


## Read a key-value pair from the lobby's global metadata.
func get_global_data(key: String) -> String:
	if current_lobby_id == 0:
		push_warning("SteamLobbyManager: get_global_data() called with no active lobby.")
		return ""
	return Steam.getLobbyData(current_lobby_id, key)

# ---------------------------------------------------------------------------
# Per-member data (K/V attached to an individual member)
# ---------------------------------------------------------------------------

## Set a key-value pair on the local user's lobby member slot.
## Visible to all lobby members.
func set_member_data(key: String, value: String) -> void:
	if current_lobby_id == 0:
		push_error("SteamLobbyManager: set_member_data() called with no active lobby.")
		return
	Steam.setLobbyMemberData(current_lobby_id, key, value)


## Read a key-value pair from a specific member's lobby slot.
## [param steam_id]  The Steam ID of the member whose data you want to read.
func get_member_data(steam_id: int, key: String) -> String:
	if current_lobby_id == 0:
		push_warning("SteamLobbyManager: get_member_data() called with no active lobby.")
		return ""
	return Steam.getLobbyMemberData(current_lobby_id, steam_id, key)

# ---------------------------------------------------------------------------
# GodotSteam callback handlers → re-emit as SteamLobbyManager signals
# ---------------------------------------------------------------------------

func _on_lobby_created(result: int, lobby_id: int) -> void:
	# result == 1 (Steam.RESULT_OK) on success.
	if result != Steam.RESULT_OK:
		push_error("SteamLobbyManager: createLobby failed (result=%d)" % result)
		return

	current_lobby_id = lobby_id
	print("SteamLobbyManager: Lobby created – ID %d" % lobby_id)
	lobby_created.emit(lobby_id)


func _on_lobby_match_list(lobbies: Array) -> void:
	print("SteamLobbyManager: Received %d lobbies from Steam" % lobbies.size())
	lobby_list_received.emit(lobbies)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# response == 1 (Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS) on success.
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		push_error("SteamLobbyManager: joinLobby failed (response=%d)" % response)
		return

	current_lobby_id = lobby_id
	print("SteamLobbyManager: Joined lobby %d" % lobby_id)
	lobby_joined.emit(lobby_id)


## GodotSteam's lobby_data_update signal fires for both lobby-level and
## member-level changes.  member_id == 0 indicates a lobby-level change;
## otherwise it holds the Steam ID of the member whose data changed.
func _on_lobby_data_update(success: bool, lobby_id: int, member_id: int) -> void:
	if not success:
		push_warning("SteamLobbyManager: lobby_data_update reported failure (lobby=%d, member=%d)" % [lobby_id, member_id])
		return
	# The K/V key is not surfaced in this callback — consumers can call
	# Steam.getLobbyData / getLobbyMemberData themselves if they need the value.
	# We forward an empty string for the key so the signal signature stays stable
	# while still notifying the UI that something changed.
	lobby_data_updated.emit(lobby_id, member_id, "")
