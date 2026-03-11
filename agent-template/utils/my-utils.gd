class_name MyUtils
extends RefCounted

static func is_authority(multiplayer: MultiplayerAPI) -> bool:
	return multiplayer.is_server() || !multiplayer.has_multiplayer_peer()

static func is_playing_over_network(multiplayer: MultiplayerAPI) -> bool:
	return multiplayer.has_multiplayer_peer()

static func get_world_or_throw(node: Node) -> World:
	var parent = node.get_parent()
	if parent == null:
		assert(false, "Node is not in World")
	if parent is World:
		return parent
	return get_world_or_throw(parent) # Recursive call
	
