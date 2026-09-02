class_name Solver
extends RefCounted

var grid: Dictionary[Vector2i, Cell] = {}
static var all_possible_tiles_master_list: Array[HexTile]= []
## compat_table[direction][neighbor_tile_index] -> Dictionary of current_tile_indices that are compatible
static var compat_table: Array[Array] = []
const TILES_DIR: String = "res://map-template/map-generator/tiles/"

## Pre-constraints: map of Vector2i -> Callable that filters Array[HexTile] -> Array[HexTile].
## Set before calling solve(). Example:
##   solver.constraints[Vector2i(0, 0)] = func(tiles: Array[HexTile]) -> Array[HexTile]:
##       return tiles.filter(func(t): return t.tile_name == &"boss-arena")
var constraints: Dictionary[Vector2i, Callable] = {}

var callable = func(tiles: Array[HexTile]): return tiles.filter(func(t): return t.tile_name == &"grass" && t.edge_heights.min() == 0)

func solve(size: int, height: int) -> bool:
	setup_grid(size, height)
	
	for dir in HexMath.offsets:
		constraints[dir * size] = callable # Limit all corners to grass at height 0
	constraints[Vector2i(0, 0)] = func(tiles: Array[HexTile]): return tiles.filter(func(t): return t.edge_heights.min() == height) # Limit center to highest
	
	if !_apply_constraints():
		return false

	while true:
		var all_collapsed: bool = true
		for cell: Cell in grid.values():
			if !cell.is_collapsed:
				all_collapsed = false
				break
		if all_collapsed:
			return true
		
		if !observe():
			return false # failed
	return true

#region setup
func setup_grid(size: int, height: int):
	if len(Solver.all_possible_tiles_master_list) == 0:
		load_all_possible_tiles(height)
	grid = {}
	
	var start_pos: Vector2i =  Vector2i(0, 0)
	var places_to_grow: Array = [[size, start_pos]]
	
	while len(places_to_grow) != 0:
		var curr = places_to_grow.pop_front()
		var curr_size = curr[0]
		var curr_coord = curr[1]
		
		if grid.has(curr_coord):
			continue
		
		var cell: Cell = Cell.new()
		cell.coords = curr_coord
		cell.possible_tiles = Solver.all_possible_tiles_master_list.duplicate()
		grid.set(curr_coord, cell)
		
		if curr_size == 0:
			continue
		
		for dir in HexMath.offsets:
			places_to_grow.append([curr_size - 1, curr_coord + dir])

