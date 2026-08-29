extends Label

var time_since_start: float = 0

func _process(delta):
	time_since_start += delta
	
	modulate = Color(1, 1, 1, sin(time_since_start * 3) * 0.2 + 0.5)

func _unhandled_input(event):
	if event.is_pressed():
		var app_orchestrator: AppOrchestrator = AppOrchestrator.get_or_null(self)
		if app_orchestrator != null:
			app_orchestrator.show_main_menu()
			get_viewport().set_input_as_handled()
