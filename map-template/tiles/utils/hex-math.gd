class_name HexMath
extends RefCounted

static var offsets: Array[Vector2i] = [
	Vector2i(1, 0), # East
	Vector2i(0, 1), # South-East
	Vector2i(-1, 1), # South-West
	Vector2i(-1, 0), # West
	Vector2i(0, -1), # North-West
	Vector2i(1, -1), # North-East
]

static func get_neighbor(cell: Vector2i, dir_index: int) -> Vector2i:
	return cell + HexMath.offsets[dir_index]

static func get_opposite_direction(dir_index: int) -> int:
	return (dir_index + 3) % 6

static func rotate_array(arr: Array[Variant], amount: int) -> Array[Variant]:
	return arr.slice(amount) + arr.slice(0, amount)

static func axial_to_world(q: int, r: int, size: float = 1.0) -> Vector3:
	var x = size * sqrt(3.0) * (q + r / 2.0)
	var z = size * (3.0 / 2.0) * r
	return Vector3(x, 0, z)
