## HexWFCManager - Top-level orchestrator for WFC hex map generation.
##
## This is the main node you add to your scene to generate hex-based terrain.
## It handles:
##   - Loading tile definitions from the registry
##   - Creating and running WFC solver instances
##   - Running the solver on a background thread (non-blocking)
##   - Rendering the result as 3D geometry
##   - Multi-chunk generation (multiple hex grids stitched together)
##   - Reporting progress and completion via signals
##
## USAGE:
##   1. Add this node (or its scene) to your Godot scene tree
##   2. Configure @export properties in the inspector (seed, radius, etc.)
##   3. On _ready(), it auto-generates (or call generate() manually)
##   4. Connect to signals for progress updates and completion notification
##
## THREADING MODEL:
##   The WFC solver is pure computation -- no scene tree access, no rendering.
##   It runs on a background Thread so the game doesn't freeze during generation.
##
##   Main Thread                          Background Thread
##   -----------                          -----------------
##   generate() called
##     |-- creates solver(s)
##     |-- Thread.start(_thread_solve) -----> _thread_solve()
##     |                                         |
##     | _process() polls solver.progress        solver.solve()
##     | emits generation_progress               (pure computation)
##     |                                         |
##     |  <-- call_deferred("_on_complete") -----'
##     v
##   _on_solve_complete()
##     |-- thread.wait_to_finish()
##     |-- render_grid() on main thread
##     |-- emit generation_completed
##
##   Thread safety rules:
##   - Solver operates entirely on its own data (no shared state during solving)
##   - Only solver.progress (float) is read from main thread during solve
##   - call_deferred() ensures rendering happens on the main thread
##   - Thread is cleaned up via wait_to_finish() in _on_solve_complete and _exit_tree
##
## MULTI-CHUNK GENERATION:
##   For large maps, the system can generate multiple hex grid "chunks"
##   arranged in a hexagonal pattern:
##     chunk_count=1:  Just the center chunk
##     chunk_count=7:  Center + 6 surrounding chunks (1 ring)
##     chunk_count=19: Center + 6 + 12 chunks (2 rings)
##
##   Chunks are solved sequentially. Each chunk's boundary cells are constrained
##   to match the already-solved neighboring chunks, ensuring seamless terrain.
##
## USED BY:
##   - Add to any scene that needs procedural hex terrain
##   - Works standalone -- no dependencies on other project templates
class_name HexWFCManager
extends Node3D

# -------------------------------------------------------------------
# Editor Configuration
# -------------------------------------------------------------------

## Random seed for deterministic generation. Same seed = same map.
## Set to 0 for a random seed based on system time.
@export var generation_seed: int = 0

## Radius of each hex chunk (number of rings from center).
## radius=5 gives 91 cells per chunk, radius=10 gives 331 cells.
@export var grid_radius: int = 5

## Maximum terrain elevation level. Tiles can be placed from level 0 to this value.
@export var max_level: int = 4

## Outer radius of each hexagon (center to vertex distance in world units).
## Controls how far apart tiles are spaced.
@export var hex_size: float = 1.0

## World-space height per elevation level.
@export var level_height: float = 0.5

## Number of chunks to generate.
## 1 = single grid, 7 = center + ring of 6, 19 = center + 2 rings.
@export_enum("1", "7", "19") var chunk_count: int = 1

## If true, generation starts automatically when the node enters the scene tree.
@export var auto_generate: bool = true

# -------------------------------------------------------------------
# Signals
# -------------------------------------------------------------------

## Emitted when generation begins.
signal generation_started

## Emitted periodically with progress (0.0 to 1.0).
signal generation_progress(percent: float)

## Emitted when generation finishes. success=true if all chunks solved.
signal generation_completed(success: bool)

## Emitted when an individual chunk finishes solving.
signal chunk_completed(chunk_index: int)

# -------------------------------------------------------------------
# Internal State
# -------------------------------------------------------------------

## The tile type registry (loads all .tres tile definitions).
var _registry: HexTileRegistry

## The 3D renderer that converts solved data to scene nodes.
var _renderer: HexTileRenderer

## Solver instances (one per chunk).
var _solvers: Array = []

## Solved result dictionaries (one per chunk).
var _chunk_results: Array = []

## Chunk center positions in cube coordinates.
var _chunk_offsets: Array[Vector3i] = []

