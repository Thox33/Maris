extends Control
## Main menu / lobby flow:
## Main -> Host / Join / Options
## Host shows local worlds and allows creating a new one.

const MAIN_SCENE_SCRIPT := preload("res://scenes/main/main.gd")
const MENU_STYLES := preload("res://scripts/ui/menu_styles.gd")

const STATUS_NORMAL := Color(0.80, 0.92, 0.96)
const STATUS_ERROR := Color(1.0, 0.56, 0.56)

@onready var section_label: Label = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/SectionLabel
@onready var status_label: Label = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/StatusLabel

@onready var main_screen: VBoxContainer = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/MainScreen
@onready var host_screen: VBoxContainer = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/HostScreen
@onready var join_screen: VBoxContainer = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/JoinScreen
@onready var options_screen: VBoxContainer = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/OptionsScreen

@onready var main_host_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/MainScreen/HostButton
@onready var main_join_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/MainScreen/JoinButton
@onready var main_options_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/MainScreen/OptionsButton
@onready var quit_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/MainScreen/QuitButton

@onready var world_list: ItemList = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/HostScreen/WorldListPanel/ExistingWorldsList
@onready var world_summary_label: Label = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/HostScreen/WorldSummaryLabel
@onready var host_selected_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/HostScreen/HostSelectedWorldButton
@onready var new_world_edit: LineEdit = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/HostScreen/CreateRow/NewWorldEdit
@onready var create_world_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/HostScreen/CreateRow/CreateWorldButton
@onready var host_back_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/HostScreen/HostBackButton

@onready var address_edit: LineEdit = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/JoinScreen/JoinRow/AddressEdit
@onready var port_edit: LineEdit = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/JoinScreen/JoinRow/PortEdit
@onready var join_connect_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/JoinScreen/ConnectButton
@onready var join_back_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/JoinScreen/JoinBackButton

@onready var options_name_edit: LineEdit = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/OptionsScreen/OptionsNameEdit
@onready var save_profile_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/OptionsScreen/SaveProfileButton
@onready var options_back_button: Button = $SafeArea/Layout/MenuColumn/MenuPanel/MenuPadding/MenuContent/Screens/OptionsScreen/OptionsBackButton

var _busy: bool = false


func _ready() -> void:
	theme = MENU_STYLES.create_theme()

	main_host_button.pressed.connect(_on_open_host_pressed)
	main_join_button.pressed.connect(_on_open_join_pressed)
	main_options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	host_selected_button.pressed.connect(_on_host_selected_world_pressed)
	create_world_button.pressed.connect(_on_create_world_pressed)
	host_back_button.pressed.connect(_show_main_screen)
	world_list.item_selected.connect(_on_world_selected)
	world_list.item_activated.connect(_on_world_activated)

	join_connect_button.pressed.connect(_on_join_pressed)
	join_back_button.pressed.connect(_show_main_screen)

	save_profile_button.pressed.connect(_on_save_profile_pressed)
	options_back_button.pressed.connect(_show_main_screen)

	new_world_edit.text_submitted.connect(_on_new_world_submitted)
	address_edit.text_submitted.connect(_on_address_submitted)
	port_edit.text_submitted.connect(_on_port_submitted)
	options_name_edit.text_submitted.connect(_on_options_name_submitted)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	_sync_settings_fields(ClientProfile.display_name)
	address_edit.text = "127.0.0.1"
	port_edit.text = str(GameConstants.DEFAULT_PORT)
	_show_main_screen()


func _on_options_pressed() -> void:
	_sync_settings_fields(ClientProfile.display_name)
	_show_screen(options_screen, "Settings")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _show_main_screen() -> void:
	_show_screen(main_screen, "Main Menu")
	main_host_button.grab_focus()


func _on_open_host_pressed() -> void:
	_refresh_world_list()
	_show_screen(host_screen, "Host World")
	if world_list.item_count > 0:
		world_list.grab_focus()
	else:
		new_world_edit.grab_focus()


func _on_open_join_pressed() -> void:
	_show_screen(join_screen, "Join World")
	address_edit.grab_focus()


func _show_screen(screen: Control, section: String) -> void:
	for node: Control in [main_screen, host_screen, join_screen, options_screen]:
		node.visible = node == screen
	section_label.text = section
	if not _busy:
		_clear_status()


