## HexTileState - Encodes a tile state as a single integer for fast WFC operations.
##
## A "state" in the WFC solver represents one specific possibility for a cell:
## a particular tile type, at a particular rotation, at a particular elevation level.
##
## For example: "road_straight tile, rotated 60 degrees, at level 0" is one state.
## "grass tile, no rotation, at level 2" is another state.
##
## STATE KEY ENCODING:
## Instead of storing these as objects or strings (which are slow to hash and compare),
## we pack all three values into a single integer:
##
##   state_key = tile_type_id * (MAX_ROTATIONS * MAX_LEVELS) + rotation * MAX_LEVELS + level
##   state_key = tile_type_id * 48 + rotation * 8 + level
##
## This gives us:
##   - Up to 680 tile types (limited by int range in PackedInt32Array)
##   - 6 rotations (0-5, representing 0 to 300 degrees in 60-degree steps)
##   - 8 levels (0-7, representing terrain elevation)
##
## WHY INTEGERS INSTEAD OF STRINGS?
## The reference implementation uses strings like "0_2_1" (type_rotation_level).
## We use packed integers because:
##   1. Integer hashing is O(1) and trivial; string hashing reads every character
##   2. Integer comparison is a single CPU instruction; string comparison is character-by-character
##   3. PackedInt32Array is a contiguous memory block; Array[String] boxes each element
##   4. The WFC solver checks state keys thousands of times per solve -- this matters
##
## DECODING:
## To unpack a state key back to its components:
##   level = key % MAX_LEVELS
##   rotation = (key / MAX_LEVELS) % MAX_ROTATIONS
##   tile_type_id = key / (MAX_ROTATIONS * MAX_LEVELS)
##
## USED BY:
##   - HexWFCCell: stores possibilities as PackedInt32Array of state keys
##   - HexWFCAdjacency: indexes state keys by edge type for O(1) lookup
##   - HexWFCSolver: encodes/decodes states during observe and propagate
##   - HexWFCBacktracker: records removed state keys for undo operations
class_name HexTileState
extends RefCounted

## Maximum number of rotation values (0-5 for hexagons = 6 total).
const MAX_ROTATIONS: int = 6

## Maximum number of elevation levels (0-7 = 8 total).
## Increase this if you need more than 8 height levels.
const MAX_LEVELS: int = 8

## Multiplier for encoding: rotation * MAX_LEVELS.
const ROTATION_STRIDE: int = MAX_LEVELS  # = 8

## Multiplier for encoding: tile_type_id * (MAX_ROTATIONS * MAX_LEVELS).
const TYPE_STRIDE: int = MAX_ROTATIONS * MAX_LEVELS  # = 48

## The tile type ID (index into the tile registry).
var tile_type_id: int

## Rotation in 60-degree steps (0-5). 0=no rotation, 1=60 degrees CW, etc.
var rotation: int

## Elevation level (0-7). 0=ground, higher=elevated terrain.
var level: int


## Creates a new HexTileState with the given components.
func _init(_tile_type_id: int = 0, _rotation: int = 0, _level: int = 0) -> void:
	tile_type_id = _tile_type_id
	rotation = _rotation
	level = _level


## Packs this state into a single integer key.
## Formula: tile_type_id * 48 + rotation * 8 + level
func get_key() -> int:
	return tile_type_id * TYPE_STRIDE + rotation * ROTATION_STRIDE + level


## Creates a HexTileState by unpacking an integer key.
## This is the inverse of get_key().
static func from_key(key: int) -> HexTileState:
	var _level: int = key % MAX_LEVELS
	var _rotation: int = (key / MAX_LEVELS) % MAX_ROTATIONS
	var _tile_type_id: int = key / TYPE_STRIDE
	return HexTileState.new(_tile_type_id, _rotation, _level)


## Extracts just the tile_type_id from a state key without creating an object.
## Useful in hot loops where you only need the type (e.g., for weight lookup).
static func type_from_key(key: int) -> int:
	return key / TYPE_STRIDE


## Extracts just the rotation from a state key without creating an object.
static func rotation_from_key(key: int) -> int:
	return (key / MAX_LEVELS) % MAX_ROTATIONS


## Extracts just the level from a state key without creating an object.
static func level_from_key(key: int) -> int:
	return key % MAX_LEVELS


## Returns a human-readable string for debugging.
## Format: "type_id:rotation:level" (e.g., "5:2:0" = tile 5, rotation 2, level 0)
func to_debug_string() -> String:
	return "%d:%d:%d" % [tile_type_id, rotation, level]
