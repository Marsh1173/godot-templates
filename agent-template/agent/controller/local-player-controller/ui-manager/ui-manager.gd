extends Control
class_name UiManager

var fps_component = preload("res://agent-template/agent/controller/local-player-controller/ui-manager/fps-component/fps-component.tscn")

func _ready():
	if OS.is_debug_build():
		add_child(fps_component.instantiate())
