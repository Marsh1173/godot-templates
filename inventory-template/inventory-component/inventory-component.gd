extends Node3D
class_name InventoryComponent

signal on_inventory_change(inventory: Array[Variant])

#Currently only called on host :(
signal on_item_add(item: ItemData)

func _serialize_item_data_or_null(item):
	if item == null:
		return null
	else:
		return item.serialize()
func _deserialize_item_data_or_null(item):
	if item == null:
		return null
	else:
		return ItemData.deserialize(item)

# : Array[null | serialized ItemData]
@export var serialized_inventory: Array[Variant] = []:
	set(new_value):
		serialized_inventory = new_value
		if !MyUtils.is_authority(multiplayer):
			inventory = new_value.map(_deserialize_item_data_or_null)

# : Array[null | ItemData]
var inventory: Array[Variant] = []:
	set(new_value):
		inventory = new_value
		if MyUtils.is_authority(multiplayer):
			serialized_inventory = new_value.map(_serialize_item_data_or_null)
		on_inventory_change.emit(inventory)

func ready_with_data(inventory_size: float):
	if MyUtils.is_authority(multiplayer):
		change_inventory_size(0, 0) # As host, clear it first
		change_inventory_size(0, inventory_size)

# Only called on host
func change_inventory_size(_old_size_f: float, new_size_f: float):
	var new_size: int = round(new_size_f)
	if new_size == inventory.size():
		# No size change
		return
	elif new_size > inventory.size():
		# Inventory expanding
		for i in range(new_size - inventory.size()):
			inventory.append(null)
		inventory = inventory.duplicate() # Trigger network sync
	else:
		# Inventory shrinking
		var leftover_items: Array = inventory.slice(new_size, inventory.size())
		var temp_inventory: Array = inventory.slice(0, new_size)
		var world: World = MyUtils.get_world_or_throw(self)
		
		for item in leftover_items:
			if item != null:
				var index = temp_inventory.find(null)
				if index == -1:
					world.item_spawner.spawn_item(item, global_position)
				else:
					temp_inventory.set(index, item)
		inventory = temp_inventory # Trigger network sync

func has_space_in_inventory() -> bool:
	return inventory.has(null)

# Attempts to put the item in the provided index, then first available space if any.
# Only called on host. Throws error if no space.
func add_item(item_data: ItemData, index: int = -1):
	# Get valid index
	if index == -1 or index >= inventory.size() or inventory[index] == null:
		index = inventory.find(null)
	
	if index == -1:
		# Still couldn't find any valid inventory spots
		assert(false, "Tried to insert into a full inventory")
		return
	
	# Apply
	inventory.set(index, item_data)
	inventory = inventory.duplicate() # Trigger network sync
	on_item_add.emit(item_data)

# Only called on host
func throw_out_all_items():
	var world: World = MyUtils.get_world_or_throw(self)
	for item in inventory:
		if item is ItemData:
			world.item_spawner.spawn_item(item, global_position)
	inventory = []
