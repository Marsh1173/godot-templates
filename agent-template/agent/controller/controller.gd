extends Node
class_name Controller
	
var focus_node = null
var focus_pitch: float = 0
var focus_yaw: float = 0

var action_buffer: Array[Action] = []

var owner_peer_id: int = 1

# Called when created
func with_data(_owner_peer_id: int):
	owner_peer_id = _owner_peer_id
	return self

func queue_action(action: Action):
	if MyNetwork.is_authority(multiplayer):
		action_buffer.append(action)
	else:
		var serialized_action = action.to_json()
		send_action.rpc_id(1, serialized_action)

@rpc("any_peer", "call_remote", "reliable")
func send_action(data: String):
	if multiplayer.get_remote_sender_id() == owner_peer_id:
		var deserialized_action: Action = Action.from_json(data)
		queue_action(deserialized_action)

func gather_actions() -> Array[Action]:
	if action_buffer.size() == 0:
		return []
	
	var actions = action_buffer.duplicate()
	action_buffer.clear()
	return actions

func set_focus_node(node):
	focus_node = node

func set_view_direction(pitch: float, yaw: float):
	focus_pitch = pitch
	focus_yaw = yaw
