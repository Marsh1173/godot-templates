class_name TempTester
extends Node

@export var size: int = 7
@export var height: int = 3

## Background thread for solving.
var _thread: Thread

## Whether generation is currently in progress.
var _is_generating: bool = false

func _ready():
	do_until_success()

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				do_until_success()

func do_until_success():
	if _is_generating:
		return
	
	_is_generating = true
	# Start background thread
	_thread = Thread.new()
	_thread.start(_do_thread_entry)

func _do_thread_entry():
	while !do():
		pass

func do() -> bool:
	var start_time = Time.get_ticks_msec()
	
	var solver = Solver.new()
	var success: bool = solver.solve(size, height)
	if !success:
		return false
	
	call_deferred("create_meshes", solver)
	
	var end_time = Time.get_ticks_msec()
	var elapsed_ms = end_time - start_time
	var elapsed_sec = elapsed_ms / 1000.0

	print("Elapsed time: ", elapsed_sec, " seconds")
	return true

func create_meshes(solver: Solver):
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for cell: Cell in solver.grid.values():
		if !cell.is_collapsed:
			continue
		var scene: Node3D = cell.possible_tiles[0].scene.instantiate()
		scene.position = HexMath.axial_to_world(cell.coords.x, cell.coords.y, 1.1547)
		scene.rotation.y = cell.possible_tiles[0].rotation * PI / 3
		scene.position.y = cell.possible_tiles[0].edge_heights.min()
		add_child(scene)
	if _thread != null:
		_thread.wait_to_finish()
	_is_generating = false

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
