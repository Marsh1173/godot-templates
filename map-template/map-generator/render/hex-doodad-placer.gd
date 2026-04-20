## HexDoodadPlacer - Post-solve decoration placement for hex tiles.
##
## After the WFC solver generates the base terrain, this class places
## decorative 3D objects ("doodads") on top of tiles. Think trees on forest
## tiles, rocks on cliffs, flowers on grass, buoys on water, etc.
##
## HOW IT WORKS:
##
## 1. REGISTRATION:
##    Before placement, you register which decorations go with which tile types.
##    Each registration specifies:
##      - The tile name (e.g., &"forest")
##      - An array of PackedScene options (e.g., [tree1.tscn, tree2.tscn, rock.tscn])
##      - A density value from 0.0 to 1.0 (probability of placing a doodad on each tile)
##
## 2. PLACEMENT:
##    After the WFC solve, call place_doodads() with the result dictionary.
##    For each tile in the result:
##      a. Look up its tile type name
##      b. Check if there are registered doodads for that type
##      c. Roll the RNG against the density -- if it passes, place a doodad
##      d. Pick a random doodad from the available scenes
##      e. Instantiate it at the tile's world position with a random Y rotation
##      f. Add a small random XZ offset so doodads don't all sit dead-center
##
## WHY SEPARATE FROM THE SOLVER?
## Doodads are purely visual and don't affect tile adjacency rules.
## Keeping them separate means:
##   - The solver stays fast (no extra data to track)
##   - Doodads can be re-randomized without re-solving
##   - Different visual styles can share the same tile rules
##
## USED BY:
##   - HexWFCManager: creates and configures the placer after solve completes
class_name HexDoodadPlacer
extends RefCounted

## Registered doodad configurations per tile type.
## Maps tile_name (StringName) -> DoodadConfig { scenes, density }
var _configs: Dictionary = {}


## Registers decoration scenes for a specific tile type.
##
## Parameters:
##   tile_name: The tile type name (must match HexTileType.tile_name, e.g., &"forest")
##   scenes: Array of PackedScene objects -- one will be randomly chosen per placement
##   density: Float from 0.0 (never place) to 1.0 (always place) -- the probability
##            that a doodad will be placed on each tile of this type
func register_doodad(tile_name: StringName, scenes: Array[PackedScene], density: float) -> void:
	_configs[tile_name] = {
		"scenes": scenes,
		"density": clampf(density, 0.0, 1.0),
	}


## Places doodads on all tiles in the result that have registered decorations.
##
## Parameters:
##   result: The solved grid dictionary from HexWFCSolver.get_result()
##   registry: Tile registry for looking up tile names by ID
##   parent: Node3D to add doodad instances as children of
##   rng: SeededRandom for deterministic placement
##   hex_size: Hex outer radius for world position conversion
##   level_height: Height per elevation level
##   offset: Optional chunk offset in cube coordinates
func place_doodads(
	result: Dictionary,
	registry: HexTileRegistry,
	parent: Node3D,
	rng: SeededRandom,
	hex_size: float,
	level_height: float,
	offset: Vector3i = Vector3i.ZERO,
) -> void:
	var placed_count: int = 0

	for coords: Variant in result:
		var data: Dictionary = result[coords]
		var tile_type: HexTileType = registry.get_tile(data["tile_type_id"])
		if tile_type == null:
			continue

		# Check if this tile type has registered doodads
		var config: Variant = _configs.get(tile_type.tile_name)
		if config == null:
			continue

		var scenes: Array = config["scenes"]
		var density: float = config["density"]

		if scenes.size() == 0:
			continue

		# Roll against density
		if rng.next_float() > density:
			continue

		# Pick a random doodad scene
		var scene_index: int = rng.next_int() % scenes.size()
		var scene: PackedScene = scenes[scene_index]
		if scene == null:
			continue

		# Compute world position
		var world_coords: Vector3i = Vector3i(
			int(coords.x) + offset.x,
			int(coords.y) + offset.y,
			int(coords.z) + offset.z
		)
		var world_pos: Vector3 = HexCoords.cube_to_world(
			world_coords, hex_size, data["level"], level_height
		)

		# Add a small random offset within the hex (keep inside the hex boundary)
		# Max offset is about 40% of hex_size to stay well within the hex
		var offset_range: float = hex_size * 0.4
		var random_x: float = (rng.next_float() - 0.5) * 2.0 * offset_range
		var random_z: float = (rng.next_float() - 0.5) * 2.0 * offset_range
		world_pos.x += random_x
		world_pos.z += random_z

		# Instantiate the doodad
		var instance: Node3D = scene.instantiate()
		instance.position = world_pos

		# Random Y rotation for visual variety
		instance.rotation.y = rng.next_float() * TAU

		parent.add_child(instance)
		placed_count += 1

	if placed_count > 0:
		print("HexDoodadPlacer: Placed %d doodads" % placed_count)


## Returns the number of registered doodad configurations.
func get_config_count() -> int:
	return _configs.size()


## Removes all registered doodad configurations.
func clear_configs() -> void:
	_configs.clear()
