extends Node
class_name Stat

"""
Stat is a basic class that allows for ID-ed modifiers, and caches the value.
"""

enum AggregateMethod {
	Add,
	Multiply,
	Divide,
}

@export var aggregate_method: AggregateMethod = AggregateMethod.Add
@export var min_value: float = 0
@export var max_value: float = INF

@export var base_value: float
@export var value: float:
	set(new_value):
		var old_value: float = value
		value = new_value
		changed.emit(old_value, value)

func _ready():
	if MyUtils.is_authority(multiplayer):
		_recalc_value() # Set value

# Only called on host
signal changed(old_value: float, new_value: float)

var modifiers: Dictionary[String, float] = {}

func add_modifier(key: String, amount: float):
	modifiers.set(key, amount)
	_recalc_value()

func remove_modifier(key: String):
	modifiers.erase(key)
	_recalc_value()

func _recalc_value():
	if not MyUtils.is_authority(multiplayer):
		push_error("Tried to recalc Stat value from non-host peer")
		return
	var temp_value: float = base_value
	for modifier_key in modifiers:
		match aggregate_method:
			AggregateMethod.Add:
				temp_value = max(min_value, min(max_value, temp_value + modifiers[modifier_key]))
			AggregateMethod.Multiply:
				temp_value = max(min_value, min(max_value, temp_value * modifiers[modifier_key]))
			AggregateMethod.Divide:
				temp_value = max(min_value, min(max_value, temp_value / modifiers[modifier_key]))
	value = temp_value # Buffer in a temp value so value's setter is only called once
