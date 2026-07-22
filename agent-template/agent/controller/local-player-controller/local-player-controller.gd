class_name LocalPlayerController
extends Controller

@onready var ui_manager: UiManager = $UiManager
@onready var controlled_camera: Node3D = $ControlledCamera
const view_sensitivity: float = 0.007

func set_view_direction(pitch: float, yaw: float):
	controlled_camera.rotation.x = pitch
	controlled_camera.rotation.y = yaw
	
	state_replicator.focus_pitch = pitch
	state_replicator.focus_yaw = yaw
	
func _physics_process(_delta):
	if focus_node != null:
		controlled_camera.global_position = focus_node.global_position

func set_focus_node(node):
	super(node)
	if node is Pawn:
		ui_manager.set_pawn_or_null(node)
	else:
		ui_manager.set_pawn_or_null(null)
		

func _unhandled_input(event: InputEvent):
	state_replicator.movement_vector = Input.get_vector("move-left", "move-right", "move-forward", "move-backward")

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		set_view_direction(
			max(-PI / 2, min(PI / 2, state_replicator.focus_pitch + (-event.relative.y * view_sensitivity))),
			fmod(state_replicator.focus_yaw - (event.relative.x * view_sensitivity), PI * 2),
		)
		get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				queue_action(Action.new(Action.Name.StartPrimaryAbility))
			else:
				queue_action(Action.new(Action.Name.StopPrimaryAbility))
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		if event.is_action_pressed("sprint"):
			queue_action(Action.new(Action.Name.StartSprint))
			get_viewport().set_input_as_handled()
		elif event.is_action_released("sprint"):
			queue_action(Action.new(Action.Name.StopSprint))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("jump"):
			queue_action(Action.new(Action.Name.StartJump))
			get_viewport().set_input_as_handled()
		elif event.is_action_released("jump"):
			queue_action(Action.new(Action.Name.StopJump))
			get_viewport().set_input_as_handled()
		#elif event.is_action_pressed("roll"):
			#queue_action(Action.new(Action.Name.Roll))
			#get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact"):
			if focus_node is Pawn:
				get_viewport().set_input_as_handled()
				var targeted_interactable = focus_node.interactor_component.targeted_interactable_or_null
				if targeted_interactable is Interactable:
					match targeted_interactable.contextual_id:
						Interactable.ContextualId.None:
							if MyUtils.is_authority(multiplayer):
								focus_node.interactor_component.request_interact(targeted_interactable.get_path())
							else:
								focus_node.interactor_component.request_interact.rpc_id(1, targeted_interactable.get_path())
						_:
							assert(false, "Interactable contextual ID not implemented yet")
		elif event.is_action_released("interact"):
			if focus_node is Pawn:
				get_viewport().set_input_as_handled()
				if MyUtils.is_authority(multiplayer):
					focus_node.interactor_component.request_stop_interact()
				else:
					focus_node.interactor_component.request_stop_interact.rpc_id(1)
