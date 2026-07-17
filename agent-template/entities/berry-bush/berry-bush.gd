extends Node3D

@onready var interactable: Interactable = $Interactable

func _ready():
	interactable.on_attempt_interact.connect(_on_attempt_interact)

#region interaction logic
# Only called on host
func _on_attempt_interact(_interactor: InteractorComponent):
	var world: World = MyUtils.get_world_or_throw(self)
	world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Berries), global_position + Vector3.UP * 2)
#endregion
