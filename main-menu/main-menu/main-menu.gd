extends Control

@onready var steam_name: Label = $ProfileContainer/HBoxContainer/SteamName
@onready var avatar_rect: TextureRect = $ProfileContainer/HBoxContainer/AvatarRect
var lobby_manager: LobbyManager

func _ready():
	lobby_manager = AppOrchestrator.get_or_error(self).lobby_manager
	
	steam_name.text = Steam.getFriendPersonaName(Steam.getSteamID())
	Steam.avatar_loaded.connect(avatar_loaded)
	Steam.getPlayerAvatar(Steam.AVATAR_SMALL)
	
	search_lobbies_container.back_button.pressed.connect(_close_search_lobbies)
	create_game_container.back_button.pressed.connect(_close_create_game)
	
	lobby_manager.lobby_joined.connect(_on_lobby_join)
	lobby_manager.lobby_left.connect(_on_lobby_leave)

func avatar_loaded(_avatar_id: int, image_size: int, data: PackedByteArray):
	# Create image from buffer
	var avatar_image: Image = Image.create_from_data(image_size, image_size, false, Image.FORMAT_RGBA8, data)
	var avatar_texture: ImageTexture = ImageTexture.create_from_image(avatar_image)
	avatar_rect.texture = avatar_texture

@onready var main_actions_container: Control = $MainActionsContainer

#region buttons
@onready var settings_container: Control = $SettingsContainer

func _on_settings_button_pressed():
	_open_settings()

func _on_close_settings_button_pressed():
	_close_settings()

func _open_settings():
	main_actions_container.visible = false
	settings_container.visible = true

func _close_settings():
	main_actions_container.visible = true
	settings_container.visible = false
	
@onready var search_lobbies_container: SearchLobbies = $SearchLobbies

func _on_search_lobbies_button_pressed():
	_open_search_lobbies()
	
func _open_search_lobbies():
	main_actions_container.visible = false
	search_lobbies_container.visible = true

func _close_search_lobbies():
	main_actions_container.visible = true
	search_lobbies_container.visible = false
	
@onready var create_game_container: CreateGame = $CreateGame

func _on_create_game_button_pressed():
	_open_create_game()
	
func _open_create_game():
	main_actions_container.visible = false
	create_game_container.visible = true

func _close_create_game():
	main_actions_container.visible = true
	create_game_container.visible = false
#endregion

@onready var lobby: Lobby = $Lobby

func _on_lobby_join(lobby_id: int):
	main_actions_container.visible = false
	search_lobbies_container.visible = false
	create_game_container.visible = false
	
	lobby.load_lobby_to_ui(lobby_id)
	lobby.visible = true

func _on_lobby_leave(_lobby_id: int):
	main_actions_container.visible = true
	lobby.visible = false

func _on_exit_game_pressed():
	get_tree().quit()
