extends CanvasLayer
## Local player inventory HUD.
## Hotbar always visible. Inventory panel above it can be toggled.

const ITEM_ICON_VISUALS := preload("res://scripts/items/item_icon_visuals.gd")
const WORLD_INPUT_BLOCKER_GROUP := &"world_input_blocking_ui"
const INVENTORY_TOGGLE_ACTION := &"inventory_toggle"
const SLOT_SIZE := 40.0
const SLOT_ICON_SIZE := 20.0
const SLOT_SPACING := 2
const PANEL_PADDING := 8
const INVENTORY_ROWS := 3
const HELD_PREVIEW_OFFSET := Vector2(8.0, 8.0)
const DRAG_THRESHOLD := 6.0

var _block_interaction: Node2D
var _inventory_manager: Node

var _slot_panels: Array = []
var _slot_icons: Array = []
var _slot_counts: Array = []
var _slot_hotkeys: Array = []
var _body_slot_indices: Array[int] = []

var _selected_index: int = 0
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _style_container: StyleBoxFlat
var _hotbar_actions: Array[StringName] = []
var _is_open: bool = false
var _held_preview_panel: PanelContainer
var _held_preview_icon: TextureRect
var _held_preview_count: Label
var _hovered_slot_index: int = -1
var _left_press_active: bool = false
var _left_press_started_with_held: bool = false
var _left_press_source_slot_index: int = -1
var _left_press_position: Vector2 = Vector2.ZERO
var _left_drag_active: bool = false
var _left_drag_started_with_held: bool = false
var _left_drag_source_slot_index: int = -1
var _drag_distribute_slots: Array[int] = []
var _preview_active: bool = false
var _preview_slot_data: Dictionary = {}
var _preview_held_slot: Dictionary = {"item_id": ItemProperties.NONE, "count": 0}
var _last_pickup_slot_index: int = -1
var _last_pickup_item_id: int = ItemProperties.NONE

@onready var _inventory_panel: PanelContainer = $Root/BottomDock/Stack/InventoryPanel
@onready var _body_grid: GridContainer = $Root/BottomDock/Stack/InventoryPanel/BodyPadding/BodyGrid
@onready var _hotbar_panel: PanelContainer = $Root/BottomDock/Stack/HotbarPanel
@onready var _hotbar_row: GridContainer = $Root/BottomDock/Stack/HotbarPanel/HotbarPadding/HotbarRow


func setup_session(block_interaction: Node2D, inventory_manager: Node) -> void:
	_block_interaction = block_interaction
	_inventory_manager = inventory_manager


func _ready() -> void:
	if not get_parent().is_multiplayer_authority():
		visible = false
		set_process_unhandled_input(false)
		return

	_hotbar_actions = _build_hotbar_actions()

	_create_styles()
	_apply_container_styles()
	_build_slots()
	_configure_inventory_panel()
	_build_held_preview()
	_register_world_input_blockers()

	if _block_interaction == null:
		return

	_selected_index = _block_interaction.selected_hotbar_slot
	_refresh_selection()

	if _inventory_manager == null:
		return

	_inventory_manager.local_slot_changed.connect(_on_slot_changed)
	_inventory_manager.local_inventory_synced.connect(_refresh_all_slots)
	_inventory_manager.local_held_slot_changed.connect(_refresh_held_preview)
	_refresh_all_slots()
	_refresh_held_preview()


