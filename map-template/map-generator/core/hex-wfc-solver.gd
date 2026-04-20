## HexWFCSolver - The core Wave Function Collapse solver for hexagonal grids.
##
## This is the heart of the map generation system. It takes a set of tile
## definitions and produces a fully-collapsed hex grid where every tile's
## edges match its neighbors' edges -- creating coherent terrain.
##
## ============================================================================
## WAVE FUNCTION COLLAPSE ALGORITHM OVERVIEW
## ============================================================================
##
## WFC is a constraint satisfaction algorithm inspired by quantum mechanics.
## Each cell starts in a "superposition" of all possible states (like a quantum
## particle that hasn't been observed yet). The algorithm repeatedly:
##
##   1. OBSERVE: Pick the most constrained cell (lowest entropy) and "collapse"
##      it to one specific state (weighted random choice).
##
##   2. PROPAGATE: The collapse constrains neighboring cells. Remove any neighbor
##      states that are incompatible with the collapsed cell's edges. Those
##      removals may further constrain THEIR neighbors, cascading outward.
##
##   3. REPEAT: Go back to step 1 until all cells are collapsed.
##
##   4. BACKTRACK: If propagation creates a contradiction (a cell with zero
##      possibilities), undo the last collapse decision and try a different state.
##
## ============================================================================
## DETAILED ALGORITHM STEPS
## ============================================================================
##
## INITIALIZATION:
##   - Create a HexGrid with all cell positions
##   - For each cell, set possibilities = ALL valid state keys
##   - A state key encodes (tile_type, rotation, level) as a single int
##   - Apply any boundary constraints (for multi-chunk generation)
##
## MAIN LOOP:
##   while true:
##     1. Find the uncollapsed cell with the lowest entropy.
##        If no uncollapsed cells remain -> SUCCESS (all collapsed).
##
##     2. Record a decision checkpoint (for backtracking).
##
##     3. Collapse the cell: pick one state via weighted random selection.
##        Higher-weight tiles (like grass) are more likely to be chosen.
##
##     4. Propagate constraints:
##        - Push the collapsed cell onto a propagation queue
##        - While queue is not empty:
##          - Pop a cell from the queue
##          - For each of its 6 neighbors:
##            - Compute which states are ALLOWED in the neighbor
##              (based on what edges the current cell's states expose)
##            - Remove any neighbor states not in the allowed set
##            - If the neighbor was modified, push it onto the queue
##            - If the neighbor has ZERO possibilities -> CONTRADICTION
##
##     5. If contradiction:
##        - Call backtracker to undo to last decision
##        - Try a different state for that cell
##        - If all states exhausted, backtrack further up the stack
##        - If can't backtrack at all -> FAILURE (restart with different seed)
##
## ============================================================================
## PERFORMANCE NOTES
## ============================================================================
##
## - The adjacency index provides O(1) edge compatibility lookups
## - State keys are packed integers for fast Dictionary operations
## - Possibilities are PackedInt32Array (contiguous memory, no Variant boxing)
## - The solver is designed to run on a background Thread
## - For a radius-5 grid (91 cells) with 12 tile types, expect ~360 states/cell
##   and solve times under 100ms
##
## ============================================================================
## REFERENCE
## ============================================================================
##
## Based on the WFC implementation in https://github.com/felixturner/hex-map-wfc
## Specifically the wfc.worker.js file which contains the solve loop,
## HexWFCCore.js which contains cell and adjacency rule classes.
##
## USED BY:
##   - HexWFCManager: creates solver instances and runs them on background threads
class_name HexWFCSolver
extends RefCounted

## Solve status codes.
enum Status {
	IDLE = 0,        ## Solver hasn't started yet.
	RUNNING = 1,     ## Solver is currently running.
	COMPLETE = 2,    ## Solver finished successfully -- all cells collapsed.
	FAILED = 3,      ## Solver failed -- contradiction with no backtrack possible.
}

## Maximum number of backtracks before we give up on this attempt.
## Prevents infinite loops on unsolvable configurations.
const MAX_BACKTRACK_COUNT: int = 10000

# -------------------------------------------------------------------
# Configuration (set during _init, read-only during solve)
# -------------------------------------------------------------------

## The tile registry containing all tile type definitions.
var registry: HexTileRegistry

## Precomputed adjacency rules for fast constraint lookups.
var adjacency: HexWFCAdjacency

