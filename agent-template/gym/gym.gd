extends Node3D

@onready var world: World = $World
var CHEST_SCENE = preload("res://agent-template/entities/chest/chest.tscn")
	
func _ready():
	if MyUtils.is_authority(multiplayer):
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Beer), Vector3(2, 6, 3))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Berries), Vector3(1, 6, 3))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Meat), Vector3(3, 6, 3))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Obsidian), Vector3(2, 6, 4))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Stone), Vector3(1, 6, 4))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Wood), Vector3(3, 6, 4))
		
		var chest: Node3D = CHEST_SCENE.instantiate()
		chest.position = Vector3(4, 0, 4)
		chest.rotation.y = PI / 3
		world.entity_spawner.add_child(chest)
