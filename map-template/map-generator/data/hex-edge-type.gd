## HexEdgeType - Edge type definitions for hex tile connectivity.
##
## Each hex tile has 6 edges (one per direction). Each edge has a TYPE that
## determines which other edges it can connect to.
##
## THE CORE RULE OF WFC ADJACENCY:
## Two adjacent tiles are compatible if and only if their touching edges
## have the same type AND the same level. The one exception is GRASS:
## grass edges connect to grass edges at ANY level (level-agnostic).
##
## This means:
##   - A ROAD edge on tile A's east side can only neighbor a ROAD edge
##     on tile B's west side, and both must be at the same height level.
##   - A GRASS edge can neighbor any other GRASS edge regardless of level,
##     which allows smooth terrain at different elevations.
##   - COAST edges connect water bodies to land -- a COAST edge on one tile
##     must face a COAST edge on the neighbor.
##
## WHY THIS MATTERS:
## The edge type system is the foundation of the entire WFC constraint system.
## When the solver collapses a cell to a specific tile+rotation+level, it
## propagates constraints to neighbors by checking: "given my edge type in
## direction X, which neighbor states have a compatible edge in the opposite
## direction?" This is how the map self-organizes into coherent terrain.
##
## ADDING NEW EDGE TYPES:
## To add a new terrain transition (e.g., SAND, SWAMP), add it to the Type enum,
## add its name to NAMES, and define tiles that use it in their edge dictionaries.
## The solver will automatically respect the new type in its adjacency rules.
##
## USED BY:
##   - HexTileType: each tile's edges dictionary maps direction -> edge type
##   - HexWFCAdjacency: builds the lookup index grouping states by edge type
##   - HexWFCSolver: during propagation, checks edge compatibility
class_name HexEdgeType
extends RefCounted

## All terrain edge types supported by the system.
## Each value is used as a key in adjacency lookups.
enum Type {
	GRASS = 0,       ## Basic walkable terrain. Level-agnostic (connects at any height).
	WATER = 1,       ## Open water (ocean, lake). Must match water on neighbor.
	ROAD = 2,        ## Paths and roads. Creates connected road networks.
	RIVER = 3,       ## Flowing water channels. Creates connected rivers.
	COAST = 4,       ## Transition between land and water. Bridges grass<->water.
	CLIFF = 5,       ## Vertical terrain drop. Connects tiles at different levels.
	CLIFF_ROAD = 6,  ## Cliff with a road going up/down it.
	#FOREST = 7,      ## Dense tree coverage. Creates forest regions.
}

## Human-readable names for each edge type (used in debug output).
const NAMES: Array[StringName] = [
	&"grass", &"water", &"road", &"river",
	&"coast", &"cliff", &"cliff_road", ## &"forest",
]


## Returns true if this edge type ignores level when matching.
##
## Only GRASS is level-agnostic. This means a grass edge at level 0 can
## connect to a grass edge at level 2, allowing natural elevation changes
## in open terrain without requiring explicit slope tiles for every transition.
##
## All other edge types require EXACT level matching. A road at level 0
## can only connect to a road at level 0. This forces the solver to use
## slope/cliff tiles to bridge elevation changes for structured terrain.
static func is_level_agnostic(type: int) -> bool:
	return type == Type.GRASS


## Returns the human-readable name of an edge type.
static func type_name(type: int) -> StringName:
	if type >= 0 and type < NAMES.size():
		return NAMES[type]
	return &"unknown"