## Deterministic random number generator (seeded for reproducibility).
var rng: SeededRandom

## The hex grid containing all cells.
var grid: HexGrid

## Trail-based backtracking manager.
var backtracker: HexWFCBacktracker

## Maximum terrain elevation level.
var max_level: int = 4

# -------------------------------------------------------------------
# Precomputed data (built during _init for solver performance)
# -------------------------------------------------------------------

## All valid state keys in the system.
var _all_state_keys: PackedInt32Array

## State key -> weight mapping for fast entropy and weighted selection.
var _state_weights: Dictionary

# -------------------------------------------------------------------
# Runtime state (used during solve)
# -------------------------------------------------------------------

## Queue of cells whose neighbors need constraint checking.
## Front-popped during propagation (FIFO order).
var _propagation_queue: Array[Vector3i] = []

## External boundary constraints for multi-chunk generation.
## Maps cube coords -> PackedInt32Array of allowed state keys.
## Cells with boundary constraints start with restricted possibilities.
var _boundary_constraints: Dictionary = {}

# -------------------------------------------------------------------
# Status (readable from main thread during background solve)
# -------------------------------------------------------------------

## Current solver status (see Status enum).
var status: int = Status.IDLE

## Solve progress from 0.0 (just started) to 1.0 (all cells collapsed).
var progress: float = 0.0

## Number of cells successfully collapsed so far.
var collapse_count: int = 0

## Number of times the solver had to backtrack.
var backtrack_count: int = 0


## Creates and initializes a new solver.
##
## Parameters:
##   _registry: Tile registry with all tile type definitions
##   _seed: Random seed for deterministic generation
##   _radius: Hex grid radius (number of rings from center)
##   _max_level: Maximum terrain elevation (0 to _max_level)
func _init(_registry: HexTileRegistry, _seed: int, _radius: int, _max_level: int = 4) -> void:
	registry = _registry
	rng = SeededRandom.new(_seed)
	max_level = _max_level
	grid = HexGrid.new(_radius)
	backtracker = HexWFCBacktracker.new()

	# Build the adjacency index (this precomputes all edge compatibility rules)
	adjacency = HexWFCAdjacency.new()
	adjacency.build(registry, max_level)

	# Cache state keys and weights for fast access during solving
	_all_state_keys = adjacency.get_all_state_keys()
	_state_weights = adjacency.get_state_weights()


## Adds a boundary constraint for multi-chunk generation.
## Boundary cells will start with only these allowed states instead of all states.
##
## Parameters:
##   coords: Cube coordinates of the boundary cell
##   allowed_states: PackedInt32Array of state keys this cell may collapse to
func set_boundary_constraint(coords: Vector3i, allowed_states: PackedInt32Array) -> void:
	_boundary_constraints[coords] = allowed_states


# ===================================================================
# MAIN SOLVE ENTRY POINT
# ===================================================================

## Runs the complete WFC solve algorithm. This is typically called from a
## background thread via HexWFCManager.
##
## Returns true on success (all cells collapsed), false on failure.
##
## The solve loop:
##   1. Initialize all cells with all possible states
##   2. Apply boundary constraints (if multi-chunk)
##   3. Loop: observe (collapse lowest entropy cell) -> propagate -> backtrack if needed
##   4. Repeat until all collapsed or unrecoverable contradiction
func solve() -> bool:
	status = Status.RUNNING
	collapse_count = 0
	backtrack_count = 0

	# STEP 1: Initialize the grid with all cell positions and full possibility sets
	_initialize_cells()

	# STEP 2: Apply boundary constraints from neighboring chunks
	_apply_boundary_constraints()

	var total_cells: int = grid.get_cell_count()

	# STEP 3: Main WFC loop -- observe, propagate, backtrack
	while true:
		# 3a. Find the uncollapsed cell with the lowest entropy
		var target_coords: Variant = _find_lowest_entropy_cell()

		# If no uncollapsed cells remain, we're done!
		if target_coords == null:
			status = Status.COMPLETE
			return true

		# 3b. Record decision checkpoint (for backtracking)
		var cell: HexWFCCell = grid.get_cell(target_coords)
		backtracker.push_decision(target_coords, cell.possibilities)

		# 3c. Collapse this cell to a weighted random state
		var collapse_ok: bool = _collapse_cell(target_coords)
		if not collapse_ok:
			# Cell had no possibilities -- contradiction before we even started
			if not _backtrack():
				status = Status.FAILED
				return false
			continue

		# 3d. Propagate constraints to neighbors
		_propagation_queue.clear()
		_propagation_queue.append(target_coords)
		var propagate_ok: bool = _propagate()

		if not propagate_ok:
			# Propagation hit a contradiction -- try backtracking
			if not _backtrack():
				status = Status.FAILED
				return false
			# Backtrack succeeded, continue the main loop
			continue

		# Update progress
		collapse_count += 1
		progress = float(collapse_count) / float(total_cells)

	# Should never reach here, but just in case
	status = Status.FAILED
	return false


