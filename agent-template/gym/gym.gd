extends Node3D

@onready var world: World = $World
	
func _ready():
	if MyUtils.is_authority(multiplayer):
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Beer), Vector3(2, 6, 3))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Berries), Vector3(1, 6, 3))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Meat), Vector3(3, 6, 3))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Obsidian), Vector3(2, 6, 4))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Stone), Vector3(1, 6, 4))
		world.item_spawner.spawn_item(ItemData.new(ItemData.ID.Wood), Vector3(3, 6, 4))
