class_name Action
extends RefCounted

enum Name {
	StartJump,
	StopJump,
	StartSprint,
	StopSprint,
	Roll,
	StartPrimaryAbility,
	StopPrimaryAbility,
}

@export var name: Name

func _init(_name: Name = Name.StartJump):
	name = _name

# Some actions are applied locally instantly for snappy responsiveness, e.g. jumping
func is_locally_applied_action() -> bool:
	return name == Name.StartJump or\
		name == Name.StopJump or\
		name == Name.StartSprint or\
		name == Name.StopSprint

static var _serialization_config: Dictionary[String, int] = {
	"name": TYPE_INT,
}

static var _serialization_key = Serialization.register("Action", _serialization_config)

static func from_dict(data: Dictionary) -> Action:
	return Serialization.get_config(_serialization_key)["from_dict"].call(data, Action.new)
func to_dict() -> Dictionary:
	return Serialization.get_config(_serialization_key)["to_dict"].call(self)
