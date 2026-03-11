extends TextureRect
class_name ItemUi

const ICON = preload("uid://ct55jkeh3k533")

func set_item(item_data_or_null: ItemData):
	if item_data_or_null == null:
		set_texture(null)
	else:
		set_texture(ICON)
