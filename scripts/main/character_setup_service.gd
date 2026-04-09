extends Node

const MENU_STYLES := preload("res://scripts/ui/menu_styles.gd")
const CHARACTER_APPEARANCE := preload("res://scripts/player/character_appearance.gd")

var _join_service: Node
var _player_spawn_service: Node

var _character_setup_root: Control
var _character_setup_title: Label
var _character_setup_message: Label
var _character_name_edit: LineEdit
var _character_color_option: OptionButton
var _character_color_preview: ColorRect
var _character_create_button: Button

var _pending_character_setup: Dictionary = {}
var _is_initialized: bool = false


func setup(
	join_service: Node,
	player_spawn_service: Node,
	character_setup_root: Control,
	character_setup_title: Label,
	character_setup_message: Label,
	character_name_edit: LineEdit,
	character_color_option: OptionButton,
	character_color_preview: ColorRect,
	character_create_button: Button
) -> void:
	_join_service = join_service
	_player_spawn_service = player_spawn_service
	_character_setup_root = character_setup_root
	_character_setup_title = character_setup_title
	_character_setup_message = character_setup_message
	_character_name_edit = character_name_edit
	_character_color_option = character_color_option
	_character_color_preview = character_color_preview
	_character_create_button = character_create_button

	if _is_initialized:
		return

	_character_setup_root.theme = MENU_STYLES.create_theme()
	_character_setup_root.visible = false
	_populate_character_color_options()
	_character_create_button.pressed.connect(_on_character_create_pressed)
	_character_name_edit.text_submitted.connect(_on_character_name_submitted)
	_character_color_option.item_selected.connect(_on_character_color_selected)
	_is_initialized = true


func begin_for_peer(peer_id: int, account_id: String, display_name: String) -> void:
	_pending_character_setup[peer_id] = {
		"account_id": account_id,
		"display_name": display_name,
	}
	_show_character_setup(peer_id, display_name)


func clear_pending(peer_id: int) -> void:
	_pending_character_setup.erase(peer_id)


func discard_peer(peer_id: int) -> void:
	_pending_character_setup.erase(peer_id)
	if peer_id == multiplayer.get_unique_id():
		_close_character_setup()


@rpc("authority", "reliable")
func _open_character_setup(default_name: String) -> void:
	_character_setup_title.text = "Create Character"
	_character_setup_message.text = "This world needs a character before you can join."
	_character_name_edit.text = default_name
	_character_color_option.select(0)
	_refresh_character_color_preview(0)
	_character_setup_root.visible = true
	_character_name_edit.grab_focus()


@rpc("authority", "reliable")
func _close_character_setup() -> void:
	_character_setup_root.visible = false


@rpc("any_peer", "reliable")
func _submit_character_setup(character_name: String, color_index: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		sender_id = multiplayer.get_unique_id()

	var pending := _pending_character_setup.get(sender_id, {}) as Dictionary
	if pending.is_empty():
		return

	var safe_character_name := _sanitize_character_name(
		character_name, String(pending.get("display_name", ""))
	)
	var appearance := CHARACTER_APPEARANCE.create_appearance_from_outfit_index(color_index)
	var account_id := String(pending.get("account_id", ""))
	if account_id.is_empty():
		_pending_character_setup.erase(sender_id)
		_hide_character_setup(sender_id)
		if _join_service != null and _join_service.has_method("reject_join"):
			_join_service.reject_join(sender_id, "Character setup failed.")
		return

	var player_record := SaveManager.load_player(account_id)
	player_record["account"] = {
		"account_id": account_id,
		"display_name": String(pending.get("display_name", "")),
	}
	player_record["character"] = {
		"name": safe_character_name,
		"appearance": appearance,
		"created_at": Time.get_datetime_string_from_system(true),
	}
	SaveManager.save_player(account_id, player_record)

	_hide_character_setup(sender_id)
	_pending_character_setup.erase(sender_id)

	if _player_spawn_service != null and _player_spawn_service.has_method("complete_join"):
		_player_spawn_service.complete_join(sender_id, player_record)


func _show_character_setup(peer_id: int, default_name: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		_open_character_setup(default_name)
	else:
		_open_character_setup.rpc_id(peer_id, default_name)


func _hide_character_setup(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_close_character_setup()
	else:
		_close_character_setup.rpc_id(peer_id)


func _sanitize_character_name(character_name: String, fallback_name: String) -> String:
	var safe_name := character_name.strip_edges().left(24)
	if safe_name.is_empty():
		safe_name = fallback_name.strip_edges().left(24)
	if safe_name.is_empty():
		safe_name = "Diver"
	return safe_name


func _populate_character_color_options() -> void:
	_character_color_option.clear()
	for index in range(CHARACTER_APPEARANCE.get_outfit_option_count()):
		_character_color_option.add_item(CHARACTER_APPEARANCE.get_outfit_option_label(index))


func _refresh_character_color_preview(index: int) -> void:
	_character_color_preview.color = CHARACTER_APPEARANCE.get_outfit_preview_color(index)


func _on_character_create_pressed() -> void:
	if multiplayer.is_server():
		_submit_character_setup(_character_name_edit.text, _character_color_option.selected)
	else:
		_submit_character_setup.rpc_id(1, _character_name_edit.text, _character_color_option.selected)


func _on_character_name_submitted(_text: String) -> void:
	_on_character_create_pressed()


func _on_character_color_selected(index: int) -> void:
	_refresh_character_color_preview(index)
