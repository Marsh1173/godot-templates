## LobbyUI.gd
## Attached to a Control node that lives in the lobby scene.
##
## Responsibilities:
##   1. Bridge: reacts to SessionManager events and triggers NetworkManager transport calls.
##   2. Authority: validates and applies team assignments server-side via RPC.
##   3. Reactive UI: rebuilds team lists whenever session data changes.
##
## This script communicates ONLY with SessionManager and NetworkManager.
## SteamLobbyManager is an implementation detail hidden behind SessionManager.
##
## Team roster is stored as a JSON string in Steam lobby global data under the
## key "roster". Schema:
##   {
##     "red":  [ { "peer_id": 2, "steam_id": 76561198000000001, "name": "Alice" },
##               { "peer_id": "bot_1", "steam_id": 0, "name": "AI Bot 1" } ],
##     "blue": [ { "peer_id": 3, "steam_id": 76561198000000002, "name": "Bob"   } ]
##   }
extends Control

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Valid team identifiers. Extend this array to support more teams.
const VALID_TEAMS: Array[String] = ["red", "blue"]

## Maximum human + AI players allowed per team.
const MAX_TEAM_SIZE: int = 4

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

## Monotonically increasing counter used to generate unique bot slot IDs.
var _bot_counter: int = 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_connect_lobby_signals()


func _connect_lobby_signals() -> void:
	SessionManager.lobby_created.connect(_on_lobby_created)
	SessionManager.lobby_joined.connect(_on_lobby_joined)
	SessionManager.lobby_data_updated.connect(_on_lobby_data_updated)

# ---------------------------------------------------------------------------
# SteamLobbyManager signal handlers — the "bridge" layer
# ---------------------------------------------------------------------------

## Fired when the session has been created and this peer is the host.
## Steam path: triggered after SteamLobbyManager confirms lobby creation.
## ENet path:  triggered immediately by SessionManager.create_lobby().
## Note: For the Steam path, NetworkManager.host_game() is called by
## SessionManager.create_lobby() directly; nothing extra needed here.
func _on_lobby_created(lobby_id: int) -> void:
	print("LobbyUI: Session %d created — initialising roster." % lobby_id)
	_init_roster()
	# Publish our peer ID so _get_steam_id_for_peer() can resolve us.
	# For ENet this writes into SessionManager's local member store.
	SessionManager.set_member_data("peer_id", str(multiplayer.get_unique_id()))


## Fired when this peer has joined a session (host or client).
## Steam path: triggered after SteamLobbyManager confirms the join.
## ENet path:  triggered immediately by SessionManager.join_lobby().
## Note: Transport connection (host_game / join_game) is handled inside
## SessionManager; LobbyUI only needs to publish its peer ID here.
func _on_lobby_joined(lobby_id: int) -> void:
	print("LobbyUI: Joined session %d — publishing peer ID." % lobby_id)
	# Publish our peer ID to member data.
	# Note: multiplayer.get_unique_id() is valid only after the transport
	# handshake completes. If it reads 0 here, connect this call to
	# NetworkManager.transport_ready instead.
	SessionManager.set_member_data("peer_id", str(multiplayer.get_unique_id()))


## Fired whenever any lobby or member key-value pair changes.
## Pull the canonical roster from Steam and rebuild the UI.
func _on_lobby_data_updated(_lobby_id: int, _member_id: int, _key: String) -> void:
	_refresh_roster_ui()

# ---------------------------------------------------------------------------
# Authoritative team assignment — RPC
# ---------------------------------------------------------------------------

## Called by any peer to request joining [param team_name].
##
## Annotation breakdown:
##   "any_peer"   — any connected peer may invoke this RPC.
##   "call_local" — executes on the remote target AND locally when sender == target.
##                  This is critical: when the Host (peer 1) calls rpc_id(1, ...),
##                  sender == target, so "call_remote" would silently skip execution.
##                  "call_local" guarantees the host can join its own teams.
##   "reliable"   — guaranteed delivery, ordered.
##
## Usage (any peer, including the host):
##   rpc_id(1, "request_join_team", "red")
@rpc("any_peer", "call_local", "reliable")
func request_join_team(team_name: String) -> void:
	# This block executes exclusively on the host (peer ID 1).
	var sender_peer_id: int  = multiplayer.get_remote_sender_id()
	var sender_steam_id: int = _get_steam_id_for_peer(sender_peer_id)
	var sender_name: String  = Steam.getFriendPersonaName(sender_steam_id)

	print("LobbyUI [HOST]: Peer %d (%s) requests team '%s'." % [sender_peer_id, sender_name, team_name])

	# --- Validate ---
	if team_name not in VALID_TEAMS:
		push_warning("LobbyUI [HOST]: Invalid team '%s' requested by peer %d." % [team_name, sender_peer_id])
		return

	var roster: Dictionary = _parse_roster()

	# Remove the sender from any team they are already on.
	_remove_peer_from_all_teams(roster, sender_peer_id)

	# Check capacity *after* removal so a player switching teams isn't double-counted.
	var team_list: Array = roster.get(team_name, [])
	if team_list.size() >= MAX_TEAM_SIZE:
		push_warning("LobbyUI [HOST]: Team '%s' is full; rejecting request from peer %d." % [team_name, sender_peer_id])
		return

	# --- Commit ---
	team_list.append({
		"peer_id":  sender_peer_id,
		"steam_id": sender_steam_id,
		"name":     sender_name,
	})
	roster[team_name] = team_list
	_save_roster(roster)

