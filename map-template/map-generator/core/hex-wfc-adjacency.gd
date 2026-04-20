## HexWFCAdjacency - Precomputed adjacency rule index for fast WFC constraint propagation.
##
## This is the "brain" of the constraint system. It precomputes which states are
## compatible with which other states, indexed for O(1) lookup during solving.
##
## THE PROBLEM IT SOLVES:
## During constraint propagation, the solver needs to answer this question millions
## of times: "Given that cell A has state S, and cell B is in direction D from A,
## which states can cell B have?"
##
## Without precomputation, answering this requires:
##   1. Get state S's edge type in direction D
##   2. For every possible state in cell B, get its edge in the opposite direction
##   3. Check if the two edges are compatible (same type and level)
## This is O(N) per query where N = number of possible states.
##
## WITH precomputation (this class):
##   1. Get state S's edge info in direction D -> O(1) dictionary lookup
##   2. Look up all compatible states by (edge_type, opposite_direction, level) -> O(1)
## This is O(1) per query, which is critical for performance.
##
## HOW THE INDEX IS BUILT:
## For each tile type × valid rotation × level:
##   1. Create the state key (packed int)
##   2. For each of the 6 directions, compute what edge type this state exposes
##      (applying rotation to the tile's base edges)
##   3. Compute the edge's level (base level, or base+1 if this direction is a high_edge)
##   4. Store in _state_edges: state_key -> { dir -> { type, level } }
##   5. Store in _index: edge_type -> direction -> level -> [list of state keys]
##
## EDGE COMPATIBILITY RULE (from reference implementation):
##   Two adjacent cells are compatible if:
##     - Their touching edges have the SAME type AND the SAME level
##     - EXCEPTION: GRASS edges match at ANY level (level-agnostic)
##
##   This means when building the index for GRASS edges, we add the state to
##   ALL levels in the index, not just its own level.
##
## PREVENT_CHAINING:
## If a tile type has prevent_chaining=true, it cannot be placed adjacent to
## another tile of the same type. This is handled during propagation by the
## solver (not in this index), since it's a state-pair constraint rather than
## an edge-type constraint.
##
## USED BY:
##   - HexWFCSolver._propagate(): looks up compatible states during propagation
##   - HexWFCSolver._initialize_cells(): gets all valid state keys
class_name HexWFCAdjacency
extends RefCounted

## Primary lookup index.
## Structure: _index[edge_type_int][direction_int][level_int] = PackedInt32Array of state keys
##
## Given an edge type, the direction that edge faces, and the level, this returns
## all state keys that have a matching edge. This is the key data structure that
## makes constraint propagation fast.
##
## Example lookup: _index[ROAD][E][0] = all states with a ROAD edge facing East at level 0
var _index: Dictionary = {}

## Per-state edge information.
## Structure: _state_edges[state_key][direction_int] = { "type": int, "level": int }
##
## For a given state (tile+rotation+level), this tells you what edge type and
## level it exposes in each direction. Used by the solver to figure out what
## constraints to propagate.
var _state_edges: Dictionary = {}

## All valid state keys generated during build.
var _all_state_keys: PackedInt32Array = PackedInt32Array()

## Mapping from state key to its weight (from tile definition).
## Precomputed for fast entropy calculation.
var _state_weights: Dictionary = {}

## The maximum level used during build.
var _max_level: int = 4