# ===================================================================
# INITIALIZATION
# ===================================================================

## Creates all cells in the grid, each initialized with all possible states.
func _initialize_cells() -> void:
	grid.initialize_positions()
	for coords: Vector3i in grid.get_all_coords():
		var cell: HexWFCCell = HexWFCCell.new(coords, _all_state_keys, _state_weights)
		grid.set_cell(coords, cell)


## Applies boundary constraints from neighboring chunks.
##
## For multi-chunk generation, edge cells of this chunk must match the
## already-solved cells of adjacent chunks. This restricts their initial
## possibilities to only compatible states.
func _apply_boundary_constraints() -> void:
	for coords: Vector3i in _boundary_constraints:
		if not grid.has_cell(coords):
			continue
		var cell: HexWFCCell = grid.get_cell(coords)
		var allowed: PackedInt32Array = _boundary_constraints[coords]

		# Remove any possibilities not in the allowed set
		var allowed_set: Dictionary = {}
		for key: int in allowed:
			allowed_set[key] = true

		var to_remove: PackedInt32Array = PackedInt32Array()
		for key: int in cell.possibilities:
			if not allowed_set.has(key):
				to_remove.append(key)

		for key: int in to_remove:
			cell.remove_possibility(key, _state_weights)

		# If this constraint collapsed the cell, propagate from it
		if cell.collapsed:
			_propagation_queue.append(coords)

	# Run initial propagation from boundary-constrained cells
	if _propagation_queue.size() > 0:
		_propagate()


# ===================================================================
# OBSERVE (COLLAPSE)
# ===================================================================

## Finds the uncollapsed cell with the lowest entropy.
##
## The minimum entropy heuristic ensures we collapse the most constrained
## cells first. This reduces the search space and minimizes contradictions.
##
## A small random noise is added to break ties between cells with identical
## entropy, preventing systematic bias in collapse order.
##
## Returns the cube coordinates of the chosen cell, or null if all collapsed.
func _find_lowest_entropy_cell() -> Variant:
	var min_entropy: float = INF
	var min_coords: Variant = null

	for coords: Variant in grid.get_all_coords():
		var cell: HexWFCCell = grid.get_cell(coords)
		if cell == null or cell.collapsed:
			continue

		# Skip cells that are already contradictions
		if cell.possibilities.size() == 0:
			continue

		var entropy: float = cell.get_entropy_with_noise(rng)
		if entropy < min_entropy:
			min_entropy = entropy
			min_coords = coords

	return min_coords


## Collapses a cell to a single weighted-random state.
##
## The weight of each possible state determines how likely it is to be chosen.
## High-weight tiles (like grass at 500) dominate, while rare tiles (like
## road-T at 10) appear sparingly.
##
## Parameters:
##   coords: Cube coordinates of the cell to collapse
## Returns:
##   true if collapse succeeded, false if cell had no possibilities
func _collapse_cell(coords: Vector3i) -> bool:
	var cell: HexWFCCell = grid.get_cell(coords)
	if cell.possibilities.size() == 0:
		return false

	# Build weights array for weighted selection
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(cell.possibilities.size())
	for i: int in cell.possibilities.size():
		weights[i] = _state_weights.get(cell.possibilities[i], 1.0)

	# Weighted random choice
	var chosen_key: int = rng.weighted_choice(cell.possibilities, weights)

	# Record all removed states in the trail (everything except the chosen state)
	for key: int in cell.possibilities:
		if key != chosen_key:
			backtracker.record_removal(coords, key)

	# Collapse the cell
	cell.collapse(chosen_key)
	backtracker.mark_tried(chosen_key)

	return true


# ===================================================================
# PROPAGATE (CONSTRAINT PROPAGATION)
# ===================================================================

