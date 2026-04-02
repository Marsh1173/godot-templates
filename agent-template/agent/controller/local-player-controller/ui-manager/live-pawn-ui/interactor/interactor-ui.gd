extends Control
class_name InteractorUi

@onready var box_container: Control = $BoxContainer
@onready var label: RichTextLabel = $BoxContainer/Label

var pawn: Pawn = null

func ready_with_data(_pawn: Pawn):
	pawn = _pawn
	pawn.interactor_component.on_interactable_changed.connect(_on_targeted_interactable_change)
	_on_targeted_interactable_change(pawn.interactor_component.targeted_interactable_or_null)

func _on_targeted_interactable_change(interactable: Interactable):
	if interactable == null:
		box_container.visible = false
	else:
		box_container.visible = true
		label.text = interactable.interact_prompt

func _process(_delta):
	if pawn.interactor_component.targeted_interactable_or_null != null:
		var camera = get_viewport().get_camera_3d()
		var world_position = pawn.interactor_component.targeted_interactable_or_null.global_position
		
		# Convert 3D to 2D
		var screen_pos = camera.unproject_position(world_position)
		
		# Move a UI element to that spot
		#box_container.position.x = screen_pos.x - (box_container.size.x / 2)
		#box_container.position.y = screen_pos.y
		
		box_container.position.x = screen_pos.x + 40
		box_container.position.y = screen_pos.y - (box_container.size.y / 2)
