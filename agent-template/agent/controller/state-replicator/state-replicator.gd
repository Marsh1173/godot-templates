extends Node
class_name ControllerStateReplicator

@export var focus_pitch: float = 0
@export var focus_yaw: float = 0

@export var movement_vector: Vector2 = Vector2.ZERO

@onready var controller: Controller = $".."

func _process(_delta):
	if controller.focus_node is Pawn:
		controller.focus_node.set_view_direction(focus_pitch, focus_yaw)

func _physics_process(_delta):
	if controller.focus_node is Pawn:
		controller.focus_node.movement_component.movement_vector = movement_vector
