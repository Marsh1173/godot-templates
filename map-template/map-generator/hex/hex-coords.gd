## HexCoords - Hexagonal coordinate math for flat-top hex grids.
##
## This class handles all spatial math for the hex grid using CUBE COORDINATES.
##
## CUBE COORDINATES:
## Each hex cell is identified by three integers (q, r, s) stored as Vector3i,
## subject to the constraint: q + r + s = 0.
##
## This coordinate system has several advantages over offset coordinates:
##   - Neighbor calculation is trivial: just add a direction vector
##   - Distance is simple: max(|dq|, |dr|, |ds|) or (|dq| + |dr| + |ds|) / 2
##   - Rotations, reflections, and rings are straightforward
##   - Works naturally with Dictionary keys (Vector3i is hashable)
##
## The q-axis points to the right (East), r-axis points to the upper-left,
## and s-axis points to the lower-left. But you rarely need to think about
## the axis directions -- just use the neighbor() function with HexDirection.
##
## FLAT-TOP ORIENTATION:
## We use flat-top hexagons, meaning the flat edges are on the left and right.
## This affects the world-space conversion formulas:
##   x = hex_size * 3/2 * q
##   z = hex_size * sqrt(3) * (r + q/2)
##   y = level * level_height  (vertical height for elevation)
##
## REFERENCE:
## Based on the hex-map-wfc reference implementation's coordinate system.
## See also: https://www.redblobgames.com/grids/hexagons/ (the definitive hex guide)
##
## USED BY:
##   - HexGrid: to generate cell positions and compute neighbors
##   - HexTileRenderer: to convert grid positions to 3D world coordinates
##   - HexWFCManager: to compute chunk offsets in multi-chunk generation
class_name HexCoords
extends RefCounted

## Direction vectors in cube coordinates for flat-top hexagons.
## Adding one of these to a cube coordinate gives the neighbor in that direction.
## Index matches HexDirection.Dir enum values (NE=0, E=1, SE=2, SW=3, W=4, NW=5).
##
## Derivation (flat-top hex, cube coords):
##   NE: q+1, r stays,  s-1  -> (+1,  0, -1)
##   E:  q+1, r-1,      s stays -> (+1, -1,  0)
##   SE: q stays, r-1,  s+1  -> ( 0, -1, +1)
##   SW: q-1, r stays,  s+1  -> (-1,  0, +1)
##   W:  q-1, r+1,      s stays -> (-1, +1,  0)
##   NW: q stays, r+1,  s-1  -> ( 0, +1, -1)
const DIRECTION_VECTORS: Array[Vector3i] = [
	Vector3i(1, 0, -1),   # NE (Dir.NE = 0)
	Vector3i(1, -1, 0),   # E  (Dir.E  = 1)
	Vector3i(0, -1, 1),   # SE (Dir.SE = 2)
	Vector3i(-1, 0, 1),   # SW (Dir.SW = 3)
	Vector3i(-1, 1, 0),   # W  (Dir.W  = 4)
	Vector3i(0, 1, -1),   # NW (Dir.NW = 5)
]


## Returns the cube coordinates of the neighbor in the given direction.
## This is the fundamental operation for traversing the hex grid.
##
## Parameters:
##   cube: The current cell's cube coordinates (Vector3i)
##   dir: The direction to move (HexDirection.Dir value, 0-5)
## Returns:
##   The neighboring cell's cube coordinates
static func neighbor(cube: Vector3i, dir: int) -> Vector3i:
	return cube + DIRECTION_VECTORS[dir]


