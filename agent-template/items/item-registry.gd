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
	ItemData.ID.Beer: ItemDefinition.new(
		ItemData.ID.Beer,
		"Beer",
	),
	ItemData.ID.Berries: ItemDefinition.new(
		ItemData.ID.Berries,
		"Berries",
	),
	ItemData.ID.Meat: ItemDefinition.new(
		ItemData.ID.Meat,
		"Meat",
	),
	ItemData.ID.Obsidian: ItemDefinition.new(
		ItemData.ID.Obsidian,
		"Obsidian",
	),
	ItemData.ID.Stone: ItemDefinition.new(
		ItemData.ID.Stone,
		"Stone",
	),
	ItemData.ID.Wood: ItemDefinition.new(
		ItemData.ID.Wood,
		"Wood",
	),
}
