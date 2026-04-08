extends Panel
class_name ItemUi

@onready var texture_rect: TextureRect = $TextureRect

static var item_icons = ItemRegistry.item_registry.keys().reduce(func(accum, key):
	accum[key] = load(ItemRegistry.item_registry[key].get_icon_path())
	return accum
, {})

var item_data: ItemData = null

func set_item(item_data_or_null: ItemData):
	item_data = item_data_or_null
	if item_data_or_null == null:
		texture_rect.set_texture(null)
	else:
		texture_rect.set_texture(ItemUi.item_icons[item_data_or_null.id])

#region drag and drop
func _get_drag_data(_at_position:Vector2)->Variant:
	if item_data == null:
		return null
	
	var offset: Vector2 = -self.custom_minimum_size / 2
	
	var control: Control = Control.new()
	var preview: TextureRect = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	control.add_child(preview)
	preview.texture = ItemUi.item_icons[item_data.id]
	
	preview.position = offset
	preview.custom_minimum_size = self.custom_minimum_size
	set_drag_preview(control)
	return item_data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if !data is ItemData: return false
	print("Checking?")
	return true
	#var drag_data := data as ItemDrag
	## Check if the item can fit in the inventory at this position
	#return !inventory.intersects_at(_drag_data.item, at_position)

func _drop_data(_at_position:Vector2, data:Variant)->void:
	if !data is ItemData: return
	print("DROPPED")
	#var drag_data := data as ItemDrag
#
	#drag_data.destination = self
	#if drag_data.source: drag_data.source.remove_item(drag_data.item)
#
	#inventory.add_item_at(drag_data.item, at_position)
#endregion

#func _get_drag_data(at_position):
	#print("Dragging?")
	## 1. Create a visual preview (the icon following the mouse)
	#var preview = TextureRect.new()
	#preview.texture = texture
	#preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	#preview.custom_minimum_size = Vector2(64, 64)
	#preview.modulate.a = 0.5 # Make it semi-transparent
	##set_drag_preview(preview)
	#
	## 2. Return the data being dragged
	#return item_data


#func _get_drag_data(at_position:Vector2)->Variant:
	#var item := inventory.item_at(at_position)
	#if item == null: return null
#
	#var drag_data = ItemDrag.new(self, item, _create_item_preview(item))
	#set_drag_preview(drag_data.preview)
#
	#return drag_data
#
#func _can_drop_data(at_position:Vector2, data:Variant)->bool:
	#if !data is ItemDrag: return false
	#var drag_data := data as ItemDrag
	## Check if the item can fit in the inventory at this position
	#return !inventory.intersects_at(drag_data.item, at_position)
#
#func _drop_data(at_position:Vector2, data:Variant)->void:
	#if !data is ItemDrag: return
	#var drag_data := data as ItemDrag
#
	#drag_data.destination = self
	#if drag_data.source: drag_data.source.remove_item(drag_data.item)
#
	#inventory.add_item_at(drag_data.item, at_position)