## Converts cube coordinates + level to a 3D world position.
##
## The hex_size parameter is the "outer radius" -- the distance from the center
## of a hexagon to any of its vertices. This determines the spacing of the grid.
##
## For flat-top hexagons:
##   - Horizontal spacing between columns: hex_size * 1.5 (because adjacent columns
##     share edges, and the width of a hex is 2 * hex_size, but they overlap)
##   - Vertical spacing between rows: hex_size * sqrt(3) (the height of a hex)
##   - Odd columns are offset vertically by half a row height
##
## The level parameter adds vertical height (Y axis in Godot's coordinate system).
##
## Parameters:
##   cube: Cell position in cube coordinates
##   hex_size: Outer radius of hexagons (center to vertex distance)
##   level: Elevation level (0 = ground, higher = elevated)
##   level_height: World-space height per level increment
## Returns:
##   Vector3 world position (x=horizontal, y=up, z=horizontal-depth)
static func cube_to_world(cube: Vector3i, hex_size: float, level: int = 0, level_height: float = 1.0) -> Vector3:
	var q: float = cube.x
	var r: float = cube.y
	var x: float = hex_size * 1.5 * q
	var z: float = hex_size * sqrt(3.0) * (r + q / 2.0)
	var y: float = level * level_height
	return Vector3(x, y, z)


## Returns the hex distance between two cells (number of steps to walk).
## In cube coordinates, this is (|dq| + |dr| + |ds|) / 2.
static func distance(a: Vector3i, b: Vector3i) -> int:
	var diff: Vector3i = a - b
	return (absi(diff.x) + absi(diff.y) + absi(diff.z)) / 2


## Generates all cube coordinates within a hexagonal area of the given radius.
##
## radius=0 returns just the center (1 cell).
## radius=1 returns center + 6 neighbors (7 cells).
## radius=2 returns 19 cells (7 + 12 on the outer ring).
## General formula: 3*r^2 + 3*r + 1 cells for radius r.
##
## The cells are returned center-first, then ring 1, ring 2, etc.
## Within each ring, cells go clockwise starting from the SW direction.
##
## This is used to initialize the hex grid with all cell positions.
##
## Parameters:
##   center: The center cell's cube coordinates
##   radius: Number of rings outward from center (0 = just center)
## Returns:
##   Array of all cube coordinates in the hexagonal area
static func spiral(center: Vector3i, radius: int) -> Array[Vector3i]:
	var results: Array[Vector3i] = [center]
	if radius <= 0:
		return results
	for r_ring: int in range(1, radius + 1):
		var ring_cells: Array[Vector3i] = ring(center, r_ring)
		results.append_array(ring_cells)
	return results


## Generates all cube coordinates on a single ring at the given radius.
##
## A ring at radius R has exactly 6*R cells.
##
## Algorithm (from Red Blob Games hex reference):
## Start at center + W_direction * radius, then walk along directions
## NE, E, SE, SW, W, NW for 'radius' steps each. This traces the ring clockwise.
##
## WHY direction W (not SW)?
## Starting at the W corner and walking NE keeps us ON the ring (at constant
## distance from center). Starting at SW and walking NE moves TOWARD the center,
## producing cells at the wrong distance -- causing visible bands of missing tiles.
##
## Parameters:
##   center: The center cell's cube coordinates
##   radius: Distance of the ring from center (must be > 0 for a real ring)
## Returns:
##   Array of cube coordinates forming the ring
static func ring(center: Vector3i, radius: int) -> Array[Vector3i]:
	if radius <= 0:
		return [center]
	var results: Array[Vector3i] = []
	# Start at the cell that is 'radius' steps in the W direction from center.
	# Direction 4 (W) is the correct starting corner per the Red Blob Games algorithm.
	var current: Vector3i = center + DIRECTION_VECTORS[HexDirection.Dir.W] * radius
	# Walk along each of the 6 hex edges. Each edge has 'radius' steps.
	# The directions we walk are NE(0), E(1), SE(2), SW(3), W(4), NW(5) in order.
	for dir: int in HexDirection.COUNT:
		for _step: int in radius:
			results.append(current)
			current = neighbor(current, dir)
	return results


## Converts offset coordinates (col, row) to cube coordinates.
## Uses "even-q" offset layout for flat-top hexagons.
## This is mainly useful for interfacing with 2D array storage if needed.
static func offset_to_cube(col: int, row: int) -> Vector3i:
	var q: int = col
	var r: int = row - (col + (col & 1)) / 2
	var s: int = -q - r
	return Vector3i(q, r, s)


## Converts cube coordinates back to offset coordinates (col, row).
static func cube_to_offset(cube: Vector3i) -> Vector2i:
	var col: int = cube.x
	var row: int = cube.y + (cube.x + (cube.x & 1)) / 2
	return Vector2i(col, row)
