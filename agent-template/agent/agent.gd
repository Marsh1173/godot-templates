class_name Agent
extends Node

@onready var pawn_spawner: PawnSpawner = $PawnSpawner

const local_ai_controller_scene = preload("res://agent-template/agent/controller/local-ai-controller/local-ai-controller.tscn")
const local_player_controller_scene = preload("res://agent-template/agent/controller/local-player-controller/local-player-controller.tscn")
const remote_controller_scene = preload("res://agent-template/agent/controller/remote-controller/remote-controller.tscn")

var pawn = null
var controller: Controller

var agent_id: int = -1
var agent_name: String = ''
var peer_id_or_null = null

# Called when instantiating the scene
func with_data(_agent_id: int, _agent_name: String, _peer_id_or_null):
	agent_id = _agent_id
	agent_name = _agent_name
	peer_id_or_null = _peer_id_or_null
	return self

func _ready():
	if peer_id_or_null == multiplayer.get_unique_id():
		controller = local_player_controller_scene.instantiate().with_data(peer_id_or_null);
	elif peer_id_or_null == null and MyNetwork.is_authority(multiplayer):
		controller = local_ai_controller_scene.instantiate().with_data(1);
	else:
		var owner_peer_id = 1 if peer_id_or_null == null else peer_id_or_null
		controller = remote_controller_scene.instantiate().with_data(owner_peer_id);
	
	controller.name = "Controller" # Force identical name for cross-network node traversal
	add_child(controller, true)
	if peer_id_or_null != null:
		controller.set_multiplayer_authority(peer_id_or_null, true)
	
	pawn_spawner.child_entered_tree.connect(_on_pawn_spawn)
	pawn_spawner.child_exiting_tree.connect(_on_pawn_despawn)

func _on_pawn_spawn(_pawn: Pawn):
	controller.set_focus_node(_pawn)
	pawn = _pawn

func _on_pawn_despawn():
	controller.set_focus_node(null)
	pawn = null

func _process(_delta):
	var controller_actions: Array[Action] = controller.gather_actions()
	
	for action in controller_actions:
		if pawn is Pawn:
			pawn.handle_action(action)
