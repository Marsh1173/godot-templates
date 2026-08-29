extends Node

func _ready():
	var is_fullscreen: bool = PlayerSettings.get_setting(PlayerSettings.Fields.Fullscreen)
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
