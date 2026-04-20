## HexDirection - Hexagonal direction enum and rotation utilities.
##
## This class provides the 6 cardinal directions for a flat-top hexagonal grid
## and helper functions for rotating directions and edge dictionaries.
##
## FLAT-TOP HEX LAYOUT:
## In a flat-top hexagon, the pointy vertices are at the top and bottom,
## and the flat edges are on the left and right sides.
##
##        NW    NE
##          \  /
##     W --- * --- E
##          /  \
##        SW    SE
##
## Directions are numbered 0-5 clockwise starting from NE:
##   NE=0, E=1, SE=2, SW=3, W=4, NW=5
##
## This numbering is critical because:
##   - opposite(dir) = (dir + 3) % 6  (always works with this order)
##   - rotate(dir, n) = (dir + n) % 6  (clockwise rotation by n steps)
##   - Each step is 60 degrees clockwise
##
## USED BY:
##   - HexCoords: to compute neighbor positions via direction vectors
##   - HexWFCAdjacency: to index edges by direction
##   - HexTileType: to define which edge type faces each direction
##   - HexWFCSolver: to iterate neighbor directions during propagation
class_name HexDirection
extends RefCounted

## The 6 hex directions as an enum. Values 0-5, clockwise from NE.
enum Dir {
	NE = 0,
	E = 1,
	SE = 2,
	SW = 3,
	W = 4,
	NW = 5,
}

## Total number of directions on a hexagon.
const COUNT: int = 6

## Convenience array of all direction values for iteration.
## Usage: for dir in HexDirection.ALL:
const ALL: Array[int] = [Dir.NE, Dir.E, Dir.SE, Dir.SW, Dir.W, Dir.NW]

## Human-readable names for debug output.
const NAMES: Array[StringName] = [&"NE", &"E", &"SE", &"SW", &"W", &"NW"]


## Returns the opposite direction (180 degrees).
## Since directions are numbered 0-5 clockwise, the opposite is always +3 mod 6.
## Examples: opposite(NE=0) -> SW=3, opposite(E=1) -> W=4
static func opposite(dir: int) -> int:
	return (dir + 3) % 6


## Rotates a direction clockwise by the given number of 60-degree steps.
## Negative steps rotate counter-clockwise.
## Examples: rotate(NE=0, 1) -> E=1, rotate(NE=0, -1) -> NW=5
static func rotate(dir: int, steps: int) -> int:
	return ((dir + steps) % 6 + 6) % 6


## Rotates an entire edge dictionary by the given number of steps.
##
## An "edge dictionary" maps direction (int) -> edge type (int).
## For example, a tile's edges at rotation 0 might be:
##   { NE: GRASS, E: ROAD, SE: GRASS, SW: GRASS, W: ROAD, NW: GRASS }
##
## Rotating by 1 step (60 degrees clockwise) shifts all keys:
##   { E: GRASS, SE: ROAD, SW: GRASS, W: GRASS, NW: ROAD, NE: GRASS }
##
## This is how we compute the actual edge layout for a tile at a given rotation.
## The tile definition stores edges at rotation=0; we call this function with
## the desired rotation to get the actual edge map.
##
## Parameters:
##   edges: Dictionary mapping Dir (int) -> edge type (int) at rotation 0
##   rotation: Number of 60-degree clockwise steps (0-5)
## Returns:
##   New Dictionary with rotated direction keys
static func rotated_edges(edges: Dictionary, rotation: int) -> Dictionary:
	if rotation == 0:
		return edges.duplicate()
	var result: Dictionary = {}
	for dir: int in edges:
		var new_dir: int = rotate(dir, rotation)
		result[new_dir] = edges[dir]
	return result


## Returns the human-readable name for a direction.
## Example: dir_name(0) -> &"NE"
static func dir_name(dir: int) -> StringName:
	return NAMES[dir]
