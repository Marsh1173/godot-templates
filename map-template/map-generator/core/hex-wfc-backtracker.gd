## HexWFCBacktracker - Trail-based backtracking system for the WFC solver.
##
## When the WFC solver hits a CONTRADICTION (a cell with no valid states),
## it needs to undo recent decisions and try different choices. This class
## manages that undo system.
##
## HOW BACKTRACKING WORKS:
##
## 1. DECISIONS: Every time the solver collapses a cell, it records a "decision"
##    on the decision stack. A decision remembers:
##    - Which cell was collapsed (target_coords)
##    - What possibilities it had before collapse (prev_possibilities)
##    - Which states have already been tried and failed (tried_states)
##    - Where in the trail this decision's removals start (trail_start)
##
## 2. TRAIL: Every time a state is removed from ANY cell (during propagation),
##    it's recorded in the trail. The trail is a flat array of {coords, state_key}
##    entries. This is the "undo log" -- when we backtrack, we replay trail entries
##    in reverse to restore removed possibilities.
##
## 3. ON CONTRADICTION:
##    a. Pop the most recent decision from the stack
##    b. Undo all trail entries from trail_start to the end (restore removed states)
##    c. Restore the collapsed cell to its pre-collapse possibilities
##    d. Mark the tried state as exhausted (don't try it again)
##    e. Pick a new state from the remaining untried possibilities
##    f. If no untried states remain, pop another decision (backtrack further)
##
## WHY TRAIL-BASED (vs. full state snapshots)?
## The reference implementation uses this same approach. Instead of copying the
## entire grid state before each decision (which would be O(cells * states) memory),
## we only record individual state removals. Backtracking replays them in reverse.
## This is O(1) per removal to record and O(removals) to undo, which is typically
## much less memory and work than full snapshots.
##
## ANALOGY:
## Think of it like an "undo stack" in a text editor. Instead of saving the entire
## document before each keystroke, you record each individual edit. To undo, you
## replay edits in reverse. Much more memory-efficient.
##
## USED BY:
##   - HexWFCSolver: pushes decisions, records removals, calls backtrack on contradiction
class_name HexWFCBacktracker
extends RefCounted

## The trail: ordered log of every state removal during solving.
## Each entry is: { "coords": Vector3i, "state_key": int }
## Entries are appended during propagation and replayed in reverse during backtrack.
var _trail: Array = []

## The decision stack: one entry per collapse decision.
## Each entry is: {
##   "target_coords": Vector3i,          # Which cell was collapsed
##   "prev_possibilities": PackedInt32Array,  # Cell's possibilities BEFORE collapse
##   "tried_states": Dictionary,          # States already tried (used as Set)
##   "trail_start": int,                  # Index into _trail where this decision's removals begin
##   "collapsed_key": int,                # The state key we collapsed to
## }
## LIFO order: most recent decision is at the end.
var _decision_stack: Array = []


## Records that a state was removed from a cell during propagation.
## This must be called EVERY TIME a possibility is removed, so that
## backtracking can restore it later.
##
## Parameters:
##   cell_coords: The cube coordinates of the cell that lost a possibility
##   state_key: The state key that was removed
func record_removal(cell_coords: Vector3i, state_key: int) -> void:
	_trail.append({ "coords": cell_coords, "state_key": state_key })


## Pushes a new decision onto the stack. Call this BEFORE collapsing a cell.
##
## This snapshots the cell's current possibilities so we can restore them
## if this decision leads to a contradiction.
##
## Parameters:
##   target_coords: The cell being collapsed
##   prev_possibilities: The cell's possibilities BEFORE collapse
func push_decision(target_coords: Vector3i, prev_possibilities: PackedInt32Array) -> void:
	_decision_stack.append({
		"target_coords": target_coords,
		"prev_possibilities": prev_possibilities.duplicate(),
		"tried_states": {},  # Dictionary used as a Set for O(1) lookup
		"trail_start": _trail.size(),
		"collapsed_key": -1,
	})


