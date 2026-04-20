## HexTileRenderer - Converts a solved WFC grid into 3D scene geometry.
##
## After the WFC solver produces a result dictionary (mapping cube coordinates
## to tile type + rotation + level), this class instantiates the actual 3D
## mesh scenes and positions them in world space.
##
## TWO RENDERING MODES:
##
## 1. SCENE INSTANTIATION (render_grid):
##    Each tile becomes its own Node3D instance (from the tile's mesh_scene).
##    Pros: Per-tile collision, materials, scripts, click detection.
##    Cons: Higher draw call count. Fine for grids up to ~500 tiles.
##    Best for: Prototyping, small maps, tiles that need individual behavior.
##
## 2. MULTIMESH BATCHING (render_grid_multimesh) -- FUTURE:
##    Groups identical tile types into MultiMeshInstance3D nodes.
##    Pros: Dramatically fewer draw calls (one per tile type instead of one per tile).
##    Cons: No per-tile collision or scripting out of the box.
##    Best for: Large maps (1000+ tiles), distant terrain, performance-critical.
##
## COORDINATE CONVERSION:
## The solver works in cube coordinates (Vector3i). This renderer converts them
## to world-space positions using HexCoords.cube_to_world(). The hex_size and
## level_height parameters control the physical spacing and elevation.
##
## ROTATION:
## Hex tiles are rotated around the Y axis by rotation * 60 degrees (TAU/6).
## Rotation value 0 = no rotation, 1 = 60 degrees CW, 2 = 120 degrees, etc.
##
## USED BY:
##   - HexWFCManager: owns the renderer, calls render_grid after solve completes
class_name HexTileRenderer
extends Node3D

## Distance from hex center to vertex. Controls grid spacing.
@export var hex_size: float = 1.0

## World-space height per elevation level.
@export var level_height: float = 0.5

## Reference to the tile registry for looking up mesh scenes by tile ID.
var _registry: HexTileRegistry

## Lookup of rendered tile nodes by their cube coordinates.
## Useful for later operations like highlighting or replacing individual tiles.
var _tile_nodes: Dictionary = {}


## Initializes the renderer with a tile registry.
## Must be called before render_grid().
func initialize(p_registry: HexTileRegistry) -> void:
	_registry = p_registry


## Renders a complete solved grid as individual scene instances.
##
## For each cell in the result, this:
##   1. Looks up the tile type by ID
##   2. Instantiates the tile's mesh_scene (a PackedScene)
##   3. Positions it in world space using cube_to_world()
##   4. Rotates it by the appropriate amount
##   5. Adds it as a child of this node
##
## Parameters:
##   result: Dictionary from HexWFCSolver.get_result()
##           Maps Vector3i -> { "tile_type_id": int, "rotation": int, "level": int }
##   offset: Optional world-space offset for multi-chunk positioning (Vector3i cube coords)
func render_grid(result: Dictionary, offset: Vector3i = Vector3i.ZERO) -> void:
	for coords: Variant in result:
		var data: Dictionary = result[coords]
		var tile_type: HexTileType = _registry.get_tile(data["tile_type_id"])
		if tile_type == null:
			push_warning("HexTileRenderer: Unknown tile_type_id %d at %s" % [data["tile_type_id"], str(coords)])
			continue
		if tile_type.mesh_scene == null:
			# No mesh for this tile type -- skip rendering (tile still exists in data)
			continue

		# Instantiate the tile's 3D scene
		var instance: Node3D = tile_type.mesh_scene.instantiate()

		# Compute world position from cube coordinates
		# Apply chunk offset first (offset is in cube coords, not world coords)
		var world_coords: Vector3i = Vector3i(
			int(coords.x) + offset.x,
			int(coords.y) + offset.y,
			int(coords.z) + offset.z
		)
		var world_pos: Vector3 = HexCoords.cube_to_world(
			world_coords, hex_size, data["level"], level_height
		)
		instance.position = world_pos

		# Rotate by rotation * 60 degrees around the Y axis
		instance.rotation.y = data["rotation"] * (TAU / 6.0)

		# Name the node for debugging (e.g., "tile_0_2_-2")
		instance.name = "tile_%d_%d_%d" % [int(coords.x), int(coords.y), int(coords.z)]

		add_child(instance)
		_tile_nodes[coords] = instance


## Removes all rendered tile nodes from the scene tree.
## Call this before re-rendering (e.g., when regenerating the map).
func clear() -> void:
	for child: Node in get_children():
		child.queue_free()
	_tile_nodes.clear()


## Returns the rendered Node3D for a specific cell, or null if not rendered.
func get_tile_at(coords: Vector3i) -> Node3D:
	return _tile_nodes.get(coords)


## Returns the total number of rendered tiles.
func get_rendered_count() -> int:
	return _tile_nodes.size()
