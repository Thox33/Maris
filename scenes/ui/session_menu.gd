extends CanvasLayer
## In-game session UI for disconnect handling and returning to the lobby.

const MENU_STYLES := preload("res://scripts/ui/menu_styles.gd")

@onready var _root: Control = $Root
@onready var _title_label: Label = $Root/PanelContainer/VBoxContainer/TitleLabel
@onready var _message_label: Label = $Root/PanelContainer/VBoxContainer/MessageLabel
@onready var _resume_button: Button = $Root/PanelContainer/VBoxContainer/ResumeButton
@onready var _return_button: Button = $Root/PanelContainer/VBoxContainer/ReturnButton

var _disconnect_mode: bool = false


func _ready() -> void:
	visible = true
	_root.visible = false
	_root.theme = MENU_STYLES.create_theme()
	_resume_button.pressed.connect(_on_resume_pressed)
	_return_button.pressed.connect(_on_return_pressed)
	NetworkManager.session_ended.connect(_on_session_ended)
	_update_content()


func _unhandled_input(event: InputEvent) -> void:
	if _disconnect_mode:
		return

	if event.is_action_pressed("ui_cancel"):
		_root.visible = not _root.visible
		_update_content()
		get_viewport().set_input_as_handled()


func _on_resume_pressed() -> void:
	_root.visible = false


func _on_return_pressed() -> void:
	if _disconnect_mode:
		# Session already torn down by the network event — just navigate.
		get_tree().change_scene_to_file("res://scenes/ui/lobby_ui.tscn")
	else:
		# leave_game() will emit session_ended, which triggers navigation.
		NetworkManager.leave_game("user_left")


func _on_session_ended(reason: String) -> void:
	if reason == "app_quit":
		return
	if reason == "connection_lost":
		_disconnect_mode = true
		_root.visible = true
		_update_content()
	else:
		get_tree().change_scene_to_file("res://scenes/ui/lobby_ui.tscn")


func _update_content() -> void:
	if _disconnect_mode:
		_title_label.text = "Connection Lost"
		_message_label.text = "The connection to the host was lost."
		_resume_button.visible = false
	else:
		_title_label.text = "Game Menu"
		_message_label.text = "Leave the current session or continue playing."
		_resume_button.visible = true
