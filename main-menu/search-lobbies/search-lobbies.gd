extends Control
class_name SearchLobbies

const LOBBY_LIST_ITEM := preload("uid://dcb1fy2et50ua")
@onready var lobby_list: Control = $CenterContainer/VBoxContainer/VScrollBar/LobbyList

@onready var back_button: Button = $CenterContainer/VBoxContainer/HBoxContainer/BackButton
@onready var refresh_button: Button = $CenterContainer/VBoxContainer/HBoxContainer/RefreshButton
@onready var loading_label: Label = $CenterContainer/VBoxContainer/VScrollBar/LobbyList/Loading
@onready var no_results_label: Label = $CenterContainer/VBoxContainer/VScrollBar/LobbyList/NoResults

var lobby_manager: LobbyManager

var loading := false

func _ready():
	lobby_manager = AppOrchestrator.get_or_error(self).lobby_manager
	
	refresh_button.pressed.connect(_get_lobby_list)
	lobby_manager.lobby_list_updated.connect(_lobby_list_updated)
	_get_lobby_list()
	
	lobby_manager.lobby_joined.connect(_on_lobby_joined_or_failed)

func _get_lobby_list():
	if loading:
		return
	loading = true
	
	lobby_manager.get_lobby_list()
	refresh_button.disabled = true
	loading_label.visible = true
	no_results_label.visible = false
	for child in lobby_list.get_children():
		if not child is Label:
			child.free()

func _lobby_list_updated(lobby_ids: Array[int]):
	loading = false
	
	refresh_button.disabled = false
	loading_label.visible = false
	no_results_label.visible = lobby_ids.size() == 0
	
	for lobby_id: int in lobby_ids:
		var lobby_list_item: LobbyListItem = LOBBY_LIST_ITEM.instantiate()
		lobby_list.add_child(lobby_list_item)
		lobby_list_item.ready_with_data(lobby_id)
		lobby_list_item.joining_lobby.connect(_on_joining_lobby)

func _on_joining_lobby():
	for child in lobby_list.get_children():
		if child is LobbyListItem:
			child.disabled = true
	back_button.disabled = true
	refresh_button.disabled = true

func _on_lobby_joined_or_failed(_lobby_id: int):
	for child in lobby_list.get_children():
		if child is LobbyListItem:
			child.disabled = false
	back_button.disabled = false
	refresh_button.disabled = false
