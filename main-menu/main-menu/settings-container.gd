extends CenterContainer

@onready var fullscreen_toggle: CheckButton = $VBoxContainer/FullscreenToggle

func _ready():
	var is_fullscreen: bool = PlayerSettings.get_setting(PlayerSettings.Fields.Fullscreen)
	fullscreen_toggle.set_pressed_no_signal(is_fullscreen)

func _on_fullscreen_toggle_toggled(toggled_on: bool):
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	PlayerSettings.set_setting(PlayerSettings.Fields.Fullscreen, toggled_on)
