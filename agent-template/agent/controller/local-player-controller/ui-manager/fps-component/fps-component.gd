extends Control
class_name FpsComponent

@onready var label: Label = $Label

func _process(_delta):
	var fps = Engine.get_frames_per_second()
	label.text = "FPS: " + str(int(fps)) # Trim leading .0