## Builds the complete adjacency index from the tile registry.
##
## This must be called before the solver can run. It enumerates every valid
## (tile_type, rotation, level) combination, computes edge info, and builds
## the lookup indices.
##
## Parameters:
##   registry: The tile registry containing all tile type definitions
##   max_level: Maximum terrain elevation level (0 to max_level inclusive)
func build(registry: HexTileRegistry, max_level: int) -> void:
	_max_level = max_level
	_index.clear()
	_state_edges.clear()
	_state_weights.clear()
	var all_keys: Array[int] = []

	# Enumerate all valid states
	for tile: HexTileType in registry.get_all_tiles():
		var valid_rotations: Array[int] = tile.get_valid_rotations()

		for rotation: int in valid_rotations:
			# Determine valid level range for this tile
			# Tiles with level_increment can't be at the max level (nowhere to go up)
			var max_tile_level: int = max_level - tile.level_increment
			if max_tile_level < 0:
				continue  # This tile can't fit at any level

			for level: int in range(0, max_tile_level + 1):
				var state: HexTileState = HexTileState.new(tile.tile_id, rotation, level)
				var key: int = state.get_key()
				all_keys.append(key)
				_state_weights[key] = tile.weight

				# Compute edge info for all 6 directions
				var edges_info: Dictionary = {}
				var rotated_edges: Dictionary = tile.get_rotated_edges(rotation)

				for dir: int in HexDirection.ALL:
					var edge_type: int = rotated_edges.get(dir, HexEdgeType.Type.GRASS)

					# Compute edge level: base level, or +level_increment if this is a high edge.
					# High edges are specified at rotation=0, so we need to rotate them too.
					var edge_level: int = level
					for high_dir: int in tile.high_edges:
						var rotated_high_dir: int = HexDirection.rotate(high_dir, rotation)
						if rotated_high_dir == dir:
							edge_level = level + tile.level_increment
							break

					edges_info[dir] = { "type": edge_type, "level": edge_level }

					# Add this state to the index
					_add_to_index(edge_type, dir, edge_level, key)

					# For GRASS (level-agnostic), also add to all OTHER levels
					# so that grass at level 0 can match grass at level 2, etc.
					if HexEdgeType.is_level_agnostic(edge_type):
						for other_level: int in range(0, max_level + 1):
							if other_level != edge_level:
								_add_to_index(edge_type, dir, other_level, key)

				_state_edges[key] = edges_info

	# Convert all index entries from Array (used during build for reference semantics)
	# to PackedInt32Array (used during solve for fast iteration).
	_convert_index_to_packed()

	_all_state_keys = PackedInt32Array(all_keys)
	print("HexWFCAdjacency: Built index with %d states from %d tile types" % [
		_all_state_keys.size(), registry.get_tile_count()
	])


## Returns all state keys that have a compatible edge for the given parameters.
##
## This is the primary query used during constraint propagation:
## "Which states have an edge of type X, facing direction D, at level L?"
##
## Parameters:
##   edge_type: The edge type to match (HexEdgeType.Type value)
##   direction: The direction the edge must face (HexDirection.Dir value)
##   level: The level the edge must be at
## Returns:
##   PackedInt32Array of compatible state keys (empty if none)
func get_compatible_states(edge_type: int, direction: int, level: int) -> PackedInt32Array:
	var by_dir: Dictionary = _index.get(edge_type, {})
	var by_level: Dictionary = by_dir.get(direction, {})
	return by_level.get(level, PackedInt32Array())


## Returns the edge info for a specific state in a specific direction.
##
## Returns a Dictionary with "type" (edge type int) and "level" (edge level int).
## Returns null if the state key is not in the index.
func get_state_edge(state_key: int, direction: int) -> Variant:
	var edges: Dictionary = _state_edges.get(state_key, {})
	return edges.get(direction)


## Returns all valid state keys that were generated during build().
func get_all_state_keys() -> PackedInt32Array:
	return _all_state_keys


## Returns the precomputed weight for a state key.
func get_state_weight(state_key: int) -> float:
	return _state_weights.get(state_key, 1.0)


## Returns the full state_key -> weight mapping dictionary.
func get_state_weights() -> Dictionary:
	return _state_weights


## Converts all Array entries in the index to PackedInt32Array after build is complete.
## Array is a reference type (needed during build so nested dict appends work),
## but PackedInt32Array is faster for iteration during the solve phase.
func _convert_index_to_packed() -> void:
	for edge_type: int in _index:
		for direction: int in _index[edge_type]:
			for level: int in _index[edge_type][direction]:
				var arr: Array = _index[edge_type][direction][level]
				_index[edge_type][direction][level] = PackedInt32Array(arr)


## Adds a state key to the index at the given (edge_type, direction, level) position.
##
## IMPORTANT: We use Array (reference type) internally during build, NOT PackedInt32Array.
## PackedInt32Array is a value type in GDScript -- accessing it from a nested Dictionary
## returns a COPY, so dict[a][b][c].append(x) silently discards the change.
## After build completes, we convert to PackedInt32Array for fast iteration during solving.
func _add_to_index(edge_type: int, direction: int, level: int, state_key: int) -> void:
	if not _index.has(edge_type):
		_index[edge_type] = {}
	if not _index[edge_type].has(direction):
		_index[edge_type][direction] = {}
	if not _index[edge_type][direction].has(level):
		# Use Array (reference type) so nested dict access + append works correctly
		_index[edge_type][direction][level] = []

	# Avoid duplicates (can happen with level-agnostic edges)
	var arr: Array = _index[edge_type][direction][level]
	if state_key in arr:
		return
	arr.append(state_key)
