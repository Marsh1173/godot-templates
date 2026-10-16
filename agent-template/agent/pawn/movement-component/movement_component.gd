extends Node
class_name MovementComponent

"""
Pure Physics & Reconciliation Movement Engine

Responsibilities:
1. Physics: Applies gravity, jump velocity, ground acceleration, air control, and move_and_slide.
2. Prediction: Predicts WASD movement and jump for the local client.
3. Forced Movement: Generic API for server-authoritative impulses (Roll, TNT, Knockback).
   Suspends client prediction while active to prevent fighting/jitter.
4. Reconciliation: Buffers historical predicted ticks and reconciles via rollback & replay
   when server snapshots disagree beyond RECONCILIATION_THRESHOLD.
5. Ingestion: Consumes client input from LocalPlayerController or network jitter buffer.
"""

@onready var pawn: Pawn = $".."
@onready var stamina_component: StaminaComponent = $"../StaminaComponent"

# Movement input & state
var movement_vector: Vector2 = Vector2.ZERO
var is_jumping: bool = false
var is_sprinting: bool = false
var want_sprint: bool = false

# Generic forced movement (Roll, TNT, Knockback, Teleport)
var is_forced_movement: bool = false
var forced_movement_timer: float = 0.0
var forced_movement_total_duration: float = 0.0
var forced_velocity: Vector3 = Vector3.ZERO

# Physics constants
const ground_accel: float = 70.0
const air_accel: float = 30.0

# Network & reconciliation constants
const RECONCILIATION_THRESHOLD: float = 0.20 # 20cm divergence threshold
const MAX_HISTORY: int = 120 # ~2 seconds at 60Hz
const JITTER_BUFFER_TARGET: int = 2 # 2 frames cushion on server

var current_input_id: int = 0
var input_history: Array[Dictionary] = []

# Server-side input queue & tracking
var server_input_queue: Array[Dictionary] = []
var last_processed_input_id: int = 0

func _ready():
	stamina_component.exhausted.connect(stop_sprinting)
	pawn.action_received.connect(_on_action_received)

func stop_sprinting():
	want_sprint = false
	is_sprinting = false

func _on_action_received(action: Action):
	if not MyUtils.is_authority(multiplayer):
		return
	match action.name:
		Action.Name.StartSprint:
			want_sprint = true
		Action.Name.StopSprint:
			want_sprint = false

## Generic API for Server-Authoritative Forced Movement (Roll, TNT, Knockback)
func start_forced_movement(initial_velocity: Vector3, duration: float):
	if not MyUtils.is_authority(multiplayer):
		return
	is_forced_movement = true
	forced_velocity = initial_velocity
	forced_movement_timer = duration
	forced_movement_total_duration = duration

func is_local_human() -> bool:
	return pawn.peer_id_or_null != null and pawn.is_owned_by_peer()

## Ingests input and packages into a sequence-tagged packet
func poll_input_packet() -> Dictionary:
	current_input_id += 1
	var input_vector = Vector2.ZERO
	var jump = false

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input_vector = Input.get_vector("move-left", "move-right", "move-forward", "move-backward")
		jump = Input.is_action_pressed("jump")

	return {
		"id": current_input_id,
		"vector": input_vector,
		"yaw": pawn.global_rotation.y,
		"jump": jump
	}

## Unified single physics simulation tick for standard WASD + Jump
func simulate_step(input: Dictionary, delta: float):
	pawn.global_rotation.y = input.yaw
	movement_vector = input.vector
	is_jumping = input.jump

	apply_gravity(delta)
	apply_jump()
	apply_movement(delta)
	pawn.move_and_slide()

func _physics_process(delta: float):
	if MyUtils.is_authority(multiplayer):
		# Server-authoritative sprint & stamina deduction
		if want_sprint and pawn.stamina_component and pawn.stamina_component.stamina > 0.0:
			is_sprinting = true
			pawn.stamina_component.stamina -= delta * 10.0
		else:
			is_sprinting = false

		var should_broadcast = false

		# 1. Handle Forced Movement (Roll, TNT, Knockback)
		if is_forced_movement:
			forced_movement_timer -= delta
			if forced_movement_timer <= 0.0:
				is_forced_movement = false
				forced_movement_timer = 0.0
				forced_movement_total_duration = 0.0
				pawn.velocity.x = 0.0
				pawn.velocity.z = 0.0
			else:
				var progress = forced_movement_timer / max(forced_movement_total_duration, 0.001)
				var speed = lerp(pawn.stats_component.move_speed.value, forced_velocity.length(), ease(progress, 0.5))
				var dir = forced_velocity.normalized()
				pawn.velocity.x = dir.x * speed
				pawn.velocity.z = dir.z * speed

			apply_gravity(delta)
			pawn.move_and_slide()
			should_broadcast = true

			# Keep server queue drained during forced movement so inputs don't pile up
			while server_input_queue.size() > 0:
				var inp = server_input_queue.pop_front()
				pawn.global_rotation.y = inp.yaw
				movement_vector = inp.vector
				last_processed_input_id = inp.id

		# 2. Host Player Normal Simulation
		elif is_local_human():
			var player_input = poll_input_packet()
			simulate_step(player_input, delta)
			should_broadcast = true

		# 3. Remote Client Input Consumption with Jitter Buffer
		elif pawn.peer_id_or_null != null:
			if server_input_queue.size() > 0:
				if last_processed_input_id > 0 or server_input_queue.size() >= JITTER_BUFFER_TARGET:
					var steps = 1
					if server_input_queue.size() > JITTER_BUFFER_TARGET + 2:
						steps = 2
					steps = min(steps, server_input_queue.size())
					for _i in range(steps):
						var input_data = server_input_queue.pop_front()
						simulate_step(input_data, delta)
						last_processed_input_id = input_data.id
					should_broadcast = true

		# 4. AI Pawn Simulation
		else:
			apply_gravity(delta)
			apply_movement(delta)
			pawn.move_and_slide()
			should_broadcast = true

		# Broadcast snapshot to peers
		if should_broadcast:
			sync_pos_from_host.rpc([
				pawn.global_position.x,
				pawn.global_position.y,
				pawn.global_position.z,
				pawn.velocity.x,
				pawn.velocity.y,
				pawn.velocity.z,
				pawn.global_rotation.y,
				last_processed_input_id,
				is_sprinting,
				is_forced_movement
			])

	# Client Prediction Loop
	elif is_local_human():
		var player_input = poll_input_packet()
		receive_client_input.rpc_id(1, player_input)

		if is_forced_movement:
			# Prediction is suspended during server-authoritative forced movement
			pass
		else:
			simulate_step(player_input, delta)

			input_history.append({
				"id": player_input.id,
				"input": player_input,
				"position": pawn.global_position,
				"velocity": pawn.velocity
			})

			if input_history.size() > MAX_HISTORY:
				input_history.pop_front()

