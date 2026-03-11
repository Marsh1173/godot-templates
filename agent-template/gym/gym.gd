extends Node3D

@onready var world: World = $World
	
func _ready():
	if MyUtils.is_authority(multiplayer):
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Wood), Vector3(2, 6, 3))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Apple), Vector3(1, 6, 3))
