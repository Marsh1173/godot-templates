class_name MyNetwork
extends RefCounted

static func is_authority(multiplayer: MultiplayerAPI) -> bool:
	return multiplayer.is_server() || !multiplayer.has_multiplayer_peer()