## Background thread for solving.
var _thread: Thread

## Whether generation is currently in progress.
var _is_generating: bool = false

## Mutex for thread-safe reads of solver state.
var _mutex: Mutex


func _ready() -> void:
	# Initialize the tile registry (auto-loads all .tres tile definitions)
	_registry = HexTileRegistry.new()

	# Create the renderer as a child node
	_renderer = HexTileRenderer.new()
	_renderer.name = "HexTileRenderer"
	_renderer.hex_size = hex_size
	_renderer.level_height = level_height
	_renderer.initialize(_registry)
	add_child(_renderer)

	_mutex = Mutex.new()

	if auto_generate:
		# Use call_deferred to let the scene tree finish setup first
		call_deferred("generate")


## Starts (or restarts) map generation with current settings.
##
## If generation_seed is 0, a random seed is chosen from the system clock.
## Creates solver(s) for each chunk and runs them on a background thread.
func generate() -> void:
	if _is_generating:
		push_warning("HexWFCManager: Generation already in progress")
		return

	# Pick a seed if none was specified
	var actual_seed: int = generation_seed
	if actual_seed == 0:
		actual_seed = int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF

	print("HexWFCManager: Starting generation with seed %d, radius %d, chunks %d" % [
		actual_seed, grid_radius, chunk_count
	])

	_is_generating = true
	generation_started.emit()

	# Compute chunk layout
	_compute_chunk_offsets()
	_chunk_results.resize(_chunk_offsets.size())
	_solvers.clear()

	# Create a solver for each chunk
	for i: int in _chunk_offsets.size():
		# Each chunk gets a unique seed derived from the base seed
		var chunk_seed: int = actual_seed + i * 7919  # 7919 is prime, ensures distinct seeds
		var solver: HexWFCSolver = HexWFCSolver.new(_registry, chunk_seed, grid_radius, max_level)
		_solvers.append(solver)

	# Start background thread
	_thread = Thread.new()
	_thread.start(_thread_solve)


## Background thread entry point.
## Solves each chunk sequentially. Later chunks are constrained by earlier ones.
func _thread_solve() -> void:
	for i: int in _solvers.size():
		var solver: HexWFCSolver = _solvers[i]

		# Apply boundary constraints from already-solved neighboring chunks
		if i > 0:
			_apply_inter_chunk_constraints(i, solver)

		# Run the solver
		var success: bool = solver.solve()

		_mutex.lock()
		if success:
			_chunk_results[i] = solver.get_result()
			# Validate in debug builds
			if not solver.validate_result():
				push_warning("HexWFCManager: Chunk %d validation failed!" % i)
		else:
			push_error("HexWFCManager: Chunk %d solve FAILED after %d backtracks" % [
				i, solver.backtrack_count
			])
			_chunk_results[i] = {}
		_mutex.unlock()

	# Return to main thread for rendering
	call_deferred("_on_solve_complete")


## Called on the main thread after all chunks are solved.
func _on_solve_complete() -> void:
	# Wait for the thread to finish (should be immediate since we're in deferred)
	if _thread != null:
		_thread.wait_to_finish()

	_is_generating = false

	# Render each chunk
	var any_success: bool = false
	for i: int in _chunk_results.size():
		var chunk_result: Dictionary = _chunk_results[i]
		if chunk_result.size() > 0:
			_renderer.render_grid(chunk_result, _chunk_offsets[i])
			chunk_completed.emit(i)
			any_success = true

	print("HexWFCManager: Generation complete. %d chunks rendered." % _chunk_results.size())
	generation_completed.emit(any_success)


## Polls solver progress each frame for UI updates.
func _process(_delta: float) -> void:
	if not _is_generating or _solvers.size() == 0:
		return

	# Calculate average progress across all solvers
	var total_progress: float = 0.0
	for solver: HexWFCSolver in _solvers:
		total_progress += solver.progress
	generation_progress.emit(total_progress / _solvers.size())


# -------------------------------------------------------------------
# Chunk Layout
# -------------------------------------------------------------------

