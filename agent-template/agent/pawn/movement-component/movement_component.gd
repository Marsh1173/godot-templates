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

#region movement flags used by host and pawn owner
var moving_forward: bool = false
var moving_backward: bool = false
var moving_left: bool = false
var moving_right: bool = false

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

func _ready():
	stamina_component.exhausted.connect(stop_sprinting)

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
			pawn.global_rotation.y
		])
	
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_pos_from_host(data: Variant):
	var global_position = Vector3(data[0], data[1], data[2])
	var velocity = Vector3(data[3], data[4], data[5])
	var global_rotation_y = data[6]
	
	if not pawn.is_owned_by_peer():
		pawn.global_position = global_position
		pawn.velocity = velocity
		pawn.global_rotation.y = global_rotation_y
	else:
		# Only set values if peer's values differ too much from host's values
		if global_position.distance_to(pawn.global_position) > 0.3:
			pawn.global_position = global_position
		if velocity.distance_to(pawn.velocity) > 0.3:
			pawn.velocity = velocity
		if abs(angle_difference(global_rotation_y, pawn.global_rotation.y)) > 0.3:
			pawn.global_rotation.y = global_rotation_y

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
	
	var velocity_vector: Vector2 = Vector2.ZERO
	
	if moving_backward and !moving_forward:
		velocity_vector.y += 1
	if moving_forward and !moving_backward:
		velocity_vector.y -= 1
	
	if moving_right and !moving_left:
		velocity_vector.x += 1
	if moving_left and !moving_right:
		velocity_vector.x -= 1
	
	# Rotate to face same direction as pawn
	velocity_vector = velocity_vector.rotated(-pawn.global_rotation.y)
	
	# Scale velocity to player's max speed this frame
	velocity_vector = velocity_vector.normalized() * max_speed
	
	# Flatten pawn's current velocity and move toward target velocity
	var flattened_pawn_v = Vector2(pawn.velocity.x, pawn.velocity.z)
	var final_pawn_v = flattened_pawn_v.move_toward(velocity_vector, delta * accel)
	
	pawn.velocity.x = final_pawn_v.x
	pawn.velocity.z = final_pawn_v.y
