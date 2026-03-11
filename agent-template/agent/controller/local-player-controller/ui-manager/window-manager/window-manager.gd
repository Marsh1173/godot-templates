extends Node

# A set of all currently open UI "windows"
var open_windows = []

func register_window(window_name: String):
	if not open_windows.has(window_name):
		open_windows.append(window_name)
	update_mouse_mode()

func unregister_window(window_name: String):
	open_windows.erase(window_name)
	update_mouse_mode()

func update_mouse_mode():
	if open_windows.size() > 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
