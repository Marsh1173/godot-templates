extends RigidBody3D
class_name DroppedItem

@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D
@onready var interactable: Interactable = $Interactable
@onready var multiplayer_synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

var item_data: ItemData
var _starting_pos: Vector3

func with_data(_item_data: ItemData, pos: Vector3, throw_angle_or_null: float) -> DroppedItem:
	item_data = _item_data
	_starting_pos = pos
	if throw_angle_or_null != null:
		linear_velocity = (Vector3.FORWARD + Vector3.UP).rotated(Vector3.UP, throw_angle_or_null) * 2
	return self

func _ready():
	global_position = _starting_pos
	interactable.interact_prompt = "Pick up " + ItemRegistry.item_registry.get(item_data.id).name
	add_item_mesh()
	interactable.on_attempt_interact.connect(_on_attempt_interact)

func _process(delta: float):
	if location_that_picked_up_this_item != null:
		_zoom_to_location_that_picked_up_this_item(delta)
	else:
		_do_bob(delta)

#region bobbing anim
var time_since_spawn: float = 0.0
func _do_bob(delta):
	time_since_spawn += delta
	# Bobbing motion
	mesh_instance_3d.position.y = sin(time_since_spawn * 2) / 6
	# slow rotating
	mesh_instance_3d.rotate_y(delta / 2)
#endregion

#region interaction logic
# Only called on host
func _on_attempt_interact(interactor: InteractorComponent):
	if interactor.inventory_component != null and\
		interactor.inventory_component.has_space_in_inventory():
			
		interactor.inventory_component.add_item(item_data)
		set_location_that_picked_up_this_item.rpc(interactor.inventory_component.global_position)
#endregion

#region zoom to location that picked this up
var location_that_picked_up_this_item = null
var time_since_pickup: float = 0.0
const pickup_anim_length: float = 0.15

@rpc("authority", "call_local", "reliable")
func set_location_that_picked_up_this_item(_location_that_picked_up_this_item: Vector3):
	location_that_picked_up_this_item = _location_that_picked_up_this_item
	interactable.queue_free() # Interactable can't be interacted with anymore
	multiplayer_synchronizer.queue_free() # Interactable pos shouldn't be synced anymore

func _zoom_to_location_that_picked_up_this_item(delta: float):
	time_since_pickup += delta
	
	mesh_instance_3d.global_position = mesh_instance_3d.global_position.lerp(
		location_that_picked_up_this_item,
		delta / (pickup_anim_length - time_since_pickup)
	)
	
	# Lerp scale from 0.5 (mesh instance's default scale) to 0.001 and no further
	mesh_instance_3d.scale = Vector3.ONE * 0.5 * max(0.001, (1 - (time_since_pickup / pickup_anim_length)))
	
	if time_since_pickup >= pickup_anim_length and MyUtils.is_authority(multiplayer):
		queue_free()
#endregion

#region mesh
const BEER = preload("uid://dmq7p12tbkor2")
const BERRIES = preload("uid://dk66gy7oc0465")
const MEAT = preload("uid://bphxdfcdd26ed")
const OBSIDIAN = preload("uid://b6vjutl8u1666")
const STONE = preload("uid://b6g32rxopmuxt")
const WOOD = preload("uid://8cmlk5rjwtf5")

func add_item_mesh():
	match item_data.id:
		ItemData.ID.Beer:
			mesh_instance_3d.mesh = BEER
		ItemData.ID.Berries:
			mesh_instance_3d.mesh = BERRIES
		ItemData.ID.Meat:
			mesh_instance_3d.mesh = MEAT
		ItemData.ID.Obsidian:
			mesh_instance_3d.mesh = OBSIDIAN
		ItemData.ID.Stone:
			mesh_instance_3d.mesh = STONE
		ItemData.ID.Wood:
			mesh_instance_3d.mesh = WOOD
#endregion
