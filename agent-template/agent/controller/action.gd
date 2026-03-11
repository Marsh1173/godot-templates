class_name Action
extends RefCounted

enum Name {
	# Movement actions
	StartMoveForward,
	StopMoveForward,
	StartMoveBackward,
	StopMoveBackward,
	StartMoveLeft,
	StopMoveLeft,
	StartMoveRight,
	StopMoveRight,
	StartJump,
	StopJump,
	StartSprint,
	StopSprint,
	# Ability actions
	Roll,
	StartPrimaryAbility,
	StopPrimaryAbility,
	# Other
	SetViewDirection,
}

@export var name: Name

@export var pitch: float = 0
@export var yaw: float = 0

func _init(_name: Name = Name.StartJump):
	name = _name

# Some actions are applied locally instantly for snappy responsiveness, e.g. jumping
func is_locally_applied_action() -> bool:
	return name == Name.StartMoveForward or\
		name == Name.StopMoveForward or\
		name == Name.StartMoveBackward or\
		name == Name.StopMoveBackward or\
		name == Name.StartMoveLeft or\
		name == Name.StopMoveLeft or\
		name == Name.StartMoveRight or\
		name == Name.StopMoveRight or\
		name == Name.StartJump or\
		name == Name.StopJump or\
		name == Name.StartSprint or\
		name == Name.StopSprint or\
		name == Name.SetViewDirection

static var _serialization_config: Dictionary[String, int] = {
	"name": TYPE_INT,
	"pitch": TYPE_FLOAT,
	"yaw": TYPE_FLOAT,
}

static var _serialization_key = Serialization.register("Action", _serialization_config)

static func from_json(json_string: String) -> Action:
	return Serialization.get_config(_serialization_key)["from_json"].call(json_string, Action.new)
func to_json() -> String:
	return Serialization.get_config(_serialization_key)["to_json"].call(self)
