## HexWFCCell - Represents a single cell in the WFC grid during solving.
##
## Each cell starts with ALL possible states (every tile type x rotation x level
## combination) and gradually has possibilities removed as constraints propagate
## from neighboring cells. Eventually, the cell is "collapsed" to exactly one state.
##
## KEY CONCEPTS:
##
## POSSIBILITIES:
## A PackedInt32Array of state keys (see HexTileState for encoding).
## Initially contains every valid state. As the solver runs, incompatible states
## are removed. When only one remains, the cell auto-collapses.
##
## ENTROPY:
## Shannon entropy measures how "uncertain" a cell is. Lower entropy = fewer
## possibilities = easier to decide. The solver always picks the lowest-entropy
## uncollapsed cell to collapse next (this is the "minimum entropy heuristic").
##
## Formula: entropy = log(sum_of_weights) - (sum_of(w * log(w))) / sum_of_weights
##
## This is NOT just the count of possibilities. Tiles with higher weights
## contribute more entropy than low-weight tiles. A cell with 5 high-weight
## possibilities has higher entropy than a cell with 5 low-weight possibilities.
##
## WHY ENTROPY MATTERS:
## Collapsing low-entropy cells first reduces the chance of contradictions.
## Think of it like solving a puzzle: start with the most constrained spots
## (where few pieces fit) rather than the wide-open areas.
##
## COLLAPSING:
## When the solver "observes" a cell, it picks one state from the possibilities
## (weighted random) and collapses the cell to just that state. This triggers
## constraint propagation to all neighbors.
##
## USED BY:
##   - HexWFCSolver: the solver reads/writes cells during the solve loop
##   - HexWFCBacktracker: restores removed possibilities during backtracking
##   - HexGrid: stores cells indexed by cube coordinates
class_name HexWFCCell
extends RefCounted

## This cell's position in the hex grid (cube coordinates).
var cube_coords: Vector3i

## Array of state keys that are still valid for this cell.
## See HexTileState for how state keys are packed integers.
var possibilities: PackedInt32Array

## True once this cell has been collapsed to a single state.
var collapsed: bool = false

## The chosen state key after collapse. -1 if not yet collapsed.
var collapsed_state_key: int = -1

## Cached entropy value. Recalculated whenever possibilities change.
## INF means the cell is uncollapsed with no entropy computed yet.
var _entropy: float = INF

## Cached sum of weights for entropy calculation.
var _weight_sum: float = 0.0

## Cached sum of (weight * log(weight)) for entropy calculation.
var _weight_log_sum: float = 0.0


## Creates a new cell at the given position with the given initial possibilities.
##
## Parameters:
##   _cube_coords: This cell's position in the hex grid
##   initial_possibilities: All valid state keys for this cell (typically all states)
##   state_weights: Lookup array mapping state_key -> weight (precomputed by solver)
func _init(_cube_coords: Vector3i, initial_possibilities: PackedInt32Array, state_weights: Dictionary) -> void:
	cube_coords = _cube_coords
	possibilities = initial_possibilities.duplicate()
	_recalculate_entropy(state_weights)


## Removes a single state key from this cell's possibilities.
##
## Returns true if the state was actually present and removed.
## Returns false if the state wasn't in possibilities (no-op).
##
## After removal, entropy is recalculated. If only one possibility remains,
## the cell auto-collapses to that state.
##
## This is the most frequently called method during constraint propagation.
## The solver calls it for every incompatible state found in every neighbor check.
func remove_possibility(state_key: int, state_weights: Dictionary) -> bool:
	var idx: int = _find_state(state_key)
	if idx < 0:
		return false

	# Remove by swapping with last element (O(1) removal from packed array)
	var last_idx: int = possibilities.size() - 1
	if idx != last_idx:
		possibilities[idx] = possibilities[last_idx]
	possibilities.resize(last_idx)

	# Update entropy
	_recalculate_entropy(state_weights)

	# Auto-collapse if only one possibility remains
	if possibilities.size() == 1 and not collapsed:
		collapse(possibilities[0])

	return true


## Returns the current entropy of this cell.
## Lower entropy = more constrained = fewer/lighter possibilities.
func get_entropy() -> float:
	return _entropy


## Returns entropy with a tiny random noise added to break ties.
## When two cells have identical entropy, the noise ensures we don't always
## pick the same one (which could cause systematic bias in generation).
func get_entropy_with_noise(rng: SeededRandom) -> float:
	return _entropy - rng.next_float() * 0.001


## Returns true if this cell has no possibilities and isn't collapsed.
## This is a CONTRADICTION -- the solver must backtrack when this happens.
func is_contradiction() -> bool:
	return possibilities.size() == 0 and not collapsed


## Collapses this cell to the given state key.
## After collapse, possibilities contains only the chosen state.
## This is called by the solver during the "observe" step.
func collapse(state_key: int) -> void:
	collapsed = true
	collapsed_state_key = state_key
	possibilities = PackedInt32Array([state_key])
	_entropy = 0.0


## Restores this cell to an uncollapsed state with the given possibilities.
## Used by the backtracker to undo a collapse and try a different state.
func restore(restored_possibilities: PackedInt32Array, state_weights: Dictionary) -> void:
	collapsed = false
	collapsed_state_key = -1
	possibilities = restored_possibilities.duplicate()
	_recalculate_entropy(state_weights)


## Recalculates Shannon entropy from current possibilities and their weights.
##
## Shannon entropy for weighted possibilities:
##   entropy = log(W) - (sum_i(w_i * log(w_i))) / W
##   where W = sum of all weights, w_i = weight of possibility i
##
## This formulation avoids computing probabilities explicitly:
##   Standard: H = -sum(p_i * log(p_i)) where p_i = w_i / W
##   Simplified: H = log(W) - sum(w_i * log(w_i)) / W  (algebraically equivalent)
func _recalculate_entropy(state_weights: Dictionary) -> void:
	if possibilities.size() == 0:
		_entropy = 0.0
		_weight_sum = 0.0
		_weight_log_sum = 0.0
		return

	if possibilities.size() == 1:
		_entropy = 0.0
		return

	_weight_sum = 0.0
	_weight_log_sum = 0.0

	for key: int in possibilities:
		var w: float = state_weights.get(key, 1.0)
		_weight_sum += w
		if w > 0.0:
			_weight_log_sum += w * log(w)

	if _weight_sum > 0.0:
		_entropy = log(_weight_sum) - _weight_log_sum / _weight_sum
	else:
		_entropy = 0.0


## Finds the index of a state key in the possibilities array.
## Returns -1 if not found. Uses linear scan (PackedInt32Array has no built-in find).
func _find_state(state_key: int) -> int:
	for i: int in possibilities.size():
		if possibilities[i] == state_key:
			return i
	return -1
