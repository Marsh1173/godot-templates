extends Node
class_name StaminaComponent

@onready var stats_component: StatsComponent = $"../StatsComponent"

signal exhausted()
signal stamina_changed(old_value: float, new_value: float)

@export var stamina: float = 0:
	set(new_value):
		var old_value = stamina
		stamina = clamp(new_value, 0, stats_component.max_stamina.value)
		stamina_changed.emit(old_value, stamina)
		
		if old_value >= new_value:
			_time_without_regen_interruption = 0
		
		if stamina == 0:
			exhausted.emit()

func _ready():
	if MyUtils.is_authority(multiplayer):
		stamina = stats_component.max_stamina.value
		stats_component.max_stamina.changed.connect(_on_max_stamina_change)

func _on_max_stamina_change(_old_value: float, new_value: float):
	if new_value < stamina:
		stamina = new_value

#region stamina regeneration
var _time_without_regen_interruption: float = 0

func _process(delta):
	_time_without_regen_interruption += delta
	if MyUtils.is_authority(multiplayer):
		if _time_without_regen_interruption > stats_component.stamina_regen_interrupt_length.value:
			stamina += stats_component.stamina_regen_rate.value * delta
#endregion
