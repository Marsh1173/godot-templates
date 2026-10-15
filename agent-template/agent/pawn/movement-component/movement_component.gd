extends Node
class_name MovementComponent

"""
Tick-Based Client Prediction and Server Reconciliation Movement Component

Step 1: Tag inputs with an incremental sequence ID (get_player_input)
Step 2: Maintain client history buffer (input_history)
Step 3: Send inputs to the server via unreliable RPC (receive_client_input)
Step 4: Server processes queued inputs and broadcasts snapshots with last_processed_input_id
Step 5: Client reconciles by comparing snapshot with historical record:
        Rollback & Replay subsequent unacknowledged inputs on divergence.
"""

@onready var pawn: Pawn = $".."
@onready var stamina_component: StaminaComponent = $"../StaminaComponent"

# Movement state
var movement_vector: Vector2 = Vector2.ZERO
var is_sprinting: bool = false
var is_jumping: bool = false

# Constants
const ground_accel: float = 70.0
const air_accel: float = 30.0

# Tick-based reconciliation
const RECONCILIATION_THRESHOLD: float = 0.05 # 5cm divergence threshold
const MAX_HISTORY: int = 120 # ~2 seconds at 60Hz

var current_input_id: int = 0
var input_history: Array[Dictionary] = []

# Server-side input queue & tracking
var server_input_queue: Array[Dictionary] = []
var last_processed_input_id: int = 0

func _ready():
	stamina_component.exhausted.connect(stop_sprinting)

func stop_sprinting():
	is_sprinting = false

func is_local_human() -> bool:
	return pawn.peer_id_or_null != null and pawn.is_owned_by_peer()

# Step 1: Tag Inputs with an Incremental ID
func get_player_input() -> Dictionary:
	current_input_id += 1
	var input_vector = Vector2.ZERO
	var jump = false
	var sprint = false

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input_vector = Input.get_vector("move-left", "move-right", "move-forward", "move-backward")
		jump = Input.is_action_pressed("jump")
		sprint = Input.is_action_pressed("sprint")

	return {
		"id": current_input_id,
		"vector": input_vector,
		"yaw": pawn.global_rotation.y,
		"jump": jump,
		"sprint": sprint
	}

# Unified single simulation step
func simulate_step(input: Dictionary, delta: float):
	pawn.global_rotation.y = input.yaw
	movement_vector = input.vector
	is_jumping = input.jump
	is_sprinting = input.sprint and stamina_component.stamina > 0

	apply_gravity(delta)
	apply_forced_movement()
	apply_movement(delta)
	pawn.move_and_slide()

func _physics_process(delta: float):
	if MyUtils.is_authority(multiplayer):
		# Server / Host Simulation
		if is_local_human():
			# Host player controlling their own pawn
			var player_input = get_player_input()
			simulate_step(player_input, delta)
		elif pawn.peer_id_or_null != null:
			# Step 4: Server processes client inputs from queue
			if server_input_queue.size() > 0:
				var steps = min(server_input_queue.size(), 5)
				for _i in range(steps):
					var input_data = server_input_queue.pop_front()
					simulate_step(input_data, delta)
					last_processed_input_id = input_data.id
			elif last_processed_input_id > 0:
				apply_gravity(delta)
				pawn.move_and_slide()
		else:
			# AI pawn running on host
			apply_gravity(delta)
			apply_movement(delta)
			pawn.move_and_slide()

		# Step 4: Periodically broadcast snapshot back to clients
		sync_pos_from_host.rpc([
			pawn.global_position.x,
			pawn.global_position.y,
			pawn.global_position.z,
			pawn.velocity.x,
			pawn.velocity.y,
			pawn.velocity.z,
			pawn.global_rotation.y,
			last_processed_input_id
		])
	elif is_local_human():
		# Step 2 & 3: Client Prediction & Send Inputs to Server
		var player_input = get_player_input()

		# Send to host via unreliable RPC
		receive_client_input.rpc_id(1, player_input)

		# Predict locally
		simulate_step(player_input, delta)

		# Store in history buffer
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

	# Non-owning peers (remote observers) simply accept the authoritative snapshot
	if not pawn.is_owned_by_peer():
		pawn.global_position = server_pos
		pawn.velocity = server_vel
		pawn.global_rotation.y = server_rot_y
		return

	# Step 5: Reconciliation (Rollback & Replay) for owning client
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

		# Divergence check: if distance exceeds threshold, rollback & replay
		if distance > RECONCILIATION_THRESHOLD:
			pawn.global_position = server_pos
			pawn.velocity = server_vel

			var physics_delta = get_physics_process_delta_time()
			for i in range(match_index + 1, input_history.size()):
				var item = input_history[i]
				simulate_step(item.input, physics_delta)
				item.position = pawn.global_position
				item.velocity = pawn.velocity

		# Discard acknowledged history items up to and including match_index
		input_history = input_history.slice(match_index + 1)
	elif input_history.size() > 0 and ack_input_id > input_history[-1].id:
		pawn.global_position = server_pos
		pawn.velocity = server_vel
		input_history.clear()

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