func _process(_delta: float) -> void:
	if _held_preview_panel == null or not _held_preview_panel.visible:
		return
	_held_preview_panel.position = get_viewport().get_mouse_position() + HELD_PREVIEW_OFFSET


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if not mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_complete_left_pointer_action()
	elif event is InputEventMouseMotion:
		_maybe_start_left_drag(event.position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if not ChatManager.is_chat_open and _is_inventory_toggle_key(event):
			_toggle_inventory()
			get_viewport().set_input_as_handled()
			return

		for index: int in range(_hotbar_actions.size()):
			var action_name: StringName = StringName(_hotbar_actions[index])
			if event.is_action_pressed(action_name):
				_select_slot(index)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_slot(
				(_selected_index - 1 + GameConstants.HOTBAR_SIZE) % GameConstants.HOTBAR_SIZE
			)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_slot((_selected_index + 1) % GameConstants.HOTBAR_SIZE)
			get_viewport().set_input_as_handled()


func _select_slot(index: int) -> void:
	if index == _selected_index:
		return
	_selected_index = index
	_block_interaction.selected_hotbar_slot = index
	_refresh_selection()


func _refresh_selection() -> void:
	for i: int in range(GameConstants.HOTBAR_SIZE):
		var style := _style_selected if i == _selected_index else _style_normal
		_slot_panels[i].add_theme_stylebox_override("panel", style)


func _on_slot_changed(slot_index: int) -> void:
	if _preview_active:
		_recompute_distribute_preview()
	else:
		_update_slot(slot_index)


func _refresh_all_slots() -> void:
	for i: int in range(GameConstants.INVENTORY_SIZE):
		_update_slot(i)


func _update_slot(index: int) -> void:
	if _inventory_manager.local_inventory == null:
		_clear_slot_visual(index)
		return

	var slot: Dictionary = _get_display_slot(index)
	var is_preview_slot: bool = _preview_active and _preview_slot_data.has(index)
	if slot["item_id"] == ItemProperties.NONE:
		_clear_slot_visual(index)
		return

	_slot_icons[index].texture = _build_slot_icon_texture(slot["item_id"])

	if is_preview_slot:
		_slot_counts[index].text = str(slot["count"])
	elif slot["count"] > 1:
		_slot_counts[index].text = str(slot["count"])
	else:
		_slot_counts[index].text = ""


func _clear_slot_visual(index: int) -> void:
	_slot_icons[index].texture = null
	_slot_counts[index].text = ""


func _on_slot_gui_input(slot_index: int, event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	var mouse_event: InputEventMouseButton = event
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if mouse_event.shift_pressed:
			_cancel_left_pointer_state()
			_clear_preview()
			_request_inventory_action("quick_transfer", slot_index)
		elif mouse_event.double_click and _can_pickup_matching_from_same_slot(slot_index):
			_cancel_left_pointer_state()
			_clear_preview()
			_request_pickup_matching_item(_last_pickup_item_id)
		else:
			_begin_left_press(slot_index, mouse_event.position)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if _left_press_active or _left_drag_active or _preview_active:
			_cancel_left_pointer_state()
			_clear_preview()
			get_viewport().set_input_as_handled()
			return
		if _has_local_held_slot():
			_request_inventory_action("place_one", slot_index)
		else:
			_request_inventory_action("pickup_half", slot_index)
		get_viewport().set_input_as_handled()


func _request_inventory_action(action: String, slot_index: int) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_inventory_manager._request_inventory_action(action, slot_index)
	else:
		_inventory_manager._request_inventory_action.rpc_id(1, action, slot_index)


func _request_inventory_distribute_even(slot_indices: Array[int]) -> void:
	if multiplayer.multiplayer_peer == null or slot_indices.is_empty():
		return
	if multiplayer.is_server():
		_inventory_manager._request_inventory_distribute_even(slot_indices)
	else:
		_inventory_manager._request_inventory_distribute_even.rpc_id(1, slot_indices)


func _request_pickup_matching_item(item_id: int) -> void:
	if multiplayer.multiplayer_peer == null or item_id == ItemProperties.NONE:
		return
	if multiplayer.is_server():
		_inventory_manager._request_pickup_matching_item(item_id)
	else:
		_inventory_manager._request_pickup_matching_item.rpc_id(1, item_id)


func _has_local_held_slot() -> bool:
	if _inventory_manager == null:
		return false
	var held: Dictionary = _inventory_manager.local_held_slot
	return held.get("item_id", ItemProperties.NONE) != ItemProperties.NONE and held.get("count", 0) > 0


func _begin_left_press(slot_index: int, mouse_position: Vector2) -> void:
	_left_press_active = true
	_left_press_started_with_held = _has_local_held_slot()
	_left_press_source_slot_index = slot_index
	_left_press_position = mouse_position
	if not _left_press_started_with_held:
		var slot: Dictionary = _inventory_manager.local_inventory.get_slot(slot_index)
		if slot.get("item_id", ItemProperties.NONE) == ItemProperties.NONE:
			_cancel_left_pointer_state()
			return
		_last_pickup_slot_index = slot_index
		_last_pickup_item_id = slot["item_id"]
		_request_inventory_action("pickup_full", slot_index)


func _maybe_start_left_drag(mouse_position: Vector2) -> void:
	if not _left_press_active or _left_drag_active:
		return
	if _left_press_position.distance_to(mouse_position) < DRAG_THRESHOLD:
		return

	_left_drag_active = true
	_left_drag_started_with_held = _left_press_started_with_held
	_left_drag_source_slot_index = _left_press_source_slot_index
	_drag_distribute_slots.clear()
	if _left_drag_started_with_held:
		_append_drag_distribute_slot(_left_drag_source_slot_index)
		_recompute_distribute_preview()


func _complete_left_pointer_action() -> void:
	var target_slot_index: int = _hovered_slot_index

	if _left_drag_active:
		var started_with_held: bool = _left_drag_started_with_held
		var source_slot_index: int = _left_drag_source_slot_index
		var distribute_slots: Array[int] = _drag_distribute_slots.duplicate()
		_cancel_left_pointer_state()

		if target_slot_index < 0:
			_clear_preview()
			return
		if started_with_held:
			if distribute_slots.size() > 1:
				_clear_preview()
				_request_inventory_distribute_even(distribute_slots)
				return
			_clear_preview()
			if distribute_slots.size() == 1:
				_request_inventory_action("place_full", distribute_slots[0])
			return
		if target_slot_index != source_slot_index:
			_request_inventory_action("place_full", target_slot_index)
		return

	if _left_press_active:
		var pressed_with_held: bool = _left_press_started_with_held
		var pressed_slot_index: int = _left_press_source_slot_index
		_cancel_left_pointer_state()

		if target_slot_index != pressed_slot_index:
			return
		if pressed_with_held:
			_request_inventory_action("place_full", pressed_slot_index)


func _cancel_left_pointer_state() -> void:
	_left_press_active = false
	_left_press_started_with_held = false
	_left_press_source_slot_index = -1
	_left_press_position = Vector2.ZERO
	_left_drag_active = false
	_left_drag_started_with_held = false
	_left_drag_source_slot_index = -1
	_drag_distribute_slots.clear()


func _set_hovered_slot(slot_index: int) -> void:
	_hovered_slot_index = slot_index
	if _left_drag_active and _left_drag_started_with_held:
		_append_drag_distribute_slot(slot_index)
		_recompute_distribute_preview()


func _clear_hovered_slot(slot_index: int) -> void:
	if _hovered_slot_index == slot_index:
		_hovered_slot_index = -1


func _append_drag_distribute_slot(slot_index: int) -> void:
	if slot_index < 0:
		return
	if _inventory_manager == null or not _has_local_held_slot():
		return
	var held: Dictionary = _inventory_manager.local_held_slot
	var slot: Dictionary = _inventory_manager.local_inventory.get_slot(slot_index)
	if not _is_slot_eligible_for_held_item(slot, held["item_id"]):
		return
	if slot_index in _drag_distribute_slots:
		return
	_drag_distribute_slots.append(slot_index)


func _can_pickup_matching_from_same_slot(slot_index: int) -> bool:
	if slot_index != _last_pickup_slot_index:
		return false
	if not _has_local_held_slot():
		return false
	return _inventory_manager.local_held_slot.get("item_id", ItemProperties.NONE) == _last_pickup_item_id


func _get_display_slot(index: int) -> Dictionary:
	if _preview_active and _preview_slot_data.has(index):
		return _preview_slot_data[index]
	if _inventory_manager == null or _inventory_manager.local_inventory == null:
		return {"item_id": ItemProperties.NONE, "count": 0}
	return _inventory_manager.local_inventory.get_slot(index)


func _get_display_held_slot() -> Dictionary:
	if _preview_active:
		return _preview_held_slot
	if _inventory_manager == null:
		return {"item_id": ItemProperties.NONE, "count": 0}
	return _inventory_manager.local_held_slot


func _clear_preview() -> void:
	_preview_active = false
	_preview_slot_data.clear()
	_preview_held_slot = {"item_id": ItemProperties.NONE, "count": 0}
	_refresh_all_slots()
	_refresh_held_preview()


func _recompute_distribute_preview() -> void:
	if _inventory_manager == null or _inventory_manager.local_inventory == null:
		return
	if not _left_drag_active or not _left_drag_started_with_held:
		_clear_preview()
		return

	var held: Dictionary = _inventory_manager.local_held_slot
	if held.get("item_id", ItemProperties.NONE) == ItemProperties.NONE or held.get("count", 0) <= 0:
		_clear_preview()
		return

	var item_id: int = held["item_id"]
	var props: ItemProperties = ItemProperties.get_properties(item_id)
	if props == null:
		_clear_preview()
		return

	_preview_slot_data.clear()
	var eligible_slots: Array[int] = []
	for slot_index in _drag_distribute_slots:
		var slot: Dictionary = _inventory_manager.local_inventory.get_slot(slot_index)
		if not _is_slot_eligible_for_held_item(slot, item_id):
			continue
		eligible_slots.append(slot_index)
		_preview_slot_data[slot_index] = {
			"item_id": slot.get("item_id", ItemProperties.NONE),
			"count": slot.get("count", 0),
		}

	if eligible_slots.is_empty():
		_clear_preview()
		return

	var remaining: int = held["count"]
	while remaining > 0:
		var placed_in_pass: bool = false
		for slot_index in eligible_slots:
			if remaining <= 0:
				break
			var slot: Dictionary = _preview_slot_data[slot_index]
			if slot["item_id"] == ItemProperties.NONE:
				slot["item_id"] = item_id
				slot["count"] = 1
				remaining -= 1
				placed_in_pass = true
			elif slot["item_id"] == item_id and slot["count"] < props.max_stack:
				slot["count"] += 1
				remaining -= 1
				placed_in_pass = true
			_preview_slot_data[slot_index] = slot
		if not placed_in_pass:
			break

	_preview_active = true
	_preview_held_slot = {
		"item_id": item_id if remaining > 0 else ItemProperties.NONE,
		"count": remaining,
	}
	_refresh_all_slots()
	_refresh_held_preview()


func _is_slot_eligible_for_held_item(slot: Dictionary, item_id: int) -> bool:
	if slot.get("item_id", ItemProperties.NONE) == ItemProperties.NONE:
		return true
	if slot["item_id"] != item_id:
		return false
	var props: ItemProperties = ItemProperties.get_properties(item_id)
	return props != null and slot.get("count", 0) < props.max_stack


func _toggle_inventory() -> void:
	_is_open = not _is_open
	_inventory_panel.visible = _is_open


func _build_slots() -> void:
	_slot_panels.resize(GameConstants.INVENTORY_SIZE)
	_slot_icons.resize(GameConstants.INVENTORY_SIZE)
	_slot_counts.resize(GameConstants.INVENTORY_SIZE)
	_slot_hotkeys.resize(GameConstants.INVENTORY_SIZE)

	for i: int in range(GameConstants.HOTBAR_SIZE):
		_create_slot_widget(_hotbar_row, i, true)

	for row: int in range(INVENTORY_ROWS, 0, -1):
		var row_start: int = row * GameConstants.HOTBAR_SIZE
		for column_offset: int in range(GameConstants.HOTBAR_SIZE):
			var slot_index: int = row_start + column_offset
			_body_slot_indices.append(slot_index)
			_create_slot_widget(_body_grid, slot_index, false)


func _create_slot_widget(parent: Control, slot_index: int, show_hotkey: bool) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_to_group(WORLD_INPUT_BLOCKER_GROUP)
	panel.add_theme_stylebox_override("panel", _style_normal)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		_on_slot_gui_input(slot_index, event)
	)
	panel.mouse_entered.connect(func() -> void:
		_set_hovered_slot(slot_index)
	)
	panel.mouse_exited.connect(func() -> void:
		_clear_hovered_slot(slot_index)
	)

	var slot_root := Control.new()
	slot_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(slot_root)

	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = Vector2(SLOT_ICON_SIZE, SLOT_ICON_SIZE)
	icon.position = Vector2(-SLOT_ICON_SIZE * 0.4, -SLOT_ICON_SIZE * 0.4)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slot_root.add_child(icon)

	var count_label := Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.modulate = Color(1.0, 1.0, 1.0, 0.9)
	count_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	count_label.position = Vector2(4.0, 10.0)
	count_label.size = Vector2(24.0, 14.0)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_root.add_child(count_label)

	var hotkey_label := Label.new()
	hotkey_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hotkey_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hotkey_label.add_theme_font_size_override("font_size", 10)
	hotkey_label.modulate = Color(0.8, 0.9, 1.0, 1.0)
	hotkey_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hotkey_label.position = Vector2(4.0, 2.0)
	hotkey_label.size = Vector2(22.0, 13.0)
	hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotkey_label.text = (
		_get_action_display_text(_hotbar_actions[slot_index]) if show_hotkey else ""
	)
	slot_root.add_child(hotkey_label)

	parent.add_child(panel)
	_slot_panels[slot_index] = panel
	_slot_icons[slot_index] = icon
	_slot_counts[slot_index] = count_label
	_slot_hotkeys[slot_index] = hotkey_label


func _build_held_preview() -> void:
	_held_preview_panel = PanelContainer.new()
	_held_preview_panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_held_preview_panel.visible = false
	_held_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_preview_panel.add_theme_stylebox_override("panel", _style_selected)
	add_child(_held_preview_panel)

	var slot_root := Control.new()
	slot_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_preview_panel.add_child(slot_root)

	_held_preview_icon = TextureRect.new()
	_held_preview_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_held_preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_held_preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_held_preview_icon.size = Vector2(SLOT_ICON_SIZE, SLOT_ICON_SIZE)
	_held_preview_icon.position = Vector2(-SLOT_ICON_SIZE * 0.4, -SLOT_ICON_SIZE * 0.4)
	_held_preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_preview_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slot_root.add_child(_held_preview_icon)

	_held_preview_count = Label.new()
	_held_preview_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_held_preview_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_held_preview_count.add_theme_font_size_override("font_size", 12)
	_held_preview_count.modulate = Color(1.0, 1.0, 1.0, 0.95)
	_held_preview_count.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_held_preview_count.position = Vector2(4.0, -24.0)
	_held_preview_count.size = Vector2(24.0, 14.0)
	_held_preview_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_root.add_child(_held_preview_count)


func _register_world_input_blockers() -> void:
	_inventory_panel.add_to_group(WORLD_INPUT_BLOCKER_GROUP)
	_hotbar_panel.add_to_group(WORLD_INPUT_BLOCKER_GROUP)


func _configure_inventory_panel() -> void:
	_inventory_panel.custom_minimum_size = Vector2(0.0, _get_inventory_body_height())
	_inventory_panel.visible = false


func _refresh_held_preview() -> void:
	if _held_preview_panel == null or _inventory_manager == null:
		return

	var held: Dictionary = _get_display_held_slot()
	if held.get("item_id", ItemProperties.NONE) == ItemProperties.NONE or held.get("count", 0) <= 0:
		_held_preview_panel.visible = false
		_held_preview_icon.texture = null
		_held_preview_count.text = ""
		return

	_held_preview_panel.visible = true
	_held_preview_panel.position = get_viewport().get_mouse_position() + HELD_PREVIEW_OFFSET
	_held_preview_icon.texture = _build_slot_icon_texture(held["item_id"])
	_held_preview_count.text = str(held["count"]) if held["count"] > 1 else ""


func _get_inventory_body_height() -> float:
	return (
		(INVENTORY_ROWS * SLOT_SIZE)
		+ ((INVENTORY_ROWS - 1) * float(SLOT_SPACING))
		+ (PANEL_PADDING * 2.0)
	)


func _apply_container_styles() -> void:
	_hotbar_panel.add_theme_stylebox_override("panel", _style_container)
	_inventory_panel.add_theme_stylebox_override("panel", _style_container)


func _create_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.1, 0.15, 0.25, 0.75)
	_style_normal.border_color = Color(0.3, 0.4, 0.5, 0.8)
	_style_normal.set_border_width_all(1)
	_style_normal.set_corner_radius_all(2)

	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0.15, 0.25, 0.4, 0.85)
	_style_selected.border_color = Color(0.5, 0.8, 1.0, 1.0)
	_style_selected.set_border_width_all(2)
	_style_selected.set_corner_radius_all(2)

	_style_container = StyleBoxFlat.new()
	_style_container.bg_color = Color(0.06, 0.1, 0.18, 0.82)
	_style_container.border_color = Color(0.28, 0.38, 0.5, 0.9)
	_style_container.set_border_width_all(1)
	_style_container.set_corner_radius_all(4)
	_style_container.content_margin_left = PANEL_PADDING
	_style_container.content_margin_top = PANEL_PADDING
	_style_container.content_margin_right = PANEL_PADDING
	_style_container.content_margin_bottom = PANEL_PADDING


func _build_hotbar_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	for i: int in range(GameConstants.HOTBAR_SIZE):
		actions.append(StringName("hotbar_slot_%d" % (i + 1)))
	return actions


func _get_action_display_text(action_name: StringName) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action_name)
	for event: InputEvent in events:
		if event is InputEventKey:
			return OS.get_keycode_string(event.keycode if event.keycode != 0 else event.physical_keycode)
	return ""


func _is_inventory_toggle_key(event: InputEventKey) -> bool:
	return (
		event.is_action_pressed(INVENTORY_TOGGLE_ACTION)
		or event.keycode == KEY_E
		or event.physical_keycode == KEY_E
	)


func _build_slot_icon_texture(item_id: int) -> Texture2D:
	return ITEM_ICON_VISUALS.build_outlined_icon_texture(item_id)
