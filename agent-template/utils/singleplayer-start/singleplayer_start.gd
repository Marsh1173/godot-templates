extends Node

const GYM = preload("res://agent-template/gym/gym.tscn")

const instance_player_ids = [25, 27, 23, 21, 18, 15]

var agent_datas: Array[Array] = [
	[25, "Nate"],
	[27, "Mark"],
	[23, "Paul"],
]

var agent_id_to_peer_id: Dictionary[int, int] = {}

func _ready():
	agent_id_to_peer_id.set(instance_player_ids[0], 1)
	start_game()

func start_game():
	var gym = GYM.instantiate()
	add_child(gym, true)
	
	if MyUtils.is_authority(multiplayer):
		gym.world.ready_with_host_data(agent_id_to_peer_id, agent_datas)
	
