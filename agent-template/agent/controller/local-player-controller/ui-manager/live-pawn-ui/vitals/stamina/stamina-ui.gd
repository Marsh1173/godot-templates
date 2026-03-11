extends Control
class_name StaminaUi

@onready var bar: ProgressBar = $Bar
var pawn: Pawn = null

func ready_with_data(_pawn: Pawn):
	pawn = _pawn
	
	pawn.stats_component.max_stamina.changed.connect(max_stamina_changed)
	max_stamina_changed(0, pawn.stats_component.max_stamina.value)
	pawn.stamina_component.stamina_changed.connect(stamina_changed)
	stamina_changed(0, pawn.stamina_component.stamina)

func max_stamina_changed(_old_value: float, new_value: float):
	bar.max_value = new_value
	
	# If both change at the same time, sometimes the stamina is updated before
	# the max stamina lets it
	bar.value = pawn.stamina_component.stamina

func stamina_changed(_old_value: float, new_value: float):
	bar.value = new_value
