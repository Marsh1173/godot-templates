extends Node

# A set of all currently open UI "windows"
var open_windows = []

func register_window(window_name: String, control_to_snap_mouse_to: Control = null):
	if not open_windows.has(window_name):
		open_windows.append(window_name)
	update_mouse_mode()
	if open_windows.size() == 1 and control_to_snap_mouse_to != null:
		snap_mouse_to_center_of_control(control_to_snap_mouse_to)

func unregister_window(window_name: String):
	open_windows.erase(window_name)
	update_mouse_mode()

func update_mouse_mode():
	if open_windows.size() > 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func snap_mouse_to_center_of_control(control: Control):
	Input.warp_mouse(
		Vector2(
			control.global_position.x + (control.size.x / 2),
			control.global_position.y + (control.size.y / 2),
		)
	)
