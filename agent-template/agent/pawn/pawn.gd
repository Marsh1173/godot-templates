extends CharacterBody3D
class_name Pawn

@onready var stats_component: StatsComponent = $StatsComponent
@onready var movement_component: MovementComponent = $MovementComponent
@onready var health_component: HealthComponent = $HealthComponent
@onready var stamina_component: StaminaComponent = $StaminaComponent
@onready var inventory_component: InventoryComponent = $InventoryComponent

var _peer_id_or_null = null

signal died()

func _ready():
	health_component.health_changed.connect(_did_health_reach_zero)

func _did_health_reach_zero(_old_value: int, new_value: int):
	if new_value == 0 and MyUtils.is_authority(multiplayer):
		died.emit()
		queue_free()

func set_peer_id_or_null(inner_peer_id_or_null):
	_peer_id_or_null = inner_peer_id_or_null

func is_owned_by_peer() -> bool:
	return multiplayer.get_unique_id() == _peer_id_or_null

func handle_action(action: Action):
	match action.name:
		Action.Name.StartMoveForward:
			movement_component.moving_forward = true
		Action.Name.StopMoveForward:
			movement_component.moving_forward = false
		Action.Name.StartMoveBackward:
			movement_component.moving_backward = true
		Action.Name.StopMoveBackward:
			movement_component.moving_backward = false
		Action.Name.StartMoveLeft:
			movement_component.moving_left = true
		Action.Name.StopMoveLeft:
			movement_component.moving_left = false
		Action.Name.StartMoveRight:
			movement_component.moving_right = true
		Action.Name.StopMoveRight:
			movement_component.moving_right = false
		Action.Name.StartSprint:
			movement_component.is_sprinting = true
		Action.Name.StopSprint:
			movement_component.is_sprinting = false
		Action.Name.StartJump:
			movement_component.is_jumping = true
		Action.Name.StopJump:
			movement_component.is_jumping = false
		Action.Name.SetViewDirection:
			global_rotation.y = action.yaw
		Action.Name.StartPrimaryAbility:
			if !MyUtils.is_authority(multiplayer):
				return

			# Damage nearest non-self pawn 4hp
			var agents = get_tree().get_nodes_in_group("Agents")
			var other_pawns: Array[Pawn] = []
			for agent in agents:
				if agent is Agent and\
					agent.pawn is Pawn and\
					self != agent.pawn:
						other_pawns.append(agent.pawn)
			
			var closest_pawn = null
			for other_pawn in other_pawns:
				if closest_pawn == null:
					closest_pawn = other_pawn
				else:
					var closest_dist = global_position.distance_squared_to(closest_pawn.global_position)
					var other_dist = global_position.distance_squared_to(other_pawn.global_position)
					if closest_dist > other_dist:
						closest_pawn = other_pawn
			if closest_pawn is Pawn:
				closest_pawn.health_component.health -= 4
		Action.Name.StopPrimaryAbility:
			pass
