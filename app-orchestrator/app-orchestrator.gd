extends Node
class_name AppOrchestrator

@onready var lobby_manager: LobbyManager = $LobbyManager

#region boilerplate
var current: Node = null

static func get_or_error(node: Node) -> AppOrchestrator:
	var parent = node.get_parent()
	if parent == null:
		assert(false, "Could not find AppOrchestrator")
	if parent is AppOrchestrator:
		return parent
	return get_or_error(parent) # Recursive call

static func get_or_null(node: Node) -> AppOrchestrator:
	var parent = node.get_parent()
	if parent == null:
		return null
	if parent is AppOrchestrator:
		return parent
	return get_or_null(parent) # Recursive call

func _ready():
	show_landing_page()

func _set_as_current(node: Node):
	if current != null:
		current.queue_free()
	current = node
	add_child(node, true)
#endregion

const LANDING_PAGE = preload("uid://kf23x7chvg3e")
func show_landing_page():
	var landing_page = LANDING_PAGE.instantiate()
	_set_as_current(landing_page)

const MAIN_MENU = preload("uid://8lj2xemdavw")
func show_main_menu():
	var main_menu = MAIN_MENU.instantiate()
	_set_as_current(main_menu)
	
const WORLD = preload("uid://dr0mjka3ukg4q")
func show_game():
	var world = WORLD.instantiate()
	_set_as_current(world)

func show_game_as_host(agent_id_to_peer_id: Dictionary[int, int], agent_id_to_steam_id: Dictionary[int, int], agent_datas: Array[Array]):
	var world: World = WORLD.instantiate()
	_set_as_current(world)
	world.ready_with_host_data(agent_id_to_peer_id, agent_id_to_steam_id, agent_datas)
