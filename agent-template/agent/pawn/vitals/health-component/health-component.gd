extends Node
class_name HealthComponent

@onready var stats_component: StatsComponent = $"../StatsComponent"

signal health_changed(old_value: int, new_value: int)

@export var health: int = 0:
	set(new_value):
		var old_value: int = health
		health = clamp(new_value, 0, stats_component.max_health.value)
		health_changed.emit(old_value, health)

func _ready():
	if (MyUtils.is_authority(multiplayer)):
		health = round(stats_component.max_health.value) # float to int
		stats_component.max_health.changed.connect(_on_max_health_change)

func _on_max_health_change(_old_value: float, new_value: float):
	if new_value < health:
		health = round(new_value) # float to int
