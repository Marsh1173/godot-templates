extends Control
class_name HealthUi

@onready var bar: ProgressBar = $Bar
var pawn: Pawn = null

func ready_with_data(_pawn: Pawn):
	pawn = _pawn
	
	pawn.stats_component.max_health.changed.connect(max_health_changed)
	max_health_changed(0, pawn.stats_component.max_health.value)
	pawn.health_component.health_changed.connect(health_changed)
	health_changed(0, pawn.health_component.health)

func max_health_changed(_old_value: float, new_value: float):
	bar.max_value = new_value
	
	# If both change at the same time, sometimes the health is updated before
	# the max health lets it
	bar.value = pawn.health_component.health

func health_changed(_old_value: int, new_value: int):
	bar.value = new_value
