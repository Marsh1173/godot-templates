extends Control
class_name DebugStatsComponent

@onready var fps_label: Label = $FpsLabel
@onready var ping_label: Label = $PingLabel

const update_interval: float = 1.0
var update_countdown: float = 0

func _process(delta):
	update_countdown -= delta
	
	if update_countdown <= 0:
		update_countdown += update_interval
		
		var fps = Engine.get_frames_per_second()
		fps_label.text = "FPS: " + str(int(fps)) # Trim leading .0
		
		if multiplayer.get_unique_id() != 1 and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			# Access the low-level ENetPacketPeer for this specific ID
			var enet_peer: ENetPacketPeer = multiplayer.multiplayer_peer.get_peer(1)
			# Returns the RTT in milliseconds
			var ping: float = enet_peer.get_statistic(ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME)
			ping_label.text = "Ping: " + str(int(ping)) + "ms" # Trim leading .0
		else:
			ping_label.text = ""
