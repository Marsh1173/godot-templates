extends RefCounted
class_name ItemData

enum ID {
	Wood,
	Apple,
}

@export var id: ID

func _init(_id: ID):
	id = _id

func serialize() -> Dictionary[String, Variant]:
	return {
		"id": id
	}

static func deserialize(data: Dictionary[String, Variant]) -> ItemData:
	var item_data: ItemData = ItemData.new(
		data.get("id")
	)
	return item_data
