extends Node
class_name MapDoodads

signal doodads_done()

func generate_doodads():
	doodads_done.emit()
