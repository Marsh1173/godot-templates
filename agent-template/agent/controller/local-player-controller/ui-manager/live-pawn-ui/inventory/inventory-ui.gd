extends Control
class_name InventoryUi

const ITEM_UI = preload("uid://6pv5wlewdnn8")

@onready var h_flow_container: HFlowContainer = $BlurPanel/HFlowContainer
@onready var blur_panel: Control = $BlurPanel
var pawn: Pawn = null

func _ready():
	toggle_menu(false)

func ready_with_data(_pawn: Pawn):
	pawn = _pawn
	pawn.inventory_component.on_inventory_change.connect(_on_inventory_change)

func toggle_menu(open: bool):
	blur_panel.visible = open
	if open:
		WindowManager.register_window("InGameInventory")
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		WindowManager.unregister_window("InGameInventory")
		mouse_filter = Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.keycode == KEY_E and event.is_pressed():
		toggle_menu(!blur_panel.visible)
		get_viewport().set_input_as_handled()

func _on_inventory_change(inventory: Array[Variant]):
	# Add / remove UI components if necessary
	if inventory.size() > h_flow_container.get_children().size():
		for i in range(inventory.size() - h_flow_container.get_children().size()):
			var item_ui = ITEM_UI.instantiate()
			h_flow_container.add_child(item_ui)
		#_resize_inventory_ui(inventory.size())
	elif inventory.size() < h_flow_container.get_children().size():
		for i in range(inventory.size(), h_flow_container.get_children().size()):
			# Maybe cause issues down the line? queue_free isn't instant
			h_flow_container.get_child(i).queue_free()
		#_resize_inventory_ui(inventory.size())
	
	for i in range(inventory.size()):
		var item_ui: ItemUi = h_flow_container.get_child(i)
		item_ui.set_item(inventory[i])
	
#func _resize_inventory_ui(inventory_size: int):
	#const gap: int = 4
	#const slot_height: int = 40
	
	#blur_panel.size.
