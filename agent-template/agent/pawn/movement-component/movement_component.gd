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
@onready var multiplayer_synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

#region movement flags
@export var moving_forward: bool = false
@export var moving_backward: bool = false
@export var moving_left: bool = false
@export var moving_right: bool = false

@export var is_sprinting: bool = false
@export var is_jumping: bool = false
#endregion

#region consts
const ground_accel: float = 70
const air_accel: float = 30
#const water_accel: float = 0.7

#const water_speed_multiplier: float = 0.5
#const sprint_speed_multiplier: float = 1.2
#endregion

func _physics_process(delta: float):
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

func apply_gravity(delta: float):
	var gravity_vec = pawn.get_gravity()
	pawn.velocity += gravity_vec * delta

func apply_forced_movement():
	if pawn.is_on_floor() and is_jumping:
		pawn.velocity.y = pawn.stats_component.jump_height.get_value()

func apply_movement(delta: float):
	var accel: float = ground_accel
	var max_speed: float = pawn.stats_component.move_speed.get_value()
	
	if is_sprinting:
		max_speed *= pawn.stats_component.sprint_speed_multiplier.get_value()
	
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
