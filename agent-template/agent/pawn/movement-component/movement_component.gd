extends Node
class_name MovementComponent

"""
Architecting the movement component

RESPONSIBLE FOR
* Translates desired movement intent into velocity for Pawn
* Applying gravity
* Movement on ground or in air
* Sprint / roll / movement ability execution
* Respecting movement locks
* Emitting movement state changes (sprint, stop, airborne, etc)

NOT RESPONSIBLE FOR
* Reading input
* Deciding when to sprint, roll, move ability
* Stamina math
* Network logic
* Collision damage or combat
"""

@onready var pawn: Pawn = $".."
@onready var stamina_component: StaminaComponent = $"../StaminaComponent"

#region movement state used by host and pawn owner
var movement_vector: Vector2 = Vector2.ZERO

var is_sprinting: bool = false
var is_jumping: bool = false
#endregion

#region consts
const ground_accel: float = 70
const air_accel: float = 30
#const water_accel: float = 0.7

#const water_speed_multiplier: float = 0.5
#const sprint_speed_multiplier: float = 1.2
#endregion

#region smooth network interpolation
const IGNORE_DISTANCE = 0.5  # Less than this - do nothing.
const SNAP_DISTANCE = 2.0    # Greater than this - hard teleport.
const CORRECTION_SPEED = 10.0 # How aggressively to dissolve the error.

# This stores the vector difference between the server and the client
var position_error: Vector3 = Vector3.ZERO
#endregion

func _ready():
	stamina_component.exhausted.connect(stop_sprinting)
	pawn.action_received.connect(_on_action_received)

func _on_action_received(action: Action):
	match action.name:
		Action.Name.StartSprint:
			is_sprinting = true
		Action.Name.StopSprint:
			is_sprinting = false
		Action.Name.StartJump:
			is_jumping = true
		Action.Name.StopJump:
			is_jumping = false

func stop_sprinting():
	#if MyUtils.is_authority(multiplayer): WE NEED TO ADD A SYNCHRONIZER FOR THIS PROPERTY
	is_sprinting = false

func _physics_process(delta: float):
	if MyUtils.is_authority(multiplayer) or pawn.is_owned_by_peer():
		#1. Authority check
		#2. Death check
		#3. Apply gravity
		apply_gravity(delta)
		#4. Check hard movement locks
		#5. Check forced movement (roll, knockback)
		apply_forced_movement()
		#6. Resolve normal movement intent
		apply_movement(delta)
	
	#7. move_and_slide()
	pawn.move_and_slide()
	
	#8. Emit transitions (signals)
	if MyUtils.is_authority(multiplayer):
		sync_pos_from_host.rpc([
			pawn.global_position.x,
			pawn.global_position.y,
			pawn.global_position.z,
			pawn.velocity.x,
			pawn.velocity.y,
			pawn.velocity.z,
			pawn.global_rotation.y,
			Time.get_unix_time_from_system()
		])
	elif position_error.length_squared() > 0.001:
		var correction_step = position_error * clamp(CORRECTION_SPEED * delta, 0.0, 1.0)
		pawn.global_position += correction_step
		position_error -= correction_step
	
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_pos_from_host(data: Variant):
	var global_position = Vector3(data[0], data[1], data[2])
	var velocity = Vector3(data[3], data[4], data[5])
	var global_rotation_y = data[6]
	
	var snapshot_timestamp: float = data[7]
	var now_timestamp: float = Time.get_unix_time_from_system()
	var time_since_sync = now_timestamp - snapshot_timestamp
	
	var extrapolated_global_pos = global_position + (time_since_sync * velocity)
	
	if not pawn.is_owned_by_peer():
		pawn.global_position = extrapolated_global_pos
		pawn.velocity = velocity
		pawn.global_rotation.y = global_rotation_y
	else:
		var distance := extrapolated_global_pos.distance_to(pawn.global_position)
		if distance > SNAP_DISTANCE:
			pawn.global_position = extrapolated_global_pos
			position_error = Vector3.ZERO
		elif distance > IGNORE_DISTANCE:
			position_error = extrapolated_global_pos - pawn.global_position
		
		if velocity.distance_to(pawn.velocity) > 0.1:
			pawn.velocity = velocity

func apply_gravity(delta: float):
	var gravity_vec = pawn.get_gravity()
	pawn.velocity += gravity_vec * delta

func apply_forced_movement():
	if pawn.is_on_floor() and is_jumping:
		pawn.velocity.y = pawn.stats_component.jump_height.value

func apply_movement(delta: float):
	var accel: float = ground_accel
	var max_speed: float = pawn.stats_component.move_speed.value
	
	if is_sprinting:
		max_speed *= pawn.stats_component.sprint_speed_multiplier.value
		if MyUtils.is_authority(multiplayer):
			stamina_component.stamina -= delta * 10
	
	if !pawn.is_on_floor():
		accel = air_accel
	
	# Rotate input to face the same direction as the pawn
	var velocity_vector: Vector2 = movement_vector.rotated(-pawn.global_rotation.y)
	
	# Scale velocity to player's max speed this frame
	velocity_vector = velocity_vector.normalized() * max_speed
	
	# Flatten pawn's current velocity and move toward target velocity
	var flattened_pawn_v = Vector2(pawn.velocity.x, pawn.velocity.z)
	var final_pawn_v = flattened_pawn_v.move_toward(velocity_vector, delta * accel)
	
	pawn.velocity.x = final_pawn_v.x
	pawn.velocity.z = final_pawn_v.y
