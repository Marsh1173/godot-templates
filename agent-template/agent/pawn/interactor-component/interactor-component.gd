extends Area3D
class_name InteractorComponent

@onready var closest_to_decider: Node3D = $ClosestToDecider

var targeted_interactable_or_null: Interactable = null:
	set(new_value):
		targeted_interactable_or_null = new_value
		if MyUtils.is_authority(multiplayer):
			if new_value is Interactable:
				targeted_interactable_path_or_null = new_value.get_path()
			else:
				targeted_interactable_path_or_null = null

# NodePath | null
@export var targeted_interactable_path_or_null: NodePath = null:
	set(new_value):
		if not MyUtils.is_authority(multiplayer):
			if new_value is NodePath:
				targeted_interactable_or_null = get_tree().get_node_or_null(new_value)
			else:
				targeted_interactable_or_null = null

# Host-only
var interactables_in_range: Array[Interactable] = []

func _ready():
	if MyUtils.is_authority(multiplayer):
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D):
	if body is Interactable:
		interactables_in_range.append(interactables_in_range)

func _on_body_exited(body: Node3D):
	interactables_in_range.erase(body)
	
	if targeted_interactable_or_null == body:
		targeted_interactable_or_null = null # Maybe redo, this will trigger two changes if there's another body in range

func _process(_delta):
	if MyUtils.is_authority(multiplayer):
		var temp_targeted_interactable_or_null = targeted_interactable_or_null
		for interactable in interactables_in_range:
			if temp_targeted_interactable_or_null == null:
				temp_targeted_interactable_or_null = interactable
			elif closest_to_decider.global_position.distance_squared_to(temp_targeted_interactable_or_null.global_position) < closest_to_decider.global_position.distance_squared_to(interactable.global_position):
				temp_targeted_interactable_or_null = interactable
		
		if temp_targeted_interactable_or_null != targeted_interactable_or_null:
			targeted_interactable_or_null = temp_targeted_interactable_or_null
