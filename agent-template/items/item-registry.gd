class_name ItemRegistry

class ItemDefinition:
	var id: ItemData.ID
	var name: String
	
	func _init(_id: ItemData.ID, _name: String):
		id = _id
		name = _name

static func get_by_id(id: ItemData.ID) -> ItemDefinition:
	return item_registry.get(id)

static var item_registry: Dictionary[ItemData.ID, ItemDefinition] = {
	ItemData.ID.Wood: ItemDefinition.new(
		ItemData.ID.Wood,
		"Wood",
	),
	ItemData.ID.Apple: ItemDefinition.new(
		ItemData.ID.Apple,
		"Apple",
	),
}