## Marks a state key as "tried" for the current (top) decision.
## After backtracking, tried states are excluded from future selection.
##
## Parameters:
##   state_key: The state key that was tried (and may have led to contradiction)
func mark_tried(state_key: int) -> void:
	if _decision_stack.size() > 0:
		_decision_stack[-1]["tried_states"][state_key] = true
		_decision_stack[-1]["collapsed_key"] = state_key


## Returns true if there are decisions on the stack that can be undone.
func can_backtrack() -> bool:
	return _decision_stack.size() > 0


## Undoes the most recent decision and restores all state removals it caused.
##
## This is the core backtracking operation:
##   1. Pops the top decision from the stack
##   2. Replays trail entries in reverse from trail_start to end
##   3. For each trail entry, re-adds the removed state to the cell
##   4. Restores the collapsed cell to its pre-collapse state
##   5. Trims the trail back to trail_start
##
## Parameters:
##   cells: The grid's cells dictionary (Vector3i -> HexWFCCell)
##          Cells are modified in-place to restore possibilities.
##   state_weights: Weight lookup for entropy recalculation
## Returns:
##   The decision dictionary (with tried_states updated), or empty dict if stack empty
func pop_and_undo(cells: Dictionary, state_weights: Dictionary) -> Dictionary:
	if _decision_stack.size() == 0:
		return {}

	var decision: Dictionary = _decision_stack.pop_back()
	var trail_start: int = decision["trail_start"]

	# Track which cells were modified so we can fix them up after
	var affected_coords: Dictionary = {}  # Used as Set

	# Undo all trail entries from this decision (reverse order)
	# This restores every state that was removed during propagation
	# after this collapse decision was made.
	for i: int in range(_trail.size() - 1, trail_start - 1, -1):
		var entry: Dictionary = _trail[i]
		var cell: Variant = cells.get(entry["coords"])
		if cell != null:
			# Re-add the removed possibility
			cell.possibilities.append(entry["state_key"])
			affected_coords[entry["coords"]] = true

	# Trim the trail back to before this decision
	_trail.resize(trail_start)

	# Fix up all affected cells:
	# Cells that were auto-collapsed during propagation (reduced to 1 possibility)
	# need to be un-collapsed now that they have more possibilities again.
	# Also recalculate entropy for all affected cells.
	for coords: Variant in affected_coords:
		var affected_cell: Variant = cells.get(coords)
		if affected_cell == null:
			continue
		if affected_cell.collapsed and affected_cell.possibilities.size() > 1:
			affected_cell.collapsed = false
			affected_cell.collapsed_state_key = -1
		affected_cell._recalculate_entropy(state_weights)

	# Restore the collapsed cell (the one we made a decision about) to its
	# pre-collapse state. This uses the saved snapshot, which is more reliable
	# than the trail-restored state (which may have redundant entries).
	var target_coords: Vector3i = decision["target_coords"]
	var cell: Variant = cells.get(target_coords)
	if cell != null:
		cell.restore(decision["prev_possibilities"], state_weights)

	return decision


## Returns the possibilities that haven't been tried yet for a given decision.
## These are the remaining options after excluding all states that already led
## to contradictions.
##
## Parameters:
##   decision: A decision dictionary from pop_and_undo()
## Returns:
##   PackedInt32Array of state keys that haven't been tried yet
func get_untried_states(decision: Dictionary) -> PackedInt32Array:
	var prev: PackedInt32Array = decision["prev_possibilities"]
	var tried: Dictionary = decision["tried_states"]
	var untried: PackedInt32Array = PackedInt32Array()
	for key: int in prev:
		if not tried.has(key):
			untried.append(key)
	return untried


## Clears all state -- trail and decision stack.
## Called when restarting a solve attempt.
func clear() -> void:
	_trail.clear()
	_decision_stack.clear()


## Returns the current depth of the decision stack (number of collapse decisions).
func get_decision_depth() -> int:
	return _decision_stack.size()


## Returns the current size of the trail (total state removals recorded).
func get_trail_size() -> int:
	return _trail.size()
