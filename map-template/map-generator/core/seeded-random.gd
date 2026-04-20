## SeededRandom - Deterministic pseudo-random number generator.
##
## Implements the Mulberry32 algorithm, matching the reference implementation's
## SeededRandom.js exactly. Given the same seed, this will always produce the
## same sequence of random numbers, which is essential for:
##
##   1. REPRODUCIBLE MAP GENERATION: Same seed = same map, every time.
##      Players can share seeds to get identical worlds.
##
##   2. MULTIPLAYER SYNC: Host sends just the seed to clients.
##      Each client generates the identical map locally without needing
##      to transmit the entire grid state over the network.
##
##   3. DEBUGGING: If a seed produces a bad map (contradiction, ugly layout),
##      you can reproduce it reliably to investigate.
##
## MULBERRY32 ALGORITHM:
## A simple 32-bit PRNG with good statistical properties for game use.
## State is a single 32-bit integer that advances with each call.
## Period is 2^32 (over 4 billion values before repeating).
##
## GDSCRIPT 64-BIT INT CAVEAT:
## GDScript uses 64-bit signed integers, but Mulberry32 relies on 32-bit
## unsigned integer overflow behavior. We simulate this by masking with
## & 0xFFFFFFFF after every arithmetic operation. Without this masking,
## the sequence would diverge from the reference implementation.
##
## USED BY:
##   - HexWFCSolver: for weighted tile selection and entropy tie-breaking
##   - HexWFCManager: creates per-chunk RNG instances with offset seeds
##   - HexDoodadPlacer: randomized decoration placement
class_name SeededRandom
extends RefCounted

## Bitmask to truncate 64-bit GDScript ints to 32-bit unsigned range.
const MASK_32: int = 0xFFFFFFFF

## Current PRNG state (advances with each call to next_int).
var _state: int

## The original seed, stored so we can reset the sequence.
var _initial_seed: int


## Creates a new SeededRandom with the given seed value.
## The seed is masked to 32 bits to match Mulberry32's expected input range.
func _init(seed_value: int = 0) -> void:
	_initial_seed = seed_value & MASK_32
	_state = _initial_seed


## Resets the PRNG back to its initial seed, restarting the sequence.
func reset() -> void:
	_state = _initial_seed


## Returns the initial seed this PRNG was created with.
func get_seed() -> int:
	return _initial_seed


## Advances the state and returns a raw 32-bit unsigned integer (0 to 2^32-1).
##
## This is the core Mulberry32 step, translated from JavaScript:
##   function mulberry32(a) {
##     return function() {
##       a = a + 0x6D2B79F5 | 0;
##       var t = Math.imul(a ^ a >>> 15, 1 | a);
##       t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
##       return (t ^ t >>> 14) >>> 0;
##     }
##   }
##
## Each line mixes the state bits to produce well-distributed output.
## The magic constant 0x6D2B79F5 is a carefully chosen odd number that
## ensures good bit avalanche properties.
func next_int() -> int:
	_state = (_state + 0x6D2B79F5) & MASK_32
	var t: int = _state
	t = _imul(t ^ (t >> 15), (1 | t)) & MASK_32
	t = (t + (_imul(t ^ (t >> 7), (61 | t)) & MASK_32) ^ t) & MASK_32
	return (t ^ (t >> 14)) & MASK_32


## Returns a float in the range [0.0, 1.0).
## Divides the 32-bit int by 2^32 to normalize to unit range.
func next_float() -> float:
	return float(next_int()) / 4294967296.0


## Returns a random integer in [min_val, max_val] inclusive.
func next_range(min_val: int, max_val: int) -> int:
	var range_size: int = max_val - min_val + 1
	return min_val + (next_int() % range_size)


## Performs a weighted random selection from a set of options.
##
## This is the key function used by the WFC solver when collapsing a cell.
## Each possible state has a weight (from the tile definition), and we pick
## one randomly with probability proportional to its weight.
##
## Algorithm:
##   1. Sum all weights to get total_weight
##   2. Generate random float r in [0, total_weight)
##   3. Walk through options, accumulating weight until we exceed r
##   4. Return the option that pushed us past r
##
## This is called "roulette wheel selection" -- higher weights get
## proportionally larger slices of the wheel.
##
## Parameters:
##   keys: PackedInt32Array of state keys to choose from
##   weights: PackedFloat32Array of corresponding weights (same length)
## Returns:
##   The chosen key from the keys array
func weighted_choice(keys: PackedInt32Array, weights: PackedFloat32Array) -> int:
	var total: float = 0.0
	for w: float in weights:
		total += w
	if total <= 0.0:
		# Fallback: if all weights are zero, pick uniformly at random
		return keys[next_int() % keys.size()]
	var r: float = next_float() * total
	var cumulative: float = 0.0
	for i: int in keys.size():
		cumulative += weights[i]
		if r <= cumulative:
			return keys[i]
	# Floating point edge case: return last element
	return keys[keys.size() - 1]


## Fisher-Yates shuffle -- randomizes array order in-place.
## Used to break ties and add variety when multiple options have equal weight.
func shuffle_array(arr: Array) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = next_int() % (i + 1)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Emulates JavaScript's Math.imul(): 32-bit wrapping integer multiplication.
##
## In JavaScript, Math.imul(a, b) multiplies two 32-bit integers and returns
## the low 32 bits of the result. In GDScript with 64-bit ints, we need to
## manually mask both inputs and the output to get the same behavior.
##
## This is critical for seed reproducibility -- without masking, the
## multiplication would use 64-bit precision and produce different results.
static func _imul(a: int, b: int) -> int:
	return ((a & MASK_32) * (b & MASK_32)) & MASK_32
