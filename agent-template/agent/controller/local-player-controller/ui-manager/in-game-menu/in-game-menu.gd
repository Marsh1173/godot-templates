extends Control
class_name InGameMenu

@onready var blur_panel: PanelContainer = $BlurPanel

signal leave_game()

func _ready():
	# Open menu if game isn't focused on start
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		toggle_menu(true)
	else:
		toggle_menu(false)

func toggle_menu(open: bool):
	blur_panel.visible = open
	var is_playing_over_network := MyUtils.is_playing_over_network(multiplayer)
	if open:
		WindowManager.register_window("InGameMenu")
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		WindowManager.unregister_window("InGameMenu")
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# If game is not networked, pause the whole game when menu is open
	if !MyUtils.is_playing_over_network(multiplayer):
		get_tree().paused = open

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed():
		toggle_menu(!blur_panel.visible)
		get_viewport().set_input_as_handled()

func _on_resume_pressed():
	toggle_menu(false)

func _on_leave_game_pressed():
	leave_game.emit()

func _on_fullscreen_pressed():
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


	pass # Replace with function body.
