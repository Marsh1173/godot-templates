extends Control
class_name PerformanceStatsComponent

@onready var fps_label: Label = $FpsLabel
@onready var ping_label: Label = $PingLabel

const update_interval: float = 1.0
var update_countdown: float = 0
var network_manager: NetworkManager = null

func _ready():
	network_manager = AppOrchestrator.get_or_null(self).network_manager

func _process(delta):
	update_countdown -= delta
	
	if update_countdown <= 0:
		update_countdown += update_interval
		
		var fps = Engine.get_frames_per_second()
		fps_label.text = "FPS: " + str(int(fps)) # Trim leading .0
		
		if multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != 1 and network_manager != null:
			ping_label.text = "Ping: " + str(int(network_manager.current_ping)) + "ms"
		else:
			ping_label.text = ""
