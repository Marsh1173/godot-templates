extends Node3D

@onready var world: World = $World
const CHEST_SCENE = preload("res://agent-template/entities/chest/chest.tscn")
const BERRY_BUSH_SCENE = preload("uid://ctv0bmra5aybu")
	
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
		
		var berry_bush: Node3D = BERRY_BUSH_SCENE.instantiate()
		berry_bush.position = Vector3(8, -0.247, -7)
		world.entity_spawner.add_child(berry_bush)
