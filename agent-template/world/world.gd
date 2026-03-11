extends Node3D
class_name World

@onready var agent_spawner: AgentSpawner = $AgentSpawner
@onready var item_spawner: ItemSpawner = $ItemSpawner

# Only called on host
func ready_with_host_data(agent_id_to_peer_id: Dictionary[int, int], agent_datas: Array[Array]):
	agent_spawner.ready_with_host_data(agent_id_to_peer_id, agent_datas)