func _refresh_world_list() -> void:
	world_list.clear()
	var worlds: Array[String] = SaveManager.list_worlds()
	for world_name: String in worlds:
		world_list.add_item(world_name)

	if worlds.is_empty():
		world_summary_label.text = "No local worlds"
		host_selected_button.disabled = true
		return

	var selected_index := 0
	var active_world := SaveManager.get_world_name()
	if not active_world.is_empty():
		var active_index := worlds.find(active_world)
		if active_index != -1:
			selected_index = active_index

	world_list.select(selected_index)
	_update_world_summary(selected_index)


func _update_world_summary(index: int) -> void:
	if index < 0 or index >= world_list.item_count:
		world_summary_label.text = "No world selected"
		host_selected_button.disabled = true
		return

	var world_name := world_list.get_item_text(index)
	world_summary_label.text = "Selected: %s" % world_name
	host_selected_button.disabled = false


func _on_world_selected(index: int) -> void:
	_update_world_summary(index)


func _on_world_activated(index: int) -> void:
	_update_world_summary(index)
	_on_host_selected_world_pressed()


func _on_host_selected_world_pressed() -> void:
	if world_list.item_count == 0:
		_set_status("No local world available", true)
		return

	var selected: PackedInt32Array = world_list.get_selected_items()
	if selected.is_empty():
		_set_status("Select a world", true)
		return

	_host_world(world_list.get_item_text(selected[0]))


func _on_create_world_pressed() -> void:
	var raw_name := new_world_edit.text.strip_edges()
	if raw_name.is_empty():
		_set_status("Enter a world name", true)
		return

	var world_name := _sanitize_world_name(raw_name)
	new_world_edit.text = world_name
	_host_world(world_name)


func _host_world(world_name: String) -> void:
	if _busy:
		return

	MAIN_SCENE_SCRIPT.selected_world_name = world_name
	MAIN_SCENE_SCRIPT.dedicated_server = false

	var error := NetworkManager.host_game()
	if error != OK:
		_set_status("Failed to host '%s'" % world_name, true)
		return

	_set_busy(true)
	_set_status("Hosting '%s'..." % world_name)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_join_pressed() -> void:
	if _busy:
		return

	var address := address_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
		address_edit.text = address

	if not port_edit.text.is_valid_int():
		_set_status("Port must be a number", true)
		return

	var port := port_edit.text.to_int()
	if port <= 0 or port > 65535:
		_set_status("Port must be between 1 and 65535", true)
		return

	var error := NetworkManager.join_game(address, port)
	if error != OK:
		_set_status("Failed to join %s:%d" % [address, port], true)
		return

	_set_busy(true)
	_set_status("Connecting to %s:%d..." % [address, port])


func _on_save_profile_pressed() -> void:
	_apply_profile_from_edit(options_name_edit)
	_set_status("Settings saved")


func _apply_profile_from_edit(source: LineEdit) -> void:
	var entered_name := source.text.strip_edges().left(32)
	if entered_name.is_empty():
		entered_name = "Player"
	ClientProfile.display_name = entered_name
	ClientProfile.save_profile()
	_sync_settings_fields(entered_name)


func _sync_settings_fields(display_name: String) -> void:
	options_name_edit.text = display_name


func _clear_status() -> void:
	status_label.text = ""
	status_label.visible = false


func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.visible = not text.is_empty()
	status_label.add_theme_color_override(
		"font_color", STATUS_ERROR if is_error else STATUS_NORMAL
	)


func _set_busy(value: bool) -> void:
	_busy = value
	for button: Button in [
		main_host_button,
		main_join_button,
		main_options_button,
		quit_button,
		host_selected_button,
		create_world_button,
		host_back_button,
		join_connect_button,
		join_back_button,
		save_profile_button,
		options_back_button,
	]:
		button.disabled = value


func _on_player_connected(_peer_id: int) -> void:
	if _busy:
		return
	_set_status("%d player(s) connected" % NetworkManager.players.size())


func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_connection_failed() -> void:
	_set_busy(false)
	_show_screen(join_screen, "Join World")
	_set_status("Connection failed", true)


func _sanitize_world_name(raw: String) -> String:
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
	var sanitized := ""
	for c: String in raw.strip_edges():
		if c in allowed:
			sanitized += c
	return sanitized if not sanitized.is_empty() else "default"

func _on_new_world_submitted(_text: String) -> void:
	_on_create_world_pressed()


func _on_address_submitted(_text: String) -> void:
	port_edit.grab_focus()


func _on_port_submitted(_text: String) -> void:
	_on_join_pressed()


func _on_options_name_submitted(_text: String) -> void:
	_on_save_profile_pressed()