# Step 3: Server receives client input
@rpc("any_peer", "call_remote", "unreliable")
func receive_client_input(input_data: Dictionary):
	if not MyUtils.is_authority(multiplayer):
		return
	if multiplayer.get_remote_sender_id() != pawn.peer_id_or_null:
		return
	if input_data.id <= last_processed_input_id:
		return

	# Insert input sorted by ID and discard duplicates
	var inserted = false
	for i in range(server_input_queue.size() - 1, -1, -1):
		if server_input_queue[i].id == input_data.id:
			return
		if server_input_queue[i].id < input_data.id:
			server_input_queue.insert(i + 1, input_data)
			inserted = true
			break
	if not inserted:
		server_input_queue.push_front(input_data)

# Step 4 & 5: Server snapshot broadcast and Client Reconciliation
@rpc("authority", "call_remote", "unreliable")
func sync_pos_from_host(data: Array):
	var server_pos = Vector3(data[0], data[1], data[2])
	var server_vel = Vector3(data[3], data[4], data[5])
	var server_rot_y: float = data[6]
	var ack_input_id: int = data[7]
	var server_is_sprinting: bool = data[8]
	var server_is_forced_movement: bool = data[9]

	is_sprinting = server_is_sprinting
	var was_forced = is_forced_movement
	is_forced_movement = server_is_forced_movement

	# Non-owning peers (remote observers) simply accept the authoritative snapshot
	if not pawn.is_owned_by_peer():
		pawn.global_position = server_pos
		pawn.velocity = server_vel
		pawn.global_rotation.y = server_rot_y
		return

	# During forced movement: adopt server state directly and wipe history to prevent replay fighting
	if is_forced_movement:
		pawn.global_position = server_pos
		pawn.velocity = server_vel
		pawn.global_rotation.y = server_rot_y
		input_history.clear()
		return

	# If forced movement just ended, snap to final state and start fresh history
	if was_forced and not is_forced_movement:
		pawn.global_position = server_pos
		pawn.velocity = server_vel
		pawn.global_rotation.y = server_rot_y
		input_history.clear()
		return

	# Normal Reconciliation (Rollback & Replay) for predicted WASD + Jump
	if ack_input_id <= 0:
		return

	var match_index = -1
	for i in range(input_history.size()):
		if input_history[i].id == ack_input_id:
			match_index = i
			break

	if match_index != -1:
		var historical_record = input_history[match_index]
		var distance = server_pos.distance_to(historical_record.position)

		# Rollback & replay if client prediction diverged from server snapshot
		if distance > RECONCILIATION_THRESHOLD:
			pawn.global_position = server_pos
			pawn.velocity = server_vel

			var physics_delta = get_physics_process_delta_time()
			for i in range(match_index + 1, input_history.size()):
				var item = input_history[i]
				simulate_step(item.input, physics_delta)
				item.position = pawn.global_position
				item.velocity = pawn.velocity

		# Discard acknowledged history
		input_history = input_history.slice(match_index + 1)
	elif input_history.size() > 0 and ack_input_id > input_history[-1].id:
		pawn.global_position = server_pos
		pawn.velocity = server_vel
		input_history.clear()

func apply_gravity(delta: float):
	var gravity_vec = pawn.get_gravity()
	pawn.velocity += gravity_vec * delta

func apply_jump():
	if pawn.is_on_floor() and is_jumping:
		pawn.velocity.y = pawn.stats_component.jump_height.value

func apply_movement(delta: float):
	var accel: float = ground_accel
	var max_speed: float = pawn.stats_component.move_speed.value

	if is_sprinting:
		max_speed *= pawn.stats_component.sprint_speed_multiplier.value

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
