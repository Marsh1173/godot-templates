extends Node

const GYM = preload("res://agent-template/gym/gym.tscn")

var game_instance = -1
const IP_ADDRESS := "192.168.1.159"
const PORT := 8080

const instance_player_ids = [25, 27, 23, 21, 18, 15]
#var agent_datas: Dictionary[int, AgentData] = {
	#25: AgentData.new(25, "Nate"),
	#27: AgentData.new(27, "Mark"),
	#23: AgentData.new(23, "Paul"),
	#21: AgentData.new(21, "Ethan"),
	#18: AgentData.new(18, "Kate"),
	#15: AgentData.new(15, "John"),
#}
var agent_datas: Array[Array] = [
	[25, "Nate"],
	[27, "Mark"],
	[23, "Paul"],
	#[21, "Ethan"],
	#[18, "Kate"],
	#[15, "John"],
]
var agent_id_to_peer_id: Dictionary[int, int] = {}

func _ready():
	_connect_everyone()
	
func _connect_everyone():
	game_instance = get_game_instance()
	if game_instance == 0:
		as_server()
		await get_tree().create_timer(1).timeout
		all_peers_ready.rpc()
	else:
		await get_tree().create_timer(0.5).timeout
		as_client()

func get_game_instance() -> int:
	for arg in OS.get_cmdline_args():
		if arg.contains("instance="):
			return int(arg.replace("instance=", ""))
	return -1

func as_server():
	# Create server.
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	
	agent_id_to_peer_id.set(instance_player_ids[game_instance], 1)

func as_client():
	# Create client.
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(IP_ADDRESS, PORT)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_set_peer_id_to_agent_id)

func _set_peer_id_to_agent_id():
	set_player_id.rpc_id(1, instance_player_ids[game_instance]) # Tell server what player this is
	multiplayer.connected_to_server.disconnect(_set_peer_id_to_agent_id)

@rpc("any_peer", "call_remote", "reliable")
func set_player_id(id: int):
	agent_id_to_peer_id.set(id, multiplayer.get_remote_sender_id())

@rpc("authority", "call_local", "reliable")
func all_peers_ready():
	start_game()

func start_game():
	var gym = GYM.instantiate()
	add_child(gym, true)
	
	if MyNetwork.is_authority(multiplayer):
		gym.ready_with_host_data(agent_id_to_peer_id, agent_datas)
	
