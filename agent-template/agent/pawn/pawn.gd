extends CharacterBody3D
class_name Pawn

@onready var movement_component: MovementComponent = $MovementComponent
@onready var stats_component: StatsComponent = $StatsComponent

var is_authority: bool = false

func _ready():
	is_authority = MyNetwork.is_authority(multiplayer)

func handle_action(action: Action):
	match action.name:
		Action.Name.StartMoveForward:
			movement_component.moving_forward = true
		Action.Name.StopMoveForward:
			movement_component.moving_forward = false
		Action.Name.StartMoveBackward:
			movement_component.moving_backward = true
		Action.Name.StopMoveBackward:
			movement_component.moving_backward = false
		Action.Name.StartMoveLeft:
			movement_component.moving_left = true
		Action.Name.StopMoveLeft:
			movement_component.moving_left = false
		Action.Name.StartMoveRight:
			movement_component.moving_right = true
		Action.Name.StopMoveRight:
			movement_component.moving_right = false
		Action.Name.StartSprint:
			movement_component.is_sprinting = true
		Action.Name.StopSprint:
			movement_component.is_sprinting = false
		Action.Name.StartJump:
			movement_component.is_jumping = true
		Action.Name.StopJump:
			movement_component.is_jumping = false
		Action.Name.SetViewDirection:
			global_rotation.y = action.yaw
