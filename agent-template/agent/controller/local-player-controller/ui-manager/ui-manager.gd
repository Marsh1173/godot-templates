extends Control
class_name UiManager

const LIVE_PAWN_UI = preload("uid://4l2m7g2sdxhy")
const DEBUG_STATS_COMPONENT = preload("uid://bh2mqx3hbr7ok")

func _ready():
	if OS.is_debug_build():
		add_child(DEBUG_STATS_COMPONENT.instantiate())

var pawn: Pawn = null

func set_pawn_or_null(pawn_or_null):
	pawn = pawn_or_null
	
	if pawn_or_null is Pawn:
		var live_pawn_ui = LIVE_PAWN_UI.instantiate().with_data(pawn)
		add_child(live_pawn_ui)
		move_child(live_pawn_ui, 0) # InGameMenu should appear above
	else:
		for child in get_children():
			if child is LivePawnUi:
				child.queue_free()
