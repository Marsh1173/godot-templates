extends Control
class_name LoadingScreen

@onready var progress_bar: ProgressBar = $CenterContainer/VBoxContainer/ProgressBar

const load_time: float = 1.0
const fade_out_time: float = 0.2

var time_since_load_start: float = 0
var is_fading: bool = false

signal done_loading()

func _process(delta):
	time_since_load_start += delta
	
	if is_fading:
		modulate.a = 1 - min(1, max(0, (time_since_load_start - load_time) / fade_out_time))
		if time_since_load_start / (load_time + fade_out_time) >= 1:
			queue_free()
	else:
		progress_bar.value = min(1, max(0, time_since_load_start / load_time))
		if time_since_load_start / load_time >= 1:
			done_loading.emit()
			is_fading = true
