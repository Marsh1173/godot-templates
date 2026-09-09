extends Node
class_name MapTiles

var _size: int
var _height: int

signal tiles_done(grid: Dictionary[Vector2i, MapCell])

# Background thread for solving.
var _thread: Thread

# This will be populated when the solver has succeeded.
var _solved_grid: Dictionary[Vector2i, MapCell]

func generate_tiles(size: int, height: int):
	_size = size
	_height = height
	
	_do_until_success()

func _do_until_success():
	# Start background thread
	_thread = Thread.new()
	_thread.start(_do_thread_entry)

func _do_thread_entry():
	while !_do():
		pass
	tiles_done.emit(_solved_grid)
#
func _do() -> bool:
	var start_time = Time.get_ticks_msec()
	
	var solver = MapTilesSolver.new()
	var success: bool = solver.solve(_size, _height)
	if !success:
		return false
	
	_solved_grid = solver.grid
	
	var end_time = Time.get_ticks_msec()
	var elapsed_ms = end_time - start_time
	var elapsed_sec = elapsed_ms / 1000.0

	print("Elapsed time: ", elapsed_sec, " seconds")
	return true

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
