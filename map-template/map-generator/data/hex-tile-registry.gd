## HexTileRegistry - Auto-loading registry of all tile type definitions.
##
## This class scans the data/tiles/ directory at initialization and loads
## every .tres file as a HexTileType resource. It provides O(1) lookup
## by tile_id or tile_name.
##
## HOW IT WORKS:
## 1. On creation (_init), it opens the tiles/ directory with DirAccess
## 2. For each .tres file found, it loads the resource with ResourceLoader
## 3. If the resource is a valid HexTileType, it's added to the internal arrays
## 4. Lookup dictionaries are built for fast access by id or name
##
## WHY AUTO-LOADING?
## Instead of manually maintaining a list of tile types in code, the registry
## discovers them from the filesystem. This means adding a new tile type is as
## simple as creating a new .tres file -- no code changes needed.
##
## TILE ID UNIQUENESS:
## Each HexTileType must have a unique tile_id. The registry will print a
## warning if duplicates are found. Tile IDs are used in state key encoding
## (see HexTileState), so duplicates would cause the solver to confuse
## different tile types.
##
## USED BY:
##   - HexWFCSolver: gets all tiles to enumerate possible states
##   - HexWFCAdjacency: reads tile edges to build constraint index
##   - HexTileRenderer: looks up mesh_scene by tile_id for rendering
##   - HexWFCManager: creates and owns the registry instance
class_name HexTileRegistry
extends RefCounted

## Path to the directory containing .tres tile definitions.
const TILES_DIR: String = "res://map-template/map-generator/data/tiles/"

## All loaded tile types, in load order.
var tile_types: Array[HexTileType] = []

## Fast lookup by tile_id (int -> HexTileType).
var by_id: Dictionary = {}

## Fast lookup by tile_name (StringName -> HexTileType).
var by_name: Dictionary = {}


## Loads all tile definitions from the tiles/ directory on creation.
func _init() -> void:
	_load_tiles()


## Scans the tiles directory and loads every .tres file as a HexTileType.
func _load_tiles() -> void:
	var dir: DirAccess = DirAccess.open(TILES_DIR)
	if dir == null:
		push_error("HexTileRegistry: Cannot open tiles directory: ", TILES_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		# Godot may import .tres files as .tres.remap in exported builds
		if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			var path: String = TILES_DIR + file_name.replace(".remap", "")
			var resource: Resource = ResourceLoader.load(path)
			if resource is HexTileType:
				_register_tile(resource as HexTileType)
			else:
				push_warning("HexTileRegistry: Skipping non-HexTileType resource: ", path)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Sort by tile_id for consistent ordering
	tile_types.sort_custom(func(a: HexTileType, b: HexTileType) -> bool:
		return a.tile_id < b.tile_id
	)

	print("HexTileRegistry: Loaded %d tile types" % tile_types.size())


## Registers a single tile type into the lookup structures.
func _register_tile(tile: HexTileType) -> void:
	# Check for duplicate IDs
	if by_id.has(tile.tile_id):
		var existing: HexTileType = by_id[tile.tile_id]
		push_warning("HexTileRegistry: Duplicate tile_id %d! '%s' conflicts with '%s'" % [
			tile.tile_id, tile.tile_name, existing.tile_name
		])

	tile_types.append(tile)
	by_id[tile.tile_id] = tile
	by_name[tile.tile_name] = tile


## Returns the tile type with the given ID, or null if not found.
func get_tile(id: int) -> HexTileType:
	return by_id.get(id)


## Returns the tile type with the given name, or null if not found.
func get_tile_by_name(tile_name: StringName) -> HexTileType:
	return by_name.get(tile_name)


## Returns all loaded tile types (sorted by tile_id).
func get_all_tiles() -> Array[HexTileType]:
	return tile_types


## Returns the number of loaded tile types.
func get_tile_count() -> int:
	return tile_types.size()
