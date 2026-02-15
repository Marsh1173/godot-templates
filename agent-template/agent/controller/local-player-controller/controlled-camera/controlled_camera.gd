extends Node3D

@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var camera_3d: Camera3D = $Camera3D

const collision_margin: float = 0.3
const max_range: float = 5

func _ready():
	ray_cast_3d.target_position.z = max_range + collision_margin

# RayCast3D is updated every process, not physics_process
func _process(delta):
	var desired_point: Vector3 = global_position + global_transform.basis.z * max_range
	if ray_cast_3d.is_colliding():
		desired_point = ray_cast_3d.get_collision_point() - (global_transform.basis.z.normalized() * collision_margin)
	
	if global_position.distance_to(desired_point) < global_position.distance_to(camera_3d.global_position):
		# Current camera pos is further than furthest possible point
		camera_3d.global_position = desired_point
	else:
		# Slowly zoom out to furthest possible point. Increase move_toward delta to make it faster
		var lerped_point = camera_3d.global_position.move_toward(desired_point, delta * 5)
		camera_3d.global_position = lerped_point