func load_all_possible_tiles(height: int):
	var dir: DirAccess = DirAccess.open(TILES_DIR)
	if dir == null:
		push_error("HexTileRegistry: Cannot open tiles directory: ", TILES_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		# Godot may import .tres files as .tres.remap in exported builds
		if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			var path: String = TILES_DIR + file_name.replace(".remap", "")
			var resource: Resource = ResourceLoader.load(path)
			if resource is HexTile:
				var raised_variants: Array[HexTile] = resource.create_raised_variants(height)
				var rotated_and_raised_variants = raised_variants.map(
					func (raised_variant: HexTile): return raised_variant.create_rotated_variants()
				)
				for inner_array in rotated_and_raised_variants: 
					Solver.all_possible_tiles_master_list.append_array(inner_array)
			else:
				push_warning("HexTileRegistry: Skipping non-HexTileType resource: ", path)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Assign indices and build compatibility lookup table
	for i in range(len(Solver.all_possible_tiles_master_list)):
		Solver.all_possible_tiles_master_list[i].index = i
	_build_compat_table()

static func _build_compat_table():
	var tile_count: int = len(all_possible_tiles_master_list)
	compat_table = []
	for dir: int in range(6):
		var dir_table: Array[Dictionary] = []
		dir_table.resize(tile_count)
		var opposite_dir: int = HexMath.get_opposite_direction(dir)
		for n_idx: int in range(tile_count):
			var compatible: Dictionary = {}
			var n_tile: HexTile = all_possible_tiles_master_list[n_idx]
			var n_edge: HexTile.Edge = n_tile.edges[opposite_dir]
			var n_height: int = n_tile.edge_heights[opposite_dir]
			for c_idx: int in range(tile_count):
				var c_tile: HexTile = all_possible_tiles_master_list[c_idx]
				if n_height != c_tile.edge_heights[dir]:
					continue
				var c_edge: HexTile.Edge = c_tile.edges[dir]

				var cliffs_match: bool = (c_edge == HexTile.Edge.CLIFF_LEFT or c_edge == HexTile.Edge.CLIFF_RIGHT) and (n_edge == HexTile.Edge.CLIFF_LEFT or n_edge == HexTile.Edge.CLIFF_RIGHT) and (n_edge != c_edge)

				var non_cliffs_match: bool = c_edge != HexTile.Edge.CLIFF_LEFT and c_edge != HexTile.Edge.CLIFF_RIGHT and n_edge != HexTile.Edge.CLIFF_LEFT and n_edge != HexTile.Edge.CLIFF_RIGHT and n_edge == c_edge

				if cliffs_match or non_cliffs_match:
					compatible[c_idx] = true
			dir_table[n_idx] = compatible
		compat_table.append(dir_table)

func _setup_grid_recursive(curr: Vector2i, size: int):
	if grid.has(curr):
		return
	
	var cell: Cell = Cell.new()
	cell.coords = curr
	cell.possible_tiles = Solver.all_possible_tiles_master_list.duplicate()
	grid.set(curr, cell)
	
	if size == 0:
		return
	
	for dir in HexMath.offsets:
		_setup_grid_recursive(curr + dir, size - 1)
#endregion

func _apply_constraints() -> bool:
	for coord: Vector2i in constraints:
		var cell: Cell = grid.get(coord)
		if cell == null:
			push_warning("Constraint at ", coord, " is outside the grid, skipping.")
			continue
		cell.possible_tiles = constraints[coord].call(cell.possible_tiles)
		if len(cell.possible_tiles) == 0:
			push_error("Constraint at ", coord, " eliminated all tiles.")
			return false
		if len(cell.possible_tiles) == 1:
			cell.is_collapsed = true
		if !propagate(coord):
			return false
	return true

#region Observe and propagate
func get_lowest_entropy_cell() -> Cell:
	const buffer: float = 2
	var lowest_entropy: float = INF
	var tied_cells: Array[Cell] = []
	
	for cell: Cell in grid.values(): # TODO calling .values() could be expensive
		if cell.is_collapsed:
			continue
		
		var entropy: float = cell.get_entropy()
		if entropy == 0:
			return null
		
		if entropy < lowest_entropy - buffer:
			lowest_entropy = entropy
			tied_cells = [cell]
		elif entropy < lowest_entropy + buffer:
			tied_cells.append(cell)
	
	if len(tied_cells) == 0:
		assert(false, "tied_cells were at 0")
		return 
	
	if len(tied_cells) == 1:
		return tied_cells[0]
	else:
		return tied_cells[randi_range(0, len(tied_cells) - 1)] # Return a random 

func observe() -> bool:
	var lowest_entropy_cell: Cell = get_lowest_entropy_cell()
	if lowest_entropy_cell == null:
		assert(false, "lowest_entropy_cell was null")
		return false
	else:
		lowest_entropy_cell.collapse()
		return propagate(lowest_entropy_cell.coords)
	
func propagate(start_coords: Vector2i) -> bool:
	var propagate_stack: Array[Vector2i] = [start_coords]
	var in_stack: Dictionary = {start_coords: true}

	while len(propagate_stack) != 0:
		var next_coord: Vector2i = propagate_stack.pop_front()
		in_stack.erase(next_coord)
		var next_cell: Cell = grid.get(next_coord)

		# Build current tile index set once per cell
		var current_set: Dictionary = {}
		for tile: HexTile in next_cell.possible_tiles:
			current_set[tile.index] = true

		for dir_index: int in range(6):
			var neighbor_coord: Vector2i = HexMath.get_neighbor(next_coord, dir_index)
			var neighbor_cell: Cell = grid.get(neighbor_coord)
			if neighbor_cell == null:
				continue
			if neighbor_cell.is_collapsed:
				continue

			var matched_tiles: Array[HexTile] = _calc_matched_tiles(
				current_set,
				neighbor_cell.possible_tiles,
				dir_index
			)

			if len(matched_tiles) == len(neighbor_cell.possible_tiles):
				continue
			if len(matched_tiles) == 0:
				print("Cell collapsed to 0")
				return false

			neighbor_cell.possible_tiles = matched_tiles
			if not in_stack.has(neighbor_coord):
				propagate_stack.append(neighbor_coord)
				in_stack[neighbor_coord] = true
			if len(matched_tiles) == 1:
				neighbor_cell.is_collapsed = true
	return true

func _calc_matched_tiles(
	current_set: Dictionary,
	neighbor: Array[HexTile],
	direction_to_neighbor_index: int
) -> Array[HexTile]:
	var dir_table: Array[Dictionary] = Solver.compat_table[direction_to_neighbor_index]
	var new_neighbor: Array[HexTile] = []

	for neighbor_tile: HexTile in neighbor:
		var compatible: Dictionary = dir_table[neighbor_tile.index]
		for c_idx: int in compatible:
			if current_set.has(c_idx):
				new_neighbor.append(neighbor_tile)
				break

	return new_neighbor
#endregion