## Queue-based constraint propagation.
##
## Starting from recently-changed cells, this checks each neighbor to see if
## any of its possibilities have become incompatible. Incompatible states are
## removed, and if a neighbor's possibilities change, IT is also added to the
## queue for further propagation. This cascading effect is what makes WFC
## produce globally-coherent output from local rules.
##
## THE KEY LOGIC:
## For each neighbor in each direction:
##   1. For each state still possible in the current cell, look up what edge
##      it exposes in this direction and find all compatible states for the neighbor.
##   2. The UNION of all those compatible states is the "allowed set" for the neighbor.
##   3. Remove any neighbor states NOT in the allowed set.
##   4. If the neighbor was modified, add it to the queue.
##   5. If the neighbor has zero possibilities, we have a CONTRADICTION.
##
## Returns true if propagation completed without contradictions.
## Returns false if a contradiction was found (some cell has zero possibilities).
func _propagate() -> bool:
	while _propagation_queue.size() > 0:
		var current_coords: Vector3i = _propagation_queue.pop_front()
		var current_cell: HexWFCCell = grid.get_cell(current_coords)

		if current_cell == null:
			continue

		# Check each of the 6 neighbors
		for dir: int in HexDirection.ALL:
			var neighbor_coords: Vector3i = grid.get_neighbor_coords(current_coords, dir)
			var neighbor_cell: Variant = grid.get_neighbor_cell(current_coords, dir)

			# Skip if neighbor is outside the grid or already collapsed
			if neighbor_cell == null or neighbor_cell.collapsed:
				continue

			# Build the ALLOWED SET: all states that are compatible with
			# at least one of the current cell's remaining possibilities.
			var opposite_dir: int = HexDirection.opposite(dir)
			var allowed_set: Dictionary = {}  # Using Dictionary as a Set for O(1) lookup

			for state_key: int in current_cell.possibilities:
				# What edge does this state expose in this direction?
				var edge_info: Variant = adjacency.get_state_edge(state_key, dir)
				if edge_info == null:
					continue

				# Find all states that have a compatible edge in the opposite direction
				var compatible: PackedInt32Array = adjacency.get_compatible_states(
					edge_info["type"], opposite_dir, edge_info["level"]
				)
				for compat_key: int in compatible:
					allowed_set[compat_key] = true

			# Remove any neighbor states not in the allowed set
			var changed: bool = false
			var to_remove: PackedInt32Array = PackedInt32Array()

			for state_key: int in neighbor_cell.possibilities:
				if not allowed_set.has(state_key):
					to_remove.append(state_key)

			for key: int in to_remove:
				backtracker.record_removal(neighbor_coords, key)
				neighbor_cell.remove_possibility(key, _state_weights)
				changed = true

			# Check for contradiction (zero possibilities)
			if neighbor_cell.is_contradiction():
				return false  # CONTRADICTION -- caller must backtrack

			# If neighbor was modified, add it to propagation queue
			# so its own neighbors get checked too (cascading propagation)
			if changed:
				_propagation_queue.append(neighbor_coords)

	return true  # All propagation completed without contradiction


# ===================================================================
# BACKTRACK
# ===================================================================

