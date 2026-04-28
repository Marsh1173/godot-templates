class_name Solver
extends RefCounted

var grid: Dictionary[Vector2i, Cell] = {}
static var all_possible_tiles_master_list: Array[HexTile]= []
const TILES_DIR: String = "res://map-template/map-generator/tiles/"

func solve(size: int, height: int) -> bool:
	setup_grid(size, height)
	
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
	is_on_first_cell = true
	
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

#region Observe and propagate
func get_lowest_entropy_cell() -> Cell:
	var lowest_entropy: float = INF
	var tied_cells: Array[Cell] = []
	
	for cell: Cell in grid.values(): # TODO calling .values() could be expensive
		if cell.is_collapsed:
			continue
		
		var entropy: float = cell.get_entropy()
		if entropy == 0:
			return null
		
		if entropy < lowest_entropy - 0.5:
			lowest_entropy = entropy
			tied_cells = [cell]
		elif entropy < lowest_entropy + 0.5:
			tied_cells.append(cell)
	
	if len(tied_cells) == 0:
		assert(false, "tied_cells were at 0")
		return 
	
	if len(tied_cells) == 1:
		return tied_cells[0]
	else:
		return tied_cells[randi_range(0, len(tied_cells) - 1)] # Return a random 

var is_on_first_cell: bool = true

func observe() -> bool:
	var lowest_entropy_cell: Cell = get_lowest_entropy_cell()
	if lowest_entropy_cell == null:
		assert(false, "lowest_entropy_cell was null")
		return false
	else:
		lowest_entropy_cell.collapse()
		if is_on_first_cell:
			# Start on y = 0
			lowest_entropy_cell.possible_tiles[0].reset_edge_heights()
			is_on_first_cell = false
		return propagate(lowest_entropy_cell.coords)
	
func propagate(start_coords: Vector2i) -> bool:
	var propagate_stack: Array[Vector2i] = [start_coords]
	
	while len(propagate_stack) != 0:
		var next_coord: Vector2i = propagate_stack.pop_front()
		var next_cell: Cell = grid.get(next_coord)
		
		for dir_index in range(len(HexMath.offsets)):
			var neighbor_coord: Vector2i = HexMath.get_neighbor(next_coord, dir_index)
			var neighbor_cell: Cell = grid.get(neighbor_coord)
			if neighbor_cell == null:
				continue
			if neighbor_cell.is_collapsed:
				continue
			
			var matched_tiles = calc_matched_tiles(
				next_cell.possible_tiles,
				neighbor_cell.possible_tiles,
				dir_index
			)
			
			if len(matched_tiles) == len(neighbor_cell.possible_tiles):
				continue
			if len(matched_tiles) == 0:
				print("Cell collapsed to 0")
				return false # Collapsed
			
			neighbor_cell.possible_tiles = matched_tiles
			propagate_stack.append(neighbor_coord)
			if len(matched_tiles) == 1:
				neighbor_cell.is_collapsed = true
	return true

func calc_matched_tiles(
	current_tiles: Array[HexTile],
	neighbor: Array[HexTile],
	direction_to_neighbor_index: int
) -> Array[HexTile]:
	var opposite_dir: int = HexMath.get_opposite_direction(direction_to_neighbor_index)
	var new_neighbor: Array[HexTile] = []
	
	for neighbor_tile: HexTile in neighbor:
		for current_tile: HexTile in current_tiles:
			if neighbor_tile.edges[opposite_dir] == current_tile.edges[direction_to_neighbor_index] and\
			neighbor_tile.edge_heights[opposite_dir] == current_tile.edge_heights[direction_to_neighbor_index]:
				new_neighbor.append(neighbor_tile)
				break
	
	return new_neighbor
#endregion
