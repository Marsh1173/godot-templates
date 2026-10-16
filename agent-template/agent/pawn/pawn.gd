extends CharacterBody3D
class_name Pawn

@onready var stats_component: StatsComponent = $StatsComponent
@onready var movement_component: MovementComponent = $MovementComponent
@onready var health_component: HealthComponent = $HealthComponent
@onready var stamina_component: StaminaComponent = $StaminaComponent
@onready var inventory_component: InventoryComponent = $InventoryComponent
@onready var interactor_component: InteractorComponent = $InteractorComponent

var peer_id_or_null = null

signal died()
signal action_received(action: Action)

func _ready():
	health_component.health_changed.connect(_did_health_reach_zero)
	
	if MyUtils.is_authority(multiplayer):
		inventory_component.ready_with_data(stats_component.inventory_size.value)
		
		stats_component.inventory_size.changed.connect(inventory_component.change_inventory_size)
		died.connect(inventory_component.throw_out_all_items)

func _did_health_reach_zero(old_value: int, new_value: int):
	if new_value == 0 and old_value != 0 and MyUtils.is_authority(multiplayer):
		died.emit()
		queue_free()

func set_peer_id_or_null(_peer_id_or_null):
	peer_id_or_null = _peer_id_or_null
	interactor_component.set_peer_id_or_null(peer_id_or_null)

func is_owned_by_peer() -> bool:
	if peer_id_or_null == null:
		return MyUtils.is_authority(multiplayer)
	else:
		return multiplayer.get_unique_id() == peer_id_or_null

func set_view_direction(_pitch: float, yaw: float):
	global_rotation.y = yaw
	# Someday handle pitch too

var roll_cooldown_timer: float = 0.0
const ROLL_COOLDOWN: float = 0.3
const ROLL_SPEED: float = 14.0
const ROLL_DURATION: float = 0.35
const ROLL_STAMINA_COST: float = 20.0

var explode_cooldown_timer: float = 0.0
const EXPLODE_COOLDOWN: float = 0.5
const EXPLODE_FORCE: float = 20.0
const EXPLODE_RANGE: float = 3.0

func _physics_process(delta: float):
	if MyUtils.is_authority(multiplayer) and roll_cooldown_timer > 0.0:
		roll_cooldown_timer -= delta
	if MyUtils.is_authority(multiplayer) and explode_cooldown_timer > 0.0:
		explode_cooldown_timer -= delta

func handle_action(action: Action):
	action_received.emit(action)
	
	if not MyUtils.is_authority(multiplayer):
		return

	if action.name == Action.Name.Roll:
		execute_roll()
	if action.name == Action.Name.Explode:
		execute_explode()
	elif action.name == Action.Name.StartPrimaryAbility:
		# Damage nearest non-self pawn 4hp
		var agents = get_tree().get_nodes_in_group("Agents")
		var other_pawns: Array[Pawn] = []
		for agent in agents:
			if agent is Agent and agent.pawn is Pawn and self != agent.pawn:
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

func execute_roll():
	if movement_component.is_forced_movement or roll_cooldown_timer > 0.0:
		return
	if stamina_component.stamina < ROLL_STAMINA_COST:
		return

	stamina_component.stamina -= ROLL_STAMINA_COST
	roll_cooldown_timer = ROLL_COOLDOWN

	# Direction: current move input rotated by pawn yaw, or pawn forward if stationary
	var roll_dir: Vector3
	if movement_component.movement_vector.length_squared() > 0.01:
		var rotated = movement_component.movement_vector.normalized().rotated(-global_rotation.y)
		roll_dir = Vector3(rotated.x, 0.0, rotated.y).normalized()
	else:
		var fwd = -global_transform.basis.z.normalized()
		fwd.y = 0.0
		roll_dir = Vector3.FORWARD if fwd.length_squared() < 0.01 else fwd.normalized()

	movement_component.start_forced_movement(roll_dir * ROLL_SPEED, ROLL_DURATION)

func execute_explode():
	if explode_cooldown_timer > 0.0:
		return

	explode_cooldown_timer = EXPLODE_COOLDOWN

	# Damage nearest non-self pawn 4hp
	var agents = get_tree().get_nodes_in_group("Agents")
	var other_pawns: Array[Pawn] = []
	for agent in agents:
		if agent is Agent and agent.pawn is Pawn and self != agent.pawn:
			other_pawns.append(agent.pawn)
	
	for other_pawn in other_pawns:
		if global_position.distance_to(other_pawn.global_position) < EXPLODE_RANGE:
			var direction: Vector3 = global_position.direction_to(other_pawn.global_position) + (Vector3.UP * 0.2)
			other_pawn.velocity = direction * EXPLODE_FORCE
