extends Node
class_name Controller
	
var focus_node = null
var focus_pitch: float = 0
var focus_yaw: float = 0

var action_buffer: Array[Action] = []

func queue_action(action: Action):
	action_buffer.append(action)

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
