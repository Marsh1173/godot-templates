## HexTileType - Resource definition for a single hex tile type.
##
## Each tile type is a Godot Resource (.tres file) that defines:
##   - What the tile looks like (mesh_scene)
##   - What edges it exposes in each direction (edges dictionary)
##   - How likely it is to be placed (weight)
##   - How it interacts with elevation (level_increment, high_edges)
##   - Its rotational symmetry (symmetry)
##
## EDGE DICTIONARY FORMAT:
## The 'edges' dictionary maps direction integers to edge type integers:
##   { 0: 0, 1: 2, 2: 0, 3: 0, 4: 2, 5: 0 }
##   which means: NE=GRASS, E=ROAD, SE=GRASS, SW=GRASS, W=ROAD, NW=GRASS
##
## Edges are defined at ROTATION 0. When the solver considers this tile at
## rotation R, it calls get_rotated_edges(R) to shift the edge assignments.
## For example, at rotation=1, the NE edge becomes the E edge, etc.
##
## WEIGHT:
## Higher weight = more likely to be chosen during WFC collapse.
## GRASS at weight=500 will dominate the map, while ROAD at weight=30
## will appear sparingly. Weights are relative -- only ratios matter.
##
## SYMMETRY:
## Controls how many unique rotations this tile has:
##   symmetry=6: All rotations look the same (e.g., all-grass tile).
##               Only rotation=0 is used (others would be identical).
##   symmetry=3: 180-degree symmetry (e.g., straight road: NE-SW same as SW-NE).
##               Only rotations 0,1,2 are unique (3,4,5 duplicate 0,1,2).
##   symmetry=2: 120-degree symmetry (e.g., three-way junction).
##               Only rotations 0,1 are unique.
##   symmetry=1: No symmetry -- all 6 rotations are unique.
##
## ELEVATION (LEVEL SYSTEM):
## The reference implementation supports multi-level terrain:
##   - level_increment: How many levels this tile rises (0=flat, 1=slope)
##   - high_edges: Which directions have elevated edges
##   For example, a slope tile might have high_edges=[E, NE] and level_increment=1,
##   meaning its east and northeast edges are one level higher than the base.
##   Neighbors touching those high edges must be at level+1.
##
## CREATING NEW TILES:
## 1. Create a new .tres file in data/tiles/
## 2. Set the script to this resource (hex-tile-type.gd)
## 3. Assign a unique tile_id (check existing tiles to avoid duplicates)
## 4. Define edges for each direction at rotation 0
## 5. Set weight based on desired frequency
## 6. Point mesh_scene to a hex mesh .tscn in meshes/
## 7. The registry auto-loads all .tres files at startup
##
## USED BY:
##   - HexTileRegistry: loads and indexes all tile types
##   - HexTileState: encodes (tile_type_id, rotation, level) as int
##   - HexWFCAdjacency: reads edges to build the constraint index
##   - HexTileRenderer: instantiates the mesh_scene for rendering
class_name HexTileType
extends Resource

## Unique human-readable name for this tile (e.g., &"grass", &"road_straight").
@export var tile_name: StringName = &""

## Unique integer identifier. Used in state key encoding.
## MUST be unique across all tile types. Range: 0 to ~680 (limited by state packing).
@export var tile_id: int = 0

## Edge types for each of the 6 directions, at rotation 0.
## Keys: HexDirection.Dir values (0-5)
## Values: HexEdgeType.Type values (0-7)
## Example for a straight road tile (road on E and W):
##   { 0: 0, 1: 2, 2: 0, 3: 0, 4: 2, 5: 0 }  (NE:GRASS, E:ROAD, SE:GRASS, SW:GRASS, W:ROAD, NW:GRASS)
@export var edges: Dictionary = {}

## Selection weight during WFC collapse.
## Higher = more common. Only relative ratios matter.
## Typical values: GRASS=500, FOREST=150, WATER=200, ROAD=30, COAST=50
@export var weight: float = 100.0

## The 3D scene to instantiate when rendering this tile.
## Should be a hex-shaped mesh scene from the meshes/ directory.
@export var mesh_scene: PackedScene = null

## How many levels this tile raises the terrain.
## 0 = flat tile (most tiles). 1 = gentle slope. 2 = steep slope.
## When level_increment > 0, high_edges defines which edges are elevated.
@export var level_increment: int = 0

## Which edge directions are at the elevated level.
## Only meaningful when level_increment > 0.
## Array of HexDirection.Dir values.
## Example for a slope rising to the east: [1] (just Dir.E)
@export var high_edges: Array[int] = []

## If true, the solver won't place two of these tiles adjacent to each other.
## Useful for grass to prevent large featureless plains.
@export var prevent_chaining: bool = false

## Rotational symmetry of this tile (see class doc for full explanation).
## 6 = all rotations identical, 3 = 180-degree symmetric, 1 = all unique.
@export var symmetry: int = 6

## Whether agents can walk on this tile (for future navigation mesh generation).
@export var walkable: bool = true


## Returns the edges dictionary rotated by the given number of 60-degree steps.
##
## At rotation=0, this just returns a copy of the original edges.
## At rotation=1, NE's edge type moves to E, E moves to SE, etc.
## This is how the solver knows what edges a tile exposes at any given rotation.
func get_rotated_edges(rotation: int) -> Dictionary:
	return HexDirection.rotated_edges(edges, rotation)


## Returns the edge type at a specific direction after applying rotation.
func get_edge_at(direction: int, rotation: int) -> int:
	# The edge that ends up at 'direction' after rotation was originally at
	# (direction - rotation), so we un-rotate the direction to look up the
	# original edge.
	var original_dir: int = HexDirection.rotate(direction, -rotation)
	return edges.get(original_dir, HexEdgeType.Type.GRASS)


## Returns an array of rotation values that produce unique edge configurations.
##
## For symmetry=6 (uniform tile like all-grass): returns [0]
## For symmetry=3 (180-degree like straight road): returns [0, 1, 2]
## For symmetry=2 (120-degree like T-junction): returns [0, 1]
## For symmetry=1 (all unique): returns [0, 1, 2, 3, 4, 5]
##
## The solver only generates states for unique rotations, avoiding duplicate
## states that would waste memory and slow down constraint propagation.
func get_valid_rotations() -> Array[int]:
	var unique_count: int = 6 / symmetry
	var rotations: Array[int] = []
	for r: int in unique_count:
		rotations.append(r)
	return rotations
