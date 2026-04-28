class_name HexTile
extends Resource

enum Edge {
	GRASS = 0,
	ROAD = 1,
	RIVER = 2,
	CLIFF_LEFT = 3,
	CLIFF_RIGHT = 4
}

@export var tile_name: StringName
@export var scene: PackedScene
@export var weight: float = 1.0

## Must be 6 items in length. Each index represents a direction in HexMath.offsets
@export var edges: Array[HexTile.Edge]

## Must be 6 items in length. Each index represents a direction in HexMath.offsets
@export var edge_heights: Array[int] = [0,0,0,0,0,0]

## Rotational symmetry (6=uniform, 3=180-deg, 3=120deg, 1=all unique)
@export_enum("All unique:1", "Opposite edges mirror:2", "Triangle:3", "All the same:6") var symmetry_mod: int = 1

## Keeps track of how many 60-degree turns for this specific tile's mesh. Can be 0-5
var rotation: int = 0

func reset_edge_heights():
	var new_edge_heights: Array[int] = edge_heights.duplicate()
	var lowest: int = new_edge_heights.min()
	for i in range(len(new_edge_heights)):
		new_edge_heights[i] -= lowest
	edge_heights = new_edge_heights

func create_raised_variants(height: int) -> Array[HexTile]:
	var copies: Array[HexTile] = []
	
	for i: int in range(height):
		var dup: HexTile = self.duplicate(true)
		for j in range(len(dup.edge_heights)):
			dup.edge_heights[j] += i + 1
		copies.append(dup)
	
	copies.append(self)
	return copies

func create_rotated_variants() -> Array[HexTile]:
	var copies: Array[HexTile] = []
	match symmetry_mod:
		1:
			copies = [
				self.duplicate(false),
				self.duplicate(false),
				self.duplicate(false),
				self.duplicate(false),
				self.duplicate(false)
			]
		2:
			copies = [
				self.duplicate(false),
				self.duplicate(false)
			]
		3:
			copies = [
				self.duplicate(false)
			]
		6:
			copies = []
		_:
			assert(false, "symmetry_mod not valid: " + str(symmetry_mod))
	for i in range(len(copies)):
		copies[i].rotation = i + 1
		copies[i].edges = HexMath.rotate_array(copies[i].edges, i + 1)
		copies[i].edge_heights = HexMath.rotate_array(copies[i].edge_heights, i + 1)
	copies.append(self)
	return copies
