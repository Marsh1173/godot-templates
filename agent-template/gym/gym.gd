extends Node3D

@onready var agent_spawner: AgentSpawner = $AgentSpawner

# Only called on host
func ready_with_host_data(agent_id_to_peer_id: Dictionary[int, int], agent_datas: Array[Array]):
	agent_spawner.ready_with_host_data(agent_id_to_peer_id, agent_datas)
	
func _ready():
	pass
	#var player: Agent = agent_scene.instantiate().with_data(false);
	#player.name = "Player"
	#add_child(player, true)
	
	#var ai = agent_scene.instantiate()._with_data(true);
	#ai.name = "AI"
	#add_child(ai, true) # Force readable name for cross-network communication
