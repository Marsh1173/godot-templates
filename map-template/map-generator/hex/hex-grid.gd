## HexGrid - Hexagonal grid data structure for storing WFC cells.
##
## This class manages a hexagonal grid of cells using cube coordinates.
## Each cell position is a Vector3i (q, r, s) key in a Dictionary, and
## each cell value is a HexWFCCell that tracks which states are still possible.
##
## WHY A DICTIONARY INSTEAD OF A 2D ARRAY?
## Hex grids are naturally hexagonal in shape (not rectangular), so a 2D array
## would have many wasted entries in the corners. A Dictionary[Vector3i, Cell]
## is memory-efficient for any grid shape, and Vector3i is hashable in Godot 4,
## giving us O(1) lookup. The slight overhead vs. array indexing is negligible
## compared to the WFC solver's constraint propagation work.
##
## GRID SHAPE:
## The grid is a regular hexagon with a given radius:
##   radius=0 -> 1 cell (just the center)
##   radius=1 -> 7 cells
##   radius=2 -> 19 cells
##   radius=3 -> 37 cells
##   radius=5 -> 91 cells
##   radius=10 -> 331 cells
##   General formula: 3*r^2 + 3*r + 1
##
## USED BY:
##   - HexWFCSolver: owns the grid, reads/writes cells during solve
##   - HexWFCBacktracker: reads cells to restore possibilities during undo
class_name HexGrid
extends RefCounted

## The radius of this hexagonal grid (number of rings from center).
var radius: int

## Cell storage: cube coordinates (Vector3i) -> HexWFCCell.
## Populated by initialize_positions() and filled with actual cells by the solver.
var cells: Dictionary = {}


## Creates a new hex grid with the given radius.
## Call initialize_positions() to populate the coordinate keys.
func _init(_radius: int = 5) -> void:
	radius = _radius


## Generates all cell positions for a hexagonal grid of the configured radius.
## After calling this, cells will contain entries for every position, but the
## values will be null until the solver initializes them with HexWFCCell objects.
func initialize_positions() -> void:
	cells.clear()
	var positions: Array[Vector3i] = HexCoords.spiral(Vector3i.ZERO, radius)
	for pos: Vector3i in positions:
		cells[pos] = null


## Returns the cell at the given cube coordinates, or null if not in the grid.
func get_cell(cube_coords: Vector3i) -> Variant:
	return cells.get(cube_coords)


## Sets (or replaces) the cell at the given cube coordinates.
func set_cell(cube_coords: Vector3i, cell: Variant) -> void:
	cells[cube_coords] = cell


## Returns true if this grid contains the given position.
func has_cell(cube_coords: Vector3i) -> bool:
	return cells.has(cube_coords)


## Returns the cube coordinates of a neighbor in the given direction,
## regardless of whether that position exists in the grid.
func get_neighbor_coords(cube_coords: Vector3i, dir: int) -> Vector3i:
	return HexCoords.neighbor(cube_coords, dir)


## Returns the cell at the neighbor position, or null if it's outside the grid.
## This is a convenience that combines neighbor coordinate lookup + cell lookup.
func get_neighbor_cell(cube_coords: Vector3i, dir: int) -> Variant:
	var neighbor_coords: Vector3i = HexCoords.neighbor(cube_coords, dir)
	return cells.get(neighbor_coords)


## Returns all cube coordinates that have cells in this grid.
func get_all_coords() -> Array:
	return cells.keys()


## Returns the total number of cell positions in this grid.
func get_cell_count() -> int:
	return cells.size()


## Returns all cell positions on the outermost ring (the boundary).
## These are the cells at exactly 'radius' distance from the center.
## Used for multi-chunk boundary constraints.
func get_boundary_coords() -> Array[Vector3i]:
	if radius <= 0:
		return [Vector3i.ZERO]
	return HexCoords.ring(Vector3i.ZERO, radius)
