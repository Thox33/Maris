extends CanvasLayer
## In-game chat UI. Instanced as a child of the local player node.
## Non-authority instances disable themselves entirely in _ready().

const MESSAGE_LIFETIME: float = 10.0
const FADE_DURATION: float = 3.0
const MAX_HISTORY: int = 100

var _outer: VBoxContainer
var _scroll: ScrollContainer
var _message_log: VBoxContainer
var _input_row: HBoxContainer
var _line_edit: LineEdit
var _history: Array[Dictionary] = []


func _ready() -> void:
	var parent := get_parent()
	if not (parent is CharacterBody2D and parent.is_multiplayer_authority()):
		visible = false
		set_process(false)
		set_process_unhandled_input(false)
		return
	_build_ui()
	ChatManager.message_received.connect(_on_message_received)
	set_process(true)


func _process(_delta: float) -> void:
	_refresh_message_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and ChatManager.is_chat_open:
		var step := 36
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll.scroll_vertical = maxi(_scroll.scroll_vertical - step, 0)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll.scroll_vertical += step
			get_viewport().set_input_as_handled()
			return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if ChatManager.is_chat_open:
		if event.physical_keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_PAGEUP:
			_scroll.scroll_vertical = maxi(_scroll.scroll_vertical - 120, 0)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_PAGEDOWN:
			_scroll.scroll_vertical += 120
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER:
		_open_chat()
		get_viewport().set_input_as_handled()


func _open_chat() -> void:
	ChatManager.open_chat()
	_outer.visible = true
	_input_row.visible = true
	_line_edit.text = ""
	_line_edit.grab_focus()
	_refresh_message_visibility()
	call_deferred("_scroll_to_bottom")


func _close_chat() -> void:
	if not ChatManager.is_chat_open:
		return
	ChatManager.close_chat()
	_input_row.visible = false
	_line_edit.release_focus()
	_line_edit.text = ""
	_refresh_message_visibility()


func _submit() -> void:
	var text: String = _line_edit.text.strip_edges()
	_close_chat()
	if text.is_empty():
		return
	ChatManager.submit(text)


func _on_text_submitted(_text: String) -> void:
	_submit()


func _on_line_edit_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_ESCAPE:
		_close_chat()
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_UP:
		_apply_history_text(ChatManager.navigate_local_input_history(-1, _line_edit.text))
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_DOWN:
		_apply_history_text(ChatManager.navigate_local_input_history(1, _line_edit.text))
		get_viewport().set_input_as_handled()


func _on_line_edit_focus_exited() -> void:
	_close_chat()


func _apply_history_text(text: String) -> void:
	_line_edit.text = text
	_line_edit.caret_column = _line_edit.text.length()


func _on_message_received(msg: Dictionary) -> void:
	_add_message_entry(msg)
	_refresh_message_visibility()
	call_deferred("_scroll_to_bottom")


func _add_message_entry(msg: Dictionary) -> void:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var msg_type: String = msg.get("type", "player")
	match msg_type:
		"system":
			label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
			label.text = msg.get("text", "")
		"error":
			label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
			label.text = msg.get("text", "")
		_:
			label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			var sender_id: int = msg.get("sender_peer_id", 0)
			var sender_name := String(
				msg.get("sender_display_name", NetworkManager.get_player_visible_name(sender_id))
			)
			label.text = "%s: %s" % [sender_name, msg.get("text", "")]

	_message_log.add_child(label)
	_history.append({
		"created_at": Time.get_ticks_usec() * 0.000001,
		"label": label,
	})

	if _history.size() > MAX_HISTORY:
		var old_entry: Dictionary = _history.pop_front()
		var old: Label = old_entry["label"]
		if old != null and is_instance_valid(old):
			old.queue_free()


func _refresh_message_visibility() -> void:
	var now := Time.get_ticks_usec() * 0.000001
	var any_visible := false

	for entry: Dictionary in _history:
		var label: Label = entry["label"]
		if label == null or not is_instance_valid(label):
			continue

		if ChatManager.is_chat_open:
			label.visible = true
			label.modulate = Color(1.0, 1.0, 1.0, 1.0)
			any_visible = true
			continue

		var age: float = now - float(entry["created_at"])
		if age <= MESSAGE_LIFETIME:
			label.visible = true
			label.modulate = Color(1.0, 1.0, 1.0, 1.0)
			any_visible = true
		elif age <= MESSAGE_LIFETIME + FADE_DURATION:
			var alpha := 1.0 - ((age - MESSAGE_LIFETIME) / FADE_DURATION)
			label.visible = true
			label.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
			any_visible = true
		else:
			label.visible = false

	_outer.visible = ChatManager.is_chat_open or any_visible


func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	_scroll.scroll_vertical = int(bar.max_value)


func _build_ui() -> void:
	_outer = VBoxContainer.new()
	_outer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_outer.offset_left = 8.0
	_outer.offset_top = -220.0
	_outer.offset_right = 428.0
	_outer.offset_bottom = -8.0
	_outer.custom_minimum_size = Vector2(420.0, 212.0)
	_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outer.visible = false
	add_child(_outer)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_outer.add_child(_scroll)

	_message_log = VBoxContainer.new()
	_message_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message_log.custom_minimum_size = Vector2(420.0, 0.0)
	_message_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_message_log)

	_input_row = HBoxContainer.new()
	_input_row.visible = false
	_input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_row.custom_minimum_size = Vector2(0.0, 28.0)
	_outer.add_child(_input_row)

	_line_edit = LineEdit.new()
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_edit.placeholder_text = "Type a message..."
	_line_edit.max_length = GameConstants.MAX_CHAT_LENGTH
	_line_edit.text_submitted.connect(_on_text_submitted)
	_line_edit.gui_input.connect(_on_line_edit_gui_input)
	_line_edit.focus_exited.connect(_on_line_edit_focus_exited)
	_input_row.add_child(_line_edit)
