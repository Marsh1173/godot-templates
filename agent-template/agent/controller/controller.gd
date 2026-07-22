extends Node
class_name Controller

@onready var state_replicator: ControllerStateReplicator = $ControllerStateReplicator
	
var focus_node: Node3D = null

var action_buffer: Array[Action] = []

var owner_peer_id: int = 1

# Called when created
func with_data(_owner_peer_id: int):
	owner_peer_id = _owner_peer_id
	return self

func queue_action(action: Action):
	if MyUtils.is_authority(multiplayer):
		action_buffer.append(action)
	else:
		# If it's a locally applied action, send to host AND apply locally
		if multiplayer.get_unique_id() == owner_peer_id and action.is_locally_applied_action():
			action_buffer.append(action)
		var serialized_action = action.to_dict()
		send_action.rpc_id(1, serialized_action)

@rpc("any_peer", "call_remote", "reliable")
func send_action(data: Dictionary):
	if multiplayer.get_remote_sender_id() == owner_peer_id:
		var deserialized_action: Action = Action.from_dict(data)
		if deserialized_action:
			queue_action(deserialized_action)

func gather_actions() -> Array[Action]:
	if action_buffer.size() == 0:
		return []
	
	var actions = action_buffer.duplicate()
	action_buffer.clear()
	return actions

func set_focus_node(node):
	focus_node = node
