extends MultiplayerSpawner
class_name AgentSpawner

const AGENT = preload("res://agent-template/agent/agent.tscn")

func _ready():
	spawn_function = _custom_spawn_logic

# Only called on host, at the start of the game
func ready_with_host_data(agent_id_to_peer_id: Dictionary[int, int], agent_datas: Array[Array]):
	for agent_data in agent_datas:
		var agent_id = agent_data[0]
		var agent_name = agent_data[1]
		var peer_id_or_null = agent_id_to_peer_id.get(agent_id)
		var data = [
			agent_id,
			agent_name,
			peer_id_or_null,
		]
		var agent: Agent = spawn(data)
		
		# Agents start out alive
		agent.pawn_spawner.spawn()

func _custom_spawn_logic(data) -> Agent:
	var agent_id = data[0]
	var agent_name = data[1]
	var peer_id_or_null = data[2]
	
	var agent: Agent = AGENT.instantiate().with_data(agent_id, agent_name, peer_id_or_null)
	return agent
