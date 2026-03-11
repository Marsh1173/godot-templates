extends Control
class_name LivePawnUi

@onready var health_ui: HealthUi = $VBoxContainer/HealthUi
@onready var stamina_ui: StaminaUi = $VBoxContainer/StaminaUi
@onready var inventory_ui: InventoryUi = $InventoryUi

var pawn: Pawn

func with_data(_pawn: Pawn):
	pawn = _pawn
	return self

func _ready():
	health_ui.ready_with_data(pawn)
	stamina_ui.ready_with_data(pawn)
	inventory_ui.ready_with_data(pawn)
