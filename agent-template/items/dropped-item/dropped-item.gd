extends RigidBody3D
class_name DroppedItem

@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D

var item_data: ItemData
var _starting_pos: Vector3

func with_data(_item_data: ItemData, pos: Vector3, throw_angle_or_null: float) -> DroppedItem:
	item_data = _item_data
	_starting_pos = pos
	if throw_angle_or_null != null:
		linear_velocity = (Vector3.FORWARD + Vector3.UP).rotated(Vector3.UP, throw_angle_or_null)
	return self

func _ready():
	global_position = _starting_pos
	add_item_mesh()

var time_since_spawn: float = 0.0
const check_period: float = 0.3
const inventory_attract_range_squared: float = 4

#region pickup animation
var location_that_picked_up_this_item = null
var time_since_pickup: float = 0.0
const pickup_anim_length: float = 0.15
#endregion

func _process(delta: float):
	if location_that_picked_up_this_item != null:
		time_since_pickup += delta
		
		mesh_instance_3d.global_position = mesh_instance_3d.global_position.lerp(
			location_that_picked_up_this_item,
			delta / (pickup_anim_length - time_since_pickup)
		)
		
		# Lerp scale from 0.5 (mesh instance's default scale) to 0 and no further
		mesh_instance_3d.scale = Vector3.ONE * 0.5 * max(0, (1 - (time_since_pickup / pickup_anim_length)))
		
		if time_since_pickup >= pickup_anim_length and MyUtils.is_authority(multiplayer):
			queue_free()
	else:
		time_since_spawn += delta
		# Bobbing motion
		mesh_instance_3d.position.y = 0.5 + sin(time_since_spawn * 2) / 6
		# slow rotating
		mesh_instance_3d.rotate_y(delta / 2)
		
		if fposmod(time_since_spawn, check_period) - delta <= 0 and\
			MyUtils.is_authority(multiplayer):
			
			check_for_nearby_inventories()

# Only called on host
func check_for_nearby_inventories():
	var inventories = get_tree().get_nodes_in_group("Inventories")
	for inventory in inventories:
		if inventory is InventoryComponent and\
			global_position.distance_squared_to(inventory.global_position) < inventory_attract_range_squared and\
			inventory.has_space_in_inventory():
				
			inventory.add_item(item_data)
			set_location_that_picked_up_this_item.rpc(inventory.global_position)
			return

@rpc("authority", "call_local", "reliable")
func set_location_that_picked_up_this_item(_location_that_picked_up_this_item: Vector3):
	location_that_picked_up_this_item = _location_that_picked_up_this_item

const FOOD_INGREDIENT_TOMATO_SPHERE_043 = preload("uid://ujokehd2shs2")
const WOOD_LOG_A_WOOD_LOG_A = preload("uid://dwspfoobq6r5m")

func add_item_mesh():
	match item_data.id:
		ItemData.ID.Wood:
			mesh_instance_3d.mesh = WOOD_LOG_A_WOOD_LOG_A
		ItemData.ID.Apple:
			mesh_instance_3d.mesh = FOOD_INGREDIENT_TOMATO_SPHERE_043
