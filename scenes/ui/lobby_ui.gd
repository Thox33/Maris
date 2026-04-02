extends Control
## Simple lobby UI for hosting or joining a game.
## Shows two buttons: Host and Join. On success, switches to the game scene.

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var status_label: Label = $VBoxContainer/StatusLabel


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)


func _on_host_pressed() -> void:
	var error := NetworkManager.host_game()
	if error == OK:
		status_label.text = "Hosting..."
		host_button.disabled = true
		join_button.disabled = true
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	else:
		status_label.text = "Failed to host!"


func _on_join_pressed() -> void:
	var error := NetworkManager.join_game()
	if error == OK:
		status_label.text = "Connecting..."
		host_button.disabled = true
		join_button.disabled = true
	else:
		status_label.text = "Failed to join!"


func _on_player_connected(_peer_id: int) -> void:
	status_label.text = "%d players connected." % NetworkManager.players.size()


func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"
	host_button.disabled = false
	join_button.disabled = false
