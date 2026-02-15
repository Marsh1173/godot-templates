class_name LocalPlayerController
extends Controller

@onready var controlled_camera: Node3D = $ControlledCamera
const view_sensitivity: float = 0.0075

func set_view_direction(pitch: float, yaw: float):
	super.set_view_direction(pitch, yaw)
	controlled_camera.rotation.x = pitch
	controlled_camera.rotation.y = yaw
	
func _physics_process(_delta):
	if focus_node is Node3D:
		controlled_camera.global_position = focus_node.global_position

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		set_view_direction(
			max(-PI / 2, min(PI / 2, focus_pitch + (-event.relative.y * view_sensitivity))),
			fmod(focus_yaw - (event.relative.x * view_sensitivity), PI * 2),
		)
		
		var action = Action.new(Action.Name.SetViewDirection)
		action.pitch = focus_pitch
		action.yaw = focus_yaw
		queue_action(action)
		get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseButton and event.is_pressed():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
	elif event is InputEventKey:
		if event.is_action_pressed("move-forward"):
			queue_action(Action.new(Action.Name.StartMoveForward))
			get_viewport().set_input_as_handled()
		elif event.is_action_released("move-forward"):
			queue_action(Action.new(Action.Name.StopMoveForward))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move-backward"):
			queue_action(Action.new(Action.Name.StartMoveBackward))
			get_viewport().set_input_as_handled()
		elif event.is_action_released("move-backward"):
			queue_action(Action.new(Action.Name.StopMoveBackward))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move-left"):
			queue_action(Action.new(Action.Name.StartMoveLeft))
			get_viewport().set_input_as_handled()
		elif event.is_action_released("move-left"):
			queue_action(Action.new(Action.Name.StopMoveLeft))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move-right"):
			queue_action(Action.new(Action.Name.StartMoveRight))
			get_viewport().set_input_as_handled()
		elif event.is_action_released("move-right"):
			queue_action(Action.new(Action.Name.StopMoveRight))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("sprint"):
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
		elif event.is_action_pressed("roll"):
			queue_action(Action.new(Action.Name.Roll))
			get_viewport().set_input_as_handled()
