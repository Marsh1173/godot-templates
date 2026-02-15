extends Node
class_name StatsComponent

"""
Stat is a basic class that allows for ID-ed modifiers, and caches the value.
"""
class Stat:
	var aggregate_func: Callable
	var base_value: float
	var value: float
	
	signal changed(old_value: float, new_value: float)
	
	var modifiers: Dictionary[String, float] = {}
	func _init(_base_value: float, _aggregate_func: Callable):
		base_value = _base_value
		value = _base_value
		aggregate_func = _aggregate_func
	
	func get_value() -> float:
		return value
	
	func add_modifier(key: String, amount: float):
		modifiers.set(key, amount)
		_recalc_value()
	
	func remove_modifier(key: String):
		modifiers.erase(key)
		_recalc_value()
	
	func _recalc_value():
		var old_value = value
		value = base_value
		for modifier_key in modifiers:
			value = aggregate_func.call(value, modifiers[modifier_key])
		changed.emit(old_value, value)

var move_speed: Stat = Stat.new(
	3.5,
	func (value: float, modifier: float): return max(0, value * modifier)
)

var max_health: Stat = Stat.new(
	20,
	func (value: float, modifier: float): return max(0, value + modifier)
)

var jump_height: Stat = Stat.new(
	7.5,
	func (value: float, modifier: float): return max(0, value * modifier)
)

var sprint_speed_multiplier: Stat = Stat.new(
	1.6,
	func (value: float, modifier: float): return max(0, value + modifier)
)
