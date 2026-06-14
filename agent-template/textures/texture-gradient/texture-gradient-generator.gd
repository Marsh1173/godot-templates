@tool
extends Node2D

@export var trigger_generator: bool = false:
	set(value):
		# We check if we are in the editor to avoid accidental runs
		if Engine.is_editor_hint():
			generate_texture()

func generate_texture():
	var viewport: Viewport = $SubViewportContainer/SubViewport
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	
	var split_scene_file_path := scene_file_path.trim_prefix("res://").split("/").slice(0,-1)
	var destination_path := "./" + "/".join(split_scene_file_path) + "/texture-gradient.png"
	
	image.save_png(destination_path)
	print("Done")
