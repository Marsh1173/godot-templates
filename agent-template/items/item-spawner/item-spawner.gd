extends MultiplayerSpawner
class_name ItemSpawner

const DROPPED_ITEM = preload("uid://dlqw03cxv7cxb")

func _ready():
	spawn_function = _custom_spawn_logic

func spawn_item(item_data: ItemData, pos: Vector3):
	var data = [
		item_data.serialize(),
		pos,
		randf_range(0, TAU),
	]
	spawn(data)

func spawn_item_with_throw_angle(item_data: ItemData, pos: Vector3, throw_angle_or_null: float):
	var data = [
		item_data.serialize(),
		pos,
		throw_angle_or_null,
	]
	spawn(data)
	
func _custom_spawn_logic(data) -> DroppedItem:
	var item_data: ItemData = ItemData.deserialize(data[0])
	var pos: Vector3 = data[1]
	var throw_angle_or_null: float = data[2]
	
	var dropped_item: DroppedItem = DROPPED_ITEM.instantiate().with_data(item_data, pos, throw_angle_or_null)
	return dropped_item
