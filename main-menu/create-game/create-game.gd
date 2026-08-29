extends Control
class_name CreateGame

@onready var create_button: Button = $CenterContainer/VBoxContainer/ActionButtons/CreateButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/ActionButtons/BackButton
@onready var visibility_menu: OptionButton = $CenterContainer/VBoxContainer/HBoxContainer2/VisibilityMenu
@onready var max_players_input: SpinBox = $CenterContainer/VBoxContainer/HBoxContainer/MaxPlayersInput

var lobby_manager: LobbyManager

func _ready():
	set_not_loading()
	
	lobby_manager = AppOrchestrator.get_or_error(self).lobby_manager
	lobby_manager.lobby_created.connect(_on_lobby_created)

func set_loading():
	create_button.disabled = true
	back_button.disabled = true
	visibility_menu.disabled = true
	max_players_input.editable = false
	
	create_button.text = "Creating..."

func _on_lobby_created(_connect_status: Steam.Result, _lobby_id: int):
	set_not_loading()

func set_not_loading():
	create_button.disabled = false
	back_button.disabled = false
	visibility_menu.disabled = false
	max_players_input.editable = true
	
	create_button.text = "Create"

func _on_create_button_pressed():
	var max_players: int = floor(max_players_input.value)
	var visibility: Steam.LobbyType = visibility_menu.get_selected_id() as Steam.LobbyType
	
	set_loading()
	lobby_manager.create_lobby(visibility, max_players)
