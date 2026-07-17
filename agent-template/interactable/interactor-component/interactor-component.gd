extends Area3D
class_name InteractorComponent

@export var inventory_component: InventoryComponent = null

@export_group("Make visible to syncronizer")
@export var active_interactable_node_path_or_null = null

var peer_id_or_null = null

func set_peer_id_or_null(_peer_id_or_null):
	peer_id_or_null = _peer_id_or_null

func _ready():
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

#region tracking closest interactable
var targeted_interactable_or_null: Interactable = null
var interactables_in_range: Array[Interactable] = []

signal on_interactable_changed(new_interactable: Interactable)

func _on_area_entered(body: Node3D):
	if body is Interactable:
		interactables_in_range.append(body)

func _on_area_exited(body: Node3D):
	interactables_in_range.erase(body)
	
	if targeted_interactable_or_null == body:
		_recalc_closest()

func _process(_delta):
	_recalc_closest()

func _recalc_closest():
	var temp_targeted_interactable_or_null = targeted_interactable_or_null
	
	# Make sure the targeted interactable is still valid
	if !interactables_in_range.has(temp_targeted_interactable_or_null):
		temp_targeted_interactable_or_null = null
	
	# Find closest
	for interactable in interactables_in_range:
		if temp_targeted_interactable_or_null == null:
			temp_targeted_interactable_or_null = interactable
		elif _find_distance_score(temp_targeted_interactable_or_null) > _find_distance_score(interactable):
			temp_targeted_interactable_or_null = interactable
	
	# Optionally set and signal
	if temp_targeted_interactable_or_null != targeted_interactable_or_null:
		targeted_interactable_or_null = temp_targeted_interactable_or_null
		on_interactable_changed.emit(targeted_interactable_or_null)

func _find_distance_score(node: Node3D):
	# 1. Make sure the direction is a unit vector (length of 1)
	var n_dir = global_transform.basis * Vector3.FORWARD
	
	# 2. Find how far along that direction the target is
	var lhs = node.global_position - global_position
	var dot_product = lhs.dot(n_dir)
	
	# 3. The closest point to the line is the origin + (direction * distance)
	var closest_pos = global_position + (n_dir * dot_product)
	
	return closest_pos.distance_squared_to(node.global_position)
#endregion

#region attempting to interact
# Called on the host from the peers
@rpc("any_peer", "call_remote", "reliable")
func request_interact(target_path: NodePath, interact_context_key: String = ''):
	if not MyUtils.is_authority(multiplayer):
		assert(false, "request_interact must be called on authority")
		return
	
	# Check if caller has authority for interactor
	var called_by_authority := multiplayer.get_remote_sender_id() == 0 # 0 means called outside RPC
	var called_by_player: bool = peer_id_or_null == multiplayer.get_remote_sender_id()
	if !called_by_authority and !called_by_player:
		assert(false, "Only peer_id_or_null can call request_interact, is " + str(multiplayer.get_remote_sender_id()) + ", should be " + str(peer_id_or_null))
		return
	
	var interactable = get_node(target_path)
	# Sometimes client and host are out of sync for a few ms, might have deleted it
	if not interactable is Interactable:
		return
	# Or might have moved out of range
	if not interactables_in_range.has(interactable):
		return
	
	interactable.attempt_interact(self, interact_context_key)

# Called on the host from the peers
@rpc("any_peer", "call_remote", "reliable")
func request_stop_interact(interact_context_key: String = ''):
	if not MyUtils.is_authority(multiplayer):
		assert(false, "request_stop_interact must be called on authority")
		return
	
	# Check if caller has authority for interactor
	var called_by_authority := multiplayer.get_remote_sender_id() == 0 # 0 means called outside RPC
	var called_by_player: bool = peer_id_or_null == multiplayer.get_remote_sender_id()
	if !called_by_authority and !called_by_player:
		assert(false, "Only peer_id_or_null can call request_stop_interact, is " + str(multiplayer.get_remote_sender_id()) + ", should be " + str(peer_id_or_null))
		return
	
	#var interactable = get_node(target_path)
	## Sometimes client and host are out of sync for a few ms, might have deleted it
	#if not interactable is Interactable:
		#return
	## Or might have moved out of range
	#if not interactables_in_range.has(interactable):
		#return
	#
	#interactable.attempt_interact(self, interact_context_key)
#endregion
