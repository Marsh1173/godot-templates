extends MultiplayerSpawner
class_name PawnSpawner

const PAWN = preload("res://agent-template/agent/pawn/pawn.tscn")

func _ready():
	spawn_function = _custom_spawn_logic

func _custom_spawn_logic(_data) -> Pawn:
	var pawn: Pawn = PAWN.instantiate()
	return pawn