# ---------------------------------------------------------------------------
# AI player management — host-only
# ---------------------------------------------------------------------------

## Add an AI bot slot to [param team_name].
## Must only be called on the host; call is a no-op on clients.
func add_ai_to_team(team_name: String) -> void:
	if not multiplayer.is_server():
		push_warning("LobbyUI: add_ai_to_team() may only be called on the host.")
		return

	if team_name not in VALID_TEAMS:
		push_error("LobbyUI [HOST]: Invalid team '%s' passed to add_ai_to_team()." % team_name)
		return

	var roster: Dictionary = _parse_roster()
	var team_list: Array   = roster.get(team_name, [])

	if team_list.size() >= MAX_TEAM_SIZE:
		push_warning("LobbyUI [HOST]: Team '%s' is full; cannot add AI." % team_name)
		return

	_bot_counter += 1
	var bot_id: String = "bot_%d" % _bot_counter

	team_list.append({
		"peer_id":  bot_id,
		"steam_id": 0,
		"name":     "AI Bot %d" % _bot_counter,
	})
	roster[team_name] = team_list
	_save_roster(roster)
	print("LobbyUI [HOST]: Added AI slot '%s' to team '%s'." % [bot_id, team_name])

# ---------------------------------------------------------------------------
# Reactive UI rebuild
# ---------------------------------------------------------------------------

## Pull the authoritative roster from Steam lobby data and refresh all team lists.
func _refresh_roster_ui() -> void:
	var roster: Dictionary = _parse_roster()
	_update_team_ui_lists(roster)


## Mock UI builder — replace the print calls here when real Control nodes are wired.
## [param roster] keys are team names; values are Arrays of player-entry Dictionaries.
func _update_team_ui_lists(roster: Dictionary) -> void:
	print("--- LobbyUI: Rebuilding team UI ---")
	for team_name in VALID_TEAMS:
		var members: Array = roster.get(team_name, [])
		print("  Team '%s' (%d/%d):" % [team_name, members.size(), MAX_TEAM_SIZE])
		if members.is_empty():
			print("    (empty)")
		for entry in members:
			print("    • %s  [peer=%s | steam=%s]" % [
				entry.get("name",     "?"),
				str(entry.get("peer_id",  "?")),
				str(entry.get("steam_id", 0)),
			])
	print("-----------------------------------")

# ---------------------------------------------------------------------------
# Roster helpers
# ---------------------------------------------------------------------------

## Parse the "roster" JSON from the session's global data store.
## Returns an empty skeleton dictionary when no roster exists yet.
func _parse_roster() -> Dictionary:
	var raw: String = SessionManager.get_global_data("roster")
	if raw.is_empty():
		# First call before any roster exists — return a valid empty skeleton.
		var skeleton: Dictionary = {}
		for t in VALID_TEAMS:
			skeleton[t] = []
		return skeleton

	var json := JSON.new()
	var err: Error = json.parse(raw)
	if err != OK:
		push_error("LobbyUI: Failed to parse roster JSON (error %d). Raw: '%s'" % [err, raw])
		var skeleton: Dictionary = {}
		for t in VALID_TEAMS:
			skeleton[t] = []
		return skeleton

	return json.get_data()


## Serialize [param roster] to JSON and push it to the session's global data store.
func _save_roster(roster: Dictionary) -> void:
	var json_string: String = JSON.stringify(roster)
	SessionManager.set_global_data("roster", json_string)


## Write an empty roster to Steam lobby global data.
## Called by the host immediately after creating the lobby.
func _init_roster() -> void:
	var skeleton: Dictionary = {}
	for t in VALID_TEAMS:
		skeleton[t] = []
	_save_roster(skeleton)
	print("LobbyUI [HOST]: Roster initialized.")


## Remove all entries matching [param peer_id] from every team in [param roster].
## Modifies the dictionary in place.
func _remove_peer_from_all_teams(roster: Dictionary, peer_id: int) -> void:
	for team_name in roster.keys():
		var team_list: Array = roster[team_name]
		# Filter out any entry whose peer_id matches (bots use String IDs so
		# a strict equality check against an int will never falsely match them).
		roster[team_name] = team_list.filter(func(e): return e.get("peer_id") != peer_id)


## Look up the Steam ID associated with a given Multiplayer Peer ID.
##
## Steam transport: walks the Steam lobby member list matching against the
##                  "peer_id" member data key published by each client.
## ENet transport:  no Steam IDs exist; returns peer_id cast as an int
##                  so roster entries remain consistent in format.
func _get_steam_id_for_peer(peer_id: int) -> int:
	if NetworkManager.transport == NetworkManager.TransportLayer.ENET:
		# In ENet mode peer_id is already the unique identifier — use it directly.
		return peer_id

	var lobby_id: int     = SteamLobbyManager.current_lobby_id
	var member_count: int = Steam.getNumLobbyMembers(lobby_id)

	for i in member_count:
		var member_steam_id: int = Steam.getLobbyMemberByIndex(lobby_id, i)
		# GodotSteam stores the multiplayer peer ID as a string in "peer_id" member data.
		var stored: String = Steam.getLobbyMemberData(lobby_id, member_steam_id, "peer_id")
		if stored.to_int() == peer_id:
			return member_steam_id

	push_warning("LobbyUI [HOST]: Could not resolve Steam ID for peer %d." % peer_id)
	return 0