## Computes the cube coordinate offsets for each chunk center.
##
## chunk_count=1:  [center]
## chunk_count=7:  [center, 6 neighbors at distance grid_diameter]
## chunk_count=19: [center, 6 at distance 1, 12 at distance 2]
##
## The "grid diameter" is 2 * grid_radius + 1 (distance between chunk centers
## so their grids don't overlap).
func _compute_chunk_offsets() -> void:
	_chunk_offsets.clear()
	_chunk_offsets.append(Vector3i.ZERO)  # Center chunk

	if chunk_count <= 1:
		return

	# Chunk spacing in cube coordinates: adjacent chunk centers are separated
	# by grid_diameter cells so their hexagonal grids just touch.
	var spacing: int = 2 * grid_radius + 1

	# Ring 1: 6 neighbors
	if chunk_count >= 7:
		for dir: int in HexDirection.COUNT:
			var offset: Vector3i = HexCoords.DIRECTION_VECTORS[dir] * spacing
			_chunk_offsets.append(offset)

	# Ring 2: 12 chunks at distance 2
	if chunk_count >= 19:
		# Corners of ring 2 (directly behind each ring-1 chunk)
		for dir: int in HexDirection.COUNT:
			var offset: Vector3i = HexCoords.DIRECTION_VECTORS[dir] * spacing * 2
			_chunk_offsets.append(offset)
		# Edges of ring 2 (between adjacent ring-1 chunks)
		for dir: int in HexDirection.COUNT:
			var next_dir: int = (dir + 1) % HexDirection.COUNT
			var offset: Vector3i = (
				HexCoords.DIRECTION_VECTORS[dir] * spacing +
				HexCoords.DIRECTION_VECTORS[next_dir] * spacing
			)
			_chunk_offsets.append(offset)


## Applies boundary constraints from already-solved chunks to a new chunk.
##
## For each boundary cell of the new chunk, check if any neighboring cell
## belongs to an already-solved chunk. If so, constrain the boundary cell
## to only states compatible with the solved neighbor's edges.
func _apply_inter_chunk_constraints(chunk_index: int, solver: HexWFCSolver) -> void:
	var my_offset: Vector3i = _chunk_offsets[chunk_index]
	var boundary_coords: Array[Vector3i] = solver.grid.get_boundary_coords()

	for local_coords: Vector3i in boundary_coords:
		# Convert to global cube coordinates
		var global_coords: Vector3i = local_coords + my_offset

		# Check each direction for a solved neighbor in another chunk
		for dir: int in HexDirection.ALL:
			var neighbor_global: Vector3i = HexCoords.neighbor(global_coords, dir)

			# Find which chunk (if any) this neighbor belongs to
			for other_idx: int in chunk_index:
				var other_offset: Vector3i = _chunk_offsets[other_idx]
				var other_result: Dictionary = _chunk_results[other_idx]
				if other_result.is_empty():
					continue

				# Convert neighbor global coords to the other chunk's local coords
				var other_local: Vector3i = neighbor_global - other_offset
				if not other_result.has(other_local):
					continue

				# Found a solved neighbor! Constrain our boundary cell.
				var neighbor_data: Dictionary = other_result[other_local]
				var neighbor_state: HexTileState = HexTileState.new(
					neighbor_data["tile_type_id"],
					neighbor_data["rotation"],
					neighbor_data["level"]
				)
				var neighbor_key: int = neighbor_state.get_key()

				# Get the neighbor's edge in our direction (opposite of dir)
				var opposite_dir: int = HexDirection.opposite(dir)
				var edge_info: Variant = solver.adjacency.get_state_edge(neighbor_key, opposite_dir)
				if edge_info == null:
					continue

				# Find all states compatible with this edge
				var compatible: PackedInt32Array = solver.adjacency.get_compatible_states(
					edge_info["type"], dir, edge_info["level"]
				)

				# Set boundary constraint
				solver.set_boundary_constraint(local_coords, compatible)


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

## Clears the rendered map and regenerates with a new random seed.
func regenerate() -> void:
	_renderer.clear()
	generation_seed = 0  # Force new random seed
	generate()


## Clears the rendered map and regenerates with a specific seed.
func regenerate_with_seed(new_seed: int) -> void:
	_renderer.clear()
	generation_seed = new_seed
	generate()


## Returns true if generation is currently in progress.
func is_generating() -> bool:
	return _is_generating


# -------------------------------------------------------------------
# Cleanup
# -------------------------------------------------------------------

## Ensures the background thread is properly cleaned up when the node exits.
## Without this, Godot would crash if the scene changes while solving.
func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
