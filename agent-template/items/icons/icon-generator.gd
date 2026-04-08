@tool
extends Node3D

@export var trigger_generator: bool = false:
	set(value):
		# We check if we are in the editor to avoid accidental runs
		if Engine.is_editor_hint():
			generate_icons()

func generate_icons():
	var mesh_instance: MeshInstance3D = $SubViewportContainer/SubViewport/MeshInstance
	var viewport: Viewport = $SubViewportContainer/SubViewport
	
	var items: Array[ItemRegistry.ItemDefinition] = ItemRegistry.make_item_registry().values()
	
	for item: ItemRegistry.ItemDefinition in items:
		# 1. Set the mesh
		var mesh = load(item.get_mesh_path())
		mesh_instance.mesh = mesh
		
		# 2. Wait for a frame to render
		await RenderingServer.frame_post_draw
		
		# 3. Capture and save
		var image = viewport.get_texture().get_image()
		image.save_png(item.get_icon_path())
		print("Created icon for " + item.name)
	print("Done")