## Attempts to backtrack from a contradiction by undoing the last decision
## and trying a different state.
##
## The backtracking process:
##   1. Pop the last decision from the stack
##   2. Undo all state removals that happened after that decision (via trail)
##   3. Restore the collapsed cell to its pre-collapse possibilities
##   4. Exclude the state we already tried (it led to contradiction)
##   5. Pick a new state from the remaining untried possibilities
##   6. Propagate from the new choice
##   7. If no untried states remain, pop further up the stack (recursive backtrack)
##
## Returns true if backtracking succeeded and the solver can continue.
## Returns false if the decision stack is exhausted (unrecoverable failure).
func _backtrack() -> bool:
	if not backtracker.can_backtrack():
		return false

	backtrack_count += 1

	# Safety check: too many backtracks means the tile configuration
	# is very constrained or contradictory. Give up and let the manager retry.
	if backtrack_count > MAX_BACKTRACK_COUNT:
		push_warning("HexWFCSolver: Exceeded max backtrack count (%d). Giving up." % MAX_BACKTRACK_COUNT)
		return false

	# Clear the propagation queue -- we're rewinding
	_propagation_queue.clear()

	# Undo the last decision: restore all removed states
	var decision: Dictionary = backtracker.pop_and_undo(grid.cells, _state_weights)
	if decision.is_empty():
		return false

	# Get states we haven't tried yet for this decision
	var untried: PackedInt32Array = backtracker.get_untried_states(decision)

	if untried.size() == 0:
		# All states for this decision have been tried and failed.
		# Backtrack further up the stack.
		return _backtrack()

	# Re-push this decision (with its tried_states updated) and try a new state
	var target_coords: Vector3i = decision["target_coords"]
	var cell: HexWFCCell = grid.get_cell(target_coords)

	# Push a new decision with the already-tried states carried over
	backtracker.push_decision(target_coords, cell.possibilities)
	for tried_key: Variant in decision["tried_states"]:
		backtracker.mark_tried(tried_key)

	# Collapse to a new untried state
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(untried.size())
	for i: int in untried.size():
		weights[i] = _state_weights.get(untried[i], 1.0)
	var chosen_key: int = rng.weighted_choice(untried, weights)

	# Record removals for all non-chosen states
	for key: int in cell.possibilities:
		if key != chosen_key:
			backtracker.record_removal(target_coords, key)

	cell.collapse(chosen_key)
	backtracker.mark_tried(chosen_key)

	# Propagate from the new choice
	_propagation_queue.clear()
	_propagation_queue.append(target_coords)
	var propagate_ok: bool = _propagate()

	if not propagate_ok:
		# New choice also led to contradiction -- backtrack again
		return _backtrack()

	return true


# ===================================================================
# RESULT EXTRACTION
# ===================================================================

## Extracts the final solved grid as a result dictionary.
##
## Returns a Dictionary mapping cube coordinates (Vector3i) to tile data:
##   {
##     Vector3i(q, r, s): {
##       "tile_type_id": int,   # Index into tile registry
##       "rotation": int,       # 0-5 (60-degree steps)
##       "level": int,          # Elevation (0 to max_level)
##     },
##     ...
##   }
##
## Only collapsed cells are included. If the solve failed partway through,
## only the successfully collapsed cells appear in the result.
func get_result() -> Dictionary:
	var result: Dictionary = {}
	for coords: Variant in grid.get_all_coords():
		var cell: HexWFCCell = grid.get_cell(coords)
		if cell != null and cell.collapsed:
			var state: HexTileState = HexTileState.from_key(cell.collapsed_state_key)
			result[coords] = {
				"tile_type_id": state.tile_type_id,
				"rotation": state.rotation,
				"level": state.level,
			}
	return result


## Validates the solved grid by checking that all adjacent edges match.
## Returns true if all edges are compatible, false if any mismatch is found.
## Useful for debugging the solver and tile definitions.
func validate_result() -> bool:
	var valid: bool = true
	for coords: Variant in grid.get_all_coords():
		var cell: HexWFCCell = grid.get_cell(coords)
		if cell == null or not cell.collapsed:
			continue

		var my_state_key: int = cell.collapsed_state_key

		for dir: int in HexDirection.ALL:
			var neighbor_cell: Variant = grid.get_neighbor_cell(coords, dir)
			if neighbor_cell == null or not neighbor_cell.collapsed:
				continue

			var neighbor_state_key: int = neighbor_cell.collapsed_state_key

			# Get my edge in this direction
			var my_edge: Variant = adjacency.get_state_edge(my_state_key, dir)
			# Get neighbor's edge in the opposite direction
			var neighbor_edge: Variant = adjacency.get_state_edge(
				neighbor_state_key, HexDirection.opposite(dir)
			)

			if my_edge == null or neighbor_edge == null:
				push_error("Validation: Missing edge info at %s dir %d" % [str(coords), dir])
				valid = false
				continue

			# Check edge compatibility
			var types_match: bool = my_edge["type"] == neighbor_edge["type"]
			var levels_match: bool = my_edge["level"] == neighbor_edge["level"]
			var is_agnostic: bool = HexEdgeType.is_level_agnostic(my_edge["type"])

			if not types_match or (not levels_match and not is_agnostic):
				push_error("Validation FAIL at %s dir %s: edge %s@%d vs %s@%d" % [
					str(coords), HexDirection.dir_name(dir),
					HexEdgeType.type_name(my_edge["type"]), my_edge["level"],
					HexEdgeType.type_name(neighbor_edge["type"]), neighbor_edge["level"],
				])
				valid = false

	return valid
