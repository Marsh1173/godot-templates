extends Node
class_name GameMap

@onready var tiles: MapTiles = $Tiles
@onready var doodads: MapDoodads = $Doodads

signal done()

func _ready():
	tiles.tiles_done.connect(_start_doodads_generation)
	doodads.doodads_done.connect(_start_navmesh_generation)

func generate(map_size: int, map_height: int, seed = null):
	_start_tiles_generation(map_size, map_height)

func _start_tiles_generation(map_size: int, map_height: int):
	tiles.generate_tiles(map_size, map_height)

func _start_doodads_generation():
	doodads.generate_doodads()

func _start_navmesh_generation():
	pass

#func _start_mobs_generation():
	#pass

# TODO implement
func finish():
	done.emit()
